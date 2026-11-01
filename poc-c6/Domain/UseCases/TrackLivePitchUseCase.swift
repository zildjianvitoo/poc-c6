//
//  TrackLivePitchUseCase.swift
//  poc-c6
//
//  Compares a live pitch sample with the (transposed) guide (PRD §5.6). Octaves are ignored:
//  singing the melody an octave lower or higher counts as in tune (device feedback 2026-11-01),
//  and the trail is drawn in the target's octave so it stays on the piano roll.
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
        guard let detected else {
            let target = candidates.first
            return PitchEvaluation(referenceTime: time, detectedMIDINote: nil, targetNoteID: target?.id, centDeviation: nil, isHit: false)
        }
        let target = candidates.min {
            abs(Self.octaveFolded(detected - Float(song.transposition.transposed($0))))
                < abs(Self.octaveFolded(detected - Float(song.transposition.transposed($1))))
        }
        guard let target else {
            return PitchEvaluation(referenceTime: time, detectedMIDINote: detected, targetNoteID: nil, centDeviation: nil, isHit: false)
        }
        let targetMIDI = Float(song.transposition.transposed(target))
        let deviation = Self.octaveFolded(detected - targetMIDI)
        return PitchEvaluation(referenceTime: time, detectedMIDINote: targetMIDI + deviation, targetNoteID: target.id,
                               centDeviation: deviation * 100, isHit: abs(deviation * 100) <= configuration.hitToleranceCents)
    }

    /// Semitone difference reduced to the nearest octave: −6 … +6.
    static func octaveFolded(_ semitones: Float) -> Float {
        semitones - 12 * (semitones / 12).rounded()
    }
}
