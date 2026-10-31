//
//  TranspositionPlan.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

/// Total shift = `octaveShift * 12 + semitoneShift`, within -12...12.
nonisolated struct TranspositionPlan: Sendable, Equatable, Codable {
    static let semitoneRange = -6...6
    static let totalRange = -12...12

    /// Applied to target notes only. Audio is not changed for octaves.
    let octaveShift: Int
    /// Applied to target notes AND rendered into the earphone mix and the instrumental.
    let semitoneShift: Int

    var totalSemitones: Int { octaveShift * 12 + semitoneShift }

    static let none = TranspositionPlan(octaveShift: 0, semitoneShift: 0)

    /// Target note as shown in the piano roll and used for scoring.
    func transposed(_ note: TargetMIDINote) -> Int {
        note.midiNote + totalSemitones
    }
}
