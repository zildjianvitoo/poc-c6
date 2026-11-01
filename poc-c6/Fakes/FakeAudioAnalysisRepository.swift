//
//  FakeAudioAnalysisRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation

/// Returns the notes of `DomainFixtures.segments`, in the original key.
nonisolated final class FakeAudioAnalysisRepository: AudioAnalysisRepository {
    func extractVocalGuideNotes(from vocalGuideURL: URL) async throws -> [TargetMIDINote] {
        DomainFixtures.segments.flatMap(\.targetNotes).sorted { $0.startTime < $1.startTime }
    }
}
