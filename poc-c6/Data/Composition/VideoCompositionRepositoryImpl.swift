//
//  VideoCompositionRepositoryImpl.swift
//  poc-c6
//
//  Stitches passed takes, mixes in the instrumental and exports FinalCoverVideo.mp4 (PRD §5.9).
//  Owner: Zildjian Vito (ZV-10).
//

import AVFoundation
import CoreMedia

nonisolated final class VideoCompositionRepositoryImpl: VideoCompositionRepository {
    let outputURL: URL
    /// 1920×1080 caps a portrait recording at 1080×1920 and encodes H.264 + AAC.
    let presetName: String

    init(outputURL: URL = SessionFiles.finalVideoURL,
         presetName: String = AVAssetExportPreset1920x1080) {
        self.outputURL = outputURL
        self.presetName = presetName
    }

    func stitchAndExport(plan: CompingCompositionPlan,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let violations = plan.validate()
        guard violations.isEmpty else { throw CompingError.invalidPlan(violations) }

        let output = try await CompingCompositionBuilder().build(plan)
        guard let session = AVAssetExportSession(asset: output.composition, presetName: presetName) else {
            throw CompingError.exportUnavailable
        }
        session.audioMix = output.audioMix
        session.videoComposition = output.videoComposition
        session.timeRange = CMTimeRange(start: .zero,
                                        end: CMTime(seconds: plan.endTime, preferredTimescale: CompingCompositionBuilder.timescale))

        let url = outputURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)

        let progressTask = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }

        try await session.export(to: url, as: .mp4)
        progress(1)
        return url
    }
}
