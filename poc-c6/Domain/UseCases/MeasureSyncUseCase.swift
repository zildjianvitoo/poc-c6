//
//  MeasureSyncUseCase.swift
//  poc-c6
//
//  Click test (PRD §7.1, TK-05/TK-16): clicks are played at known song times, the microphone
//  hears them, and the difference between when each click is heard on the capture clock and
//  when the playback anchor predicted it is the system's sync error. Adding the median error
//  to `manualLatencyCalibration` makes takes line up with what the singer hears.
//

import Foundation

nonisolated struct MeasureSyncUseCase: Sendable {
    /// A block of microphone samples stamped on the capture clock.
    struct AudioChunk: Sendable {
        let startTime: TimeInterval
        let sampleRate: Double
        let samples: [Float]
    }

    struct Result: Equatable, Sendable {
        /// Per click: heard − predicted, in seconds (positive = heard later than predicted).
        let errors: [TimeInterval]
        let expectedClicks: Int
        var detectedClicks: Int { errors.count }
        var medianError: TimeInterval {
            let sorted = errors.sorted()
            guard !sorted.isEmpty else { return 0 }
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        /// Max − min of the errors: a large spread means the measurement is not trustworthy.
        var spread: TimeInterval { (errors.max() ?? 0) - (errors.min() ?? 0) }
        var isReliable: Bool {
            detectedClicks * 4 >= expectedClicks * 3 && spread <= MeasureSyncUseCase.maxReliableSpread
        }
    }

    /// Clicks are searched this far around their predicted time.
    static let searchWindow: TimeInterval = 0.45
    /// Errors that disagree by more than this make the result unreliable.
    static let maxReliableSpread: TimeInterval = 0.03
    /// A click must be this many times louder than the quiet part before it.
    static let onsetRatio: Float = 6
    /// Absolute floor, so silence plus a little noise never counts as a click.
    static let minimumOnsetLevel: Float = 0.02

    /// `predicted`: capture-clock times at which each click should be heard (anchor + click time).
    func execute(predicted: [TimeInterval], chunks: [AudioChunk]) -> Result {
        var errors: [TimeInterval] = []
        for time in predicted {
            let start = time - Self.searchWindow, end = time + Self.searchWindow
            var samples: [(time: TimeInterval, level: Float)] = []
            for chunk in chunks {
                let chunkEnd = chunk.startTime + Double(chunk.samples.count) / chunk.sampleRate
                guard chunkEnd > start, chunk.startTime < end else { continue }
                for (index, value) in chunk.samples.enumerated() {
                    let sampleTime = chunk.startTime + Double(index) / chunk.sampleRate
                    if sampleTime >= start && sampleTime < end { samples.append((sampleTime, abs(value))) }
                }
            }
            samples.sort { $0.time < $1.time }
            guard samples.count > 100 else { continue }
            // Noise floor from the quietest tenth of the window.
            let levels = samples.map(\.level).sorted()
            let floor = levels[levels.count / 10]
            let threshold = max(Self.minimumOnsetLevel, floor * Self.onsetRatio)
            if let onset = samples.first(where: { $0.level >= threshold }) {
                errors.append(onset.time - time)
            }
        }
        return Result(errors: errors, expectedClicks: predicted.count)
    }
}
