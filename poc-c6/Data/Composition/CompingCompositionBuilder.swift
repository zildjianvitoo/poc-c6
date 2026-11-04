//
//  CompingCompositionBuilder.swift
//  poc-c6
//
//  Builds the composition for the final cover (PRD §5.9). Owner: Zildjian Vito (ZV-07, ZV-08, ZV-09).
//
//  Timeline = song timeline. For every passed take, the take plus its handles goes on video
//  track A or B and vocal track A or B (alternating), so neighbouring takes overlap at each
//  boundary: the video dissolves and the vocals crossfade (equal power) over `crossfadeDuration`,
//  centred on the boundary. The instrumental has its own track from 0 to `endTime`.
//

import AVFoundation
import CoreMedia

nonisolated enum CompingError: Error, CustomStringConvertible {
    case invalidPlan([ContractViolation])
    case missingTrack(String)
    case exportUnavailable

    var description: String {
        switch self {
        case .invalidPlan(let violations): "Invalid comping plan:\n" + violations.map(\.description).joined(separator: "\n")
        case .missingTrack(let name): "Missing track: \(name)"
        case .exportUnavailable: "Export session could not be created"
        }
    }
}

nonisolated struct CompingCompositionBuilder {
    struct Output {
        let composition: AVMutableComposition
        let audioMix: AVMutableAudioMix
        let videoComposition: AVMutableVideoComposition
    }

    static let timescale: CMTimeScale = 48_000
    /// Linear pieces per crossfade ramp: AVAudioMix only ramps linearly, so the equal-power
    /// (sine/cosine) curve is approximated.
    static let fadeSteps = 8

    func build(_ plan: CompingCompositionPlan) async throws -> Output {
        let raw = AVURLAsset(url: plan.rawVideoURL)
        guard let rawVideo = try await raw.loadTracks(withMediaType: .video).first else {
            throw CompingError.missingTrack("raw video")
        }
        guard let rawAudio = try await raw.loadTracks(withMediaType: .audio).first else {
            throw CompingError.missingTrack("raw audio")
        }
        let instrumentalAsset = AVURLAsset(url: plan.instrumentalURL)
        guard let instrumental = try await instrumentalAsset.loadTracks(withMediaType: .audio).first else {
            throw CompingError.missingTrack("instrumental")
        }

        let composition = AVMutableComposition()
        guard let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vocalA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vocalB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let instrumentalTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompingError.missingTrack("composition track")
        }
        let (transform, naturalSize, frameRate, formats) = try await rawVideo.load(.preferredTransform, .naturalSize,
                                                                                  .nominalFrameRate, .formatDescriptions)
        let videoTracks = [videoA, videoB]
        let vocalTracks = [vocalA, vocalB]
        let vocalParameters = vocalTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0, at: .zero)
            return parameters
        }

        let handle = plan.crossfadeDuration.seconds
        let halfFade = handle / 2
        let lastIndex = plan.validTakes.count - 1

        for (position, take) in plan.validTakes.enumerated() {
            let segment = plan.segments[take.segmentIndex]
            // Where the segment itself starts inside the raw file (the take range includes the handles).
            let segmentStartInRaw = take.videoTimeRange.start.seconds + handle

            // No handle before the first take (song starts at 0) or after the last one (song ends at endTime).
            let lead = position == 0 ? 0 : handle
            let tail = position == lastIndex ? 0 : handle
            let source = CMTimeRange(start: time(segmentStartInRaw - lead), duration: time(segment.audioDuration + lead + tail))
            try videoTracks[position % 2].insertTimeRange(source, of: rawVideo, at: time(segment.audioStartTime - lead))
            try vocalTracks[position % 2].insertTimeRange(source, of: rawAudio, at: time(segment.audioStartTime - lead))

            // Crossfade window is centered on each boundary.
            let parameters = vocalParameters[position % 2]
            if position == 0 {
                parameters.setVolume(plan.vocalGain, at: .zero)
            } else {
                fade(parameters, in: true, gain: plan.vocalGain, from: segment.audioStartTime - halfFade, duration: handle)
            }
            if position < lastIndex {
                fade(parameters, in: false, gain: plan.vocalGain, from: segment.audioEndTime - halfFade, duration: handle)
            }
        }

        let instrumentalDuration = try await instrumentalAsset.load(.duration).seconds
        try instrumentalTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: time(min(plan.endTime, instrumentalDuration))),
            of: instrumental, at: .zero)
        let instrumentalParameters = AVMutableAudioMixInputParameters(track: instrumentalTrack)
        instrumentalParameters.setVolume(plan.instrumentalGain, at: .zero)
        if plan.instrumentalFadeOut > 0 {
            let fadeStart = max(0, plan.endTime - plan.instrumentalFadeOut)
            instrumentalParameters.setVolumeRamp(fromStartVolume: plan.instrumentalGain, toEndVolume: 0,
                                                 timeRange: CMTimeRange(start: time(fadeStart), end: time(plan.endTime)))
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = vocalParameters + [instrumentalParameters]
        let videoComposition = dissolves(plan, tracks: videoTracks, duration: composition.duration,
                                         transform: transform, naturalSize: naturalSize, frameRate: frameRate)
        // Keep the recording's own colour space (camera files are tagged, e.g. BT.709 or HLG), so the
        // dissolve doesn't convert every frame on export.
        if let extensions = formats.first.flatMap({ CMFormatDescriptionGetExtensions($0) as? [String: Any] }) {
            videoComposition.colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
            videoComposition.colorTransferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
            videoComposition.colorYCbCrMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String
        }
        return Output(composition: composition, audioMix: audioMix, videoComposition: videoComposition)
    }

    /// One take at a time, and a dissolve (outgoing take fading out over the incoming one) centred on
    /// every boundary. The raw transform keeps the portrait orientation and mirroring.
    private func dissolves(_ plan: CompingCompositionPlan, tracks: [AVMutableCompositionTrack], duration: CMTime,
                           transform: CGAffineTransform, naturalSize: CGSize, frameRate: Float) -> AVMutableVideoComposition {
        let halfFade = plan.crossfadeDuration.seconds / 2
        let boundaries = plan.validTakes.dropLast().map { plan.segments[$0.segmentIndex].audioEndTime }
        func layer(_ track: AVMutableCompositionTrack) -> AVMutableVideoCompositionLayerInstruction {
            let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            instruction.setTransform(transform, at: .zero)
            return instruction
        }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        func add(_ range: CMTimeRange, _ layers: [AVMutableVideoCompositionLayerInstruction]) {
            guard range.duration > .zero else { return }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }
        var start = CMTime.zero
        for (position, boundary) in boundaries.enumerated() {
            let fadeStart = time(boundary - halfFade), fadeEnd = time(boundary + halfFade)
            add(CMTimeRange(start: start, end: fadeStart), [layer(tracks[position % 2])])
            let outgoing = layer(tracks[position % 2])
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: fadeStart, end: fadeEnd))
            add(CMTimeRange(start: fadeStart, end: fadeEnd), [outgoing, layer(tracks[(position + 1) % 2])])
            start = fadeEnd
        }
        add(CMTimeRange(start: start, end: duration), [layer(tracks[boundaries.count % 2])])

        let video = AVMutableVideoComposition()
        video.instructions = instructions
        let rendered = CGRect(origin: .zero, size: naturalSize).applying(transform)
        video.renderSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? frameRate.rounded() : 30))
        return video
    }

    /// Equal-power fade (sine in / cosine out), as `fadeSteps` linear ramps.
    private func fade(_ parameters: AVMutableAudioMixInputParameters, in fadeIn: Bool, gain: Float,
                      from start: TimeInterval, duration: TimeInterval) {
        func level(_ step: Int) -> Float {
            let x = Double(step) / Double(Self.fadeSteps)
            return gain * Float(fadeIn ? sin(x * .pi / 2) : cos(x * .pi / 2))
        }
        let step = duration / Double(Self.fadeSteps)
        for index in 0..<Self.fadeSteps {
            parameters.setVolumeRamp(fromStartVolume: level(index), toEndVolume: level(index + 1),
                                     timeRange: CMTimeRange(start: time(start + Double(index) * step), duration: time(step)))
        }
    }

    private func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: Self.timescale)
    }
}
