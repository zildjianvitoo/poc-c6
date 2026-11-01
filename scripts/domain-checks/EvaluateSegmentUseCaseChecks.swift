//
//  EvaluateSegmentUseCaseChecks.swift
//  poc-c6
//
//  Standalone checks for EvaluateSegmentUseCase (no XCTest target in this project).
//  Compile with the Domain files plus a main.swift that calls `EvaluateSegmentUseCaseChecks.run()`.
//

import Foundation

nonisolated enum EvaluateSegmentUseCaseChecks {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// Mirrors PracticeModel.consume: grid from `segment.audioStartTime`, one evaluation per hop,
    /// referenceTime = slot + 1e-6. `sing` returns the hit state per slot time, or nil for no evaluation.
    private static func evaluations(for segment: SongSegment, hop: TimeInterval,
                                    sing: (TimeInterval, TargetMIDINote?) -> Bool?) -> [PitchEvaluation] {
        var result: [PitchEvaluation] = []
        var slot = 0
        while true {
            let time = segment.audioStartTime + Double(slot) * hop
            if time >= segment.audioEndTime { break }
            slot += 1
            let active = segment.targetNotes.first { time >= $0.startTime && time < $0.endTime }
            guard let hit = sing(time, active) else { continue }
            result.append(PitchEvaluation(referenceTime: time + 1e-6, detectedMIDINote: 60, targetNoteID: active?.id,
                                          centDeviation: hit ? 0 : 300, isHit: hit))
        }
        return result
    }

    private static func perfect(_ segment: SongSegment, hop: TimeInterval) -> [PitchEvaluation] {
        evaluations(for: segment, hop: hop) { _, note in note != nil }
    }

    private static func segment(start: TimeInterval, notes: [(TimeInterval, TimeInterval)], duration: TimeInterval) -> SongSegment {
        SongSegment(index: 0, audioStartTime: start, audioDuration: duration,
                    targetNotes: notes.map { TargetMIDINote(midiNote: 60, startTime: $0.0, duration: $0.1) })
    }

    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "EvaluateSegmentUseCase", message: message) }
        }
        let config = PoCConfiguration.default
        let hop = config.pitchHop
        let useCase = EvaluateSegmentUseCase(configuration: config)

        // Perfect singing, grid-aligned notes.
        let aligned = segment(start: 0, notes: [(0.5, 0.5), (1.5, 1.0), (3.0, 0.5)], duration: 4)
        let alignedResult = useCase.execute(segment: aligned, evaluations: perfect(aligned, hop: hop))
        try check(alignedResult.score >= 0.95, "aligned perfect score \(alignedResult.score)")
        try check(alignedResult.missedNoteIDs.isEmpty, "aligned perfect has missed notes")

        // Perfect singing, 200 random off-grid layouts.
        var generator = SeededGenerator(state: 42)
        var worst: Float = 1
        var sum: Float = 0
        for _ in 0..<200 {
            let start = 3.137
            var cursor = start + Double.random(in: 0.0...0.4, using: &generator)
            var notes: [(TimeInterval, TimeInterval)] = []
            for _ in 0..<8 {
                let duration = Double.random(in: 0.2...0.5, using: &generator)
                notes.append((cursor, duration))
                cursor += duration + Double.random(in: 0.0...0.15, using: &generator)
            }
            let layout = segment(start: start, notes: notes, duration: cursor - start + 0.3)
            let score = useCase.execute(segment: layout, evaluations: perfect(layout, hop: hop)).score
            worst = min(worst, score)
            sum += score
        }
        print("off-grid perfect singing over 200 layouts: mean \(sum / 200), worst \(worst)")
        try check(worst >= 0.95, "off-grid worst score \(worst)")

        // Silence.
        let silent = useCase.execute(segment: aligned, evaluations: [])
        try check(silent.score == 0, "silence score \(silent.score)")
        try check(silent.missedNoteIDs.count == aligned.targetNotes.count, "silence should miss every note")

        // Wrong pitch only during the first attackIgnore of each note.
        let attackOnly = evaluations(for: aligned, hop: hop) { time, note in
            guard let note else { return false }
            return time - note.startTime >= config.attackIgnore - 1e-6
        }
        try check(useCase.execute(segment: aligned, evaluations: attackOnly).score == 1, "attack-only errors must be ignored")

        // Instrumental-only auto-passes.
        let instrumental = segment(start: 0, notes: [], duration: 5)
        let instrumentalResult = useCase.execute(segment: instrumental, evaluations: [])
        try check(instrumentalResult.score == 1 && instrumentalResult.missedNoteIDs.isEmpty, "instrumental must auto-pass")

        // Half of the evaluations dropped.
        let long = segment(start: 1.3, notes: [(1.4, 6.0)], duration: 7)
        let half = perfect(long, hop: hop).enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let halfScore = useCase.execute(segment: long, evaluations: half).score
        try check(abs(halfScore - 0.5) < 0.05, "half-dropped score \(halfScore)")

        // Missed-note detection: second note sung wrong.
        let two = segment(start: 0.2, notes: [(0.37, 0.8), (1.5, 0.8)], duration: 3)
        let wrongSecond = evaluations(for: two, hop: hop) { _, note in
            guard let note else { return false }
            return note.id == two.targetNotes[0].id
        }
        let twoResult = useCase.execute(segment: two, evaluations: wrongSecond)
        try check(twoResult.missedNoteIDs == [two.targetNotes[1].id], "missed notes \(twoResult.missedNoteIDs)")
        try check(twoResult.score > 0.4 && twoResult.score < 0.6, "two-note score \(twoResult.score)")

        // Unsorted input gives the same result.
        let reversed = Array(perfect(aligned, hop: hop).reversed())
        try check(useCase.execute(segment: aligned, evaluations: reversed).score >= 0.95, "unsorted input")
        return count
    }
}
