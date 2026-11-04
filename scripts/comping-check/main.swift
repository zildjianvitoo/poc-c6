//
//  main.swift
//  comping-check
//
//  Compiled with poc-c6/Domain and poc-c6/Data/Composition by scripts/check-comping.sh.
//  Builds a synthetic raw recording whose frames and audio encode their own raw time,
//  runs the real comping code on the Mac, and checks the result (PRD §10.2–10.4, §10.7),
//  including the video dissolve and vocal crossfade at each cut.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

// MARK: - Setup

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
    .appendingPathComponent("comping-check", isDirectory: true)
try? FileManager.default.removeItem(at: outputDirectory)
try! FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let frameRate = 30
let sampleRate = 48_000.0
let rawDuration = 30.0
let crossfade = PoCConfiguration.default.crossfade
let segments = DomainFixtures.segments            // 0–6, 6–9, 9–16 s
// Fractional starts so the 440 Hz tone has a different phase in every take (a hard cut would jump).
let takeStartsInRaw: [TimeInterval] = [4.0, 15.37, 21.71] // where each segment was sung in the raw file
let beat = 0.5

var failures = 0
func check(_ name: String, _ passed: Bool, _ detail: String) {
    if !passed { failures += 1 }
    print("\(passed ? "PASS" : "FAIL")  \(name) — \(detail)")
}

/// Song beats that are clearly inside a segment (not on a boundary).
let clickSongTimes: [TimeInterval] = stride(from: 0.0, to: 16.0, by: beat).filter { time in
    segments.allSatisfy { abs(time - $0.audioStartTime) > 0.1 && abs(time - $0.audioEndTime) > 0.1 }
}

func rawTime(forSongTime songTime: TimeInterval) -> TimeInterval? {
    guard let segment = segments.first(where: { songTime >= $0.audioStartTime && songTime < $0.audioEndTime }) else { return nil }
    return takeStartsInRaw[segment.index] + (songTime - segment.audioStartTime)
}

// MARK: - Synthetic raw recording

/// Frame index is encoded in the red and green channels in steps of 8 so it survives H.264.
/// `landscape` mimics devices whose camera delivers sensor-orientation frames: 480×270 stored
/// with a 90° portrait transform (CaptureRepositoryImpl.makeVideoInput).
func writeRawVideo(to url: URL, landscape: Bool = false) async throws {
    let width = landscape ? 480 : 270, height = landscape ? 270 : 480
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
    ])
    if landscape { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    for index in 0..<Int(rawDuration) * frameRate {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let red = UInt8((index % 32) * 8), green = UInt8((index / 32) * 8)
        for row in 0..<height {
            for column in 0..<width {
                let pixel = base + row * bytesPerRow + column * 4
                pixel[0] = 128; pixel[1] = green; pixel[2] = red; pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if let error = writer.error { throw error }
}

func writeWAV(_ samples: [Float], to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

/// A continuous 440 Hz tone (phase differs at every take, so a hard cut would jump)
/// plus a 2 ms click at the raw time of every inner song beat.
func rawAudio() -> [Float] {
    var samples = (0..<Int(rawDuration * sampleRate)).map { 0.3 * Float(sin(2 * .pi * 440 * Double($0) / sampleRate)) }
    for songTime in clickSongTimes {
        guard let raw = rawTime(forSongTime: songTime) else { continue }
        let start = Int(raw * sampleRate)
        for offset in 0..<Int(0.002 * sampleRate) { samples[start + offset] = 0.9 }
    }
    return samples
}

func muxRawRecording(video: URL, audio: URL, to url: URL) async throws {
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: rawDuration, preferredTimescale: 600))
    let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video)[0]
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
    videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
    try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(range, of: try await audioAsset.loadTracks(withMediaType: .audio)[0], at: .zero)
    let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
    try await session.export(to: url, as: .mov)
}

// MARK: - Plan

func plan(takeCount: Int, rawURL: URL, instrumentalURL: URL, instrumentalGain: Float) -> CompingCompositionPlan {
    let takes = (0..<takeCount).map { index in
        TakeAttemptLog(segmentIndex: index, attemptNumber: index + 1,
                       videoTimeRange: CMTimeRange(start: CMTime(seconds: takeStartsInRaw[index] - crossfade, preferredTimescale: 48_000),
                                                   duration: CMTime(seconds: segments[index].audioDuration + 2 * crossfade, preferredTimescale: 48_000)),
                       accuracyScore: 0.9, missedNoteIDs: [], status: .passed)
    }
    let isPartial = takeCount < segments.count
    return CompingCompositionPlan(rawVideoURL: rawURL, instrumentalURL: instrumentalURL, segments: segments,
                                  validTakes: takes, endTime: segments[takeCount - 1].audioEndTime,
                                  crossfadeDuration: CMTime(seconds: crossfade, preferredTimescale: 48_000),
                                  instrumentalFadeOut: isPartial ? 1.0 : 0, vocalGain: 1.0, instrumentalGain: instrumentalGain)
}

// MARK: - Reading the result back

/// Centre pixel (RGB) of every frame, by presentation time. Read straight from the decoder:
/// image generators colour-manage tagged (exported) and untagged (synthetic raw) files differently.
func centerColors(_ asset: AVAsset) async throws -> [(time: TimeInterval, rgb: [Int])] {
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    reader.startReading()
    var frames: [(TimeInterval, [Int])] = []
    while let buffer = output.copyNextSampleBuffer(), let pixels = CMSampleBufferGetImageBuffer(buffer) {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let row = CVPixelBufferGetBytesPerRow(pixels)
        let center = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            + CVPixelBufferGetHeight(pixels) / 2 * row + CVPixelBufferGetWidth(pixels) / 2 * 4
        frames.append((CMSampleBufferGetPresentationTimeStamp(buffer).seconds, [Int(center[2]), Int(center[1]), Int(center[0])]))
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
    }
    return frames
}

func color(at seconds: TimeInterval, in frames: [(time: TimeInterval, rgb: [Int])]) -> [Int] {
    frames.min { abs($0.time - seconds) < abs($1.time - seconds) }!.rgb
}

func distance(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).map { abs($0 - $1) }.reduce(0, +) }

