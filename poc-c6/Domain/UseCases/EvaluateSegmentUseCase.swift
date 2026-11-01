//
//  EvaluateSegmentUseCase.swift
//  poc-c6
//

import Foundation

nonisolated struct EvaluateSegmentUseCase {
    var configuration = PoCConfiguration.default

    /// Missing frames count as misses. Each scheduled frame contributes once.
    func execute(segment: SongSegment, evaluations: [PitchEvaluation]) -> (score: Float, missedNoteIDs: [UUID]) {
        var total = 0
        var hits = 0
        var missed: [UUID] = []
        guard configuration.pitchHop > 0 else { return (0, segment.targetNotes.map(\.id)) }
        for note in segment.targetNotes {
            var noteTotal = 0
            var noteHits = 0
            let firstFrame = Int(ceil((note.startTime + configuration.attackIgnore) / configuration.pitchHop - 1e-9))
            let endFrame = Int(ceil(note.endTime / configuration.pitchHop - 1e-9))
            for index in firstFrame..<max(firstFrame, endFrame) {
                let time = Double(index) * configuration.pitchHop
                noteTotal += 1
                let frame = evaluations.filter {
                    $0.referenceTime >= time && $0.referenceTime < min(time + configuration.pitchHop, note.endTime)
                }.min { $0.referenceTime < $1.referenceTime }
                if frame?.isHit == true { noteHits += 1 }
            }
            total += noteTotal
            hits += noteHits
            if noteTotal > 0 && Float(noteHits) / Float(noteTotal) < configuration.missedNoteThreshold {
                missed.append(note.id)
            }
        }
        return (total == 0 ? 1 : Float(hits) / Float(total), missed)
    }
}
