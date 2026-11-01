//
//  SliceSegmentsUseCaseChecks.swift
//  poc-c6
//
//  Fixture-based checks for `SliceSegmentsUseCase` (IK-02), run on the Mac with `swiftc`
//  together with the Domain files. Not part of the app target.
//

import Foundation

nonisolated enum SliceSegmentsUseCaseChecks {
    /// Deterministic generator so the fuzz run is reproducible.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @discardableResult
    static func run() throws -> Int {
        let fixture = DomainFixtures.preparedSong
        let originalNotes = fixture.segments.flatMap(\.targetNotes)
        let tolerance = ContractTolerance.timeline
        var count = 0
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ContractViolation(contract: "IK-02 checks", message: message) }
        }
        /// Runs the use case and verifies the invariants every result must satisfy.
        func verify(_ notes: [TargetMIDINote], duration: TimeInterval,
                    configuration: PoCConfiguration) throws -> [SongSegment] {
            let result = try SliceSegmentsUseCase(configuration: configuration).execute(notes: notes, duration: duration)
            let song = PreparedSong(earphoneMixURL: fixture.earphoneMixURL,
                                    instrumentalURL: fixture.instrumentalURL,
                                    segments: result, transposition: fixture.transposition,
                                    duration: duration, separationMethod: fixture.separationMethod)
            let violations = song.validate()
            try require(violations.isEmpty, violations.map(\.description).joined(separator: "\n"))
            Contract.assertValid(violations)
            try require(result.allSatisfy {
                $0.audioDuration <= configuration.maxSegment + tolerance
                    || ($0.targetNotes.count == 1 && $0.targetNotes[0].duration > configuration.maxSegment)
            }, "Segment exceeds configured maximum without being a single sustained note.")
            // Only notes entirely outside the song may be dropped by sanitising.
            let resultIDs = result.flatMap(\.targetNotes).map(\.id)
            try require(Set(resultIDs).count == resultIDs.count
                        && Set(resultIDs).isSubset(of: Set(notes.map(\.id))), "Notes changed or duplicated.")
            return result
        }
        func check(_ notes: [TargetMIDINote], duration: TimeInterval = 16,
                   configuration: PoCConfiguration = .default) throws -> [SongSegment] {
            let result = try verify(notes, duration: duration, configuration: configuration)
            try require(result.flatMap(\.targetNotes) == notes.sorted { $0.startTime < $1.startTime },
                        "Notes changed, duplicated or disappeared.")
            count += 1
            return result
        }
        func note(_ start: Double, _ duration: Double) -> TargetMIDINote {
            TargetMIDINote(midiNote: originalNotes[0].midiNote, startTime: start, duration: duration)
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= tolerance }

        // Five IK-02 acceptance cases, using the fixture's shared contracts and key.
        let normal = try check(originalNotes)
        try require(normal.contains(where: \.isInstrumentalOnly), "Long instrumental interlude disappeared.")
        let continuous = (0..<16).map { note(Double($0), 1) }
        let noPause = try check(continuous)
        try require(noPause.map(\.audioDuration) == [8, 8], "No-gap guide should split at the middle note boundary.")
        let shortPauses = (0..<16).map { note(Double($0), 0.8) }
        _ = try check(shortPauses)
        let intro = try check(originalNotes.map {
            TargetMIDINote(id: $0.id, midiNote: $0.midiNote, startTime: $0.startTime + 4, duration: $0.duration)
        }, duration: 20)
        try require(intro.first?.isInstrumentalOnly == true, "Instrumental intro must auto-pass.")
        let longPhrase = (0..<12).map { note(Double($0), $0 == 5 ? 0.4 : 1) }
        let splitPhrase = try check(longPhrase)
        try require(near(splitPhrase[0].audioEndTime, 5.7), "Long phrase must split at its largest internal gap.")

        let empty = try check([])
        try require(empty.allSatisfy(\.isInstrumentalOnly), "An empty guide must still cover the timeline.")
        _ = try check(Array(originalNotes.reversed()).sorted { $0.startTime < $1.startTime })

        // Fixture interlude (4.8 s gap): the instrumental segment keeps segmentGap / 2 of breathing room.
        try require(near(normal[1].audioStartTime, 4.7 + 0.4) && near(normal[1].audioEndTime, 9.5 - 0.4),
                    "Interlude boundaries must sit 0.4 s away from the notes.")

        // Use binary-exact values to prove strict > semantics without decimal noise.
        var exact = PoCConfiguration.default
        exact.segmentGap = 0.5
        exact.minSegment = 1
        let equality = try check([note(0, 3.5), note(4, 3.5)], duration: 15, configuration: exact)
        try require(equality[0].targetNotes.count == 2 && equality[0].audioEndTime == 7.75,
                    "Gap equal to threshold must not start a phrase.")
        let above = try check([note(0, 3.25), note(4, 3.5)], duration: 15, configuration: exact)
        try require(above.first?.audioEndTime == 3.625, "Above-threshold gap must split at its midpoint.")

        var custom = PoCConfiguration.default
        custom.maxSegment = 4
        custom.minSegment = 2
        let tuned = try check(continuous, configuration: custom)
        try require(tuned.count == 4, "Configuration values must control splitting.")

        // Short middle phrase chooses its closer right neighbour, not the left.
        let merged = try check([note(0, 3), note(4.6, 0.2), note(5.8, 2.2)])
        try require(merged[1].targetNotes.count == 2, "Short phrase merged toward the wrong gap.")

        // Breathing room: 4 s interlude / intro / outro never put a boundary on a note edge.
        let interlude = try check([note(0.5, 3.5), note(8, 3.5)])
        try require(near(interlude[0].audioEndTime, 4.4) && near(interlude[1].audioStartTime, 4.4)
                    && near(interlude[1].audioEndTime, 7.6) && interlude[1].isInstrumentalOnly,
                    "4 s interlude must be bounded at +/-0.4 s from its notes.")
        let longIntro = try check([note(4, 3.5), note(8, 3.5), note(12, 3.5)], duration: 16.5)
        try require(longIntro[0].isInstrumentalOnly && near(longIntro[0].audioEndTime, 3.6),
                    "4 s intro must end 0.4 s before the first note.")
        let longOutro = try check([note(0, 3.5), note(4, 3.5), note(8, 3)], duration: 15)
        try require(longOutro.last?.isInstrumentalOnly == true && near(longOutro.last!.audioStartTime, 11.4),
                    "4 s outro must start 0.4 s after the last note.")
        for result in [interlude, longIntro, longOutro] {
            for boundary in result.dropFirst().map(\.audioStartTime) {
                try require(result.flatMap(\.targetNotes).allSatisfy {
                    abs($0.startTime - boundary) > tolerance && abs($0.endTime - boundary) > tolerance
                }, "A boundary sits on a note edge.")
            }
        }

        // 3.5 s gap: 3.5 - 0.8 < 3, so no instrumental segment, midpoint rule.
        let shortGap = try check([note(0.5, 3.5), note(7.5, 3.5)])
        try require(near(shortGap[0].audioEndTime, 5.75) && shortGap.filter(\.isInstrumentalOnly).count == 1,
                    "3.5 s gap must use the midpoint, not an instrumental segment.")

        // Evenly spaced phrase: float noise must not decide the cut; both sides stay >= minSegment.
        let even = try check((0..<14).map { note(Double($0) * 0.7, 0.5) })
        try require(even.filter { !$0.isInstrumentalOnly }.allSatisfy { $0.audioDuration >= 3 - tolerance },
                    "Evenly spaced phrase left a short segment.")
        try require(abs(even[0].audioEndTime - 5) < 0.4, "Evenly spaced phrase must split near the middle.")

        // Basic-Pitch-like output: unsorted, 0.5 ms overlaps, last note ends 0.4 ms past the song.
        let starts: [Double] = [-0.0003, 3.5, 7, 10.5, 12.5]
        var raw = starts.enumerated().map { index, start -> TargetMIDINote in
            let end = index + 1 < starts.count ? starts[index + 1] + 0.0005 : 16.0004
            return note(start, end - start)
        }
        raw.reverse()
        let sanitised = try verify(raw, duration: 16, configuration: .default)
        try require(sanitised.flatMap(\.targetNotes).count == raw.count, "Sanitising lost a note.")
        count += 1

        // A sustained note longer than maxSegment must not abort preparation.
        let sustained = try verify([note(3, 9)], duration: 16, configuration: .default)
        try require(sustained.contains { $0.targetNotes.count == 1 && $0.audioDuration > 8 - tolerance },
                    "Sustained note must stay in one segment.")
        count += 1
        _ = try verify([note(0, 16)], duration: 16, configuration: .default)
        count += 1

        // Clamped to [0, duration]: a note entirely outside the song is dropped, not rejected.
        let outside = try verify([note(-1, 1), note(16.2, 1), note(2, 3)], duration: 16, configuration: .default)
        try require(outside.flatMap(\.targetNotes).count == 1, "Notes outside the song must be dropped.")
        count += 1

        // Real overlaps, duplicate IDs and non-finite values are still rejected.
        let shared = note(0, 1)
        for invalidNotes in [[note(0, 2), note(1, 2)], [note(0, .nan)], [shared, shared]] {
            do {
                _ = try SliceSegmentsUseCase().execute(notes: invalidNotes, duration: 16)
                throw ContractViolation(contract: "IK-02 checks", message: "Invalid guide was accepted.")
            } catch let error as ContractViolation {
                try require(error.contract == "SliceSegmentsUseCase", "Invalid guide was accepted.")
            }
            count += 1
        }

        count += try fuzz(verify: verify, note: note)
        return count
    }

    /// Random note layouts, seeded. Returns the number of layouts checked.
    private static func fuzz(verify: ([TargetMIDINote], TimeInterval, PoCConfiguration) throws -> [SongSegment],
                             note: (Double, Double) -> TargetMIDINote) throws -> Int {
        var generator = SeededGenerator(state: 0xC6C6_2026)
        let configuration = PoCConfiguration.default
        let iterations = 5_000
        var vocalSegments = 0
        var shortVocalSegments = 0
        for iteration in 0..<iterations {
            let duration = Double.random(in: 15...60, using: &generator)
            var notes: [TargetMIDINote] = []
            var cursor = [0.0, 0.0, Double.random(in: 0...1.5, using: &generator),
                          Double.random(in: 3...8, using: &generator)].randomElement(using: &generator)!
            while true {
                let length = Int.random(in: 0..<100, using: &generator) < 3
                    ? Double.random(in: 8.5...10, using: &generator)
                    : Double.random(in: 0.15...2.5, using: &generator)
                guard cursor + length <= duration + 0.0004 else { break }
                notes.append(note(cursor, length))
                let roll = Int.random(in: 0..<100, using: &generator)
                let gap: Double
                switch roll {
                case ..<25: gap = roll < 5 ? -0.0005 : 0
                case ..<65: gap = Double.random(in: 0.05...0.8, using: &generator)
                case ..<85: gap = Double.random(in: 0.8...3, using: &generator)
                default: gap = Double.random(in: 3...8, using: &generator)
                }
                cursor += length + gap
            }
            if Bool.random(using: &generator) { notes.shuffle(using: &generator) }

            let result: [SongSegment]
            do {
                result = try verify(notes, duration, configuration)
            } catch {
                throw ContractViolation(contract: "IK-02 fuzz", message: "iteration \(iteration): \(error)")
            }
            let ids = result.flatMap(\.targetNotes).map(\.id)
            guard Set(ids).count == ids.count, Set(ids) == Set(notes.map(\.id)) else {
                throw ContractViolation(contract: "IK-02 fuzz", message: "iteration \(iteration): notes not preserved exactly once")
            }
            for segment in result where !segment.isInstrumentalOnly {
                vocalSegments += 1
                if segment.audioDuration < configuration.minSegment - ContractTolerance.timeline {
                    shortVocalSegments += 1
                }
            }
        }
        let share = Double(shortVocalSegments) / Double(max(vocalSegments, 1))
        print("IK-02 fuzz: \(iterations) layouts, \(vocalSegments) vocal segments, "
              + "\(shortVocalSegments) shorter than minSegment (\(String(format: "%.2f", share * 100))%)")
        return iterations
    }
}
