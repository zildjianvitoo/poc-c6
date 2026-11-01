//
//  PracticeModel.swift
//  poc-c6
//

import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PracticeModel {
  enum Phase { case ready, countdown, preRoll, singing, result, finished }
  var phase: Phase = .ready
  var running = false
  var requesting = false
  var elapsed = -PracticeConfiguration.countdownSeconds
  var frequency: Double?
  private(set) var detection = CrepeEstimate()
  private(set) var processingDelay = 0.0
  private(set) var outputDelay = 0.0
  private var frequencySongTime: Double?
  var comparisonTarget: ReferenceNote? {
    guard let frequencySongTime else { return nil }
    return Twinkle.note(at: frequencySongTime)
  }
  var detectionCoverage: Double {
    let expected = min(phrase.duration, max(0, elapsed))
    guard expected > 0 else { return 0 }
    return min(1, phrase.notes.reduce(0) { $0 + evaluator.voiced[$1.id] } / expected)
  }
  private let guide = TwinkleSessionGuide()
  private var evaluations: [PitchEvaluation] = []
  private(set) var missedNotes: [String] = []
  private var nextFrameTime = 0.0
  private var attemptBeginsAt = 0.0
  var endSummary: String?
  private(set) var audioRoute: AudioOutputRoute = .other
  var canStart: Bool { audioRoute == .wired || audioRoute == .bluetooth }
  func refreshAudioRoute() { audioRoute = AudioRouteMonitorImpl().currentRoute }
  var passedSegmentCount: Int { progress.scores.compactMap { $0 }.filter { $0 >= Double(PoCConfiguration.default.passThreshold) }.count }
  var evaluator = SegmentEvaluator()
  var progress = PracticeProgress()
  var points: [PitchPoint] = []
  var lastScore: Double?
  var lastPassed = false
  var message = "Use earphones to keep reference audio out of the microphone."
  var volume: Float = 0.45 { didSet { player?.volume = volume; playback.volume = volume } }
  private(set) var history = AttemptHistory()
  private(set) var historyError: String?
  private var sessionID: UUID?
  private var sessionOrigin = 0.0
  let capture = CaptureRepositoryImpl()
  @ObservationIgnored private lazy var playback = ReferencePlaybackRepositoryImpl(capture: capture)
  private let takes = SessionTakeLogRepositoryImpl()
  @ObservationIgnored private var pitchTask: Task<Void, Never>?
  private var recordingActive = false
  private(set) var finalizing = false
  private(set) var rawVideoURL: URL?
  private(set) var handoffURL: URL?
  private var discardRecording = false
  private(set) var passedTakes: [TakeAttemptLog] = []
  var manualLatencyMilliseconds: Double = UserDefaults.standard.double(forKey: "manualLatencyMilliseconds") {
    didSet {
      if manualLatencyMilliseconds.isFinite && abs(manualLatencyMilliseconds) <= 1000 {
        UserDefaults.standard.set(manualLatencyMilliseconds, forKey: "manualLatencyMilliseconds")
      }
    }
  }
  private var timer: Timer?
  private var player: AVAudioPlayer?
  private var songAudio: Data?
  private var origin = 0.0
  private var runStart = 0.0
  private(set) var displayIndex = 0
  private(set) var lastEvaluatedPhrase: Int?
  private var resultUntil = 0.0
  private var lastDetection = 0.0
  private var lastStorageCheck = 0.0
  private var generation = UUID()
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  init() {
    refreshAudioRoute()
    do { history = try AttemptHistory.load() } catch {
      historyError = "Riwayat tidak dapat dibaca: \(error.localizedDescription)"
    }

    for name in [
      AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
      AVAudioSession.mediaServicesWereResetNotification,
      AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
      Notification.Name("CaptureRepositoryFailure"),
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] notification in
          if notification.name == AVAudioSession.routeChangeNotification {
            Task { @MainActor [weak self] in self?.refreshAudioRoute() }
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard
              reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            else { return }
          }
          if notification.name == AVAudioSession.interruptionNotification {
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
          }
          Task { @MainActor [weak self] in
            guard let self, self.running else { return }
            self.stop()
            self.message = "Recording stopped after an audio or camera interruption. Any completed takes are being saved."
          }
        })
    }
  }
  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
  var phrase: Phrase { Phrase.all[displayIndex] }
  var visiblePoints: [PitchPoint] {
    points.filter { $0.time >= phrase.start && $0.time < phrase.start + phrase.duration }
      .map { PitchPoint(time: $0.time - phrase.start, frequency: $0.frequency) }
  }
  var target: ReferenceNote? {
    guard phase == .singing else { return nil }
    return phrase.notes.first {
      elapsed >= $0.start - phrase.start && elapsed < $0.start - phrase.start + $0.duration
    }
  }
  var score: Double {
    let segment = guide.segments[displayIndex]
    let end = min(segment.audioEndTime, segment.audioStartTime + max(0, elapsed))
    let activeNotes = segment.targetNotes.compactMap { note -> TargetMIDINote? in
      guard note.startTime < end else { return nil }
      return TargetMIDINote(id: note.id, midiNote: note.midiNote, startTime: note.startTime, duration: min(note.endTime, end) - note.startTime)
    }
    guard !activeNotes.isEmpty else { return 0 }
    let partial = SongSegment(index: segment.index, audioStartTime: segment.audioStartTime, audioDuration: max(0, end - segment.audioStartTime), targetNotes: activeNotes)
    return Double(EvaluateSegmentUseCase().execute(segment: partial, evaluations: evaluations).score)
  }
  var deviation: Double? {
    guard let frequency, let target = comparisonTarget else { return nil }
    return PitchDetector.cents(frequency, from: target.frequency)
  }
  var feedback: String {
    switch phase {
    case .ready: return "Ready to sing?"
    case .countdown: return "Get ready… \(max(1, Int(ceil(-elapsed - PoCConfiguration.default.preRoll))))"
    case .preRoll: return "Pre-roll… \(max(1, Int(ceil(-elapsed))))"
    case .result: return lastPassed ? "PASSED · continue singing" : "TRY AGAIN"
    case .finished: return "Session finished"
    case .singing:
      guard let deviation else { return "Sing the highlighted note" }
      if abs(deviation) <= PracticeConfiguration.hitToleranceCents { return "In tune" }
      return deviation > 0 ? "Too high ↓" : "Too low ↑"
    }
  }
  func start() async {
    guard !running && !requesting && !finalizing else { return }
    requesting = true
    defer { requesting = false }
    generation = UUID()
    let requestID = generation
    let allowed = await AVAudioApplication.requestRecordPermission()
    guard requestID == generation else {
      requesting = false
      return
    }
    guard allowed else {
      message = "Enable microphone permission in Settings → Privacy & Security → Microphone."
      return
    }
    player?.stop()
    do {
      guard manualLatencyMilliseconds.isFinite, abs(manualLatencyMilliseconds) <= 1000 else {
        throw NSError(domain: "Playback", code: 3, userInfo: [NSLocalizedDescriptionKey: "Latency calibration must be between -1000 and 1000 ms."])
      }
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP])
      try session.setPreferredSampleRate(PracticeConfiguration.preferredSampleRate)
      try session.setPreferredIOBufferDuration(PracticeConfiguration.preferredIOBufferDuration)
      try session.setActive(true)
      guard AudioRouteMonitorImpl().isEarphoneConnected else {
        throw NSError(domain: "Audio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Plug in earphones to record."])
      }
      if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
        try session.setPreferredInput(mic)
      }
      let capacity = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
      guard capacity >= PracticeConfiguration.minimumRecordingStorageBytes else {
        throw NSError(domain: "Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "At least 1.5 GB free storage is required."])
      }
      outputDelay = session.outputLatency
      try await capture.prepare()
      guard requestID == generation else { capture.stopSession(); return }
      let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("Twinkle-reference.wav")
      try Accompaniment.songWAV().write(to: audioURL, options: .atomic)
      try playback.load(earphoneMixURL: audioURL)
      playback.volume = volume
      playback.manualLatency = manualLatencyMilliseconds / 1000
      let stream = capture.analysisSamples()
      try await capture.startRecording()
      guard requestID == generation else {
        _ = try? await capture.stopRecording()
        return
      }
      recordingActive = true
      discardRecording = false
      handoffURL = nil
      rawVideoURL = nil
      passedTakes = []
      takes.clear()
      pitchTask = Task { @MainActor [weak self] in
        for await (sample, analysis) in stream {
          guard !Task.isCancelled, let self else { return }
          var estimate = analysis
          estimate.centerOffset = 0 // captureTime is already the center of the CREPE window.
          self.consume(estimate, start: sample.captureTime.seconds, duration: PoCConfiguration.default.pitchHop)
        }
      }
      progress = PracticeProgress()
      endSummary = nil
      missedNotes = []
      running = true
      sessionOrigin = capture.currentCaptureTime().seconds
      lastStorageCheck = sessionOrigin
      sessionID = history.begin()
      persistHistory()
      lastScore = nil
      lastEvaluatedPhrase = nil
      try beginPhrase()
      timer = Timer.scheduledTimer(
        withTimeInterval: PracticeConfiguration.displayInterval, repeats: true
      ) { [weak self] _ in
        Task { @MainActor [weak self] in self?.tick() }
      }
    } catch {
      stop()
      message = "Recording could not start: \(error.localizedDescription)"
    }
  }
  // Called only at session start or after failure. Success keeps the player running.
  private func beginPhrase() throws {
    playback.stop()
    runStart = Phrase.all[progress.index].start
    displayIndex = progress.index
    evaluator = SegmentEvaluator()
    evaluations = []
    nextFrameTime = runStart
    missedNotes = []
    points = []
    frequency = nil
    frequencySongTime = nil
    detection = CrepeEstimate()
    let delay = (progress.attempts[progress.index] > 0 ? PracticeConfiguration.countdownSeconds : 0) + PoCConfiguration.default.preRoll
    elapsed = -delay
    progress.beginAttempt()
    phase = progress.attempts[progress.index] > 1 ? .countdown : .preRoll
    let playbackStart = max(0, runStart - PoCConfiguration.default.preRoll)
    playback.delay = delay - (runStart - playbackStart)
    let anchor = try playback.play(from: playbackStart)
    origin = anchor.seconds - playbackStart
    attemptBeginsAt = origin + runStart
    message =
      "Segment \(progress.index + 1) · Attempt \(progress.attempts[progress.index]) · Target ≥75%"
  }
  private func consume(_ estimate: CrepeEstimate, start: Double, duration: Double) {
    let pitch = estimate.frequency
    guard phase == .singing || phase == .countdown || phase == .preRoll else { return }
    let songTime = start - origin
    let begin = max(runStart, songTime)
    let end = min(Twinkle.duration, songTime + duration)
    guard end > begin else { return }
    detection = estimate
    frequency = pitch
    frequencySongTime = songTime + estimate.centerOffset
    processingDelay = max(0, capture.currentCaptureTime().seconds - (start + estimate.centerOffset))
    lastDetection = capture.currentCaptureTime().seconds
    evaluator.ingest(frequency: pitch, start: begin, duration: end - begin, sampleTime: frequencySongTime)
    let center = songTime + estimate.centerOffset
    let halfHop = PoCConfiguration.default.pitchHop / 2
    // Populate only the interval represented by this estimate. Gaps remain misses.
    while nextFrameTime < center - halfHop { nextFrameTime += PoCConfiguration.default.pitchHop }
    while nextFrameTime < center + halfHop && nextFrameTime < Twinkle.duration {
      evaluations.append(guide.evaluate(frequency: pitch, time: nextFrameTime + 0.000001))
      nextFrameTime += PoCConfiguration.default.pitchHop
    }
    points.append(PitchPoint(time: center, frequency: pitch))
  }
  private func tick() {
    guard running else { return }
    let now = capture.currentCaptureTime().seconds
    if now - lastStorageCheck >= PracticeConfiguration.storageCheckInterval {
      lastStorageCheck = now
      if let capacity = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
         capacity < PracticeConfiguration.storageReserveBytes {
        stop()
        message = "Low storage: recording stopped and is being saved."
        return
      }
    }
    if now - sessionOrigin >= PoCConfiguration.default.maxSessionDuration {
      stop()
      message = "Session limit of 15 minutes reached."
      return
    }
    if phase == .result {
      if now >= resultUntil {
        do { try beginPhrase() } catch {
          stop()
          message = "Playback failed: \(error.localizedDescription)"
        }
      }
      return
    }
    let songTime = now - origin
    if songTime < runStart {
      elapsed = songTime - runStart
      phase = elapsed < -PoCConfiguration.default.preRoll ? .countdown : .preRoll
      return
    }
    phase = .singing
    if now - lastDetection > PracticeConfiguration.stalePitchSeconds {
      frequency = nil
      frequencySongTime = nil
      detection = CrepeEstimate(reason: "Belum ada buffer baru")
    }
    // Display the next lyric at its boundary while the last input buffer is analyzed.
    displayIndex = min(
      Phrase.all.count - 1, Phrase.all.lastIndex(where: { songTime >= $0.start }) ?? 0)
    elapsed = min(phrase.duration, songTime - phrase.start)
    // Finalize once per phrase, with a bounded grace period for in-flight audio.
    while !progress.finished {
      let judged = Phrase.all[progress.index]
      guard songTime >= judged.start + judged.duration + PracticeConfiguration.evaluationTail else {
        break
      }
      let result = EvaluateSegmentUseCase().execute(segment: guide.segments[judged.id], evaluations: evaluations)
      let value = Double(result.score)
      missedNotes = guide.segments[judged.id].targetNotes.filter { result.missedNoteIDs.contains($0.id) }.map {
        PitchDetector.noteName(440 * pow(2, Double($0.midiNote - 69) / 12))
      }
      lastScore = value
      lastEvaluatedPhrase = judged.id
      if let sessionID {
        history.record(
          sessionID: sessionID, phrase: judged,
          attempt: progress.attempts[judged.id],
          start: max(0, (judged.id == progress.index ? max(attemptBeginsAt, origin + judged.start) : origin + judged.start) - sessionOrigin), score: value)
        persistHistory()
      }
      let configuration = PoCConfiguration.default
      let referenceZero = CMTime(seconds: origin, preferredTimescale: 60000)
      if let zeroFileTime = capture.fileTime(forCaptureTime: referenceZero),
         let range = TakeRangeBuilder().execute(segment: guide.segments[judged.id], referenceZeroFileTime: zeroFileTime) {
        takes.logAttempt(TakeAttemptLog(segmentIndex: judged.id, attemptNumber: progress.attempts[judged.id],
          videoTimeRange: range, accuracyScore: Float(value), missedNoteIDs: result.missedNoteIDs,
          status: value >= Double(configuration.passThreshold) ? .passed : .failed))
      }
      lastPassed = progress.resolve(score: value)
      if !lastPassed {
        playback.stop()
        displayIndex = judged.id
        elapsed = judged.duration
        phase = .result
        resultUntil = now + PracticeConfiguration.resultSeconds
        message = "Segment \(judged.id + 1) did not reach 75%. Retry begins after the countdown."
        return
      }
      if progress.finished {
        displayIndex = judged.id
        elapsed = judged.duration
        stopAudio()
        phase = .finished
        message = "Finished! All six segments passed."
        return
      }
      progress.beginAttempt()
      message = "Segment \(judged.id + 1) passed · keep singing."
      // Deliberately no stop, seek, prepare, or countdown here.
    }
  }
  private func persistHistory() {
    do {
      try history.save()
      historyError = nil
    } catch { historyError = "Riwayat belum tersimpan: \(error.localizedDescription)" }
  }
  private func stopAudio() {
    generation = UUID()
    timer?.invalidate()
    timer = nil
    playback.shutdown()
    pitchTask?.cancel()
    pitchTask = nil
    if recordingActive {
      recordingActive = false
      finalizing = true
      let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finalize recording", expirationHandler: nil)
      Task { @MainActor [weak self] in
        guard let self else { return }
        defer {
          self.finalizing = false
          if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
          try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        do {
          let url = try await self.capture.stopRecording()
          if self.discardRecording {
            try FileManager.default.removeItem(at: url.deletingLastPathComponent())
            self.rawVideoURL = nil
            self.endSummary = "Session discarded."
            return
          }
          let duration = try await AVURLAsset(url: url).load(.duration)
          self.rawVideoURL = url
          self.passedTakes = Array(self.takes.passedTakesPrefix().prefix(while: { CMTimeRangeGetEnd($0.videoTimeRange) <= duration }))
          self.handoffURL = try RecordingHandoff.write(videoURL: url, takes: self.passedTakes, segments: self.guide.segments)
          Contract.assertValid(TakeLogContract.validatePassedTakes(self.passedTakes, segments: self.guide.segments, crossfade: PoCConfiguration.default.crossfade))
          self.endSummary = "Recorded \(self.passedTakes.count) of \(self.guide.segments.count) passed segments. Raw video is ready."
        } catch {
          self.endSummary = "Video could not be finalized: \(error.localizedDescription)"
        }
      }
    } else { capture.stopSession() }
    running = false
    frequency = nil
  }
  func stop() {
    stopAudio()
    phase = .ready
    message = "Recording stopped. Completed takes are being saved."
  }
  func endSession(discard: Bool = false) {
    discardRecording = discard
    if discard { takes.clear() }
    stopAudio()
    if discard, let sessionID {
      history.sessions.removeAll { $0.id == sessionID }
      persistHistory()
      progress = PracticeProgress()
      endSummary = "Session discarded."
    } else {
      endSummary = "Saved practice results for \(passedSegmentCount) of \(Phrase.all.count) segments."
    }
    phase = .finished
  }
  func preview() {
    guard !running && !requesting && !finalizing else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
      player = try AVAudioPlayer(data: Accompaniment.wav(phrase: phrase))
      player?.volume = volume
      player?.play()
      message = "Preview for segment \(progress.index + 1). Use earphones when recording."
    } catch { message = "Referensi gagal diputar: \(error.localizedDescription)" }
  }
}
