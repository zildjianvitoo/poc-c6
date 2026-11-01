//
//  RecordingViewModel.swift
//  poc-c6
//
//  Runs one recording session (PRD §5.5–5.8): the camera keeps recording while the loop
//  plays, evaluates, rewinds and continues; at the end the passed takes become a
//  CompingCompositionPlan. Every cut point comes from the capture clock (PRD §7.1).
//

import CoreMedia
import Foundation
import Observation

@Observable
final class RecordingViewModel {
    enum Status: Equatable {
        case starting
        case recording
        /// Finalizing the raw video file.
        case finishing
        /// Could not start; the user can fix the cause and retry.
        case blocked(UserFacingError)
        /// Stopped by a call, another app, unplugged earphones or a limit; the file is finalized.
        case interrupted(UserFacingError)
        case failed(UserFacingError)
    }

    struct SegmentResult: Equatable {
        let segmentIndex: Int
        let score: Float
        let passed: Bool
        let missedNoteIDs: [UUID]
    }

    /// One point of the user's pitch trail on the song timeline.
    struct TrailPoint {
        let songTime: TimeInterval
        let midi: Float?
        let isHit: Bool
    }

    struct PitchStats: Equatable {
        var samplesPerSecond = 0
        var voicedPercent = 0
        var lastNote: String?
        var lastLevelDB: Float = -.infinity
    }

    /// PRD §5.8: required free space before Record, and the floor that stops a running session.
    static let requiredStorageBytes: Int64 = 1_500_000_000
    static let reserveStorageBytes: Int64 = 128_000_000
    private static let storageCheckInterval: TimeInterval = 5
    private static let tickInterval: Duration = .milliseconds(20)
    /// How long to wait for the first video frame before giving up.
    private static let firstFrameTimeout: TimeInterval = 3
    /// While held, the segment start sits this far behind the playhead (the roll's past window).
    private static let heldSegmentLead: TimeInterval = 1
    /// Enough trail for the piano roll's past window.
    private static let trailLength: TimeInterval = 2

    let song: PreparedSong
    private(set) var status: Status = .starting
    private(set) var loop: LoopStateController
    private(set) var lastResult: SegmentResult?
    private(set) var trail: [TrailPoint] = []
    private(set) var route: AudioOutputRoute
    /// Debug readout: pitch samples in the last second, how many were voiced, and the last note.
    private(set) var pitchStats = PitchStats()

    @ObservationIgnored private let capture: any CaptureRepository
    @ObservationIgnored private let playback: any ReferencePlaybackRepository
    @ObservationIgnored private let routeMonitor: any AudioRouteMonitor
    @ObservationIgnored private let takeLog: any SessionTakeLogRepository
    @ObservationIgnored private let planner: AutoCompingVideoUseCase
    @ObservationIgnored private let configuration: PoCConfiguration
    @ObservationIgnored private let onFinish: (CompingCompositionPlan) -> Void
    @ObservationIgnored private let onDiscard: () -> Void
    @ObservationIgnored private let allowsSpeaker: Bool

    /// Capture-clock time at which song time 0 is heard. Set on every playback start.
    @ObservationIgnored private var anchor: CMTime?
    /// Pitch evaluations since the current playback started, in song time.
    @ObservationIgnored private var evaluations: [PitchEvaluation] = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var sessionStart: TimeInterval = 0
    @ObservationIgnored private var lastStorageCheck: TimeInterval = 0
    @ObservationIgnored private var rawVideoURL: URL?
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var recentSamples: [(time: TimeInterval, voiced: Bool)] = []

    init(song: PreparedSong,
         capture: any CaptureRepository,
         playback: any ReferencePlaybackRepository,
         routeMonitor: any AudioRouteMonitor,
         takeLog: any SessionTakeLogRepository,
         planner: AutoCompingVideoUseCase,
         configuration: PoCConfiguration,
         allowsSpeaker: Bool = false,
         onFinish: @escaping (CompingCompositionPlan) -> Void,
         onDiscard: @escaping () -> Void) {
        self.song = song
        self.capture = capture
        self.playback = playback
        self.routeMonitor = routeMonitor
        self.takeLog = takeLog
        self.planner = planner
        self.configuration = configuration
        self.onFinish = onFinish
        self.onDiscard = onDiscard
        self.allowsSpeaker = allowsSpeaker
        loop = LoopStateController(segments: song.segments, configuration: configuration)
        route = routeMonitor.currentRoute
    }

    // MARK: - What the screen shows

    var previewSource: (any CameraPreviewSource)? { capture as? any CameraPreviewSource }
    var segmentCount: Int { song.segments.count }
    var passedCount: Int { loop.passedCount }
    var showsBluetoothWarning: Bool { route == .bluetooth }
    /// Debug speaker test: recording on the loudspeaker is allowed and flagged on screen.
    var isSpeakerTest: Bool { route == .speaker && allowsSpeaker }

