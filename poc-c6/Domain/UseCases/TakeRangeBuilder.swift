//
//  TakeRangeBuilder.swift
//  poc-c6
//

import CoreMedia
import Foundation

nonisolated struct TakeRangeBuilder {
    var configuration = PoCConfiguration.default

    func execute(segment: SongSegment, referenceZeroFileTime: CMTime) -> CMTimeRange? {
        guard referenceZeroFileTime.isNumeric, referenceZeroFileTime.seconds.isFinite,
              segment.audioDuration > 0, segment.audioStartTime.isFinite else { return nil }
        let start = CMTimeAdd(referenceZeroFileTime, CMTime(seconds: segment.audioStartTime - configuration.crossfade, preferredTimescale: 60000))
        guard start.seconds >= 0 else { return nil }
        return CMTimeRange(start: start, duration: CMTime(seconds: segment.audioDuration + 2 * configuration.crossfade, preferredTimescale: 60000))
    }
}
