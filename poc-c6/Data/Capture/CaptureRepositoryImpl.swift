//
//  CaptureRepositoryImpl.swift
//  poc-c6
//
//  Front camera + built-in mic → RawMasterVideo.mov, and live CREPE pitch from the same
//  audio buffers (PRD §6.5.4, §7.1, §7.2). Permissions are requested by PermissionGate.
//

import AVFoundation

extension Notification.Name {
    /// Posted by CaptureRepositoryImpl when capture or writing fails; `object` is the repository.
    nonisolated static let captureRepositoryFailure = Notification.Name("CaptureRepositoryFailure")
}

/// Capture and writer state belongs exclusively to queue; clock snapshots and subscribers use lock.
nonisolated final class CaptureRepositoryImpl: NSObject, CaptureRepository, CameraPreviewSource, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // Recording format fixed by PRD §6.5.4.
    private static let videoSize = (width: 1080, height: 1920)
    private static let framesPerSecond: Int32 = 30
    private static let audioSampleRate = 48_000.0
    private static let audioBitRate = 128_000
    /// ~3 s of 50 ms pitch samples, so a short main-thread stall does not drop any.
    private static let pitchStreamBuffer = 64

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "recording.capture", qos: .userInitiated)
    private let lock = NSLock()
    private let worker = PitchWorker()
    private var clock: CMClock = CMClockGetHostTimeClock()
    private var firstPTS: CMTime?
    private var subscribers: [UUID: AsyncStream<PitchSample>.Continuation] = [:]
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var recording = false
    private var failure: Error? {
        didSet {
            if let failure, oldValue == nil {
                NotificationCenter.default.post(name: .captureRepositoryFailure, object: self, userInfo: [NSLocalizedDescriptionKey: failure.localizedDescription])
            }
        }
    }
    private var destination: URL?
    private var prepared = false

    var previewSession: AVCaptureSession { session }

    func prepare() async throws {
        try Self.activateAudioSession()
        try await worker.prepare()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.prepared {
                        try self.configure()
                        self.prepared = true
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                    self.lock.lock()
                    self.clock = self.session.synchronizationClock ?? CMClockGetHostTimeClock()
                    self.lock.unlock()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .hd1920x1080
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let mic = AVCaptureDevice.default(for: .audio) else { throw error("Front camera or microphone unavailable.") }
        let video = try AVCaptureDeviceInput(device: camera)
        let audio = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(video), session.canAddInput(audio) else { throw error("Cannot configure capture inputs.") }
        session.addInput(video)
        session.addInput(audio)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput), session.canAddOutput(audioOutput) else { throw error("Cannot configure capture outputs.") }
        session.addOutput(videoOutput)
        session.addOutput(audioOutput)
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(Self.framesPerSecond) && $0.maxFrameRate >= Double(Self.framesPerSecond) }) {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Self.framesPerSecond)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Self.framesPerSecond)
        }
    }

    func stopSession() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            Self.deactivateAudioSession()
        }
    }

    /// PRD §7.2: play-and-record for video, A2DP only (no HFP, no speaker default), built-in mic always.
    private static func activateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP])
        try audioSession.setPreferredSampleRate(audioSampleRate)
        try audioSession.setActive(true)
        if let mic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try audioSession.setPreferredInput(mic)
        }
    }

    private static func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func startRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard self.prepared, self.session.isRunning, !self.session.isInterrupted, !self.recording else { throw self.error("Capture is not ready.") }
                    try SessionFiles.prepareDirectory()
                    let url = SessionFiles.rawVideoURL
                    try? FileManager.default.removeItem(at: url)
                    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: Self.videoSize.width, AVVideoHeightKey: Self.videoSize.height])
                    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.audioSampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: Self.audioBitRate])
                    video.expectsMediaDataInRealTime = true
                    audio.expectsMediaDataInRealTime = true
                    guard writer.canAdd(video), writer.canAdd(audio) else { throw self.error("Video encoder unavailable.") }
                    writer.add(video)
                    writer.add(audio)
                    self.writer = writer
                    self.videoInput = video
                    self.audioInput = audio
                    self.destination = url
                    self.failure = nil
                    self.lock.lock()
                    self.firstPTS = nil
                    self.lock.unlock()
                    self.recording = true
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.recording = false
                self.session.stopRunning()
                guard let writer = self.writer, let url = self.destination else {
                    continuation.resume(throwing: self.error("No recording to finish.")); return
                }
                self.writer = nil
                if let failure = self.failure {
                    writer.cancelWriting()
                    continuation.resume(throwing: failure); return
                }
                guard writer.status == .writing else {
                    writer.cancelWriting()
                    continuation.resume(throwing: writer.error ?? self.error("No video frames were recorded.")); return
                }
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                Self.deactivateAudioSession()
                writer.finishWriting {
                    if writer.status == .completed { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: writer.error ?? self.error("Video finalization failed.")) }
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recording, let writer, let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let isVideo = CMFormatDescriptionGetMediaType(description) == kCMMediaType_Video
        if writer.status == .unknown {
            guard isVideo else { return }
            guard writer.startWriting() else { failure = writer.error ?? error("Cannot start video writer."); return }
            writer.startSession(atSourceTime: pts)
            lock.lock(); firstPTS = pts; lock.unlock()
        }
        guard writer.status == .writing else { failure = writer.error ?? error("Recording was interrupted."); return }
        lock.lock(); let first = firstPTS; lock.unlock()
        guard let first, pts >= first else { return }
        let input = isVideo ? videoInput : audioInput
        if input?.isReadyForMoreMediaData == true, input?.append(sampleBuffer) != true {
            failure = writer.error ?? error("Cannot write captured media.")
        }
        if !isVideo {
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            let count = CMSampleBufferGetNumSamples(sampleBuffer)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
            buffer.frameLength = AVAudioFrameCount(count)
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList) == noErr else { return }
            worker.accept(buffer, start: pts.seconds) { [weak self] estimate, start, _, failure in
                if let failure {
                    NotificationCenter.default.post(name: .captureRepositoryFailure, object: self, userInfo: [NSLocalizedDescriptionKey: failure])
                    return
                }
                let decibels = estimate.rms > 0 ? Float(20 * log10(estimate.rms)) : -Float.infinity
                let sample = PitchSample(captureTime: CMTime(seconds: start + estimate.centerOffset, preferredTimescale: 60000), frequency: estimate.frequency.map(Float.init), rmsDecibels: decibels)
                self?.publish(sample)
            }
        }
    }

    func pitchSamples() -> AsyncStream<PitchSample> {
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.pitchStreamBuffer)) { continuation in
            let id = UUID()
            lock.lock(); subscribers[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subscribers.removeValue(forKey: id); self.lock.unlock()
            }
        }
    }
    private func publish(_ sample: PitchSample) {
        lock.lock(); let streams = Array(subscribers.values); lock.unlock()
        for stream in streams { stream.yield(sample) }
    }
    func currentCaptureTime() -> CMTime {
        lock.lock(); let clock = clock; lock.unlock()
        return CMClockGetTime(clock)
    }
    func captureTime(forHostTime time: CMTime) -> CMTime {
        lock.lock(); let clock = clock; lock.unlock()
        return CMSyncConvertTime(time, from: CMClockGetHostTimeClock(), to: clock)
    }
    func fileTime(forCaptureTime time: CMTime) -> CMTime? {
        lock.lock(); let first = firstPTS; lock.unlock()
        return first.map { CMTimeSubtract(time, $0) }
    }
    private func error(_ message: String) -> NSError {
        NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
