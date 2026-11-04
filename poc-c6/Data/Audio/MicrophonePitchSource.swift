//
//  MicrophonePitchSource.swift
//  poc-c6
//
//  Headset microphone → CREPE pitch for the vocal range test.
//  Engine lifecycle and route changes are serialised; no silent fallback to iPhone input.
//

import AVFoundation

nonisolated final class MicrophonePitchSource: LivePitchSource, MicrophoneInputProviding, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let worker = PitchWorker()
    private let queue = DispatchQueue(label: "vocal-range.microphone", qos: .userInitiated)
    private let lock = NSLock()
    private var continuation: AsyncStream<PitchSample>.Continuation?
    private var routeObserver: NSObjectProtocol?
    private var hasTap = false
    private var generation = UUID()

    var microphoneName: String? { HeadsetMicrophoneSession.currentInput?.portName }
    var isHeadsetMicrophoneActive: Bool { HeadsetMicrophoneSession.currentInput != nil }

    func start() async throws -> AsyncStream<PitchSample> {
        stop()
        let token = queue.sync { generation }
        try await worker.prepare()
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { result in
            queue.async { [self] in
                do {
                    guard self.generation == token else { throw CancellationError() }
                    let microphoneUID = try HeadsetMicrophoneSession.activate(mode: .measurement)
                    let (stream, continuation) = AsyncStream.makeStream(of: PitchSample.self, bufferingPolicy: .bufferingNewest(64))
                    self.lock.withLock { self.continuation = continuation }
                    let input = self.engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else { throw HeadsetMicrophoneError.unavailable }
                    // 4096 frames become 256 ms at 16 kHz, making Bluetooth range feedback
                    // arrive in bursts. Request the same time interval at every input rate.
                    let tapBufferSize = AVAudioFrameCount(max(1, (format.sampleRate * PoCConfiguration.default.pitchHop).rounded()))
                    input.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { [weak self] buffer, time in
                        guard let self else { return }
                        let start = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : ProcessInfo.processInfo.systemUptime
                        self.worker.accept(buffer, start: start) { [weak self] estimate, frameStart, _, failure in
                            guard failure == nil else { return }
                            let decibels = estimate.rms > 0 ? Float(20 * log10(estimate.rms)) : -.infinity
                            let sample = PitchSample(captureTime: CMTime(seconds: frameStart + estimate.centerOffset, preferredTimescale: 60_000),
                                                     frequency: estimate.frequency.map(Float.init), rmsDecibels: decibels)
                            self?.lock.withLock { self?.continuation }?.yield(sample)
                        }
                    }
                    self.hasTap = true
                    self.engine.prepare()
                    try self.engine.start()
                    try HeadsetMicrophoneSession.verify(microphoneUID)
                    self.routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
                        guard let self else { return }
                        self.queue.async {
                            guard self.generation == token else { return }
                            if HeadsetMicrophoneSession.currentInput?.uid != microphoneUID { self.stopOnQueue() }
                        }
                    }
                    result.resume(returning: stream)
                } catch {
                    if self.generation == token { self.stopOnQueue() }
                    result.resume(throwing: error)
                }
            }
        }
    }

    func stop() { queue.sync { stopOnQueue() } }

    private func stopOnQueue() {
        generation = UUID()
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        if engine.isRunning { engine.stop() }
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
