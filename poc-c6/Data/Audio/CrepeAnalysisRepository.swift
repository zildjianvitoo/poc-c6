//
//  CrepeAnalysisRepository.swift
//  poc-c6
//
//  Guide extraction fallback (PRD §5.3): reads the trimmed vocal guide, runs CREPE every
//  50 ms and reduces the pitch track to notes with ExtractGuideNotesUseCase.
//

import AVFoundation
import Foundation

nonisolated struct CrepeAnalysisRepository: AudioAnalysisRepository {
    /// Analysis window: 4096 samples at 48 kHz (~85 ms), the same as the live path.
    static let windowDuration: TimeInterval = 4096.0 / 48_000

    /// Frames quieter than this fraction of the track's loud level (90th percentile RMS, about -12 dB)
    /// are treated as unvoiced, so a quiet bass or bleed under the gaps is not mistaken for the melody.
    static let relativeLevelGate = 0.25
    static let loudLevelPercentile = 0.9

    private let modelURL: URL?
    private let hop: TimeInterval

    /// `modelURL` nil = `CrepeTiny.mlmodelc` from the app bundle.
    init(modelURL: URL? = nil, hop: TimeInterval = PoCConfiguration.default.pitchHop) {
        self.modelURL = modelURL
        self.hop = hop
    }

    func extractVocalGuideNotes(from vocalGuideURL: URL) async throws -> [TargetMIDINote] {
        let modelURL = modelURL
        let hop = hop
        return try await Task.detached(priority: .userInitiated) {
            try Self.extract(from: vocalGuideURL, modelURL: modelURL, hop: hop)
        }.value
    }

    private static func extract(from url: URL, modelURL: URL?, hop: TimeInterval) throws -> [TargetMIDINote] {
        let detector: CrepePitchDetector
        do {
            detector = try CrepePitchDetector(modelURL: modelURL)
        } catch {
            throw NSError(
                domain: "CrepeAnalysis", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CREPE model could not be loaded: \(error.localizedDescription)"])
        }
        let (samples, rate) = try readMono(url)
        guard rate > 0 else { return [] }
        let window = Int((rate * windowDuration).rounded(.up))
        let step = max(1, Int((rate * hop).rounded()))
        guard samples.count >= window else { return [] }

        var estimates: [(time: TimeInterval, estimate: CrepeEstimate)] = []
        var start = 0
        while start + window <= samples.count {
            try Task.checkCancellation()
            let estimate = try detector.analyze(Array(samples[start..<(start + window)]), sampleRate: rate)
            let time = Double(start) / rate + estimate.centerOffset
            estimates.append((time, estimate))
            start += step
        }
        let levels = estimates.map(\.estimate.rms).sorted()
        let loud = levels.isEmpty ? 0 : levels[min(levels.count - 1, Int(Double(levels.count) * loudLevelPercentile))]
        let frames = estimates.map { time, estimate -> GuidePitchFrame in
            let audible = estimate.rms >= loud * relativeLevelGate
            let midi = audible ? estimate.frequency.flatMap(PitchMath.midi(fromFrequency:)).map(Float.init) : nil
            return GuidePitchFrame(time: time, midi: midi, confidence: estimate.confidence)
        }
        return ExtractGuideNotesUseCase(hop: hop).execute(frames: frames)
    }

    /// Whole file as mono float (channels averaged).
    private static func readMono(_ url: URL) throws -> (samples: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let length = AVAudioFrameCount(file.length)
        guard length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length) else {
            return ([], format.sampleRate)
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return ([], format.sampleRate) }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channels[0], count: count)), format.sampleRate)
        }
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for i in 0..<count { mono[i] += data[i] }
        }
        let scale = 1 / Float(channelCount)
        for i in 0..<count { mono[i] *= scale }
        return (mono, format.sampleRate)
    }
}
