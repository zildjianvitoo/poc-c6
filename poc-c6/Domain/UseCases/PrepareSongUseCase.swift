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
        let (stems, extracted) = try await extract(audioURL: audioURL, trimRange: trimRange, progress: progress)
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

    struct Choices: Sendable {
        struct Option: Sendable {
            let song: PreparedSong
            let recommendation: RecommendKeysUseCase.Recommendation
        }
        let options: [Option]
        let excerpt: ClosedRange<TimeInterval>?
        let vocalRange: VocalRange
    }

    /// Separate and analyse once; render only the best fully fitting keys.
    func executeChoices(audioURL: URL, trimRange: ClosedRange<TimeInterval>, vocalRange: VocalRange,
                        progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Choices {
        let (stems, extracted) = try await extract(audioURL: audioURL, trimRange: trimRange, progress: progress)
        return try await makeChoices(stems: stems, notes: extracted,
                                     duration: trimRange.upperBound - trimRange.lowerBound,
                                     vocalRange: vocalRange, progress: progress)
    }

    /// Also used by the demo, whose original guide is already known.
    func makeChoices(stems: SeparatedStems, notes: [TargetMIDINote], duration: TimeInterval,
                     vocalRange: VocalRange,
                     progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Choices {
        let slicer = SliceSegmentsUseCase(configuration: configuration)
        // Sanitise timestamps without simplifying away extremes or changing note durations.
        let original = try slicer.execute(notes: notes, duration: duration).flatMap(\.targetNotes)
        guard !original.isEmpty else {
            throw ContractViolation(contract: "Preparation", message: "No guide notes detected.")
        }
        let recommender = RecommendKeysUseCase(configuration: configuration)
        let recommendations = try recommender.execute(notes: original, vocalRange: vocalRange)
        let excerpt = recommender.highestPhrase(notes: original, duration: duration)
        let segments = try slicer.execute(notes: SimplifyGuideUseCase().execute(original), duration: duration)
        var options: [Choices.Option] = []
        for (index, recommendation) in recommendations.enumerated() {
            try Task.checkCancellation()
            progress("Preparing key \(index + 1) of \(recommendations.count)")
            let shift = recommendation.plan.semitoneShift
            let mix = try await transposition.renderTransposed(stems.mixURL, semitones: shift)
            try Task.checkCancellation()
            let instrumental = try await transposition.renderTransposed(stems.instrumentalURL, semitones: shift)
            try Task.checkCancellation()
            let song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: segments,
                                    transposition: recommendation.plan, duration: duration, separationMethod: stems.method)
            if let violation = song.validate().first { throw violation }
            options.append(Choices.Option(song: song, recommendation: recommendation))
        }
        return Choices(options: options, excerpt: excerpt, vocalRange: vocalRange)
    }

    private func extract(audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                         progress: @escaping @Sendable (String) -> Void) async throws -> (SeparatedStems, [TargetMIDINote]) {
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
        return (stems, extracted)
    }

}
