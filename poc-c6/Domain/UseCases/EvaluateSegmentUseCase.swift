//
//  EvaluateSegmentUseCase.swift
//  poc-c6
//

import Foundation

nonisolated struct EvaluateSegmentUseCase {
    var configuration = PoCConfiguration.default

    /// Frame slots sit on the grid anchored at `segment.audioStartTime` (slot k at `audioStartTime + k * pitchHop`),
    /// the same grid the practice loop produces evaluations on. A slot belongs to a note when its time is in
    /// `[note.startTime + attackIgnore, note.endTime)`. Each slot takes the evaluation nearest to it within
    /// ±pitchHop/2; a slot with no evaluation is a miss. Slots are never clipped at the note end.
    func execute(segment: SongSegment, evaluations: [PitchEvaluation]) -> (score: Float, missedNoteIDs: [UUID]) {
        let hop = configuration.pitchHop
        guard hop > 0 else { return (0, segment.targetNotes.map(\.id)) }
        let tolerance = ContractTolerance.timeline
        let sorted = evaluations.sorted { $0.referenceTime < $1.referenceTime }
        var total = 0
        var hits = 0
        var missed: [UUID] = []
        for note in segment.targetNotes {
            var noteTotal = 0
            var noteHits = 0
            let evaluatedStart = note.startTime + configuration.attackIgnore
            let firstSlot = Int(ceil((evaluatedStart - segment.audioStartTime - tolerance) / hop))
            var slot = max(0, firstSlot)
            while true {
                let time = segment.audioStartTime + Double(slot) * hop
                if time >= note.endTime - tolerance { break }
                noteTotal += 1
                if nearestEvaluation(in: sorted, to: time, within: hop / 2)?.isHit == true { noteHits += 1 }
                slot += 1
            }
            total += noteTotal
            hits += noteHits
            if noteTotal > 0 && Float(noteHits) / Float(noteTotal) < configuration.missedNoteThreshold {
                missed.append(note.id)
            }
        }
        return (total == 0 ? 1 : Float(hits) / Float(total), missed)
    }

    /// Binary search over evaluations sorted by `referenceTime`.
    private func nearestEvaluation(in sorted: [PitchEvaluation], to time: TimeInterval, within radius: TimeInterval) -> PitchEvaluation? {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].referenceTime < time { low = mid + 1 } else { high = mid }
        }
        var best: PitchEvaluation?
        var bestDistance = TimeInterval.infinity
        for index in [low - 1, low] where sorted.indices.contains(index) {
            let distance = abs(sorted[index].referenceTime - time)
            if distance <= radius && distance < bestDistance {
                best = sorted[index]
                bestDistance = distance
            }
        }
        return best
    }
}
