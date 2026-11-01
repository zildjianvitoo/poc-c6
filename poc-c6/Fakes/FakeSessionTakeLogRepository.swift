//
//  FakeSessionTakeLogRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation
import Synchronization

nonisolated final class FakeSessionTakeLogRepository: SessionTakeLogRepository, Sendable {
    private let attempts = Mutex<[TakeAttemptLog]>([])

    func logAttempt(_ attempt: TakeAttemptLog) {
        attempts.withLock { $0.append(attempt) }
    }

    func allAttempts() -> [TakeAttemptLog] {
        attempts.withLock { $0 }
    }

    func passedTakesPrefix() -> [TakeAttemptLog] {
        let passed = attempts.withLock { $0.filter { $0.status == .passed } }
        var prefix: [TakeAttemptLog] = []
        while let take = passed.first(where: { $0.segmentIndex == prefix.count }) {
            prefix.append(take)
        }
        return prefix
    }

    func clear() {
        attempts.withLock { $0.removeAll() }
    }
}
