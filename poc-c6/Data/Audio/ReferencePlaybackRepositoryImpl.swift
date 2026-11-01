//
//  ReferencePlaybackRepositoryImpl.swift
//  poc-c6
//
//  Earphone reference playback scheduled on host time and mapped to the capture clock (PRD §7.1).
//

import AVFoundation

/// Serial access from the session controller. Audio scheduling uses host time, not the UI timer.
nonisolated final class ReferencePlaybackRepositoryImpl: ReferencePlaybackRepository {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let capture: CaptureRepositoryImpl
    private let configuration: () -> PoCConfiguration
    private var file: AVAudioFile?
    /// Playback starts this far in the future so `play(at:)` is scheduled, never late.
    private static let schedulingLead: TimeInterval = 0.1

    /// `configuration` is read on every play so Debug Settings changes (manual latency) apply at once.
    init(capture: CaptureRepositoryImpl, configuration: @escaping () -> PoCConfiguration) {
        self.capture = capture
        self.configuration = configuration
        engine.attach(node)
    }

    func load(earphoneMixURL: URL) throws {
        node.stop()
        engine.stop()
        let file = try AVAudioFile(forReading: earphoneMixURL)
        self.file = file
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        engine.prepare()
        try engine.start()
    }

    func play(from referenceTime: TimeInterval) throws -> CMTime {
        guard let file, referenceTime.isFinite, referenceTime >= 0 else { throw failure("Invalid reference playback time.") }
        let start = AVAudioFramePosition((referenceTime * file.processingFormat.sampleRate).rounded())
        guard start < file.length else { throw failure("Playback starts outside the song.") }
        node.stop()
        if !engine.isRunning { try engine.start() }
        node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let scheduled = CMTimeAdd(host, CMTime(seconds: Self.schedulingLead, preferredTimescale: 60000))
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: scheduled.seconds)))
        let session = AVAudioSession.sharedInstance()
        let latency = session.outputLatency + session.ioBufferDuration + configuration().manualLatencyCalibration
        return CMTimeAdd(capture.captureTime(forHostTime: scheduled), CMTime(seconds: latency, preferredTimescale: 60000))
    }

    func stop() { node.stop() }
    func shutdown() { node.stop(); engine.stop() }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "Playback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
