//
//  AudioTranspositionRepositoryImpl.swift
//  poc-c6
//
//  Offline pitch-shifted copy of an audio file (docs/prd.md §5.4): AVAudioEngine manual
//  rendering + AVAudioPlayerNode -> AVAudioUnitTimePitch (pitch = semitones * 100 cents).
//  The output is uncompressed CAF (float PCM, same sample rate and channel count as the input)
//  and sample-aligned with the input: the unit's processing latency is dropped from the start
//  and the length is trimmed/padded to the input length, so song-timeline times stay valid.
//

import AVFoundation
import Foundation

nonisolated enum AudioTranspositionError: Error, LocalizedError, Equatable {
    case semitonesOutOfRange(Int)
    case unreadableInput(URL)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .semitonesOutOfRange(let value):
            return "Transposition of \(value) semitones is outside \(TranspositionPlan.semitoneRange)."
        case .unreadableInput(let url):
            return "Cannot read audio file at \(url.lastPathComponent)."
        case .renderFailed(let reason):
            return "Offline pitch render failed: \(reason)"
        }
    }
}

nonisolated struct AudioTranspositionRepositoryImpl: AudioTranspositionRepository {
    private static let blockFrames: AVAudioFrameCount = 4096
    /// Extra frames rendered beyond `latency + length` so the pitch unit's tail is fully flushed.
    private static let tailSafetyFrames: AVAudioFramePosition = 8192

    private let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Transposed", isDirectory: true)
    }

    func renderTransposed(_ audioURL: URL, semitones: Int) async throws -> URL {
        guard TranspositionPlan.semitoneRange.contains(semitones) else {
            throw AudioTranspositionError.semitonesOutOfRange(semitones)
        }
        if semitones == 0 { return audioURL }
        let cacheDirectory = self.cacheDirectory
        return try await Task.detached(priority: .userInitiated) {
            try Self.render(audioURL, semitones: semitones, cacheDirectory: cacheDirectory)
        }.value
    }

    // MARK: - Rendering

    private static func render(_ audioURL: URL, semitones: Int, cacheDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        let outputURL = cacheDirectory.appendingPathComponent(cacheName(for: audioURL, semitones: semitones))
        if fileManager.fileExists(atPath: outputURL.path) { return outputURL }

        let inputFile: AVAudioFile
        do { inputFile = try AVAudioFile(forReading: audioURL) } catch {
            throw AudioTranspositionError.unreadableInput(audioURL)
        }
        let totalFrames = inputFile.length
        let format = inputFile.processingFormat
        guard totalFrames > 0 else { throw AudioTranspositionError.unreadableInput(audioURL) }

        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let partialURL = cacheDirectory.appendingPathComponent(UUID().uuidString + ".partial.caf")
        defer { try? fileManager.removeItem(at: partialURL) }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = Float(semitones * 100)
        timePitch.rate = 1
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockFrames)
            try engine.start()
        } catch {
            throw AudioTranspositionError.renderFailed("engine start: \(error.localizedDescription)")
        }
        defer { engine.stop() }

        player.scheduleFile(inputFile, at: nil)
        player.play()

        // Processing latency of the time-pitch unit (seconds -> frames), plus the mixer's own.
        let latencySeconds = timePitch.auAudioUnit.latency + engine.mainMixerNode.auAudioUnit.latency
        let latencyFrames = AVAudioFramePosition((latencySeconds * format.sampleRate).rounded())

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: blockFrames) else {
            throw AudioTranspositionError.renderFailed("buffer allocation")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(forWriting: partialURL, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioTranspositionError.renderFailed("create output: \(error.localizedDescription)")
        }

        var rendered: AVAudioFramePosition = 0
        let renderTarget = latencyFrames + totalFrames + tailSafetyFrames
        var written: AVAudioFramePosition = 0
        while written < totalFrames && rendered < renderTarget {
            let remaining = renderTarget - rendered
            let request = AVAudioFrameCount(min(AVAudioFramePosition(blockFrames), remaining))
            buffer.frameLength = 0
            let status: AVAudioEngineManualRenderingStatus
            do { status = try engine.renderOffline(request, to: buffer) } catch {
                throw AudioTranspositionError.renderFailed("render: \(error.localizedDescription)")
            }
            guard status == .success || status == .insufficientDataFromInputNode else {
                throw AudioTranspositionError.renderFailed("status \(status.rawValue)")
            }
            let produced = AVAudioFramePosition(buffer.frameLength)
            // Drop the leading latency samples, keep at most `totalFrames` after them.
            let blockStart = rendered
            rendered += produced
            let keepFrom = max(latencyFrames - blockStart, 0)
            if keepFrom >= produced { continue }
            let keepCount = min(produced - keepFrom, totalFrames - written)
            if keepCount > 0 {
                try write(buffer, from: Int(keepFrom), count: Int(keepCount), to: outputFile)
                written += keepCount
            }
        }
        // Pad with silence if the render ended short, so output length == input length.
        while written < totalFrames {
            let count = min(AVAudioFramePosition(blockFrames), totalFrames - written)
            buffer.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(format.channelCount) {
                buffer.floatChannelData![channel].update(repeating: 0, count: Int(count))
            }
            try write(buffer, from: 0, count: Int(count), to: outputFile)
            written += count
        }

        do {
            if fileManager.fileExists(atPath: outputURL.path) { return outputURL }
            try fileManager.moveItem(at: partialURL, to: outputURL)
        } catch {
            throw AudioTranspositionError.renderFailed("store output: \(error.localizedDescription)")
        }
        return outputURL
    }

    /// Writes `count` frames of `source` starting at `from` (non-interleaved float).
    private static func write(_ source: AVAudioPCMBuffer, from: Int, count: Int, to file: AVAudioFile) throws {
        guard let slice = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(count)),
              let src = source.floatChannelData, let dst = slice.floatChannelData else {
            throw AudioTranspositionError.renderFailed("slice allocation")
        }
        for channel in 0..<Int(source.format.channelCount) {
            dst[channel].update(from: src[channel] + from, count: count)
        }
        slice.frameLength = AVAudioFrameCount(count)
        do { try file.write(from: slice) } catch {
            throw AudioTranspositionError.renderFailed("write: \(error.localizedDescription)")
        }
    }

    /// Stable (process-independent) name from input path + modification date + semitones.
    private static func cacheName(for url: URL, semitones: Int) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path)|\(modified)"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "%016llx-%d.caf", hash, semitones)
    }
}
