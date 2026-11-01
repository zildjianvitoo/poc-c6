//
//  PrepareSongUseCase.swift
//  poc-c6
//

import Foundation

/// Orchestrates preparation using injected repositories; owns no media framework.
nonisolated struct PrepareSongUseCase: Sendable {
    let separation: any StemSeparationRepository
    let analysis: any AudioAnalysisRepository
    let fallbackAnalysis: (any AudioAnalysisRepository)?
    let transposition: any AudioTranspositionRepository
    var configuration: PoCConfiguration = .default

    func execute(audioURL: URL, trimRange: ClosedRange<TimeInterval>, vocalRange: VocalRange,
                 progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> PreparedSong {
        guard trimRange.lowerBound.isFinite, trimRange.upperBound.isFinite,
              trimRange.lowerBound >= 0, trimRange.upperBound > trimRange.lowerBound else {
            throw ContractViolation(contract: "Preparation", message: "Invalid trim range.")
        }
        try Task.checkCancellation()
        progress("Separating vocals and backing music")
        let stems = try await separation.separateStems(from: audioURL, trimRange: trimRange)
        progress("Extracting the vocal guide")
        let extracted: [TargetMIDINote]
        do {
            let primary = try await analysis.extractVocalGuideNotes(from: stems.vocalGuideURL)
            guard !primary.isEmpty else {
                throw ContractViolation(contract: "Preparation", message: "No guide notes detected.")
            }
            extracted = primary
        } catch {
            try Task.checkCancellation()
            guard let fallbackAnalysis else { throw error }
            progress("Using fallback pitch analysis")
            extracted = try await fallbackAnalysis.extractVocalGuideNotes(from: stems.vocalGuideURL)
        }
        // Fewer, longer blocks that a singer can follow (device feedback 2026-11-01).
        let notes = SimplifyGuideUseCase().execute(extracted)
        guard !notes.isEmpty else {
            throw ContractViolation(contract: "Preparation", message: "We couldn't find a vocal melody in this section. Try another part of the song.")
        }
        try Task.checkCancellation()
        progress("Building practice segments")
        let duration = trimRange.upperBound - trimRange.lowerBound
        let segments = try SliceSegmentsUseCase(configuration: configuration).execute(notes: notes, duration: duration)
        let plan = try ComputeTranspositionUseCase().execute(notes: notes, vocalRange: vocalRange)
        progress("Rendering the rehearsal key")
        // Octaves affect targets only. Both audio tracks receive the same semitone shift.
        let mix = try await transposition.renderTransposed(stems.mixURL, semitones: plan.semitoneShift)
        try Task.checkCancellation()
        let instrumental = try await transposition.renderTransposed(stems.instrumentalURL, semitones: plan.semitoneShift)
        try Task.checkCancellation()
        let song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: segments,
                                transposition: plan, duration: duration, separationMethod: stems.method)
        if let violation = song.validate().first { throw violation }
        progress("Ready")
        return song
    }
}
