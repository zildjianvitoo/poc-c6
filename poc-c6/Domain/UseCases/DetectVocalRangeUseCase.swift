//
//  DetectVocalRangeUseCase.swift
//  poc-c6
//
//  One prompt of the vocal range test (PRD §5.1): listens until ~2 s of stable pitch
//  (every frame within ±50 cents of the run's median) and returns the median MIDI note.
//  Feed it the live PitchSamples; create a new one per prompt or retry.
//

import CoreMedia
import Foundation

nonisolated struct DetectVocalRangeUseCase: Sendable {
    /// PRD §5.1: how long the note must be held.
    static let requiredDuration: TimeInterval = 2
    /// PRD §5.1: allowed variation around the median, in semitones (±50 cents).
    static let stabilityTolerance: Float = 0.5
    /// Unvoiced gaps shorter than this (a breath, a dropped frame) do not break the run.
    static let maxGap: TimeInterval = 0.2

    private struct Frame {
        let time: TimeInterval
        let midi: Float
    }

    let configuration: PoCConfiguration
    private var frames: [Frame] = []
    private var lastVoicedTime: TimeInterval?
    /// Last voiced pitch, for the live readout.
    private(set) var latestMIDI: Float?
    /// How long the current stable run has lasted, for a progress indicator.
    private(set) var stableDuration: TimeInterval = 0
    /// Set once a note has been held long enough.
    private(set) var result: Float?

    init(configuration: PoCConfiguration = .default) {
        self.configuration = configuration
    }

    /// Returns the detected note (median MIDI) once it has been held long enough.
    @discardableResult
    mutating func ingest(_ sample: PitchSample) -> Float? {
        guard result == nil else { return result }
        let time = sample.captureTime.seconds
        guard time.isFinite else { reset(); latestMIDI = nil; return nil }
        // Callback gaps must break a hold even when no unvoiced frame was delivered.
        if let lastVoicedTime, time - lastVoicedTime > Self.maxGap || time < lastVoicedTime {
            reset()
        }
        // Repeated timestamps cannot contribute elapsed hold time.
        if time == lastVoicedTime { return nil }
        guard let frequency = sample.frequency, frequency.isFinite, frequency > 0,
              sample.rmsDecibels >= configuration.noiseGateDBFS else {
            if let lastVoicedTime, time - lastVoicedTime > Self.maxGap { reset() }
            latestMIDI = nil
            return nil
        }
        let midi = 69 + 12 * log2(frequency / 440)
        latestMIDI = midi
        lastVoicedTime = time
        frames.append(Frame(time: time, midi: midi))
        // Keep the longest recent run that stays within the tolerance of its own median.
        while let first = frames.first, !isStable(frames), first.time < time {
            frames.removeFirst()
        }
        stableDuration = (frames.last?.time ?? time) - (frames.first?.time ?? time)
        if stableDuration >= Self.requiredDuration {
            result = Self.median(frames.map(\.midi))
        }
        return result
    }

    private mutating func reset() {
        frames.removeAll()
        stableDuration = 0
        lastVoicedTime = nil
    }

    private func isStable(_ frames: [Frame]) -> Bool {
        let center = Self.median(frames.map(\.midi))
        return frames.allSatisfy { abs($0.midi - center) <= Self.stabilityTolerance }
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
