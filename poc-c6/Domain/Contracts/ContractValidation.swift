//
//  ContractValidation.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//
//  Executable version of the handoff guarantees in docs/prd.md §12.2.
//  Producers call `validate()` before handing data over; consumers call
//  `assertValid()` when receiving it. An empty array means the contract holds.
//

import CoreMedia
import Foundation

nonisolated struct ContractViolation: Error, CustomStringConvertible, Equatable {
    let contract: String
    let message: String

    var description: String { "[\(contract)] \(message)" }
}

nonisolated enum ContractTolerance {
    /// Max gap/overlap between consecutive segments, and between song end and last segment.
    static let timeline: TimeInterval = 0.001
    /// Max difference between a take's duration and its segment duration + handles (≈ 1 frame at 30 fps).
    static let takeDuration: TimeInterval = 1.0 / 30.0
}

// MARK: - PreparedSong (Ikzaz -> Takin, Zildjian)

extension PreparedSong {
    nonisolated func validate() -> [ContractViolation] {
        let name = "PreparedSong"
        var violations: [ContractViolation] = []
        func fail(_ message: String) { violations.append(ContractViolation(contract: name, message: message)) }

        if duration < 15 - ContractTolerance.timeline || duration > 60 + ContractTolerance.timeline {
            fail("duration \(duration)s is outside 15...60s")
        }
        if !TranspositionPlan.semitoneRange.contains(transposition.semitoneShift) {
            fail("semitoneShift \(transposition.semitoneShift) is outside \(TranspositionPlan.semitoneRange)")
        }
        if !TranspositionPlan.totalRange.contains(transposition.totalSemitones) {
            fail("total shift \(transposition.totalSemitones) is outside \(TranspositionPlan.totalRange)")
        }
        guard let first = segments.first, let last = segments.last else {
            fail("segments is empty")
            return violations
        }
        if abs(first.audioStartTime) > ContractTolerance.timeline {
            fail("first segment starts at \(first.audioStartTime)s, expected 0")
        }
        if abs(last.audioEndTime - duration) > ContractTolerance.timeline {
            fail("last segment ends at \(last.audioEndTime)s, expected song duration \(duration)s")
        }
        for (position, segment) in segments.enumerated() {
            if segment.index != position {
                fail("segment at position \(position) has index \(segment.index)")
            }
            if segment.audioDuration <= 0 {
                fail("segment \(segment.index) has non-positive duration")
            }
            if position > 0 {
                let previous = segments[position - 1]
                let gap = segment.audioStartTime - previous.audioEndTime
                if abs(gap) > ContractTolerance.timeline {
                    fail("hole/overlap of \(gap)s between segment \(previous.index) and \(segment.index)")
                }
            }
            for note in segment.targetNotes {
                if note.startTime < segment.audioStartTime - ContractTolerance.timeline
                    || note.endTime > segment.audioEndTime + ContractTolerance.timeline {
                    fail("note \(note.id) (\(note.startTime)...\(note.endTime)s) is outside segment \(segment.index)")
                }
                if note.duration <= 0 {
                    fail("note \(note.id) has non-positive duration")
                }
            }
        }
        return violations
    }
}

// MARK: - Passed takes (Takin -> Zildjian)

nonisolated enum TakeLogContract {
    static func validatePassedTakes(_ takes: [TakeAttemptLog],
                                    segments: [SongSegment],
                                    crossfade: TimeInterval) -> [ContractViolation] {
        let name = "PassedTakes"
        var violations: [ContractViolation] = []
        func fail(_ message: String) { violations.append(ContractViolation(contract: name, message: message)) }

        if takes.count > segments.count {
            fail("\(takes.count) takes for \(segments.count) segments")
        }
        for (position, take) in takes.enumerated() {
            if take.status != .passed {
                fail("take for segment \(take.segmentIndex) has status \(take.status)")
            }
            if take.segmentIndex != position {
                fail("expected segment \(position) at position \(position), got \(take.segmentIndex) (must be prefix 0...N-1)")
            }
            let range = take.videoTimeRange
            if !range.isValid || range.start.seconds < 0 || range.duration.seconds <= 0 {
                fail("segment \(take.segmentIndex) has an invalid videoTimeRange")
            }
            if position > 0, range.start < takes[position - 1].videoTimeRange.start {
                fail("segment \(take.segmentIndex) starts before the previous take in the raw file")
            }
            if take.segmentIndex < segments.count {
                let expected = segments[take.segmentIndex].audioDuration + 2 * crossfade
                let actual = range.duration.seconds
                if abs(actual - expected) > ContractTolerance.takeDuration {
                    fail("segment \(take.segmentIndex) take is \(actual)s, expected \(expected)s (segment + 2 × handle)")
                }
            }
        }
        return violations
    }
}

// MARK: - CompingCompositionPlan

extension CompingCompositionPlan {
    nonisolated func validate() -> [ContractViolation] {
        var violations = TakeLogContract.validatePassedTakes(validTakes, segments: segments, crossfade: crossfadeDuration.seconds)
        if validTakes.isEmpty {
            violations.append(ContractViolation(contract: "CompingCompositionPlan", message: "no passed takes, nothing to export"))
        } else if let lastIndex = validTakes.last?.segmentIndex, lastIndex < segments.count {
            let expectedEnd = segments[lastIndex].audioEndTime
            if abs(endTime - expectedEnd) > ContractTolerance.timeline {
                violations.append(ContractViolation(contract: "CompingCompositionPlan",
                                                    message: "endTime \(endTime)s, expected end of segment \(lastIndex) = \(expectedEnd)s"))
            }
        }
        return violations
    }
}

// MARK: - Debug assertion

nonisolated enum Contract {
    /// Crashes in Debug with every violation listed; does nothing in Release.
    static func assertValid(_ violations: [ContractViolation], file: StaticString = #file, line: UInt = #line) {
        assert(violations.isEmpty,
               "Contract violated:\n" + violations.map(\.description).joined(separator: "\n"),
               file: file, line: line)
    }
}
