//
//  ModelPrewarmer.swift
//  poc-c6
//
//  Loads the CoreML models in the background when the app opens, so Preparation (htdemucs,
//  CREPE guide) and the vocal range test / recording (live CREPE) don't wait for them.
//  Failures are ignored here: each feature loads (and reports) its model again when used.
//

import Foundation
import os

nonisolated struct ModelPrewarmer: Sendable {
    let htDemucs: HTDemucsStemSeparationRepository

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "poc-c6", category: "Prewarm")

    func start() {
        Task.detached(priority: .utility) { [htDemucs] in
            let clock = ContinuousClock()
            // CREPE first: it is small and the vocal range test may need it right away.
            let crepe = clock.measure { try? CrepePitchDetector.prewarm() }
            let separation = clock.measure { try? htDemucs.prewarm() }
            Self.log.notice("""
                prewarm: CREPE \(crepe / .seconds(1), format: .fixed(precision: 2)) s, \
                htdemucs \(separation / .seconds(1), format: .fixed(precision: 2)) s
                """)
        }
    }
}
