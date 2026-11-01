//
//  CrepeAnalysisChecks.swift
//  poc-c6
//
//  Executable checks for CrepeAnalysisRepository (IK-07, PRD §5.3 CREPE fallback) on synthetic WAVs.
//  Needs the compiled model (`xcrun coremlcompiler compile poc-c6/Resources/CrepeTiny.mlmodel <dir>`). Not part of the app target.
//

import AVFoundation
import Foundation

nonisolated enum CrepeAnalysisChecks {
    static func run(modelURL: URL) async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "CrepeAnalysis", message: message) }
        }
        let rate = 48_000.0
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crepe-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
        func write(_ channels: [[Float]], name: String) throws -> URL {
            let url = directory.appendingPathComponent(name)
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count))!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(channels[0].count))!
            buffer.frameLength = AVAudioFrameCount(channels[0].count)
            for (index, samples) in channels.enumerated() {
                buffer.floatChannelData![index].update(from: samples, count: samples.count)
            }
            try file.write(from: buffer)
            return url
        }
        /// Sine melody; `notes` = (midi, start, end) in seconds. A little harmonic content and noise like a voice.
        func melody(_ notes: [(Int, Double, Double)], length: Double, noise: Float = 0.01) -> [Float] {
            var generator = SystemRandomNumberGenerator()
            var samples = (0..<Int(length * rate)).map { _ in Float.random(in: -noise...noise, using: &generator) }
            for (midi, start, end) in notes {
                let f = frequency(midi)
                for i in Int(start * rate)..<min(Int(end * rate), samples.count) {
                    let t = Double(i) / rate
                    let envelope = Float(min(1, min(t - start, end - t) / 0.01))
                    samples[i] += envelope * 0.4 * Float(sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t))
                }
            }
            return samples
        }
        func bass(length: Double, level: Float) -> [Float] {
            (0..<Int(length * rate)).map { level * Float(sin(2 * .pi * 110 * Double($0) / rate)) }
        }

        let truth: [(Int, Double, Double)] = [(60, 0.2, 1.2), (64, 1.4, 2.0), (67, 2.2, 3.4)]
        let repository = CrepeAnalysisRepository(modelURL: modelURL)
        var worstEdge = 0.0
        func verify(_ notes: [TargetMIDINote], _ label: String) throws {
            try check(notes.map(\.midiNote) == truth.map { $0.0 }, "\(label): MIDI \(notes.map(\.midiNote))")
            guard notes.count == truth.count else { return }
            for (note, expected) in zip(notes, truth) {
                let startError = abs(note.startTime - expected.1)
                let endError = abs(note.endTime - expected.2)
                worstEdge = max(worstEdge, startError, endError)
                try check(startError <= 0.06 && endError <= 0.06,
                          "\(label): bounds \(note.startTime)-\(note.endTime) vs \(expected.1)-\(expected.2)")
            }
        }

        // Clean melody (mono)
        let clean = melody(truth, length: 3.6)
        let cleanNotes = try await repository.extractVocalGuideNotes(from: try write([clean], name: "clean.wav"))
        try verify(cleanNotes, "clean")

        // Stereo, melody in the middle plus hard-panned low-level 110 Hz bass on the left
        let withBass = try write([zip(clean, bass(length: 3.6, level: 0.15)).map { $0 + $1 }, clean], name: "bass.wav")
        let bassNotes = try await repository.extractVocalGuideNotes(from: withBass)
        try verify(bassNotes, "bass")

        // Silence
        let silent = try await repository.extractVocalGuideNotes(from: try write([[Float](repeating: 0, count: Int(3 * rate))], name: "silence.wav"))
        try check(silent.isEmpty, "silence -> [] (got \(silent.count))")

        // Shorter than one analysis window
        let tiny = try await repository.extractVocalGuideNotes(from: try write([[Float](repeating: 0.1, count: 1000)], name: "tiny.wav"))
        try check(tiny.isEmpty, "too short -> []")

        // Missing model -> clear error
        do {
            _ = try await CrepeAnalysisRepository(modelURL: directory.appendingPathComponent("missing.mlmodelc"))
                .extractVocalGuideNotes(from: try write([clean], name: "again.wav"))
            try check(false, "missing model should throw")
        } catch let error as NSError where error.domain == "CrepeAnalysis" {
            try check(error.localizedDescription.contains("CREPE"), "model error is descriptive")
        }

        // Runtime on 60 s of audio (the 3.6 s melody repeated)
        var long: [Float] = []
        while long.count < Int(60 * rate) { long += clean }
        long = Array(long.prefix(Int(60 * rate)))
        let longURL = try write([long], name: "long.wav")
        let started = ContinuousClock.now
        let longNotes = try await repository.extractVocalGuideNotes(from: longURL)
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        try check(longNotes.count >= 45, "60 s: \(longNotes.count) notes")
        print("  CREPE guide extraction: worst edge error \(Int(worstEdge * 1000)) ms; 60 s of audio took \(String(format: "%.2f", seconds)) s (\(longNotes.count) notes)")

        return count
    }
}