func decodeAudio(_ asset: AVAsset) async throws -> [Float] {
    let track = try await asset.loadTracks(withMediaType: .audio)[0]
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
    ])
    reader.add(output)
    reader.startReading()
    var samples: [Float] = []
    while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
        samples += chunk
    }
    return samples
}

func clickTimes(in samples: [Float]) -> [TimeInterval] {
    var times: [TimeInterval] = []
    var lastIndex = -Int(sampleRate)
    for (index, value) in samples.enumerated() where value > 0.6 && index - lastIndex > Int(0.05 * sampleRate) {
        times.append(Double(index) / sampleRate)
        lastIndex = index
    }
    return times
}

func maxStep(in samples: [Float], around seconds: TimeInterval, window: TimeInterval) -> Float {
    let start = max(1, Int((seconds - window) * sampleRate)), end = min(samples.count, Int((seconds + window) * sampleRate))
    return (start..<end).map { abs(samples[$0] - samples[$0 - 1]) }.max() ?? 0
}

// MARK: - Run

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        let videoURL = outputDirectory.appendingPathComponent("raw-video.mov")
        let audioURL = outputDirectory.appendingPathComponent("raw-audio.wav")
        let rawURL = outputDirectory.appendingPathComponent("RawMasterVideo.mov")
        let instrumentalURL = outputDirectory.appendingPathComponent("instrumental.wav")
        try await writeRawVideo(to: videoURL)
        try writeWAV(rawAudio(), to: audioURL)
        try writeWAV((0..<Int(16 * sampleRate)).map { 0.2 * Float(sin(2 * .pi * 110 * Double($0) / sampleRate)) }, to: instrumentalURL)
        try await muxRawRecording(video: videoURL, audio: audioURL, to: rawURL)
        print("Synthetic raw recording ready.\n")

        // Full export, vocal only, so clicks and crossfades can be measured.
        let fullDirectory = outputDirectory.appendingPathComponent("full", isDirectory: true)
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        let started = Date()
        let fullURL = try await VideoCompositionRepositoryImpl(outputURL: fullDirectory.appendingPathComponent("FinalCoverVideo.mp4"))
            .stitchAndExport(plan: plan(takeCount: 3, rawURL: rawURL, instrumentalURL: instrumentalURL, instrumentalGain: 0)) { _ in }
        let exportSeconds = Date().timeIntervalSince(started)
        let full = AVURLAsset(url: fullURL)

        let duration = try await full.load(.duration).seconds
        check("duration", abs(duration - 16) < 0.05, String(format: "%.3f s (expected 16.000)", duration))
        check("export time", exportSeconds < 32, String(format: "%.1f s for a 16 s clip (limit 2×)", exportSeconds))

        // Compare each output frame with the raw frames around where it should come from (every raw
        // frame has its own colour; the YUV round trip moves colours by a few levels).
        let rawFrames = try await centerColors(AVURLAsset(url: rawURL))
        let fullFrames = try await centerColors(full)
        let sameFrame = 12
        var worstFrameError = 0
        // Just outside each dissolve (crossfade / 2 either side of the 6 s and 9 s cuts).
        let edge = crossfade / 2 + 1.5 / Double(frameRate)
        for songTime in [0.5, 3.3, 6 - edge, 6 + edge, 7.5, 9 - edge, 9 + edge, 12.0, 15.8] {
            let expectedRaw = rawTime(forSongTime: songTime)!
            let actual = color(at: songTime, in: fullFrames)
            let matchedOffset = [0, -1, 1, -2, 2].first { offset in
                distance(color(at: expectedRaw + Double(offset) / Double(frameRate), in: rawFrames), actual) <= sameFrame
            }
            worstFrameError = max(worstFrameError, matchedOffset.map(abs) ?? 99)
        }
        check("cut accuracy", worstFrameError <= 1, "worst error \(worstFrameError) frame(s) over 9 probes, incl. both sides of each cut")

        // Dissolve: the frame on a cut is a mix of the outgoing and the incoming take.
        let dissolveErrors = [6.0, 9.0].map { cut -> (blend: Int, outgoing: Int, incoming: Int) in
            let index = segments.firstIndex { abs($0.audioEndTime - cut) < 1e-6 }!
            let outgoing = color(at: takeStartsInRaw[index] + segments[index].audioDuration, in: rawFrames)
            let incoming = color(at: takeStartsInRaw[index + 1], in: rawFrames)
            let actual = color(at: cut, in: fullFrames)
            let mix = zip(outgoing, incoming).map { ($0 + $1) / 2 }
            return (distance(actual, mix), distance(actual, outgoing), distance(actual, incoming))
        }
        check("video dissolve", dissolveErrors.allSatisfy { $0.blend < min($0.outgoing, $0.incoming) },
              "frame on each cut is closer to the A/B mix than to either take: " + dissolveErrors.map {
                  "mix \($0.blend) vs A \($0.outgoing) / B \($0.incoming)" }.joined(separator: ", "))

        let audio = try await decodeAudio(full)
        let found = clickTimes(in: audio)
        let errors = clickSongTimes.map { expected in found.map { abs($0 - expected) }.min() ?? .infinity }
        let worstSync = (errors.max() ?? .infinity) * 1000
        check("vocal sync", found.count == clickSongTimes.count && worstSync < 5,
              String(format: "%d/%d beats found, worst offset %.1f ms (limit 5 ms; PRD target < 40 ms)", found.count, clickSongTimes.count, worstSync))

        let baseline = maxStep(in: audio, around: 3.25, window: 0.02)
        let boundarySteps = [6.0, 9.0].map { maxStep(in: audio, around: $0, window: 0.03) }
        check("no clicks at cuts", boundarySteps.allSatisfy { $0 < 0.08 },
              String(format: "max sample step at cuts %.3f / %.3f (baseline %.3f, a hard cut would be ~0.3–0.6)", boundarySteps[0], boundarySteps[1], baseline))

        // Partial export: 2 of 3 segments with the instrumental fading out.
        let partialDirectory = outputDirectory.appendingPathComponent("partial", isDirectory: true)
        try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
        let partialURL = try await VideoCompositionRepositoryImpl(outputURL: partialDirectory.appendingPathComponent("FinalCoverVideo.mp4"))
            .stitchAndExport(plan: plan(takeCount: 2, rawURL: rawURL, instrumentalURL: instrumentalURL, instrumentalGain: 0.8)) { _ in }
        let partialDuration = try await AVURLAsset(url: partialURL).load(.duration).seconds
        check("partial export", abs(partialDuration - 9) < 0.05, String(format: "%.3f s (expected 9.000)", partialDuration))

        // Orientation: portrait raw stays portrait; landscape frames with a 90° transform
        // (devices that ignore the connection's rotation) also come out portrait, unsqueezed.
        let landscapeVideoURL = outputDirectory.appendingPathComponent("raw-video-landscape.mov")
        let landscapeRawURL = outputDirectory.appendingPathComponent("RawMasterVideo-landscape.mov")
        try await writeRawVideo(to: landscapeVideoURL, landscape: true)
        try await muxRawRecording(video: landscapeVideoURL, audio: audioURL, to: landscapeRawURL)
        let rotatedDirectory = outputDirectory.appendingPathComponent("rotated", isDirectory: true)
        try FileManager.default.createDirectory(at: rotatedDirectory, withIntermediateDirectories: true)
        let rotatedURL = try await VideoCompositionRepositoryImpl(outputURL: rotatedDirectory.appendingPathComponent("FinalCoverVideo.mp4"))
            .stitchAndExport(plan: plan(takeCount: 3, rawURL: landscapeRawURL, instrumentalURL: instrumentalURL, instrumentalGain: 0.8)) { _ in }
        func displaySize(_ url: URL) async throws -> CGSize {
            let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)[0]
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            let shown = size.applying(transform)
            return CGSize(width: abs(shown.width), height: abs(shown.height))
        }
        let portraitShown = try await displaySize(fullURL), rotatedShown = try await displaySize(rotatedURL)
        let ratio = { (size: CGSize) in size.height / size.width }
        check("portrait output", abs(ratio(portraitShown) - 16.0 / 9) < 0.02 && abs(ratio(rotatedShown) - 16.0 / 9) < 0.02,
              String(format: "shown as %.0f×%.0f and %.0f×%.0f (landscape raw + 90° transform); expected 9:16",
                     portraitShown.width, portraitShown.height, rotatedShown.width, rotatedShown.height))

        print("\nOutput: \(fullURL.path)")
    } catch {
        failures += 1
        print("FAIL  error — \(error)")
    }
    semaphore.signal()
}
semaphore.wait()
print(failures == 0 ? "\nAll comping checks passed." : "\n\(failures) comping check(s) failed.")
exit(failures == 0 ? 0 : 1)
