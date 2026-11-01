//
//  LoopStateControllerChecks.swift
//  poc-c6
//
//  Executable checks for the recording loop state machine (TK-10). Not part of the app target.
//

import Foundation

nonisolated enum LoopStateControllerChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "LoopStateController", message: message) }
        }
        let configuration = PoCConfiguration.default
        let segments = DomainFixtures.segments  // 0–6, 6–9 (instrumental), 9–16
        var loop = LoopStateController(segments: segments, configuration: configuration)

        // First attempt: silent countdown, then pre-roll from 0.
        try check(loop.begin(now: -3) == .none, "begin waits for the countdown")
        try check(loop.phase == .countdown(remaining: configuration.countdownSeconds), "countdown first")
        try check(loop.tick(now: -0.5, songTime: nil) == .none && loop.phase == .countdown(remaining: 1), "counting down")
        try check(loop.tick(now: 0, songTime: nil) == .startPlayback(from: 0), "first segment plays from 0")
        try check(loop.phase == .preRoll && loop.currentAttempt == 1, "pre-roll, attempt 1")
        try check(loop.tick(now: 0, songTime: 0) == .none && loop.phase == .singing, "segment start → singing")
        try check(loop.tick(now: 6, songTime: 6) == .none, "no evaluation before end + tail")
        try check(loop.tick(now: 6.2, songTime: 6.2) == .evaluate(segmentIndex: 0), "evaluate after end + tail")

        // Pass: continue into the next segment without stopping.
        try check(loop.resolve(passed: true, now: 6.2) == .none, "pass keeps playing")
        try check(loop.segmentIndex == 1 && loop.phase == .singing && loop.currentAttempt == 1, "next segment, attempt 1")
        try check(loop.tick(now: 9.2, songTime: 9.2) == .evaluate(segmentIndex: 1), "evaluate segment 2")
        _ = loop.resolve(passed: true, now: 9.2)

        // Fail: stop, result, silent countdown, then pre-roll 2 s before the segment.
        try check(loop.tick(now: 16.2, songTime: 16.2) == .evaluate(segmentIndex: 2), "evaluate segment 3")
        try check(loop.resolve(passed: false, now: 16.2) == .stopPlayback, "fail stops playback")
        try check(loop.phase == .showingResult, "result shown")
        try check(loop.tick(now: 16.5, songTime: 16.5) == .none && loop.phase == .showingResult, "result stays ~1 s")
        _ = loop.tick(now: 17.3, songTime: 17.3)
        try check(loop.phase == .countdown(remaining: configuration.countdownSeconds), "countdown starts")
        _ = loop.tick(now: 18.4, songTime: nil)
        try check(loop.phase == .countdown(remaining: 2), "countdown counts down: \(loop.phase)")
        try check(loop.tick(now: 20.3, songTime: nil) == .startPlayback(from: 9 - configuration.preRoll), "pre-roll 2 s before the segment")
        try check(loop.phase == .preRoll && loop.currentAttempt == 2, "attempt 2")
        try check(loop.tick(now: 21, songTime: 8) == .none && loop.phase == .preRoll, "pre-roll is not evaluated")
        _ = loop.tick(now: 22, songTime: 9)
        try check(loop.phase == .singing, "singing again")

        // Last segment passes → finish; passed takes are the whole song.
        _ = loop.tick(now: 29.2, songTime: 16.2)
        try check(loop.resolve(passed: true, now: 29.2) == .finish, "last pass finishes")
        try check(loop.phase == .ended && loop.passedCount == segments.count, "all passed")

        // Ending early keeps the passed prefix.
        var early = LoopStateController(segments: segments, configuration: configuration)
        _ = early.begin(now: -3)
        _ = early.tick(now: 0, songTime: nil)
        _ = early.tick(now: 0, songTime: 0)
        _ = early.tick(now: 6.2, songTime: 6.2)
        _ = early.resolve(passed: true, now: 6.2)
        early.end()
        try check(early.passedCount == 1, "early end keeps 1 passed: \(early.passedCount)")
        return count
    }
}
