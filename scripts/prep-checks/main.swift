//
//  main.swift
//  prep-checks
//
//  Runs the song-preparation checks. Argument 1: compiled CrepeTiny.mlmodelc.
//

import Foundation

let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let suites: [(name: String, run: () async throws -> Int)] = [
    ("CenterChannelStemRepository", CenterChannelChecks.run),
    ("CrepeAnalysisRepository", { try await CrepeAnalysisChecks.run(modelURL: modelURL) }),
    ("AudioTranspositionRepositoryImpl", AudioTranspositionChecks.run),
    ("PrepareSongUseCase (end to end)", { try await PreparationPipelineChecks.run(modelURL: modelURL) }),
]

var failed = false
for suite in suites {
    do {
        print("PASS  \(suite.name) (\(try await suite.run()) checks)")
    } catch {
        failed = true
        print("FAIL  \(suite.name): \(error)")
    }
}
print(failed ? "\nSome preparation checks failed." : "\nAll preparation checks passed.")
exit(failed ? 1 : 0)
