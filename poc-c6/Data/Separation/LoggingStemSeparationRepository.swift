//
//  LoggingStemSeparationRepository.swift
//  poc-c6
//
//  Wraps a separation method and logs its time, memory footprint and errors (Debug builds), so
//  device tests can read them from the console (subsystem = bundle id, category "Separation").
//

import Foundation
import os

nonisolated struct LoggingStemSeparationRepository: StemSeparationRepository {
    let name: String
    let wrapped: any StemSeparationRepository

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "poc-c6", category: "Separation")

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        #if DEBUG
        let before = MemoryFootprint.snapshot()
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let stems = try await wrapped.separateStems(from: audioURL, trimRange: trimRange)
            let after = MemoryFootprint.snapshot()
            let seconds = (clock.now - started) / .seconds(1)
            Self.log.notice("""
                \(name, privacy: .public): \(trimRange.upperBound - trimRange.lowerBound, format: .fixed(precision: 1)) s \
                in \(seconds, format: .fixed(precision: 2)) s | footprint \(before.currentMB, format: .fixed(precision: 0)) → \
                \(after.currentMB, format: .fixed(precision: 0)) MB, peak \(before.peakMB, format: .fixed(precision: 0)) → \
                \(after.peakMB, format: .fixed(precision: 0)) MB, available before \(before.availableMB, format: .fixed(precision: 0)) MB
                """)
            return stems
        } catch {
            Self.log.error("\(name, privacy: .public) failed after \((clock.now - started) / .seconds(1), format: .fixed(precision: 2)) s: \(String(describing: error), privacy: .public)")
            throw error
        }
        #else
        return try await wrapped.separateStems(from: audioURL, trimRange: trimRange)
        #endif
    }
}
