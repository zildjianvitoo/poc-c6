//
//  LoopStateController.swift
//  poc-c6
//
//  The recording loop as a pure state machine (PRD §5.6, §6.1):
//  preRoll → singing → evaluate → { passed → singing(next) | failed → result → countdown → preRoll } → ended.
//  It only decides; RecordingViewModel performs the actions. All times are capture-clock seconds
//  (`now`) or song-timeline seconds (`songTime`), never wall-clock time.
//

import Foundation

nonisolated struct LoopStateController: Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        /// Silent countdown before a retry; `remaining` whole seconds are shown.
        case countdown(remaining: Int)
        /// Reference audio before the segment start; nothing is evaluated yet.
        case preRoll
        case singing
        /// TRY AGAIN result is on screen; playback is stopped.
        case showingResult
        case ended
    }

    enum Action: Equatable, Sendable {
        case none
        case startPlayback(from: TimeInterval)
        case stopPlayback
        case evaluate(segmentIndex: Int)
        case finish
    }

    /// PRD §5.6: the TRY AGAIN result stays up for about a second before the countdown.
    static let resultDuration: TimeInterval = 1

    let segments: [SongSegment]
    let configuration: PoCConfiguration
    private(set) var phase: Phase = .idle
    private(set) var segmentIndex = 0
    /// 1-based attempt number per segment; 0 = not reached yet.
    private(set) var attempts: [Int]
    private var countdownEndsAt: TimeInterval = 0
    private var resultEndsAt: TimeInterval = 0

    init(segments: [SongSegment], configuration: PoCConfiguration) {
        self.segments = segments
        self.configuration = configuration
        attempts = Array(repeating: 0, count: segments.count)
    }

    var currentSegment: SongSegment? { segments.indices.contains(segmentIndex) ? segments[segmentIndex] : nil }
    var currentAttempt: Int { attempts.indices.contains(segmentIndex) ? attempts[segmentIndex] : 0 }
    /// Segments 0..<passedCount have passed (always a prefix, PRD §5.7).
    var passedCount: Int { phase == .ended && segmentIndex >= segments.count ? segments.count : segmentIndex }

    /// First attempt of the first segment: pre-roll without a countdown.
    mutating func begin() -> Action {
        guard phase == .idle, let segment = currentSegment else { return .none }
        attempts[segmentIndex] = 1
        phase = .preRoll
        return .startPlayback(from: preRollStart(for: segment))
    }

    mutating func tick(now: TimeInterval, songTime: TimeInterval?) -> Action {
        switch phase {
        case .idle, .ended:
            return .none
        case .countdown:
            if now >= countdownEndsAt, let segment = currentSegment {
                attempts[segmentIndex] += 1
                phase = .preRoll
                return .startPlayback(from: preRollStart(for: segment))
            }
            phase = .countdown(remaining: max(1, Int((countdownEndsAt - now).rounded(.up))))
            return .none
        case .showingResult:
            guard now >= resultEndsAt else { return .none }
            countdownEndsAt = now + TimeInterval(configuration.countdownSeconds)
            phase = .countdown(remaining: configuration.countdownSeconds)
            return .none
        case .preRoll, .singing:
            guard let songTime, let segment = currentSegment else { return .none }
            if phase == .preRoll, songTime >= segment.audioStartTime { phase = .singing }
            guard phase == .singing, songTime >= segment.audioEndTime + configuration.evaluationTail else { return .none }
            return .evaluate(segmentIndex: segmentIndex)
        }
    }

    /// Result of the evaluation requested by `.evaluate`.
    mutating func resolve(passed: Bool, now: TimeInterval) -> Action {
        guard phase == .singing else { return .none }
        if passed {
            segmentIndex += 1
            guard segmentIndex < segments.count else {
                phase = .ended
                return .finish
            }
            // Segments tile the timeline, so the next one has already started: keep singing.
            attempts[segmentIndex] = 1
            return .none
        }
        resultEndsAt = now + Self.resultDuration
        phase = .showingResult
        return .stopPlayback
    }

    mutating func end() {
        phase = .ended
    }

    /// PRD §5.6: 2 s of reference before the segment (from 0 when not available).
    private func preRollStart(for segment: SongSegment) -> TimeInterval {
        max(0, segment.audioStartTime - configuration.preRoll)
    }
}
