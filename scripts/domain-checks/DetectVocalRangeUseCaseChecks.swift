//
//  DetectVocalRangeUseCaseChecks.swift
//  poc-c6
//
//  Executable checks for DetectVocalRangeUseCase (IK-10, PRD §5.1). Not part of the app target.
//

import CoreMedia
import Foundation

nonisolated enum DetectVocalRangeUseCaseChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "DetectVocalRangeUseCase", message: message) }
        }
        func sample(_ time: Double, _ midi: Double?, db: Float = -20) -> PitchSample {
            PitchSample(captureTime: CMTime(seconds: time, preferredTimescale: 60_000),
                        frequency: midi.map { Float(440 * pow(2, ($0 - 69) / 12)) }, rmsDecibels: db)
        }
        func run(_ frames: [(Double, Double?)], db: Float = -20) -> (result: Float?, at: Double?) {
            var detector = DetectVocalRangeUseCase()
            for (time, midi) in frames {
                if let note = detector.ingest(sample(time, midi, db: db)) { return (note, time) }
            }
            return (nil, nil)
        }
        let hop = 0.05

        // Steady C3 with ±20 cents vibrato: detected after ~2 s, median ≈ 48.
        let steady = (0..<60).map { i in (Double(i) * hop, 48 + 0.2 * sin(Double(i))) }
        let a = run(steady)
        try check(a.result.map { abs($0 - 48) < 0.1 } == true, "steady C3 → 48, got \(String(describing: a.result))")
        try check(a.at.map { $0 >= 2 && $0 < 2.2 } == true, "needs ~2 s, got \(String(describing: a.at))")

        // Drifting more than ±50 cents never stabilises within 3 s.
        let glide = (0..<60).map { i in (Double(i) * hop, 48 + Double(i) * 0.1) }
        try check(run(glide).result == nil, "a glide is not a held note")

        // A scoop into the note, then held: the scoop is dropped, the held note wins.
        let scoop = (0..<10).map { i in (Double(i) * hop, 52 + Double(i) * 0.5) } + (10..<60).map { i in (Double(i) * hop, 57.0) }
        try check(run(scoop).result.map { abs($0 - 57) < 0.01 } == true, "scoop then hold → 57")

        // A short breath (≤ 0.2 s) does not reset; a long silence does.
        let breath = (0..<20).map { i in (Double(i) * hop, Optional(60.0)) } + [(1.0, nil), (1.05, nil)]
            + (22..<50).map { i in (Double(i) * hop, Optional(60.0)) }
        try check(run(breath).at.map { $0 < 2.2 } == true, "short breath keeps the run")
        let pause = (0..<20).map { i in (Double(i) * hop, Optional(60.0)) } + (20..<30).map { i in (Double(i) * hop, Optional<Double>.none) }
            + (30..<80).map { i in (Double(i) * hop, Optional(60.0)) }
        try check(run(pause).at.map { $0 >= 3.4 } == true, "a 0.5 s pause restarts the hold: \(String(describing: run(pause).at))")

        // Below the noise gate counts as silence.
        try check(run(steady, db: -60).result == nil, "quiet input is ignored")
        return count
    }
}
