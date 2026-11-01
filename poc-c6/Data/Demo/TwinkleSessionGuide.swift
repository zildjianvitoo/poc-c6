//
//  TwinkleSessionGuide.swift
//  poc-c6
//

import Foundation

/// A stable session-local mapping from the demo notes to the shared song contracts.
nonisolated struct TwinkleSessionGuide {
    let segments: [SongSegment]

    init() {
        segments = Phrase.all.map { phrase in
            SongSegment(index: phrase.id, audioStartTime: phrase.start, audioDuration: phrase.duration,
                targetNotes: phrase.notes.map {
                    TargetMIDINote(midiNote: $0.midi, startTime: $0.start, duration: $0.duration)
                })
        }
    }

    func evaluate(frequency: Double?, time: TimeInterval) -> PitchEvaluation {
        let midi = frequency.flatMap { $0.isFinite && $0 > 0 ? Float(69 + 12 * log2($0 / 440)) : nil }
        let configuration = PoCConfiguration.default
        let candidates = segments.flatMap(\.targetNotes).filter {
            time >= $0.startTime - configuration.timingTolerance && time < $0.endTime + configuration.timingTolerance
        }
        let target = candidates.min { abs((midi ?? 0) - Float($0.midiNote)) < abs((midi ?? 0) - Float($1.midiNote)) }
        let deviation = target.flatMap { note in midi.map { ($0 - Float(note.midiNote)) * 100 } }
        return PitchEvaluation(referenceTime: time, detectedMIDINote: midi, targetNoteID: target?.id,
            centDeviation: deviation, isHit: deviation.map { abs($0) <= configuration.hitToleranceCents } ?? false)
    }
}
