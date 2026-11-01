//
//  SliceSegmentsUseCase.swift
//  poc-c6
//

import Foundation

/// Turns an already reduced monophonic guide into a complete song timeline.
/// Notes retain their IDs, original key and absolute song times.
nonisolated struct SliceSegmentsUseCase: Sendable {
    private let configuration: PoCConfiguration

    init(configuration: PoCConfiguration = .default) {
        self.configuration = configuration
    }

    func execute(notes: [TargetMIDINote], duration: TimeInterval) throws -> [SongSegment] {
        func invalid(_ message: String) -> ContractViolation {
            ContractViolation(contract: "SliceSegmentsUseCase", message: message)
        }
        guard duration.isFinite, duration > 0 else { throw invalid("Duration must be finite and positive.") }
        guard configuration.segmentGap.isFinite, configuration.segmentGap >= 0,
              configuration.minSegment.isFinite, configuration.minSegment > 0,
              configuration.maxSegment.isFinite, configuration.maxSegment >= configuration.minSegment else {
            throw invalid("Invalid segmentation configuration.")
        }
        let sorted = notes.sorted { $0.startTime < $1.startTime }
        var ids = Set<UUID>()
        for (i, note) in sorted.enumerated() {
            guard note.startTime.isFinite, note.duration.isFinite, note.endTime.isFinite,
                  note.duration > 0, note.startTime >= 0, note.endTime <= duration,
                  ids.insert(note.id).inserted else { throw invalid("Invalid or duplicate guide note.") }
            if i > 0, sorted[i - 1].endTime > note.startTime {
                throw invalid("Guide must be monophonic before segmentation.")
            }
            guard note.duration <= configuration.maxSegment else {
                throw invalid("A sustained note exceeds maxSegment and has no internal note boundary.")
            }
        }

        // Long empty regions remain explicit instrumental segments. Short pauses belong
        // to neighbouring phrases; their shared boundary is the pause midpoint.
        var boundaries: [TimeInterval] = [0]
        if let first = sorted.first, first.startTime >= configuration.minSegment {
            boundaries.append(first.startTime)
        }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            let gap = right.startTime - left.endTime
            if gap >= configuration.minSegment, gap > configuration.segmentGap {
                boundaries.append(left.endTime)
                boundaries.append(right.startTime)
            } else if gap > configuration.segmentGap {
                boundaries.append(left.endTime + gap / 2)
            }
        }
        if let last = sorted.last, duration - last.endTime >= configuration.minSegment {
            boundaries.append(last.endTime)
        }
        boundaries.append(duration)
        boundaries = Array(Set(boundaries)).sorted()

        func containedNotes(_ start: TimeInterval, _ end: TimeInterval) -> [TargetMIDINote] {
            sorted.filter { $0.startTime >= start && $0.endTime <= end }
        }

        // Merge only vocal phrases: a deliberate instrumental region must auto-pass.
        var changed = true
        while changed {
            changed = false
            for i in 0..<(boundaries.count - 1) {
                let current = containedNotes(boundaries[i], boundaries[i + 1])
                guard boundaries[i + 1] - boundaries[i] < configuration.minSegment,
                      let first = current.first, let last = current.last else { continue }
                var candidates: [(boundary: Int, gap: TimeInterval)] = []
                if i > 0, boundaries[i + 1] - boundaries[i - 1] <= configuration.maxSegment,
                   let previous = containedNotes(boundaries[i - 1], boundaries[i]).last {
                    candidates.append((i, first.startTime - previous.endTime))
                }
                if i + 2 < boundaries.count,
                   boundaries[i + 2] - boundaries[i] <= configuration.maxSegment,
                   let next = containedNotes(boundaries[i + 1], boundaries[i + 2]).first {
                    candidates.append((i + 1, next.startTime - last.endTime))
                }
                // Equal gaps choose the earlier neighbour deterministically.
                if let candidate = candidates.min(by: {
                    $0.gap == $1.gap ? $0.boundary < $1.boundary : $0.gap < $1.gap
                }) {
                    boundaries.remove(at: candidate.boundary)
                    changed = true
                    break
                }
            }
        }

        func split(_ start: TimeInterval, _ end: TimeInterval) throws -> [TimeInterval] {
            guard end - start > configuration.maxSegment else { return [start, end] }
            let inside = containedNotes(start, end)
            let midpoint = start + (end - start) / 2
            var cut: TimeInterval
            if inside.isEmpty {
                cut = midpoint
            } else {
                let gaps = zip(inside, inside.dropFirst()).map { left, right in
                    (time: left.endTime + (right.startTime - left.endTime) / 2,
                     gap: right.startTime - left.endTime)
                }
                if let best = gaps.min(by: {
                    if $0.gap != $1.gap { return $0.gap > $1.gap }
                    let a = abs($0.time - midpoint), b = abs($1.time - midpoint)
                    return a == b ? $0.time < $1.time : a < b
                }) {
                    cut = best.time
                } else {
                    // A single note can be surrounded by silence. Cut that silence,
                    // never shorten or duplicate the note to satisfy the duration limit.
                    let edges = [inside[0].startTime, inside[0].endTime].filter { $0 > start && $0 < end }
                    guard let edge = edges.min(by: { abs($0 - midpoint) < abs($1 - midpoint) }) else {
                        throw invalid("No safe note boundary exists for this segment.")
                    }
                    cut = edge
                }
            }
            return try Array(split(start, cut).dropLast()) + split(cut, end)
        }

        var tiled: [TimeInterval] = [0]
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            tiled.append(contentsOf: try split(start, end).dropFirst())
        }
        let segments = zip(tiled, tiled.dropFirst()).enumerated().map { index, interval in
            SongSegment(index: index, audioStartTime: interval.0,
                        audioDuration: interval.1 - interval.0,
                        targetNotes: containedNotes(interval.0, interval.1))
        }
        guard segments.flatMap(\.targetNotes).count == sorted.count else {
            throw invalid("Segmentation must preserve every guide note exactly once.")
        }
        return segments
    }
}
