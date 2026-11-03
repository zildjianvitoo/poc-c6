//
//  AudioExcerptRenderer.swift
//  poc-c6
//

import AVFoundation

/// Copies the original instrumental's exact PCM frame interval, without synthesising music.
nonisolated struct AudioExcerptRenderer: Sendable {
    func render(_ url: URL, excerpt: ClosedRange<TimeInterval>) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let start = AVAudioFramePosition((excerpt.lowerBound * format.sampleRate).rounded())
        let end = min(input.length, AVAudioFramePosition((excerpt.upperBound * format.sampleRate).rounded()))
        guard start >= 0, end > start,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(min(end - start, 4096))) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("key-preview-\(UUID().uuidString).caf")
        do {
            let output = try AVAudioFile(forWriting: outputURL, settings: format.settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            input.framePosition = start
            while input.framePosition < end {
                try Task.checkCancellation()
                try input.read(into: buffer, frameCount: AVAudioFrameCount(min(end - input.framePosition, AVAudioFramePosition(buffer.frameCapacity))))
                guard buffer.frameLength > 0 else { throw CocoaError(.fileReadCorruptFile) }
                try output.write(from: buffer)
            }
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
