//
//  SyncCalibrationViewModel.swift
//  poc-c6
//
//  Click test (TK-05/TK-16): plays clicks through the same playback path as a session, listens
//  with the same capture session, and measures how far the heard clicks are from where the
//  playback anchor predicted them. The result becomes `manualLatencyCalibration`.
//

import CoreMedia
import Foundation
import Observation

@Observable
final class SyncCalibrationViewModel {
    enum Status: Equatable {
        case idle
        case measuring(progress: Double)
        case finished(MeasureSyncUseCase.Result)
        case failed(String)
    }

    private static let firstFrameTimeout: TimeInterval = 3
    /// Extra listening after the last click.
    private static let tail: TimeInterval = 0.5

    private(set) var status: Status = .idle
    let currentCalibration: TimeInterval

    @ObservationIgnored private let capture: any CaptureRepository
    @ObservationIgnored private let playback: any ReferencePlaybackRepository
    @ObservationIgnored private let onApply: (TimeInterval) -> Void
    @ObservationIgnored private var chunks: [MeasureSyncUseCase.AudioChunk] = []

    init(capture: any CaptureRepository, playback: any ReferencePlaybackRepository,
         currentCalibration: TimeInterval, onApply: @escaping (TimeInterval) -> Void) {
        self.capture = capture
        self.playback = playback
        self.currentCalibration = currentCalibration
        self.onApply = onApply
    }

    /// Calibration after applying the measured error, clamped to Debug Settings' range.
    var suggestedCalibration: TimeInterval? {
        guard case .finished(let result) = status, result.isReliable else { return nil }
        return min(0.3, max(-0.3, currentCalibration + result.medianError))
    }

    func measure() async {
        guard let microphone = capture as? any MicrophoneSampleSource else {
            status = .failed("The click test needs a real iPhone (no microphone on the simulator).")
            return
        }
        status = .measuring(progress: 0)
        chunks = []
        do {
            try await capture.prepare()
            try playback.load(earphoneMixURL: ClickTrack.url())
            let stream = microphone.audioChunks()
            let collector = Task { [weak self] in
                for await chunk in stream { self?.chunks.append(chunk) }
            }
            defer { collector.cancel() }
            try await capture.startRecording()
            try await waitForFirstFrame()
            let anchor = try playback.play(from: 0).seconds
            let end = anchor + ClickTrack.duration + Self.tail
            while capture.currentCaptureTime().seconds < end {
                let elapsed = capture.currentCaptureTime().seconds - (anchor - 0.1)
                status = .measuring(progress: min(1, max(0, elapsed / (end - anchor))))
                try await Task.sleep(for: .milliseconds(100))
            }
            playback.stop()
            _ = try? await capture.stopRecording()
            SessionFiles.cleanUp()
            let result = MeasureSyncUseCase().execute(predicted: ClickTrack.clickTimes.map { anchor + $0 }, chunks: chunks)
            status = .finished(result)
        } catch {
            playback.stop()
            _ = try? await capture.stopRecording()
            SessionFiles.cleanUp()
            status = .failed(error.localizedDescription)
        }
    }

    func apply() {
        guard let suggestedCalibration else { return }
        onApply(suggestedCalibration)
    }

    private func waitForFirstFrame() async throws {
        let deadline = capture.currentCaptureTime().seconds + Self.firstFrameTimeout
        while capture.fileTime(forCaptureTime: capture.currentCaptureTime()) == nil {
            guard capture.currentCaptureTime().seconds < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
