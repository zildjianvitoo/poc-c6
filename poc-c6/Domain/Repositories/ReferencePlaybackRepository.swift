//
//  ReferencePlaybackRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Takin
//

import CoreMedia
import Foundation

nonisolated protocol ReferencePlaybackRepository: AnyObject {
    func load(earphoneMixURL: URL) throws
    /// Schedules playback from `referenceTime` and returns the capture-clock time
    /// at which that point is HEARD (scheduled host time + output latency).
    func play(from referenceTime: TimeInterval) throws -> CMTime
    func stop()
}
