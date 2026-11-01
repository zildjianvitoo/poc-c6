//
//  AutoCompingVideoUseCase.swift
//  poc-c6
//
//  Turns the passed takes of a session into the final cover (PRD §6.4). Owner: Zildjian Vito (ZV-11).
//

import CoreMedia
import Foundation

nonisolated struct AutoCompingVideoUseCase {
    let takeLog: any SessionTakeLogRepository
    let videoComposition: any VideoCompositionRepository

    /// nil when no segment has passed yet ("Nothing to export yet").
    func makePlan(rawVideoURL: URL, song: PreparedSong, configuration: PoCConfiguration) -> CompingCompositionPlan? {
        let takes = takeLog.passedTakesPrefix()
        guard let last = takes.last else { return nil }
        let isPartial = takes.count < song.segments.count
        let plan = CompingCompositionPlan(
            rawVideoURL: rawVideoURL,
            instrumentalURL: song.instrumentalURL,
            segments: song.segments,
            validTakes: takes,
            endTime: song.segments[last.segmentIndex].audioEndTime,
            crossfadeDuration: CMTime(seconds: configuration.crossfade, preferredTimescale: 48_000),
            instrumentalFadeOut: isPartial ? configuration.partialExportFadeOut : 0,
            vocalGain: configuration.vocalGain,
            instrumentalGain: configuration.instrumentalGain
        )
        Contract.assertValid(plan.validate())
        return plan
    }

    func export(_ plan: CompingCompositionPlan, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await videoComposition.stitchAndExport(plan: plan, progress: progress)
    }
}
