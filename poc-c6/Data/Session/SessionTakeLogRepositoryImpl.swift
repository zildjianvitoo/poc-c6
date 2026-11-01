//
//  SessionTakeLogRepositoryImpl.swift
//  poc-c6
//

import Foundation

nonisolated final class SessionTakeLogRepositoryImpl: SessionTakeLogRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var attempts: [TakeAttemptLog] = []

    func logAttempt(_ attempt: TakeAttemptLog) {
        lock.lock()
        defer { lock.unlock() }
        guard !attempts.contains(where: { $0.id == attempt.id }) else { return }
        attempts.append(attempt)
    }

    func allAttempts() -> [TakeAttemptLog] {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func passedTakesPrefix() -> [TakeAttemptLog] {
        lock.lock()
        defer { lock.unlock() }
        var prefix: [TakeAttemptLog] = []
        while let take = attempts.first(where: {
            $0.segmentIndex == prefix.count && $0.status == .passed
        }) {
            prefix.append(take)
        }
        return prefix
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        attempts.removeAll()
    }
}
