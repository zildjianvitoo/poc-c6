//
//  CaptureRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Takin
//

import CoreMedia
import Foundation

nonisolated protocol CaptureRepository: AnyObject {
    func prepare() async throws
    func startRecording() async throws
    /// Finalizes RawMasterVideo.mov and returns its URL.
    func stopRecording() async throws -> URL
    /// Returns a NEW stream per call (AsyncStream supports one consumer only).
    func pitchSamples() -> AsyncStream<PitchSample>
    /// Now, on the capture session's synchronization clock.
    func currentCaptureTime() -> CMTime
    /// Converts a capture-clock time to RawMasterVideo.mov file time. nil before the first frame.
    func fileTime(forCaptureTime time: CMTime) -> CMTime?
}
