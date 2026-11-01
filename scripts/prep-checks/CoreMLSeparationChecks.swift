//
//  CoreMLSeparationChecks.swift
//  poc-c6
//
//  Checks for CoreMLStemSeparationRepository (Track B) and the separation selector.
//  Separation quality on a real song is measured separately (docs/test-reports/coreml-spike-2026-11-01.md).
//

import AVFoundation

nonisolated enum CoreMLSeparationChecks {
    static func run(separationModelURL: URL) async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "CoreMLSeparation", message: message) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreml-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 25 s stereo "song" at 44.1 kHz: a voice-like harmonic tone in the centre, chords at the sides.
        let rate = 44_100.0, length = Int(25 * rate)
        var left = [Float](repeating: 0, count: length), right = left
        for i in 0..<length {
            let t = Double(i) / rate
            let voice = (1...6).reduce(Float(0)) { $0 + Float(0.25 / Double($1) * sin(2 * .pi * 220 * Double($1) * t * (1 + 0.003 * sin(2 * .pi * 5 * t)))) }
            left[i] = voice + 0.1 * Float(sin(2 * .pi * 130.8 * t))
            right[i] = voice + 0.1 * Float(sin(2 * .pi * 164.8 * t))
        }
        let songURL = directory.appendingPathComponent("song.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
        buffer.frameLength = AVAudioFrameCount(length)
        left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: length) }
        right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: length) }
        try AVAudioFile(forWriting: songURL, settings: format.settings).write(from: buffer)

        let repository = CoreMLStemSeparationRepository(modelURL: separationModelURL, directory: directory.appendingPathComponent("cache"))
        let started = Date()
        let stems = try await repository.separateStems(from: songURL, trimRange: 2...22)
        let seconds = Date().timeIntervalSince(started)
        try check(stems.method == .coreML, "method is coreML")
        func read(_ url: URL) throws -> [[Float]] {
            let file = try AVAudioFile(forReading: url)
            let channels = Int(file.processingFormat.channelCount)
            var result = [[Float]](repeating: [], count: channels)
            let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
            while file.framePosition < file.length {
                try file.read(into: b, frameCount: 65_536)
                guard b.frameLength > 0 else { break }
                for c in 0..<channels { result[c] += UnsafeBufferPointer(start: b.floatChannelData![c], count: Int(b.frameLength)) }
            }
            return result
        }
        let mix = try read(stems.mixURL), vocals = try read(stems.vocalGuideURL), instrumental = try read(stems.instrumentalURL)
        try check(mix[0].count == 882_000 && vocals[0].count == 882_000 && instrumental[0].count == 882_000, "20.000 s, sample-exact lengths: \(mix[0].count) \(vocals[0].count) \(instrumental[0].count)")
        try check(mix.count == 2 && instrumental.count == 2 && vocals.count == 1, "stereo mix/instrumental, mono vocal guide")
        try check(instrumental.allSatisfy { $0.allSatisfy(\.isFinite) } && vocals[0].allSatisfy(\.isFinite), "no NaN/inf")
        let mixStart = Int(2 * rate)
        try check(zip(mix[0].prefix(1000), left[mixStart..<(mixStart + 1000)]).allSatisfy { abs($0 - $1) < 1e-4 }, "mix is the trimmed original")
        let energy = { (x: [Float]) in x.reduce(0) { $0 + Double($1 * $1) } }
        try check(energy(instrumental[0]) < energy(mix[0]), "instrumental has less energy than the mix")
        try check(seconds < 10, String(format: "20 s separated in %.2f s", seconds))
        let again = Date()
        _ = try await repository.separateStems(from: songURL, trimRange: 2...22)
        try check(Date().timeIntervalSince(again) < 0.5, "second call reuses the cache")
        do {
            _ = try await repository.separateStems(from: songURL, trimRange: 10...40)
            try check(false, "trim past the end must throw")
        } catch CoreMLSeparationError.invalidTrim { count += 1 }

        // Selector: model missing → center-channel fallback; flag off → center-channel.
        let missing = CoreMLStemSeparationRepository(modelURL: directory.appendingPathComponent("missing.mlmodelc"),
                                                     directory: directory.appendingPathComponent("cache2"))
        let center = CenterChannelStemRepository(directory: directory.appendingPathComponent("center"))
        let fallback = try await SelectingStemSeparationRepository(coreML: missing, centerChannel: center, useCoreML: { true })
            .separateStems(from: songURL, trimRange: 2...22)
        try check(fallback.method == .centerChannelCancellation, "missing model falls back to center-channel")
        let off = try await SelectingStemSeparationRepository(coreML: repository, centerChannel: center, useCoreML: { false })
            .separateStems(from: songURL, trimRange: 2...22)
        try check(off.method == .centerChannelCancellation, "flag off uses center-channel")
        print(String(format: "  coreml: 20 s in %.2f s", seconds))
        return count
    }
}
