//
//  ComputeTranspositionUseCaseChecks.swift
//  poc-c6
//
//  Executable checks for ComputeTranspositionUseCase (IK-03). Not part of the app target.
//

import Foundation

nonisolated enum ComputeTranspositionUseCaseChecks {
    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }
    }

    private struct Suggestion {
        let plan: TranspositionPlan
        let notesOutsideRange: Int
    }

    /// Plan plus the number of notes still outside the range; no range → no shift.
    private static func suggest(notes: [TargetMIDINote], vocalRange: VocalRange?) throws -> Suggestion {
        guard let vocalRange else { return Suggestion(plan: .none, notesOutsideRange: 0) }
        let plan = try ComputeTranspositionUseCase().execute(notes: notes, vocalRange: vocalRange)
        let outside = notes.filter {
            let pitch = Float(plan.transposed($0))
            return pitch < vocalRange.lowestMIDI || pitch > vocalRange.highestMIDI
        }.count
        return Suggestion(plan: plan, notesOutsideRange: outside)
    }

    private static func suggest(segments: [SongSegment], vocalRange: VocalRange?) throws -> Suggestion {
        try suggest(notes: segments.flatMap(\.targetNotes), vocalRange: vocalRange)
    }

    /// The plan the use case picks when a one-note song needs exactly `k` semitones.
    private static func plan(forTotalShift k: Int) throws -> TranspositionPlan {
        let note = TargetMIDINote(midiNote: 60, startTime: 0, duration: 1)
        let target = Float(60 + k)
        return try ComputeTranspositionUseCase().execute(notes: [note], vocalRange: VocalRange(lowestMIDI: target, highestMIDI: target))
    }

    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "ComputeTranspositionUseCase", message: message) }
        }
        func notes(_ pitches: [Int]) -> [TargetMIDINote] {
            pitches.enumerated().map { TargetMIDINote(midiNote: $1, startTime: Double($0), duration: 0.5) }
        }
        func range(_ low: Int, _ high: Int) -> VocalRange { VocalRange(lowestMIDI: Float(low), highestMIDI: Float(high)) }

        // Done-when: male voice vs female song -> octaveShift -1.
        let female = notes([69, 72, 76, 79, 81]) // A4...A5
        let male = range(45, 69)                 // A2...A4
        var s = try suggest(notes: female, vocalRange: male)
        try check(s.plan.octaveShift == -1 && s.plan.semitoneShift == 0, "male vs female song: \(s.plan)")
        try check(s.notesOutsideRange == 0, "male vs female song should fit")

        // Done-when: range already fits -> shift 0.
        s = try suggest(notes: notes([60, 62, 64, 67]), vocalRange: range(55, 72))
        try check(s.plan == .none && s.notesOutsideRange == 0, "fitting range should give no shift: \(s.plan)")

        // Empty song / no range / no segments -> .none.
        s = try suggest(notes: [], vocalRange: range(40, 80))
        try check(s.plan == .none && s.notesOutsideRange == 0, "empty song")
        s = try suggest(notes: female, vocalRange: nil)
        try check(s.plan == .none && s.notesOutsideRange == 0, "no vocal range")
        s = try suggest(segments: [], vocalRange: range(40, 80))
        try check(s.plan == .none, "no segments")

        // Segments overload flattens notes (instrumental-only segments are fine).
        let seg1 = SongSegment(index: 0, audioStartTime: 0, audioDuration: 4, targetNotes: notes([69, 72]))
        let seg2 = SongSegment(index: 1, audioStartTime: 4, audioDuration: 4, targetNotes: notes([76, 81]))
        let seg3 = SongSegment(index: 2, audioStartTime: 8, audioDuration: 4, targetNotes: [])
        try check(try suggest(segments: [seg1, seg2, seg3], vocalRange: male).plan.octaveShift == -1, "segments overload")

        // Tie-break 1: smaller |semitoneShift|. Note 60 into 48...50: k=-12 (semi 0) beats -11 (semi 1) and -10 (semi 2).
        s = try suggest(notes: notes([60]), vocalRange: range(48, 50))
        try check(s.plan.totalSemitones == -12 && s.plan.semitoneShift == 0, "prefer smaller |semitone|: \(s.plan)")
        // Note 60 into 71...73: k=11 (semi -1), 12 (semi 0), 13 (semi 1) all fit -> 12.
        s = try suggest(notes: notes([60]), vocalRange: range(71, 73))
        try check(s.plan.totalSemitones == 12 && s.plan.semitoneShift == 0, "prefer semi 0: \(s.plan)")
        // Tie-break 2: equal |semitone| (0), smaller |k|: note 60 in 48...72 fits k=-12, 0, 12 -> 0.
        s = try suggest(notes: notes([60]), vocalRange: range(48, 72))
        try check(s.plan == .none, "smallest |k| among semitone 0: \(s.plan)")
        // Octave-only shift beats a nonzero semitone shift even with smaller |k|: note 60, range {58, 72} -> k=0 fits anyway,
        // so use note 60 in 70...72 (k=10 semi -2, 11 semi -1, 12 semi 0) -> 12.
        s = try suggest(notes: notes([60]), vocalRange: range(70, 72))
        try check(s.plan.totalSemitones == 12, "octave beats semitone shift: \(s.plan)")
        // Final tie (k=+3 vs k=-3, same |semi| and |k|): lower k wins. Two notes 60 and 66 into 57...57 / 69...69 style
        // ranges are contiguous, so use reference comparison below; direct case: note 60 into 63...63 fits only k=3.
        s = try suggest(notes: notes([60]), vocalRange: range(63, 63))
        try check(s.plan.totalSemitones == 3, "single fit k=3")

        // Too-wide melody: best k plus correct outside count.
        s = try suggest(notes: notes([40, 50, 60, 70, 80]), vocalRange: range(55, 65))
        // Spacing 10 inside 55...65: two notes fit at k=+5 or k=-5; equal |semi| and |k| -> lower k.
        try check(s.notesOutsideRange == 3, "wide melody outside count: \(s.notesOutsideRange)")
        try check(s.plan.totalSemitones == -5, "final tie-break prefers lower k: \(s.plan)")
        s = try suggest(notes: notes([50, 51, 52, 80]), vocalRange: range(60, 64))
        try check(s.notesOutsideRange == 1 && abs(s.plan.totalSemitones) <= 12, "wide melody picks best cluster: \(s.plan)")

        // Round trip: a song shifted by -k from a fitting range is detected as k.
        for k in TranspositionPlan.totalRange {
            let shifted = notes([60, 64, 67, 72].map { $0 - k })
            s = try suggest(notes: shifted, vocalRange: range(60, 72)) // width 12 = song width, so only k fits
            try check(s.plan.totalSemitones == k, "round trip k=\(k): got \(s.plan.totalSemitones)")
            try check(s.notesOutsideRange == 0, "round trip k=\(k) outside")
        }

        // Decomposition valid and consistent for every k.
        for k in TranspositionPlan.totalRange {
            let p = try plan(forTotalShift: k)
            try check(p.totalSemitones == k, "decomposition total k=\(k)")
            try check(TranspositionPlan.semitoneRange.contains(p.semitoneShift), "semitone range k=\(k)")
            try check(TranspositionPlan.totalRange.contains(p.totalSemitones), "total range k=\(k)")
        }
        // k = ±6 has two valid splits; the use case keeps the first minimal |semitone| (−6).
        try check(try plan(forTotalShift: 6) == TranspositionPlan(octaveShift: 1, semitoneShift: -6), "k=6")
        try check(try plan(forTotalShift: -6) == TranspositionPlan(octaveShift: 0, semitoneShift: -6), "k=-6")
        try check(try plan(forTotalShift: 7) == TranspositionPlan(octaveShift: 1, semitoneShift: -5), "k=7")
        try check(try plan(forTotalShift: -12) == TranspositionPlan(octaveShift: -1, semitoneShift: 0), "k=-12")

        // Naive reference for brute force.
        func reference(_ pitches: [Int], _ low: Float, _ high: Float) -> (k: Int, outside: Int) {
            var best: (k: Int, semi: Int, outside: Int)?
            for k in -12...12 {
                var out = 0
                for p in pitches {
                    let t = Float(p + k)
                    if t < low || t > high { out += 1 }
                }
                var semi = k % 12
                if semi > 6 { semi -= 12 }
                if semi < -6 { semi += 12 }
                let cand = (k: k, semi: abs(semi), outside: out)
                if let b = best {
                    let better: Bool
                    if cand.outside != b.outside { better = cand.outside < b.outside }
                    else if cand.semi != b.semi { better = cand.semi < b.semi }
                    else if abs(cand.k) != abs(b.k) { better = abs(cand.k) < abs(b.k) }
                    else { better = cand.k < b.k }
                    if !better { continue }
                }
                best = cand
            }
            return (best?.k ?? 0, best?.outside ?? 0)
        }
        var rng = SplitMix64(state: 0xC6_2026)
        for i in 0..<3000 {
            let n = rng.int(1...12)
            let base = rng.int(30...80)
            let spread = rng.int(0...30)
            let pitches = (0..<n).map { _ in base + rng.int(0...spread) }
            let low = rng.int(35...70)
            let width = rng.int(0...30)
            let halfStep: Float = rng.int(0...1) == 0 ? 0 : 0.5
            let r = VocalRange(lowestMIDI: Float(low) + halfStep, highestMIDI: Float(low + width) + halfStep)
            let got = try suggest(notes: notes(pitches), vocalRange: r)
            let expected = reference(pitches, r.lowestMIDI, r.highestMIDI)
            try check(got.plan.totalSemitones == expected.k && got.notesOutsideRange == expected.outside,
                      "random #\(i): got k=\(got.plan.totalSemitones)/out \(got.notesOutsideRange), expected k=\(expected.k)/out \(expected.outside)")
            try check(TranspositionPlan.semitoneRange.contains(got.plan.semitoneShift)
                      && TranspositionPlan.totalRange.contains(got.plan.totalSemitones)
                      && got.plan.octaveShift * 12 + got.plan.semitoneShift == got.plan.totalSemitones,
                      "random #\(i): plan invalid \(got.plan)")
        }
        return count
    }
}
