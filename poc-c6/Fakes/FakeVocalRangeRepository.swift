//
//  FakeVocalRangeRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation
import Synchronization

/// In-memory, starts empty so the app opens on the vocal range step.
nonisolated final class FakeVocalRangeRepository: VocalRangeRepository, Sendable {
    private let storage: Mutex<VocalRange?>

    init(initial: VocalRange? = nil) {
        storage = Mutex(initial)
    }

    func load() -> VocalRange? {
        storage.withLock { $0 }
    }

    func save(_ range: VocalRange) {
        storage.withLock { $0 = range }
    }
}
