//
//  VocalRange.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

/// The user's comfortable range, as float MIDI note numbers.
nonisolated struct VocalRange: Sendable, Equatable, Codable {
    let lowestMIDI: Float
    let highestMIDI: Float
}
