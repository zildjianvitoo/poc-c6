//
//  CompingCompositionBuilder.swift
//  poc-c6
//
//  Builds the composition for the final cover (PRD §5.9). Owner: Zildjian Vito (ZV-07, ZV-08, ZV-09).
//
//  Timeline = song timeline. For every passed take:
//  - video: the segment part of the take goes to `segment.audioStartTime` (hard cut);
//  - vocal: the take plus its handles goes on vocal track A or B (alternating), so
//    neighbouring takes overlap at each boundary and can be crossfaded;
//  - instrumental: its own track from 0 to `endTime`.
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
    }

    static let timescale: CMTimeScale = 48_000

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
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vocalA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vocalB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let instrumentalTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompingError.missingTrack("composition track")
        }
        // Keeps the portrait orientation (and mirroring) of the raw recording.
        videoTrack.preferredTransform = try await rawVideo.load(.preferredTransform)

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

            try videoTrack.insertTimeRange(
                CMTimeRange(start: time(segmentStartInRaw), duration: time(segment.audioDuration)),
                of: rawVideo, at: time(segment.audioStartTime))

            // No handle before the first take (song starts at 0) or after the last one (song ends at endTime).
            let lead = position == 0 ? 0 : handle
            let tail = position == lastIndex ? 0 : handle
            let track = vocalTracks[position % 2]
            try track.insertTimeRange(
                CMTimeRange(start: time(segmentStartInRaw - lead), duration: time(segment.audioDuration + lead + tail)),
                of: rawAudio, at: time(segment.audioStartTime - lead))

            // Crossfade window is centered on each boundary.
            let parameters = vocalParameters[position % 2]
            if position == 0 {
                parameters.setVolume(plan.vocalGain, at: .zero)
            } else {
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: plan.vocalGain,
                                         timeRange: CMTimeRange(start: time(segment.audioStartTime - halfFade), duration: time(handle)))
            }
            if position < lastIndex {
                parameters.setVolumeRamp(fromStartVolume: plan.vocalGain, toEndVolume: 0,
                                         timeRange: CMTimeRange(start: time(segment.audioEndTime - halfFade), duration: time(handle)))
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
        return Output(composition: composition, audioMix: audioMix)
    }

    private func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: Self.timescale)
    }
}
