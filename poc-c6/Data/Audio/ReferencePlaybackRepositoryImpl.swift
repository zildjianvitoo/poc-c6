//
//  ReferencePlaybackRepositoryImpl.swift
//  poc-c6
//
//  Earphone reference playback scheduled on host time and mapped to the capture clock (PRD §7.1).
//

import AVFoundation

/// Serial access from the session controller. Audio scheduling uses host time, not the UI timer.
nonisolated final class ReferencePlaybackRepositoryImpl: ReferencePlaybackRepository, ReferenceVocalPlayback {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let instrumentalNode = AVAudioPlayerNode()
    private var instrumentalFile: AVAudioFile?
    private var referenceVocalEnabled = true
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
        engine.attach(instrumentalNode)
    }

    func load(earphoneMixURL: URL) throws {
        node.stop(); instrumentalNode.stop()
        engine.stop()
        instrumentalFile = nil
        let file = try AVAudioFile(forReading: earphoneMixURL)
        self.file = file
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        engine.prepare()
        try engine.start()
    }

    func loadKaraoke(mixURL: URL, instrumentalURL: URL) throws {
        try load(earphoneMixURL: mixURL)
        do {
            let backing = try AVAudioFile(forReading: instrumentalURL)
            guard let file,
                  abs(Double(file.length) / file.processingFormat.sampleRate
                      - Double(backing.length) / backing.processingFormat.sampleRate) <= ContractTolerance.timeline else {
                throw failure("Reference and instrumental durations must match.")
            }
            engine.stop()
            engine.disconnectNodeOutput(instrumentalNode)
            engine.connect(instrumentalNode, to: engine.mainMixerNode, format: backing.processingFormat)
            instrumentalFile = backing
            setReferenceVocalEnabled(referenceVocalEnabled)
            engine.prepare(); try engine.start()
        } catch {
            shutdown(); throw error
        }
    }

    func setReferenceVocalEnabled(_ enabled: Bool) {
        referenceVocalEnabled = enabled
        node.volume = enabled ? 1 : 0
        instrumentalNode.volume = enabled ? 0 : 1
    }

    func play(from referenceTime: TimeInterval) throws -> CMTime {
        guard let file, referenceTime.isFinite, referenceTime >= 0 else { throw failure("Invalid reference playback time.") }
        let start = AVAudioFramePosition((referenceTime * file.processingFormat.sampleRate).rounded())
        guard start < file.length else { throw failure("Playback starts outside the song.") }
        node.stop(); instrumentalNode.stop()
        if !engine.isRunning { try engine.start() }
        node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        if let backing = instrumentalFile {
            let backingStart = AVAudioFramePosition((referenceTime * backing.processingFormat.sampleRate).rounded())
            guard backingStart < backing.length else { throw failure("Instrumental playback starts outside the song.") }
            instrumentalNode.scheduleSegment(backing, startingFrame: backingStart,
                                             frameCount: AVAudioFrameCount(backing.length - backingStart), at: nil)
        }
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let scheduled = CMTimeAdd(host, CMTime(seconds: Self.schedulingLead, preferredTimescale: 60000))
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: scheduled.seconds)))
        if instrumentalFile != nil {
            instrumentalNode.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: scheduled.seconds)))
        }
        let session = AVAudioSession.sharedInstance()
        let latency = session.outputLatency + session.ioBufferDuration + configuration().manualLatencyCalibration
        return CMTimeAdd(capture.captureTime(forHostTime: scheduled), CMTime(seconds: latency, preferredTimescale: 60000))
    }

    /// Also stops the engine so the audio session can be released; `play` restarts it.
    func stop() { node.stop(); instrumentalNode.stop(); engine.stop() }
    func shutdown() { node.stop(); instrumentalNode.stop(); engine.stop() }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "Playback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
