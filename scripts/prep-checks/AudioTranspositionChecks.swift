//
//  AudioTranspositionChecks.swift
//  poc-c6
//
//  Offline checks for AudioTranspositionRepositoryImpl (docs/prd.md §5.4): pitch accuracy,
//  duration, click alignment, channel count and cache reuse. Runs on macOS (no XCTest target).
//  Throws ContractViolation on the first failure; returns the number of checks passed.
//

import AVFoundation
import Foundation

nonisolated enum AudioTranspositionChecks {
    private static let sampleRate = 44_100.0

    static func run() async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ContractViolation(contract: "AudioTransposition", message: message) }
            count += 1
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transpose-checks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = AudioTranspositionRepositoryImpl(cacheDirectory: dir.appendingPathComponent("cache"))

        let sineURL = dir.appendingPathComponent("sine.wav")
        try writeWAV(sineURL, seconds: 4, channels: 1) { t, _ in Float(0.5 * sin(2 * .pi * 440 * t)) }

        let same = try await repo.renderTransposed(sineURL, semitones: 0)
        try check(same == sineURL, "0 semitones returns same URL")

        for (semis, expected) in [(2, 440 * pow(2, 2.0 / 12)), (-5, 440 * pow(2, -5.0 / 12))] {
            let out = try await repo.renderTransposed(sineURL, semitones: semis)
            let (samples, rate, channels) = try readChannel(out, 0)
            let edge = Int(0.5 * rate)
            let freq = zeroCrossingFrequency(Array(samples[edge..<(samples.count - edge)]), rate: rate)
            let cents = 1200 * log2(freq / expected)
            print("  \(semis) st: \(String(format: "%.2f", freq)) Hz (expected \(String(format: "%.2f", expected)), \(String(format: "%+.2f", cents)) cents)")
            try check(abs(cents) <= 5, "\(semis) st frequency off by \(cents) cents")
            try check(channels == 1 && rate == sampleRate, "format preserved")
            let inLen = try AVAudioFile(forReading: sineURL).length
            let outLen = try AVAudioFile(forReading: out).length
            try check(abs(Double(outLen - inLen)) / rate <= 0.001, "duration differs: \(outLen) vs \(inLen)")
        }

        let clickURL = dir.appendingPathComponent("clicks.wav")
        let clickLength = 44
        try writeWAV(clickURL, seconds: 5, channels: 1) { t, i in
            for c in [1.0, 3.0] {
                let start = Int(c * sampleRate)
                if i >= start && i < start + clickLength { return Float(0.9 * sin(2 * .pi * 1000 * t)) }
            }
            return 0
        }
        for semis in [3, -4] {
            let out = try await repo.renderTransposed(clickURL, semitones: semis)
            let (samples, rate, _) = try readChannel(out, 0)
            for c in [1.0, 3.0] {
                let lo = Int((c - 0.25) * rate), hi = Int((c + 0.25) * rate)
                var peak = lo
                var best: Float = 0
                for i in lo..<hi where abs(samples[i]) > best { best = abs(samples[i]); peak = i }
                // Energy centroid around the loudest sample is robust to the shifted click's shape.
                var num = 0.0, den = 0.0
                for i in max(peak - 200, 0)..<min(peak + 200, samples.count) {
                    let e = Double(samples[i] * samples[i]); num += e * Double(i); den += e
                }
                let centroid = num / den / rate
                let offsetMs = (centroid - (c + Double(clickLength) / 2 / rate)) * 1000
                print("  click \(c)s at \(semis) st: offset \(String(format: "%+.3f", offsetMs)) ms")
                try check(abs(offsetMs) <= 2, "click \(c)s offset \(offsetMs) ms for \(semis) st")
            }
            let inLen = try AVAudioFile(forReading: clickURL).length
            let outLen = try AVAudioFile(forReading: out).length
            try check(inLen == outLen, "click file length \(outLen) vs \(inLen)")
        }

        let stereoURL = dir.appendingPathComponent("stereo.wav")
        try writeWAV(stereoURL, seconds: 2, channels: 2) { t, _ in Float(0.4 * sin(2 * .pi * 330 * t)) }
        let stereoOut = try await repo.renderTransposed(stereoURL, semitones: 1)
        try check(try AVAudioFile(forReading: stereoOut).processingFormat.channelCount == 2, "stereo stays stereo")

        let started = Date()
        let again = try await repo.renderTransposed(stereoURL, semitones: 1)
        let elapsed = Date().timeIntervalSince(started)
        print("  cache hit in \(String(format: "%.4f", elapsed)) s")
        try check(again == stereoOut && elapsed < 0.05, "second call hits cache")

        do {
            _ = try await repo.renderTransposed(sineURL, semitones: 7)
            try check(false, "7 st must throw")
        } catch is AudioTranspositionError { count += 1 }
        do {
            _ = try await repo.renderTransposed(dir.appendingPathComponent("missing.wav"), semitones: 2)
            try check(false, "missing input must throw")
        } catch is AudioTranspositionError { count += 1 }

        return count
    }

    private static func writeWAV(_ url: URL, seconds: Double, channels: AVAudioChannelCount,
                                 sample: (Double, Int) -> Float) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let v = sample(Double(i) / sampleRate, i)
            for c in 0..<Int(channels) { buffer.floatChannelData![c][i] = v }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static func readChannel(_ url: URL, _ channel: Int) throws -> ([Float], Double, Int) {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
        return (samples, file.processingFormat.sampleRate, Int(file.processingFormat.channelCount))
    }

    /// Frequency from first to last upward zero crossing (sub-sample interpolated).
    private static func zeroCrossingFrequency(_ x: [Float], rate: Double) -> Double {
        var crossings: [Double] = []
        for i in 1..<x.count where x[i - 1] < 0 && x[i] >= 0 {
            crossings.append(Double(i - 1) + Double(-x[i - 1] / (x[i] - x[i - 1])))
        }
        guard crossings.count > 1 else { return 0 }
        return Double(crossings.count - 1) * rate / (crossings.last! - crossings.first!)
    }
}
