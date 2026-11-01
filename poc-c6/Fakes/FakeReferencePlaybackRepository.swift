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
    /// Called with (referenceTime, heard capture time) on every play, e.g. by SimulatedSinger.
    let onPlay: (@Sendable (TimeInterval, CMTime) -> Void)?
    private let loadedURL = Mutex<URL?>(nil)

    init(latency: TimeInterval = 0, onPlay: (@Sendable (TimeInterval, CMTime) -> Void)? = nil) {
        self.latency = latency
        self.onPlay = onPlay
    }

    func load(earphoneMixURL: URL) throws {
        loadedURL.withLock { $0 = earphoneMixURL }
    }

    func play(from referenceTime: TimeInterval) throws -> CMTime {
        let heard = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: latency, preferredTimescale: 600)
        onPlay?(referenceTime, heard)
        return heard
    }

    func stop() {}
}
