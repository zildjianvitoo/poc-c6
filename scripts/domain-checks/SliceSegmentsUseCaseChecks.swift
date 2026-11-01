//
//  SliceSegmentsUseCaseChecks.swift
//  poc-c6
//

#if DEBUG
import Foundation

/// Fixture-based checks runnable without a test target or changes to shared scripts.
nonisolated enum SliceSegmentsUseCaseChecks {
    @discardableResult
    static func run() throws -> Int {
        let fixture = DomainFixtures.preparedSong
        let originalNotes = fixture.segments.flatMap(\.targetNotes)
        var count = 0
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ContractViolation(contract: "IK-02 checks", message: message) }
        }
        func check(_ notes: [TargetMIDINote], duration: TimeInterval = 16,
                   configuration: PoCConfiguration = .default) throws -> [SongSegment] {
            let result = try SliceSegmentsUseCase(configuration: configuration).execute(notes: notes, duration: duration)
            let song = PreparedSong(earphoneMixURL: fixture.earphoneMixURL,
                                    instrumentalURL: fixture.instrumentalURL,
                                    segments: result, transposition: fixture.transposition,
                                    duration: duration, separationMethod: fixture.separationMethod)
            let violations = song.validate()
            try require(violations.isEmpty, violations.map(\.description).joined(separator: "\n"))
            Contract.assertValid(violations)
            try require(result.allSatisfy { $0.audioDuration <= configuration.maxSegment + ContractTolerance.timeline }, "Segment exceeds configured maximum.")
            try require(result.flatMap(\.targetNotes) == notes.sorted { $0.startTime < $1.startTime }, "Notes changed, duplicated or disappeared.")
            count += 1
            return result
        }
        func note(_ start: Double, _ duration: Double) -> TargetMIDINote {
            TargetMIDINote(midiNote: originalNotes[0].midiNote, startTime: start, duration: duration)
        }

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
        try require(abs(splitPhrase[0].audioEndTime - 5.7) < ContractTolerance.timeline, "Long phrase must split at its largest internal gap.")

        let empty = try check([])
        try require(empty.allSatisfy(\.isInstrumentalOnly), "An empty guide must still cover the timeline.")
        _ = try check(Array(originalNotes.reversed()))

        // Use a binary-exact gap to prove strict > semantics without decimal noise.
        var exact = PoCConfiguration.default
        exact.segmentGap = 0.5
        exact.minSegment = 1
        let equality = try check([note(0, 3.5), note(4, 4)], configuration: exact)
        try require(equality.first?.audioEndTime == 8, "Gap equal to threshold must not start a phrase.")
        let above = try check([note(0, 3.25), note(4, 4)], configuration: exact)
        try require(above.first?.audioEndTime == 3.625, "Above-threshold gap must split at its midpoint.")

        var custom = PoCConfiguration.default
        custom.maxSegment = 4
        custom.minSegment = 2
        let tuned = try check(continuous, configuration: custom)
        try require(tuned.count == 4, "Configuration values must control splitting.")

        // Short middle phrase chooses its closer right neighbour, not the left.
        let merged = try check([note(0, 3), note(4.6, 0.2), note(5.8, 2.2)])
        try require(merged[1].targetNotes.count == 2, "Short phrase merged toward the wrong gap.")

        for invalidNotes in [[note(0, 9)], [note(0, 2), note(1, 2)], [note(-1, 1)], [note(0, .nan)]] {
            do {
                _ = try SliceSegmentsUseCase().execute(notes: invalidNotes, duration: 16)
                throw ContractViolation(contract: "IK-02 checks", message: "Invalid guide was accepted.")
            } catch let error as ContractViolation {
                try require(error.contract == "SliceSegmentsUseCase", "Invalid guide was accepted.")
            }
            count += 1
        }
        return count
    }
}
#endif
