//
//  PreparedSong.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Handoff: Ikzaz (preparation) -> Takin (recording) and Zildjian (comping).
//

import Foundation

nonisolated struct PreparedSong: Sendable {
    /// Full mix, already transposed by `transposition.semitoneShift`.
    let earphoneMixURL: URL
    /// No original vocals, transposed by the SAME `semitoneShift`, starts at t = 0.
    let instrumentalURL: URL
    let segments: [SongSegment]
    let transposition: TranspositionPlan
    /// Duration of the trimmed song in seconds.
    let duration: TimeInterval
    let separationMethod: StemSeparationMethod
}