    /// "Segment 3 / 7 · Attempt 2" (index + 1 for display).
    var progressTitle: String {
        let segment = min(loop.segmentIndex, segmentCount - 1) + 1
        return "Segment \(segment) / \(segmentCount) · Attempt \(max(loop.currentAttempt, 1))"
    }

    /// Song time now, from the capture clock; nil before playback started.
    func currentSongTime() -> TimeInterval? {
        anchor.map { (capture.currentCaptureTime() - $0).seconds }
    }

    /// What the piano roll shows: live song time while singing; during the TRY AGAIN result and
    /// countdown it holds on the failed segment so its missed notes stay visible.
    func displaySongTime() -> TimeInterval? {
        switch loop.phase {
        case .showingResult, .countdown:
            loop.currentSegment.map { $0.audioStartTime + Self.heldSegmentLead }
        default:
            currentSongTime()
        }
    }

    // MARK: - Session

    func start() async {
        guard status == .starting || isBlocked else { return }
        status = .starting
        route = routeMonitor.currentRoute
        guard route.allowsRecording || allowsSpeaker else {
            status = .blocked(.speakerOutput)
            return
        }
        guard SessionFiles.availableCapacity() >= Self.requiredStorageBytes else {
            status = .blocked(.lowStorage(requiredGB: Double(Self.requiredStorageBytes) / 1_000_000_000))
            return
        }
        do {
            try await capture.prepare()
            try playback.load(earphoneMixURL: song.earphoneMixURL)
            observe()
            try await capture.startRecording()
            isCapturing = true
            // The file starts at the first video frame; playing before it exists would put the
            // first take's handle before the start of the file.
            try await waitForFirstFrame()
            sessionStart = capture.currentCaptureTime().seconds
            lastStorageCheck = sessionStart
            status = .recording
            perform(loop.begin(now: capture.currentCaptureTime().seconds))
            startTicking()
        } catch {
            stopObserving()
            status = .failed(.recordingFailed(details: error.localizedDescription))
        }
    }

