//
//  CenterChannelChecks.swift
//  poc-c6
//
//  Mac-side checks for CenterChannelStemRepository (IK-13). No XCTest: throws ContractViolation on failure.
//  Compile: see the task notes; needs poc-c6/Domain, the repository and a main.swift that calls `run()`.
//

import AVFoundation
import Foundation

nonisolated enum CenterChannelChecks {
    private static let sampleRate = 48_000.0
    private static let vocalHz = 330.0
    private static let leftHz = 220.0
    private static let rightHz = 550.0
    private static let amplitude: Float = 0.2

    /// Returns the number of checks that passed.
    static func run() async throws -> Int {
        var count = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ContractViolation(contract: "CenterChannel", message: message) }
            count += 1
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("center-channel-checks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let repository = CenterChannelStemRepository(directory: work.appendingPathComponent("cache"))

        // 30 s stereo: centered 330 Hz, hard-left 220 Hz, hard-right 550 Hz, and a click in L at t = 5 s.
        let clickFrame = Int(5 * sampleRate)
        let input = makeStereo(seconds: 30, clickFrame: clickFrame)
        let wav = work.appendingPathComponent("input.wav")
        try writeWAV(channels: [input.left, input.right], to: wav)

        // MARK: Rejection, guide, trim
        let trim: ClosedRange<TimeInterval> = 5...20
        let stems = try await repository.separateStems(from: wav, trimRange: trim)
        try expect(stems.method == .centerChannelCancellation, "method is centerChannelCancellation")

        let mix = try readWAV(stems.mixURL)
        let guide = try readWAV(stems.vocalGuideURL)
        let instrumental = try readWAV(stems.instrumentalURL)
        let expectedFrames = Int(15 * sampleRate)
        try expect(mix.channels.count == 2 && instrumental.channels.count == 2 && guide.channels.count == 1,
                   "mix/instrumental stereo, guide mono")
        try expect(mix.channels[0].count == expectedFrames, "mix is exactly 15.000 s (\(mix.channels[0].count) frames)")
        try expect(guide.channels[0].count == expectedFrames, "guide has the same length (\(guide.channels[0].count))")
        try expect(instrumental.channels[0].count == expectedFrames, "instrumental has the same length")
        try expect(mix.sampleRate == sampleRate && guide.sampleRate == sampleRate && instrumental.sampleRate == sampleRate,
                   "source sample rate kept")
        try expect(instrumental.channels[0] == instrumental.channels[1], "instrumental channels identical")

        let mixLevels = levels(mix.channels[0])
        let instrumentalLevels = levels(instrumental.channels[0])
        let rejection = 20 * log10((mixLevels.vocal / mixLevels.left) / max(instrumentalLevels.vocal / instrumentalLevels.left, 1e-12))
        print(String(format: "  measured 330 Hz rejection (relative to mix): %.1f dB", rejection))
        try expect(rejection >= 40, "330 Hz reduced by >= 40 dB (got \(rejection) dB)")
        try expect(instrumentalLevels.left > 0.05 && instrumentalLevels.right > 0.05, "220/550 Hz remain in instrumental")

        var peak: Float = 0
        for sample in instrumental.channels[0] { peak = max(peak, abs(sample)) }
        var mixPeak: Float = 0
        for channel in mix.channels { for sample in channel { mixPeak = max(mixPeak, abs(sample)) } }
        try expect(peak <= 0.99 + 1e-4 && abs(peak - mixPeak) < 0.02, "instrumental peak \(peak) matches mix peak \(mixPeak), no clipping")

        let guideLevels = levels(guide.channels[0])
        try expect(abs(guideLevels.vocal - Double(amplitude)) < 0.2 * Double(amplitude), "vocal guide keeps 330 Hz (\(guideLevels.vocal))")

        // Trim alignment: output t = 0 equals input t = 5 s (sample-exact).
        let startFrame = Int(trim.lowerBound * sampleRate)
        try expect(Array(mix.channels[0].prefix(4_800)) == Array(input.left[startFrame..<startFrame + 4_800]),
                   "mix L at t=0 equals input L at t=5 s")
        try expect(Array(mix.channels[1].suffix(4_800)) == Array(input.right[(startFrame + expectedFrames - 4_800)..<(startFrame + expectedFrames)]),
                   "mix R end equals input R at t=20 s")
        try expect(argmaxAbs(mix.channels[0]) == 0, "click marker sits at output frame 0")

        // MARK: Cache reuse
        let before = try modificationDate(stems.instrumentalURL)
        let second = try await repository.separateStems(from: wav, trimRange: trim)
        try expect(second.mixURL == stems.mixURL && second.instrumentalURL == stems.instrumentalURL, "second call returns the same cache files")
        try expect(try modificationDate(second.instrumentalURL) == before, "second call reuses the cache (files untouched)")

        // MARK: AAC input
        let m4a = work.appendingPathComponent("input.m4a")
        try writeAAC(channels: [input.left, input.right], to: m4a)
        let aacStems = try await repository.separateStems(from: m4a, trimRange: trim)
        let aacMix = try readWAV(aacStems.mixURL)
        let aacInstrumental = try readWAV(aacStems.instrumentalURL)
        let aacGuide = try readWAV(aacStems.vocalGuideURL)
        try expect(aacMix.channels[0].count == expectedFrames && aacInstrumental.channels[0].count == expectedFrames
                   && aacGuide.channels[0].count == expectedFrames,
                   "m4a input: outputs are exactly 15.000 s (\(aacMix.channels[0].count))")
        let aacMixLevels = levels(aacMix.channels[0])
        let aacInstrumentalLevels = levels(aacInstrumental.channels[0])
        let aacRejection = 20 * log10((aacMixLevels.vocal / aacMixLevels.left) / max(aacInstrumentalLevels.vocal / aacInstrumentalLevels.left, 1e-12))
        print(String(format: "  m4a 330 Hz rejection: %.1f dB", aacRejection))
        try expect(aacRejection >= 20, "m4a: 330 Hz clearly reduced (got \(aacRejection) dB)")
        let aacClick = argmaxAbs(aacMix.channels[0])
        try expect(aacClick < 2_048, "m4a: click near output t = 0 (frame \(aacClick))")

        // MARK: Errors
        let monoSamples = makeMono(seconds: 30)
        let monoURL = work.appendingPathComponent("mono.wav")
        try writeWAV(channels: [monoSamples, monoSamples], to: monoURL)
        await expectThrows(.monoSource, "dual-mono (L = R) input", { try await repository.separateStems(from: monoURL, trimRange: 0...20) }, expect: expect)
        let monoFile = work.appendingPathComponent("mono1ch.wav")
        try writeWAV(channels: [monoSamples], to: monoFile)
        await expectThrows(.monoSource, "1-channel input", { try await repository.separateStems(from: monoFile, trimRange: 0...20) }, expect: expect)
        await expectThrows(.invalidTrim, "trim beyond duration", { try await repository.separateStems(from: wav, trimRange: 10...40) }, expect: expect)
        await expectThrows(.invalidTrim, "negative trim start", { try await repository.separateStems(from: wav, trimRange: -1...10) }, expect: expect)
        await expectThrows(.invalidTrim, "empty trim", { try await repository.separateStems(from: wav, trimRange: 10...10) }, expect: expect)
        let junk = work.appendingPathComponent("junk.wav")
        try Data("not audio".utf8).write(to: junk)
        await expectThrows(.unreadable, "garbage file", { try await repository.separateStems(from: junk, trimRange: 0...5) }, expect: expect)
        await expectThrows(.unreadable, "missing file", { try await repository.separateStems(from: work.appendingPathComponent("nope.mp3"), trimRange: 0...5) }, expect: expect)

        // MARK: Timing, 60 s stereo 48 kHz
        let long = makeStereo(seconds: 60, clickFrame: 1_000)
        let longURL = work.appendingPathComponent("long.wav")
        try writeWAV(channels: [long.left, long.right], to: longURL)
        let started = Date()
        let longStems = try await repository.separateStems(from: longURL, trimRange: 0...60)
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "  60 s stereo 48 kHz separation (cold cache): %.3f s", elapsed))
        let longGuide = try readWAV(longStems.vocalGuideURL)
        try expect(longGuide.channels[0].count == Int(60 * sampleRate), "60 s output has 60.000 s of frames")
        try expect(elapsed < 5, "60 s input processed in < 5 s (\(elapsed) s)")

        return count
    }

    // MARK: - Helpers

    private static func expectThrows(_ expected: CenterChannelError, _ label: String,
                                     _ body: () async throws -> SeparatedStems,
                                     expect: (Bool, String) throws -> Void) async {
        do {
            _ = try await body()
            try? expect(false, "\(label): expected \(expected), got success")
        } catch let error as CenterChannelError {
            try? expect(error == expected, "\(label): expected \(expected), got \(error)")
        } catch {
            try? expect(false, "\(label): expected \(expected), got \(error)")
        }
    }

    private static func makeStereo(seconds: Double, clickFrame: Int) -> (left: [Float], right: [Float]) {
        let frames = Int(seconds * sampleRate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let vocal = Float(sin(2 * .pi * vocalHz * t)) * amplitude
            left[frame] = vocal + Float(sin(2 * .pi * leftHz * t)) * amplitude
            right[frame] = vocal + Float(sin(2 * .pi * rightHz * t)) * amplitude
        }
        if clickFrame < frames { left[clickFrame] = 0.9 }
        return (left, right)
    }

    private static func makeMono(seconds: Double) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { Float(sin(2 * .pi * vocalHz * Double($0) / sampleRate)) * amplitude }
    }

    /// Tone amplitudes (Hann-windowed Goertzel) of the 330 / 220 / 550 Hz components.
    private static func levels(_ samples: [Float]) -> (vocal: Double, left: Double, right: Double) {
        // Skip edges (filter/AAC transients), analyse the middle part.
        let margin = Int(sampleRate)
        let segment = Array(samples[margin..<(samples.count - margin)])
        return (goertzel(segment, vocalHz), goertzel(segment, leftHz), goertzel(segment, rightHz))
    }

    private static func goertzel(_ samples: [Float], _ frequency: Double) -> Double {
        let count = samples.count
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var s1 = 0.0, s2 = 0.0, windowSum = 0.0
        for index in 0..<count {
            let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(count - 1))
            windowSum += window
            let s0 = Double(samples[index]) * window + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        let real = s1 - s2 * cos(omega)
        let imaginary = s2 * sin(omega)
        return 2 * (real * real + imaginary * imaginary).squareRoot() / windowSum
    }

    private static func argmaxAbs(_ samples: [Float]) -> Int {
        var best = 0
        var bestValue: Float = 0
        for (index, sample) in samples.enumerated() where abs(sample) > bestValue {
            bestValue = abs(sample)
            best = index
        }
        return best
    }

    private static func modificationDate(_ url: URL) throws -> Date {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? .distantPast
    }

    private static func writeWAV(channels: [[Float]], to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: AVAudioChannelCount(channels.count), interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer(channels, format: format))
    }

    private static func writeAAC(channels: [[Float]], to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: AVAudioChannelCount(channels.count), interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels.count,
            AVEncoderBitRateKey: 256_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer(channels, format: format))
    }

    private static func buffer(_ channels: [[Float]], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames = channels[0].count
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for (index, channel) in channels.enumerated() {
            channel.withUnsafeBufferPointer { buffer.floatChannelData![index].update(from: $0.baseAddress!, count: frames) }
        }
        return buffer
    }

    private static func readWAV(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = Int(file.length)
        let channelCount = Int(file.processingFormat.channelCount)
        var channels = [[Float]](repeating: [], count: channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else {
            throw ContractViolation(contract: "CenterChannel", message: "cannot allocate read buffer")
        }
        while file.framePosition < AVAudioFramePosition(total) {
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            for index in 0..<channelCount {
                channels[index].append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![index], count: Int(buffer.frameLength)))
            }
        }
        return (channels, file.processingFormat.sampleRate)
    }
}
