//
//  RecordingHandoff.swift
//  poc-c6
//

import CoreMedia
import Foundation

/// Portable metadata alongside the raw recording; times are file seconds, including handles.
nonisolated struct RecordingHandoff: Codable {
    struct Take: Codable {
        let segmentIndex: Int
        let attempt: Int
        let fileStart: Double
        let fileDuration: Double
        let score: Float
        let missedNoteIDs: [UUID]
    }
    let version: Int
    let rawVideoFile: String
    let segments: [SongSegment]
    let passedTakes: [Take]
    let crossfadeSeconds: Double

    static func write(videoURL: URL, takes: [TakeAttemptLog], segments: [SongSegment]) throws -> URL {
        let crossfade = PoCConfiguration.default.crossfade
        let violations = TakeLogContract.validatePassedTakes(takes, segments: segments, crossfade: crossfade)
        guard violations.isEmpty else { throw violations[0] }
        let handoff = Self(version: 1, rawVideoFile: videoURL.lastPathComponent, segments: segments,
            passedTakes: takes.map { Take(segmentIndex: $0.segmentIndex, attempt: $0.attemptNumber, fileStart: $0.videoTimeRange.start.seconds, fileDuration: $0.videoTimeRange.duration.seconds, score: $0.accuracyScore, missedNoteIDs: $0.missedNoteIDs) }, crossfadeSeconds: crossfade)
        let url = videoURL.deletingLastPathComponent().appendingPathComponent("PassedTakes.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(handoff).write(to: url, options: .atomic)
        return url
    }
}