    private func waitForFirstFrame() async throws {
        let deadline = capture.currentCaptureTime().seconds + Self.firstFrameTimeout
        while capture.fileTime(forCaptureTime: capture.currentCaptureTime()) == nil {
            guard capture.currentCaptureTime().seconds < deadline else {
                throw RecordingError.noVideoFrames
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private enum RecordingError: LocalizedError {
        case noVideoFrames
        var errorDescription: String? { "The camera didn't deliver any video. Close other camera apps and try again." }
    }

    /// End Session → "Export N of M", or the session limit / last segment.
    func finish() async {
        guard let url = await stopCapture() else { return }
        if let plan = planner.makePlan(rawVideoURL: url, song: song, configuration: configuration) {
            onFinish(plan)
        } else {
            status = .interrupted(.nothingToExport)
        }
    }

    /// Stops after an interruption (PRD §5.8) and keeps the passed takes for a partial export.
    func interrupt() async {
        guard status == .recording else { return }
        if await stopCapture() != nil {
            status = .interrupted(passedCount > 0 ? .recordingInterrupted : .nothingToExport)
        }
    }

    /// Export what passed before the interruption.
    func exportAfterInterruption() {
        guard let rawVideoURL,
              let plan = planner.makePlan(rawVideoURL: rawVideoURL, song: song, configuration: configuration) else { return }
        onFinish(plan)
    }

    func discard() async {
        if isCapturing { _ = await stopCapture() }
        takeLog.clear()
        SessionFiles.cleanUp()
        onDiscard()
    }

    private var isBlocked: Bool {
        if case .blocked = status { true } else { false }
    }

    /// Finalizes RawMasterVideo.mov. Returns nil (and shows the error) when that fails.
    private func stopCapture() async -> URL? {
        guard isCapturing else { return rawVideoURL }
        isCapturing = false
        loop.end()
        stopObserving()
        playback.stop()
        status = .finishing
        do {
            let url = try await capture.stopRecording()
            rawVideoURL = url
            return url
        } catch {
            status = .failed(.recordingFailed(details: error.localizedDescription))
            return nil
        }
    }

    // MARK: - Loop

    private func startTicking() {
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        })
    }

    private func tick() {
        guard status == .recording else { return }
        let now = capture.currentCaptureTime()
        let seconds = now.seconds
        if seconds - sessionStart >= configuration.maxSessionDuration {
            Task { await interrupt() }
            return
        }
        if seconds - lastStorageCheck >= Self.storageCheckInterval {
            lastStorageCheck = seconds
            if SessionFiles.availableCapacity() < Self.reserveStorageBytes {
                Task { await interrupt() }
                return
            }
        }
        perform(loop.tick(now: seconds, songTime: anchor.map { (now - $0).seconds }))
    }

    private func perform(_ action: LoopStateController.Action) {
        switch action {
        case .none:
            break
        case .startPlayback(let referenceTime):
            evaluations = []
            trail = []
            lastResult = nil
            do {
                let heard = try playback.play(from: referenceTime)
                anchor = heard - CMTime(seconds: referenceTime, preferredTimescale: heard.timescale)
            } catch {
                Task { await fail(.recordingFailed(details: error.localizedDescription)) }
            }
        case .stopPlayback:
            playback.stop()
        case .evaluate(let index):
            evaluate(segmentIndex: index)
        case .finish:
            Task { await finish() }
        }
    }

    private func evaluate(segmentIndex index: Int) {
        let segment = song.segments[index]
        let inSegment = evaluations.filter {
            $0.referenceTime >= segment.audioStartTime - configuration.pitchHop
                && $0.referenceTime < segment.audioEndTime + configuration.pitchHop
        }
        let result = EvaluateSegmentUseCase(configuration: configuration).execute(segment: segment, evaluations: inSegment)
        let passed = result.score >= configuration.passThreshold
        // The take range is what makes comping possible; never pretend a take passed without one.
        guard let anchor,
              let referenceZero = capture.fileTime(forCaptureTime: anchor),
              let range = TakeRangeBuilder(configuration: configuration).execute(segment: segment, referenceZeroFileTime: referenceZero)
        else {
            Task { await fail(.recordingFailed(details: "This take couldn't be placed on the video timeline.")) }
            return
        }
        takeLog.logAttempt(TakeAttemptLog(
            segmentIndex: index,
            attemptNumber: loop.currentAttempt,
            videoTimeRange: range,
            accuracyScore: result.score,
            missedNoteIDs: result.missedNoteIDs,
            status: passed ? .passed : .failed))
        lastResult = SegmentResult(segmentIndex: index, score: result.score, passed: passed, missedNoteIDs: result.missedNoteIDs)
        if passed {
            // The next segment is already being sung; keep only its evaluations.
            evaluations.removeAll { $0.referenceTime < segment.audioEndTime - configuration.pitchHop }
        }
        perform(loop.resolve(passed: passed, now: capture.currentCaptureTime().seconds))
    }

    private func fail(_ error: UserFacingError) async {
        _ = await stopCapture()
        status = .failed(error)
    }

    // MARK: - Debug readout

    private func updatePitchStats(_ sample: PitchSample) {
        let time = sample.captureTime.seconds
        let voiced = sample.frequency != nil && sample.rmsDecibels >= configuration.noiseGateDBFS
        recentSamples.append((time, voiced))
        recentSamples.removeAll { $0.time < time - 1 }
        var stats = PitchStats()
        stats.samplesPerSecond = recentSamples.count
        stats.voicedPercent = recentSamples.isEmpty ? 0 : recentSamples.filter(\.voiced).count * 100 / recentSamples.count
        stats.lastNote = voiced ? sample.frequency.flatMap { PitchMath.midi(fromFrequency: Double($0)) }.map { PitchMath.noteName(midi: Int($0.rounded())) } : nil
        stats.lastLevelDB = sample.rmsDecibels
        pitchStats = stats
    }

    // MARK: - Inputs

    private func observe() {
        let pitch = capture.pitchSamples()
        let routes = routeMonitor.routeChanges()
        let interruptions = routeMonitor.interruptions()
        tasks.append(Task { [weak self] in
            for await sample in pitch { self?.handle(sample) }
        })
        tasks.append(Task { [weak self] in
            for await route in routes {
                guard let self else { return }
                self.route = route
                if !route.allowsRecording && !self.allowsSpeaker { await self.interrupt() }
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in interruptions { await self?.interrupt() }
        })
        tasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .captureRepositoryFailure) {
                await self?.fail(.recordingFailed(details: "The camera or microphone stopped. Your passed segments are saved."))
            }
        })
    }

    private func stopObserving() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func handle(_ sample: PitchSample) {
        updatePitchStats(sample)
        guard let anchor, loop.phase == .preRoll || loop.phase == .singing else { return }
        let evaluation = TrackLivePitchUseCase(configuration: configuration)
            .execute(sample: sample, playbackAnchor: anchor, song: song)
        evaluations.append(evaluation)
        trail.append(TrailPoint(songTime: evaluation.referenceTime, midi: evaluation.detectedMIDINote, isHit: evaluation.isHit))
        trail.removeAll { $0.songTime < evaluation.referenceTime - Self.trailLength }
    }
}
