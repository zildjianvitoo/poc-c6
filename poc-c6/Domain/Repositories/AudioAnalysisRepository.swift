//
//  AudioAnalysisRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Ikzaz
//

import Foundation

nonisolated protocol AudioAnalysisRepository: Sendable {
    /// Input is already trimmed. Returns notes in the ORIGINAL key, sorted by `startTime`.
    func extractVocalGuideNotes(from vocalGuideURL: URL) async throws -> [TargetMIDINote]
}
