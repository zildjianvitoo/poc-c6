//
//  SongSegment.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

/// A phrase of the song. Segments tile the whole trimmed timeline with no holes:
/// segment[0] starts at 0, each segment starts where the previous one ends,
/// and the last one ends at the song duration.
nonisolated struct SongSegment: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    /// Zero-based. UI shows `index + 1`.
    let index: Int
    let audioStartTime: TimeInterval
    let audioDuration: TimeInterval
    let targetNotes: [TargetMIDINote]

    var audioEndTime: TimeInterval { audioStartTime + audioDuration }
    /// Intro/interlude without vocals: played and recorded, auto-passes without evaluation.
    var isInstrumentalOnly: Bool { targetNotes.isEmpty }

    init(id: UUID = UUID(), index: Int, audioStartTime: TimeInterval, audioDuration: TimeInterval, targetNotes: [TargetMIDINote]) {
        self.id = id
        self.index = index
        self.audioStartTime = audioStartTime
        self.audioDuration = audioDuration
        self.targetNotes = targetNotes
    }
}
