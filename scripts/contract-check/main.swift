//
//  main.swift
//  contract-check
//
//  Compiled together with poc-c6/Domain by scripts/check-contracts.sh.
//  Runs on the Mac, no simulator or test target needed.
//

import Foundation

var failures = 0

func expectValid(_ name: String, _ violations: [ContractViolation]) {
    if violations.isEmpty {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
        violations.forEach { print("      \($0)") }
    }
}

func expectViolation(_ name: String, _ violations: [ContractViolation]) {
    if violations.isEmpty {
        failures += 1
        print("FAIL  \(name) (expected a violation, got none)")
    } else {
        print("PASS  \(name)")
    }
}

func song(segments: [SongSegment], duration: TimeInterval = 16, transposition: TranspositionPlan = .none) -> PreparedSong {
    PreparedSong(earphoneMixURL: DomainFixtures.preparedSong.earphoneMixURL,
                 instrumentalURL: DomainFixtures.preparedSong.instrumentalURL,
                 segments: segments, transposition: transposition,
                 duration: duration, separationMethod: .synthesized)
}

// Fixtures must always be valid.
expectValid("fixture PreparedSong", DomainFixtures.preparedSong.validate())
expectValid("fixture CompingCompositionPlan", DomainFixtures.compingPlan().validate())

// PreparedSong invariants.
var holed = DomainFixtures.segments
holed[1] = SongSegment(index: 1, audioStartTime: 6.5, audioDuration: 2.5, targetNotes: [])
expectViolation("hole between segments", song(segments: holed).validate())
expectViolation("last segment does not reach song end", song(segments: DomainFixtures.segments, duration: 20).validate())
expectViolation("song shorter than 15 s", song(segments: DomainFixtures.segments, duration: 10).validate())
expectViolation("semitoneShift out of range", song(segments: DomainFixtures.segments, transposition: TranspositionPlan(octaveShift: 0, semitoneShift: 7)).validate())
expectViolation("empty segments", song(segments: []).validate())

// Passed-take invariants.
let crossfade = PoCConfiguration.default.crossfade
var takes = DomainFixtures.passedTakes()
expectViolation("takes not a prefix", TakeLogContract.validatePassedTakes(Array(takes.reversed()), segments: DomainFixtures.segments, crossfade: crossfade))
takes[0] = TakeAttemptLog(segmentIndex: 0, attemptNumber: 1, videoTimeRange: takes[0].videoTimeRange,
                          accuracyScore: 0.5, missedNoteIDs: [], status: .failed)
expectViolation("failed take handed over", TakeLogContract.validatePassedTakes(takes, segments: DomainFixtures.segments, crossfade: crossfade))

print(failures == 0 ? "\nAll contract checks passed." : "\n\(failures) contract check(s) failed.")
exit(failures == 0 ? 0 : 1)
