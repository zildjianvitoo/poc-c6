//
//  HTDemucsSeparationChecks.swift
//  poc-c6
//
//  Checks for DemucsSpectrogram, HTDemucsStemSeparationRepository and the htdemucs → Open-Unmix →
//  center-channel chain. Separation quality on a real song is measured separately
//  (docs/test-reports/htdemucs-coreml-spike-2026-11-03.md).
//

import AVFoundation

nonisolated enum HTDemucsSeparationChecks {
    static func run(htDemucsModelURL: URL, openUnmixModelURL: URL) async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "HTDemucsSeparation", message: message) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("htdemucs-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // DemucsSpectrogram: shape and a near-perfect round trip on one model window.
        let spectrogram = DemucsSpectrogram()
        let segment = HTDemucsStemSeparationRepository.segmentSamples
        // Band-limited test signal: the dropped Nyquist bin carries nothing, so the round trip is exact.
        let tones = (0..<segment).map { i -> Float in
            let t = Double(i) / 44_100
            return Float(0.3 * sin(2 * .pi * 440 * t) + 0.2 * sin(2 * .pi * 1_234 * t) + 0.1 * sin(2 * .pi * 9_000 * t))
        }
        let spectra = spectrogram.forward(tones)
        try check(spectra.count == 336 && spectra[0].real.count == DemucsSpectrogram.bins + 1,
                  "343 980 samples → 336 frames of 2048 (+ dropped Nyquist) bins, got \(spectra.count)")
        let restored = spectrogram.inverse(spectra, length: segment)
        // demucs drops 2 STFT frames at each end, so the outer ~4096 samples don't round-trip, in
        // PyTorch either (same 0.24 max error there); the network's time branch covers them.
        let edge = 4 * DemucsSpectrogram.hop
        let roundTrip = zip(tones[edge..<(segment - edge)], restored[edge..<(segment - edge)]).map { abs($0 - $1) }.max() ?? 1
        try check(restored.count == segment && roundTrip < 1e-4, String(format: "round trip max error %.2e (interior)", roundTrip))

        // 20 s stereo "song": a voice-like harmonic tone in the centre, chords at the sides. Its
        // length is not a multiple of the 5.85 s chunk stride, so the short, centred last chunk is used.
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

        let cache = directory.appendingPathComponent("htdemucs")
        let repository = HTDemucsStemSeparationRepository(modelURL: htDemucsModelURL, directory: cache)
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
        // The four sources add up to the mix, so vocals + instrumental ≈ mix (also across chunk seams).
        // htdemucs leaves ~-22 dB on this synthetic tone (-35 dB on a real song, as in PyTorch); a
        // chunk-weight or seam bug lands near 0 dB.
        let monoMix = zip(mix[0], mix[1]).map { ($0 + $1) / 2 }
        let monoInstrumental = zip(instrumental[0], instrumental[1]).map { ($0 + $1) / 2 }
        let residual = (0..<monoMix.count).map { monoMix[$0] - vocals[0][$0] - monoInstrumental[$0] }
        let residualDB = 10 * log10(energy(residual) / energy(monoMix))
        try check(residualDB < -15, String(format: "vocals + instrumental ≈ mix (residual %.1f dB)", residualDB))
        try check(seconds < 20, String(format: "20 s separated in %.2f s", seconds))
        let again = Date()
        _ = try await repository.separateStems(from: songURL, trimRange: 2...22)
        try check(Date().timeIntervalSince(again) < 0.5, "second call reuses the cache")
        do {
            _ = try await repository.separateStems(from: songURL, trimRange: 10...40)
            try check(false, "trim past the end must throw")
        } catch CoreMLSeparationError.invalidTrim { count += 1 }

        // Chain: htdemucs first; missing htdemucs → Open-Unmix; both missing → center-channel; flag off → center-channel.
        let openUnmixCache = directory.appendingPathComponent("openunmix")
        let openUnmix = CoreMLStemSeparationRepository(modelURL: openUnmixModelURL, directory: openUnmixCache)
        let center = CenterChannelStemRepository(directory: directory.appendingPathComponent("center"))
        let missingHTDemucs = HTDemucsStemSeparationRepository(modelURL: directory.appendingPathComponent("missing.mlmodelc"),
                                                               directory: directory.appendingPathComponent("missing-htdemucs"))
        let missingOpenUnmix = CoreMLStemSeparationRepository(modelURL: directory.appendingPathComponent("missing.mlmodelc"),
                                                              directory: directory.appendingPathComponent("missing-openunmix"))
        func isInside(_ url: URL, _ folder: URL) -> Bool { url.path.hasPrefix(folder.path + "/") }
        let first = try await SelectingStemSeparationRepository(coreML: openUnmix, centerChannel: center, useCoreML: { true }, htDemucs: repository)
            .separateStems(from: songURL, trimRange: 2...22)
        try check(isInside(first.vocalGuideURL, cache), "htdemucs is tried first")
        let second = try await SelectingStemSeparationRepository(coreML: openUnmix, centerChannel: center, useCoreML: { true }, htDemucs: missingHTDemucs)
            .separateStems(from: songURL, trimRange: 2...22)
        try check(second.method == .coreML && isInside(second.vocalGuideURL, openUnmixCache), "missing htdemucs falls back to Open-Unmix")
        let third = try await SelectingStemSeparationRepository(coreML: missingOpenUnmix, centerChannel: center, useCoreML: { true }, htDemucs: missingHTDemucs)
            .separateStems(from: songURL, trimRange: 2...22)
        try check(third.method == .centerChannelCancellation, "both models missing falls back to center-channel")
        let off = try await SelectingStemSeparationRepository(coreML: openUnmix, centerChannel: center, useCoreML: { false }, htDemucs: repository)
            .separateStems(from: songURL, trimRange: 2...22)
        try check(off.method == .centerChannelCancellation, "flag off uses center-channel")
        do {
            _ = try await SelectingStemSeparationRepository(coreML: openUnmix, centerChannel: center, useCoreML: { true }, htDemucs: repository)
                .separateStems(from: songURL, trimRange: 10...40)
            try check(false, "invalid trim through the chain must throw")
        } catch CoreMLSeparationError.invalidTrim { count += 1 }
        print(String(format: "  htdemucs: 20 s in %.2f s, vocals + instrumental vs mix residual %.1f dB, spectrogram round trip %.1e",
                     seconds, residualDB, roundTrip))
        return count
    }
}
