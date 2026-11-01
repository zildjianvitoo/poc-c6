//
//  ReferencePlaybackRepositoryImpl.swift
//  poc-c6
//

import AVFoundation

/// Serial access from the session controller. Audio scheduling uses host time, not the UI timer.
nonisolated final class ReferencePlaybackRepositoryImpl: ReferencePlaybackRepository {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let capture: CaptureRepositoryImpl
    private var file: AVAudioFile?
    var delay: TimeInterval = 0
    var manualLatency: TimeInterval = 0
    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    init(capture: CaptureRepositoryImpl) {
        self.capture = capture
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
        let scheduled = CMTimeAdd(host, CMTime(seconds: max(delay, 0.1), preferredTimescale: 60000))
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: scheduled.seconds)))
        let session = AVAudioSession.sharedInstance()
        let latency = session.outputLatency + session.ioBufferDuration + manualLatency
        return CMTimeAdd(capture.captureTime(forHostTime: scheduled), CMTime(seconds: latency, preferredTimescale: 60000))
    }

    func stop() { node.stop() }
    func shutdown() { node.stop(); engine.stop() }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "Playback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
