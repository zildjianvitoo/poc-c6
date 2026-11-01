//
//  main.swift
//  domain-checks
//
//  Runs every use-case check. Add a line here when you add a *Checks.swift file.
//

import Foundation

let suites: [(name: String, run: () async throws -> Int?)] = [
    ("SliceSegmentsUseCase", SliceSegmentsUseCaseChecks.run),
    ("ComputeTranspositionUseCase", ComputeTranspositionUseCaseChecks.run),
    ("DetectVocalRangeUseCase", DetectVocalRangeUseCaseChecks.run),
    ("PrepareSongUseCase", { try await PreparationChecks.run(); return nil }),
    ("EvaluateSegmentUseCase", EvaluateSegmentUseCaseChecks.run),
    ("LoopStateController", LoopStateControllerChecks.run),
]

var failed = false
for suite in suites {
    do {
        let count = try await suite.run()
        print("PASS  \(suite.name)" + (count.map { " (\($0) checks)" } ?? ""))
    } catch {
        failed = true
        print("FAIL  \(suite.name): \(error)")
    }
}
print(failed ? "\nSome domain checks failed." : "\nAll domain checks passed.")
exit(failed ? 1 : 0)
