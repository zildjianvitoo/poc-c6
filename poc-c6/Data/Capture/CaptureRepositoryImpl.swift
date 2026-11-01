//
//  CaptureRepositoryImpl.swift
//  poc-c6
//

import AVFoundation

/// Capture and writer state belongs exclusively to queue; clock snapshots and subscribers use lock.
nonisolated final class CaptureRepositoryImpl: NSObject, CaptureRepository, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "recording.capture", qos: .userInitiated)
    private let lock = NSLock()
    private let worker = PitchWorker()
    private var clock: CMClock = CMClockGetHostTimeClock()
    private var firstPTS: CMTime?
    private var analyses: [UUID: AsyncStream<(PitchSample, CrepeEstimate)>.Continuation] = [:]
    private var subscribers: [UUID: AsyncStream<PitchSample>.Continuation] = [:]
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var recording = false
    private var failure: Error? {
        didSet {
            if let failure, oldValue == nil {
                NotificationCenter.default.post(name: Notification.Name("CaptureRepositoryFailure"), object: self, userInfo: [NSLocalizedDescriptionKey: failure.localizedDescription])
            }
        }
    }
    private var destination: URL?
    private var prepared = false

    func prepare() async throws {
        guard await AVCaptureDevice.requestAccess(for: .video), await AVCaptureDevice.requestAccess(for: .audio) else {
            throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera and microphone permission are required."])
        }
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
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
    }

    func stopSession() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func startRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard self.prepared, self.session.isRunning, !self.session.isInterrupted, !self.recording else { throw self.error("Capture is not ready.") }
                    let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Recordings/\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent("RawMasterVideo.mov")
                    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 1080, AVVideoHeightKey: 1920])
                    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000])
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
                    NotificationCenter.default.post(name: Notification.Name("CaptureRepositoryFailure"), object: self, userInfo: [NSLocalizedDescriptionKey: failure])
                    return
                }
                let decibels = estimate.rms > 0 ? Float(20 * log10(estimate.rms)) : -Float.infinity
                let sample = PitchSample(captureTime: CMTime(seconds: start + estimate.centerOffset, preferredTimescale: 60000), frequency: estimate.frequency.map(Float.init), rmsDecibels: decibels)
                self?.publish(sample, estimate: estimate)
            }
        }
    }

    func pitchSamples() -> AsyncStream<PitchSample> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let id = UUID()
            lock.lock(); subscribers[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.subscribers.removeValue(forKey: id); self.lock.unlock()
            }
        }
    }
    func analysisSamples() -> AsyncStream<(PitchSample, CrepeEstimate)> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let id = UUID()
            lock.lock(); analyses[id] = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.analyses.removeValue(forKey: id); self.lock.unlock()
            }
        }
    }
    private func publish(_ sample: PitchSample, estimate: CrepeEstimate) {
        lock.lock(); let streams = Array(subscribers.values); let analysisStreams = Array(analyses.values); lock.unlock()
        for stream in streams { stream.yield(sample) }
        for stream in analysisStreams { stream.yield((sample, estimate)) }
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
