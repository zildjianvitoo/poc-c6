//
//  PitchFrameBuffer.swift
//  poc-c6
//

import Foundation

/// Serial-worker storage. Discontinuities are never joined into an artificial waveform.
nonisolated struct PitchFrameBuffer {
    var configuration = PoCConfiguration.default
    private var samples: [Float] = []
    private var origin = 0.0
    private var rate = 0.0
    private var expectedStart: Double?
    /// Analysis window length: 4096 samples at 48 kHz (~85 ms), enough for CREPE's 64 ms frame.
    static let windowDuration: TimeInterval = 4096.0 / 48_000

    mutating func append(_ input: [Float], sampleRate: Double, start: Double) -> [(samples: [Float], start: Double)] {
        guard sampleRate.isFinite, sampleRate > 0, start.isFinite, !input.isEmpty else { return [] }
        let timestampTolerance = max(2 / sampleRate, configuration.pitchTimestampJitterTolerance)
        if rate != sampleRate || expectedStart.map({ abs($0 - start) > timestampTolerance }) ?? true {
            samples.removeAll(keepingCapacity: true)
            origin = start
        }
        rate = sampleRate
        samples.append(contentsOf: input)
        // Anchor to accumulated sample counts, not each jittered timestamp. This prevents
        // a sequence of small timestamp errors from accumulating into clock drift.
        expectedStart = origin + Double(samples.count) / rate
        let window = Int((rate * Self.windowDuration).rounded(.up))
        let hop = max(1, Int((rate * PoCConfiguration.default.pitchHop).rounded()))
        var frames: [(samples: [Float], start: Double)] = []
        while samples.count >= window {
            frames.append((Array(samples.prefix(window)), origin))
            samples.removeFirst(hop)
            origin += Double(hop) / rate
        }
        return frames
    }
}
