//
//  StabilizePitchDisplayUseCase.swift
//  poc-c6
//

import Foundation

/// Visual smoothing only. Raw samples still determine range stability and singing scores.
/// Within-note jitter is smoothed, but note changes are shown on their original frame.
nonisolated struct StabilizePitchDisplayUseCase: Sendable {
    var configuration: PoCConfiguration = .default
    private var lastTime: TimeInterval?
    private var displayed: Float?

    mutating func execute(midi: Float?, time: TimeInterval) -> Float? {
        guard time.isFinite else { reset(); return nil }
        if let lastTime {
            if time == lastTime { return displayed }
            if time < lastTime || time - lastTime > configuration.pitchDisplayMaximumGap { reset() }
        }
        lastTime = time
        guard let midi, midi.isFinite else { reset(); return nil }
        guard let previous = displayed else { displayed = midi; return midi }
        let difference = midi - previous
        if abs(difference) >= configuration.pitchDisplayJumpThreshold {
            displayed = midi
        } else {
            if abs(difference) > configuration.pitchDisplayDeadband {
                displayed = previous + configuration.pitchDisplaySmoothing * difference
            }
        }
        return displayed
    }

    mutating func reset() {
        lastTime = nil
        displayed = nil
    }
}
