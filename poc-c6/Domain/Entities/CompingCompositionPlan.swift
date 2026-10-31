//
//  CompingCompositionPlan.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import CoreMedia
import Foundation

nonisolated struct CompingCompositionPlan: Sendable {
    let rawVideoURL: URL
    let instrumentalURL: URL
    /// Used to place each take at `segment.audioStartTime` on the song timeline.
    let segments: [SongSegment]
    /// One passed take per segment, prefix 0...N-1, ordered by segment index.
    let validTakes: [TakeAttemptLog]
    /// End of the last passed segment, in seconds on the song timeline.
    let endTime: TimeInterval
    let crossfadeDuration: CMTime
    /// 1.0 s for a partial export, 0 for a full export.
    let instrumentalFadeOut: TimeInterval
    let vocalGain: Float
    let instrumentalGain: Float

    var isPartial: Bool { validTakes.count < segments.count }
}
