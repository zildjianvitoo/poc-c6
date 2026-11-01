//
//  FakeAudioTranspositionRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation

/// Returns the input file unchanged; no audio is rendered.
nonisolated final class FakeAudioTranspositionRepository: AudioTranspositionRepository {
    func renderTransposed(_ audioURL: URL, semitones: Int) async throws -> URL {
        audioURL
    }
}
