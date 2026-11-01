//
//  SliceSegmentsUseCase.swift
//  poc-c6
//

import Foundation

/// Turns an already reduced monophonic guide into a complete song timeline.
/// Notes retain their IDs, original key and absolute song times (analysis noise at the
/// song edges and tiny overlaps are sanitised first, see `sanitised`).
nonisolated struct SliceSegmentsUseCase: Sendable {
    private let configuration: PoCConfiguration

    init(configuration: PoCConfiguration = .default) {
        self.configuration = configuration
    }

    func execute(notes: [TargetMIDINote], duration: TimeInterval) throws -> [SongSegment] {
        guard duration.isFinite, duration > 0 else { throw Self.invalid("Duration must be finite and positive.") }
        guard configuration.segmentGap.isFinite, configuration.segmentGap >= 0,
              configuration.minSegment.isFinite, configuration.minSegment > 0,
              configuration.maxSegment.isFinite, configuration.maxSegment >= configuration.minSegment else {
            throw Self.invalid("Invalid segmentation configuration.")
        }
        let tolerance = ContractTolerance.timeline
        let segmentGap = configuration.segmentGap
        let minSegment = configuration.minSegment
        let maxSegment = configuration.maxSegment
        let sorted = try sanitised(notes, duration: duration)

        // A gap is long enough for its own instrumental-only segment when, after leaving
        // `segmentGap / 2` of breathing room on each side, `minSegment` is still left.
        func isLong(_ gap: TimeInterval) -> Bool { gap - segmentGap >= minSegment - tolerance }

        // Long empty regions remain explicit instrumental segments whose boundaries sit
        // `segmentGap / 2` away from the notes (breaths and early onsets stay inside the
        // phrase). Shorter pauses belong to the neighbouring phrases and their shared
        // boundary is the pause midpoint. No boundary ever sits on a note edge.
        var boundaries: [TimeInterval] = [0]
        if let first = sorted.first, isLong(first.startTime) {
            boundaries.append(first.startTime - segmentGap / 2)
        }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            let gap = right.startTime - left.endTime
            if gap > segmentGap + tolerance, isLong(gap) {
                boundaries.append(left.endTime + segmentGap / 2)
                boundaries.append(right.startTime - segmentGap / 2)
            } else if gap > segmentGap + tolerance {
                boundaries.append(left.endTime + gap / 2)
            }
        }
        if let last = sorted.last, isLong(duration - last.endTime) {
            boundaries.append(last.endTime + segmentGap / 2)
        }
        boundaries.append(duration)
        boundaries = Array(Set(boundaries)).sorted()

        // A note belongs to the interval holding its midpoint: robust against floating
        // noise when a cut sits on a shared note boundary.
        func containedNotes(_ start: TimeInterval, _ end: TimeInterval) -> [TargetMIDINote] {
            sorted.filter {
                let middle = ($0.startTime + $0.endTime) / 2
                return middle >= start && middle < end
            }
        }

        // Merge only vocal phrases: a deliberate instrumental region must auto-pass.
        var changed = true
        while changed {
            changed = false
            for i in 0..<(boundaries.count - 1) {
                let current = containedNotes(boundaries[i], boundaries[i + 1])
                guard boundaries[i + 1] - boundaries[i] < minSegment - tolerance,
                      let first = current.first, let last = current.last else { continue }
                var candidates: [(boundary: Int, gap: TimeInterval)] = []
                if i > 0, boundaries[i + 1] - boundaries[i - 1] <= maxSegment + tolerance,
                   let previous = containedNotes(boundaries[i - 1], boundaries[i]).last {
                    candidates.append((i, first.startTime - previous.endTime))
                }
                if i + 2 < boundaries.count,
                   boundaries[i + 2] - boundaries[i] <= maxSegment + tolerance,
                   let next = containedNotes(boundaries[i + 1], boundaries[i + 2]).first {
                    candidates.append((i + 1, next.startTime - last.endTime))
                }
                // Equal gaps (within tolerance) choose the earlier neighbour deterministically.
                if let candidate = candidates.min(by: {
                    abs($0.gap - $1.gap) <= tolerance ? $0.boundary < $1.boundary : $0.gap < $1.gap
                }) {
                    boundaries.remove(at: candidate.boundary)
                    changed = true
                    break
                }
            }
        }

        func split(_ start: TimeInterval, _ end: TimeInterval) -> [TimeInterval] {
            guard end - start > maxSegment + tolerance else { return [start, end] }
            let inside = containedNotes(start, end)
            let middle = start + (end - start) / 2
            // Larger gap wins; equal gaps (within tolerance) prefer the cut closest to the
            // middle, then the earlier one.
            func isBetter(_ a: (time: TimeInterval, gap: TimeInterval),
                          than b: (time: TimeInterval, gap: TimeInterval)) -> Bool {
                if abs(a.gap - b.gap) > tolerance { return a.gap > b.gap }
                let distanceA = abs(a.time - middle), distanceB = abs(b.time - middle)
                if abs(distanceA - distanceB) > tolerance { return distanceA < distanceB }
                return a.time < b.time
            }
            func best(_ cuts: [(time: TimeInterval, gap: TimeInterval)]) -> TimeInterval? {
                var winner: (time: TimeInterval, gap: TimeInterval)?
                for cut in cuts where winner.map({ isBetter(cut, than: $0) }) ?? true {
                    winner = cut
                }
                return winner?.time
            }
            var cut: TimeInterval
            if inside.isEmpty {
                cut = middle
            } else {
                // Gap midpoints; touching notes yield their shared boundary (gap 0).
                let cuts = zip(inside, inside.dropFirst()).map { left, right in
                    (time: left.endTime + (right.startTime - left.endTime) / 2,
                     gap: right.startTime - left.endTime)
                }
                // Prefer cuts that keep both sides at least `minSegment`.
                let balanced = cuts.filter {
                    $0.time - start >= minSegment - tolerance && end - $0.time >= minSegment - tolerance
                }
                if let chosen = best(balanced) ?? best(cuts) {
                    cut = chosen
                } else {
                    // A single note can be surrounded by silence. Cut that silence,
                    // never shorten or duplicate the note to satisfy the duration limit.
                    let edges = [inside[0].startTime, inside[0].endTime].filter {
                        $0 > start + tolerance && $0 < end - tolerance
                    }
                    guard let edge = edges.min(by: { abs($0 - middle) < abs($1 - middle) }) else {
                        // One sustained note fills the whole segment: it has no internal
                        // boundary, so keep it as a segment longer than maxSegment instead
                        // of aborting preparation.
                        return [start, end]
                    }
                    cut = edge
                }
            }
            return Array(split(start, cut).dropLast()) + split(cut, end)
        }

        var tiled: [TimeInterval] = [0]
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            tiled.append(contentsOf: split(start, end).dropFirst())
        }
        let segments = zip(tiled, tiled.dropFirst()).enumerated().map { index, interval in
            SongSegment(index: index, audioStartTime: interval.0,
                        audioDuration: interval.1 - interval.0,
                        targetNotes: containedNotes(interval.0, interval.1))
        }
        guard segments.flatMap(\.targetNotes).count == sorted.count else {
            throw Self.invalid("Segmentation must preserve every guide note exactly once.")
        }
        return segments
    }

    private static func invalid(_ message: String) -> ContractViolation {
        ContractViolation(contract: "SliceSegmentsUseCase", message: message)
    }

    /// Analysis output is cleaned instead of rejected: notes are clamped to `[0, duration]`,
    /// notes that end up with no length are dropped, and overlaps up to
    /// `ContractTolerance.timeline` are treated as touching (the earlier note's end is trimmed
    /// to the next start). A larger real overlap means the guide is not monophonic and throws.
    private func sanitised(_ notes: [TargetMIDINote], duration: TimeInterval) throws -> [TargetMIDINote] {
        var ids = Set<UUID>()
        var clamped: [TargetMIDINote] = []
        for note in notes {
            guard note.startTime.isFinite, note.duration.isFinite, note.endTime.isFinite,
                  ids.insert(note.id).inserted else { throw Self.invalid("Invalid or duplicate guide note.") }
            let start = max(0, note.startTime)
            let end = min(duration, note.endTime)
            guard end - start > 0 else { continue }
            // Untouched notes are kept as they are, free of rounding drift.
            clamped.append(start == note.startTime && end == note.endTime
                           ? note
                           : TargetMIDINote(id: note.id, midiNote: note.midiNote,
                                            startTime: start, duration: end - start))
        }
        var result: [TargetMIDINote] = []
        for note in clamped.sorted(by: { $0.startTime < $1.startTime }) {
            while let previous = result.last, previous.endTime > note.startTime {
                guard previous.endTime - note.startTime <= ContractTolerance.timeline else {
                    throw Self.invalid("Guide must be monophonic before segmentation.")
                }
                result.removeLast()
                let trimmed = note.startTime - previous.startTime
                if trimmed > 0 {
                    result.append(TargetMIDINote(id: previous.id, midiNote: previous.midiNote,
                                                 startTime: previous.startTime, duration: trimmed))
                    break
                }
            }
            result.append(note)
        }
        return result
    }
}
