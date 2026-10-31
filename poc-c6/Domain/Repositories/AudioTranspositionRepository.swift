//
//  AudioTranspositionRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Ikzaz
//

import Foundation

nonisolated protocol AudioTranspositionRepository: Sendable {
    /// Renders a pitch-shifted copy offline. Returns `audioURL` unchanged when `semitones == 0`.
    func renderTransposed(_ audioURL: URL, semitones: Int) async throws -> URL
}
