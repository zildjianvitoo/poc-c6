//
//  LivePitchSource.swift
//  poc-c6
//
//  Microphone pitch without the camera, for the vocal range test (PRD §5.1).
//  Implemented by MicrophonePitchSource (device) and FakeLivePitchSource (simulator).
//

import Foundation

nonisolated protocol LivePitchSource: AnyObject {
    /// Starts the microphone. Returns a new stream; it ends when `stop()` is called.
    func start() async throws -> AsyncStream<PitchSample>
    func stop()
}
