//
//  ComputeTranspositionUseCase.swift
//  poc-c6
//

import Foundation

nonisolated struct ComputeTranspositionUseCase: Sendable {
    func execute(notes: [TargetMIDINote], vocalRange: VocalRange) throws -> TranspositionPlan {
        guard vocalRange.lowestMIDI.isFinite, vocalRange.highestMIDI.isFinite,
              vocalRange.lowestMIDI <= vocalRange.highestMIDI else {
            throw ContractViolation(contract: "Transposition", message: "Invalid vocal range.")
        }
        guard !notes.isEmpty else { return .none }
        // Octave size is defined by the contract's symmetric total shift range.
        let octave = TranspositionPlan.totalRange.upperBound
        let plans = TranspositionPlan.totalRange.compactMap { total -> TranspositionPlan? in
            let candidates = TranspositionPlan.semitoneRange.compactMap { semitone -> TranspositionPlan? in
                guard (total - semitone).isMultiple(of: octave) else { return nil }
                return TranspositionPlan(octaveShift: (total - semitone) / octave, semitoneShift: semitone)
            }
            return candidates.min { abs($0.semitoneShift) < abs($1.semitoneShift) }
        }
        func outside(_ plan: TranspositionPlan) -> Int {
            notes.filter { note in
                let pitch = Float(plan.transposed(note))
                return pitch < vocalRange.lowestMIDI || pitch > vocalRange.highestMIDI
            }.count
        }
        return plans.min { a, b in
            let ca = (outside(a), abs(a.semitoneShift), abs(a.totalSemitones), a.totalSemitones)
            let cb = (outside(b), abs(b.semitoneShift), abs(b.totalSemitones), b.totalSemitones)
            return ca < cb
        } ?? .none
    }
}
