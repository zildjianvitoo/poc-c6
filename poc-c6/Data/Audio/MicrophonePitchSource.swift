//
//  MicrophonePitchSource.swift
//  poc-c6
//
//  Built-in microphone → CREPE pitch, without the camera (vocal range test, PRD §5.1).
//  Same detector and window as live recording (PitchWorker).
//

import AVFoundation

nonisolated final class MicrophonePitchSource: LivePitchSource, @unchecked Sendable {
    private static let tapBufferSize: AVAudioFrameCount = 4096
    private let engine = AVAudioEngine()
    private let worker = PitchWorker()
    private let lock = NSLock()
    private var continuation: AsyncStream<PitchSample>.Continuation?

    func start() async throws -> AsyncStream<PitchSample> {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true)
        if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(mic)
        }
        try await worker.prepare()

        let (stream, continuation) = AsyncStream.makeStream(of: PitchSample.self, bufferingPolicy: .bufferingNewest(64))
        lock.withLock { self.continuation = continuation }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { [weak self] buffer, time in
            guard let self else { return }
            let start = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : ProcessInfo.processInfo.systemUptime
            self.worker.accept(buffer, start: start) { [weak self] estimate, frameStart, _, failure in
                guard failure == nil else { return }
                let decibels = estimate.rms > 0 ? Float(20 * log10(estimate.rms)) : -.infinity
                let sample = PitchSample(captureTime: CMTime(seconds: frameStart + estimate.centerOffset, preferredTimescale: 60_000),
                                         frequency: estimate.frequency.map(Float.init),
                                         rmsDecibels: decibels)
                self?.lock.withLock { self?.continuation }?.yield(sample)
            }
        }
        engine.prepare()
        try engine.start()
        return stream
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
