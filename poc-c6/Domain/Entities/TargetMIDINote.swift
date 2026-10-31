//
//  TargetMIDINote.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

/// One note of the vocal guide, in the ORIGINAL key of the song.
/// Transposition is applied at display/evaluation time, never stored here.
nonisolated struct TargetMIDINote: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    /// MIDI note number, e.g. 60 = C4.
    let midiNote: Int
    /// Seconds from the start of the trimmed reference.
    let startTime: TimeInterval
    let duration: TimeInterval

    var endTime: TimeInterval { startTime + duration }

    init(id: UUID = UUID(), midiNote: Int, startTime: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.midiNote = midiNote
        self.startTime = startTime
        self.duration = duration
    }
}
