//
//  FakeReferencePlaybackRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import CoreMedia
import Foundation
import Synchronization

/// Plays nothing; reports that audio is heard `latency` seconds from now on the host clock
/// (the same clock FakeCaptureRepository uses).
nonisolated final class FakeReferencePlaybackRepository: ReferencePlaybackRepository, Sendable {
    let latency: TimeInterval
    private let loadedURL = Mutex<URL?>(nil)

    init(latency: TimeInterval = 0) {
        self.latency = latency
    }

    func load(earphoneMixURL: URL) throws {
        loadedURL.withLock { $0 = earphoneMixURL }
    }

    func play(from referenceTime: TimeInterval) throws -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: latency, preferredTimescale: 600)
    }

    func stop() {}
}
