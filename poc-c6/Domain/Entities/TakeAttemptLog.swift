//
//  TakeAttemptLog.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Handoff: Takin (recording) -> Zildjian (comping).
//

import CoreMedia
import Foundation

nonisolated enum SegmentAttemptStatus: String, Sendable, Codable {
    case passed
    case failed

    var displayLabel: String { self == .passed ? "PASSED" : "TRY AGAIN" }
}

nonisolated struct TakeAttemptLog: Identifiable, Sendable {
    let id: UUID
    /// Zero-based, matches `SongSegment.index`.
    let segmentIndex: Int
    /// 1-based, per segment.
    let attemptNumber: Int
    /// File time inside RawMasterVideo.mov, aligned to what the user heard
    /// (latency compensated), INCLUDING the crossfade handle on both sides.
    let videoTimeRange: CMTimeRange
    /// 0.0 ... 1.0
    let accuracyScore: Float
    let missedNoteIDs: [UUID]
    let status: SegmentAttemptStatus

    init(id: UUID = UUID(), segmentIndex: Int, attemptNumber: Int, videoTimeRange: CMTimeRange, accuracyScore: Float, missedNoteIDs: [UUID], status: SegmentAttemptStatus) {
        self.id = id
        self.segmentIndex = segmentIndex
        self.attemptNumber = attemptNumber
        self.videoTimeRange = videoTimeRange
        self.accuracyScore = accuracyScore
        self.missedNoteIDs = missedNoteIDs
        self.status = status
    }
}
