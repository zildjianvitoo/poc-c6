//
//  MeasureSyncUseCaseChecks.swift
//  poc-c6
//
//  Executable checks for the click-test sync measurement (TK-05/TK-16). Not part of the app target.
//

import Foundation

nonisolated enum MeasureSyncUseCaseChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "MeasureSyncUseCase", message: message) }
        }
        let rate = 48_000.0
        let clicks = (1...8).map(Double.init)   // song times of the clicks
        let anchor = 100.0                       // capture time at which song time 0 is predicted to be heard

        /// Mic audio from `start` for 10 s: light noise, each click heard `offset` after its prediction
        /// with a short decaying tail (room/speaker), split into 1024-sample capture buffers.
        func chunks(offset: Double, noise: Float = 0.003, clickLevel: Float = 0.5, missing: Set<Int> = []) -> [MeasureSyncUseCase.AudioChunk] {
            var generator = SystemRandomNumberGenerator()
            let start = anchor - 0.5
            var samples = (0..<Int(10 * rate)).map { _ in Float.random(in: -noise...noise, using: &generator) }
            for (index, click) in clicks.enumerated() where !missing.contains(index) {
                let at = Int((anchor + click + offset - start) * rate)
                for i in 0..<Int(0.05 * rate) where at + i < samples.count {
                    samples[at + i] += clickLevel * exp(-Float(i) / 300) * (i.isMultiple(of: 2) ? 1 : -1)
                }
            }
            return stride(from: 0, to: samples.count, by: 1024).map {
                MeasureSyncUseCase.AudioChunk(startTime: start + Double($0) / rate, sampleRate: rate,
                                              samples: Array(samples[$0..<min($0 + 1024, samples.count)]))
            }
        }
        let predicted = clicks.map { anchor + $0 }
        let useCase = MeasureSyncUseCase()

        for offset in [0.0, 0.24, -0.27, 0.031] {
            let result = useCase.execute(predicted: predicted, chunks: chunks(offset: offset))
            try check(result.detectedClicks == clicks.count, "offset \(offset): all clicks found, got \(result.detectedClicks)")
            try check(abs(result.medianError - offset) < 0.001, "offset \(offset): median \(result.medianError)")
            try check(result.isReliable, "offset \(offset): reliable (spread \(result.spread))")
        }
        let quiet = useCase.execute(predicted: predicted, chunks: chunks(offset: 0.1, clickLevel: 0))
        try check(quiet.detectedClicks == 0 && !quiet.isReliable, "silence detects nothing")
        let someMissing = useCase.execute(predicted: predicted, chunks: chunks(offset: 0.1, missing: [2, 5, 6]))
        try check(someMissing.detectedClicks == 5 && !someMissing.isReliable, "3 of 8 missing is not reliable")
        return count
    }
}
