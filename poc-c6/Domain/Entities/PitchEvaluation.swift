//
//  PitchEvaluation.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

/// A pitch sample compared against the (transposed) guide.
/// Used by the piano roll trail and by segment evaluation.
nonisolated struct PitchEvaluation: Sendable {
    /// Seconds on the trimmed song timeline.
    let referenceTime: TimeInterval
    let detectedMIDINote: Float?
    let targetNoteID: UUID?
    let centDeviation: Float?
    let isHit: Bool
}
