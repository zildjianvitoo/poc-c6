//
//  FakeLivePitchSource.swift
//  poc-c6
//
//  Fake for the simulator and previews. Every `start()` "sings" the next note of `notes`
//  (MIDI), held steady, so the vocal range test can be walked through without a microphone.
//

import CoreMedia
import Foundation
import Synchronization

nonisolated final class FakeLivePitchSource: LivePitchSource, Sendable {
    private struct State {
        var index = 0
        var emitter: Task<Void, Never>?
        var continuation: AsyncStream<PitchSample>.Continuation?
    }

    let notes: [Float]
    private let state = Mutex(State())

    /// Default: lowest C3, highest G4.
    init(notes: [Float] = [48, 67]) {
        self.notes = notes
    }

    func start() async throws -> AsyncStream<PitchSample> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: PitchSample.self)
        let midi = state.withLock { state -> Float in
            defer { state.index += 1 }
            return notes[min(state.index, notes.count - 1)]
        }
        let frequency = Float(440 * pow(2, (Double(midi) - 69) / 12))
        let emitter = Task {
            while !Task.isCancelled {
                // A little vibrato (±20 cents) so stability detection is exercised.
                let wobble = Float(sin(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 30)) * 0.2
                continuation.yield(PitchSample(captureTime: CMClockGetTime(CMClockGetHostTimeClock()),
                                               frequency: frequency * pow(2, wobble / 12), rmsDecibels: -20))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        state.withLock {
            $0.emitter = emitter
            $0.continuation = continuation
        }
        return stream
    }

    func stop() {
        state.withLock {
            $0.emitter?.cancel()
            $0.emitter = nil
            $0.continuation?.finish()
            $0.continuation = nil
        }
    }
}
