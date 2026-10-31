//
//  SessionTakeLogRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Takin
//

import Foundation

nonisolated protocol SessionTakeLogRepository: AnyObject {
    func logAttempt(_ attempt: TakeAttemptLog)
    func allAttempts() -> [TakeAttemptLog]
    /// The passed take of segments 0...N-1, ordered by segment index.
    func passedTakesPrefix() -> [TakeAttemptLog]
    func clear()
}
