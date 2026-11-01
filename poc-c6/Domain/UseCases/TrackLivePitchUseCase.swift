//
//  TrackLivePitchUseCase.swift
//  poc-c6
//

import CoreMedia
import Foundation

nonisolated struct TrackLivePitchUseCase {
    var configuration = PoCConfiguration.default

    /// Anchor is the capture-clock instant at which reference time zero is heard.
    func execute(sample: PitchSample, playbackAnchor: CMTime, song: PreparedSong) -> PitchEvaluation {
        let time = CMTimeSubtract(sample.captureTime, playbackAnchor).seconds
        let detected = sample.frequency.flatMap { frequency -> Float? in
            guard frequency.isFinite, frequency > 0, sample.rmsDecibels >= configuration.noiseGateDBFS else { return nil }
            return 69 + 12 * log2(frequency / 440)
        }
        let candidates = song.segments.flatMap(\.targetNotes).filter {
            time >= $0.startTime - configuration.timingTolerance && time < $0.endTime + configuration.timingTolerance
        }
        let target = candidates.min {
            abs((detected ?? 0) - Float(song.transposition.transposed($0))) < abs((detected ?? 0) - Float(song.transposition.transposed($1)))
        }
        let cents = target.flatMap { note in detected.map { ($0 - Float(song.transposition.transposed(note))) * 100 } }
        return PitchEvaluation(referenceTime: time, detectedMIDINote: detected, targetNoteID: target?.id, centDeviation: cents, isHit: cents.map { abs($0) <= configuration.hitToleranceCents } ?? false)
    }
}
