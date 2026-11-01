//
//  PitchFrameBuffer.swift
//  poc-c6
//

import Foundation

/// Serial-worker storage. Discontinuities are never joined into an artificial waveform.
nonisolated struct PitchFrameBuffer {
    private var samples: [Float] = []
    private var origin = 0.0
    private var rate = 0.0
    private var expectedStart: Double?

    mutating func append(_ input: [Float], sampleRate: Double, start: Double) -> [(samples: [Float], start: Double)] {
        guard sampleRate.isFinite, sampleRate > 0, start.isFinite, !input.isEmpty else { return [] }
        if rate != sampleRate || expectedStart.map({ abs($0 - start) > 2 / sampleRate }) ?? true {
            samples.removeAll(keepingCapacity: true)
            origin = start
        }
        rate = sampleRate
        expectedStart = start + Double(input.count) / rate
        samples.append(contentsOf: input)
        let window = Int((rate * Double(PracticeConfiguration.captureBufferSize) / PracticeConfiguration.preferredSampleRate).rounded(.up))
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
