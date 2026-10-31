//
//  FakeCaptureRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import CoreMedia
import Foundation
import Synchronization

/// Simulates a recording session on the host clock. No camera or file is used.
/// `voice` decides what the "singer" sings: seconds since recording start -> frequency in Hz (nil = silent).
nonisolated final class FakeCaptureRepository: CaptureRepository, Sendable {
    private struct State {
        var recordingStart: CMTime?
        var continuations: [UUID: AsyncStream<PitchSample>.Continuation] = [:]
        var emitter: Task<Void, Never>?
    }

    let voice: @Sendable (TimeInterval) -> Float?
    let hop: Duration
    private let state = Mutex(State())

    init(hop: Duration = .milliseconds(50), voice: @escaping @Sendable (TimeInterval) -> Float? = { _ in nil }) {
        self.hop = hop
        self.voice = voice
    }

    func prepare() async throws {}

    func startRecording() async throws {
        let start = currentCaptureTime()
        let emitter = Task { [weak self] in
            while !Task.isCancelled {
                self?.emitSample()
                try? await Task.sleep(for: self?.hop ?? .milliseconds(50))
            }
        }
        state.withLock {
            $0.emitter?.cancel()
            $0.recordingStart = start
            $0.emitter = emitter
        }
    }

    func stopRecording() async throws -> URL {
        state.withLock {
            $0.emitter?.cancel()
            $0.emitter = nil
            $0.recordingStart = nil
        }
        return DomainFixtures.placeholderDirectory.appendingPathComponent("RawMasterVideo.mov")
    }

    func pitchSamples() -> AsyncStream<PitchSample> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    func currentCaptureTime() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    func fileTime(forCaptureTime time: CMTime) -> CMTime? {
        guard let start = state.withLock({ $0.recordingStart }) else { return nil }
        return time - start
    }

    private func emitSample() {
        let now = currentCaptureTime()
        let (start, continuations) = state.withLock { ($0.recordingStart, Array($0.continuations.values)) }
        guard let start else { return }
        let frequency = voice((now - start).seconds)
        let sample = PitchSample(captureTime: now, frequency: frequency, rmsDecibels: frequency == nil ? -60 : -20)
        continuations.forEach { $0.yield(sample) }
    }
}
