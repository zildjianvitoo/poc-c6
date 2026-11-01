//
//  FakeVideoCompositionRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation

/// Validates the plan, reports progress over `duration`, and returns a placeholder URL. No file is written.
nonisolated final class FakeVideoCompositionRepository: VideoCompositionRepository {
    let duration: Duration

    init(duration: Duration = .seconds(1)) {
        self.duration = duration
    }

    func stitchAndExport(plan: CompingCompositionPlan,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        Contract.assertValid(plan.validate())
        let steps = 10
        for step in 1...steps {
            try await Task.sleep(for: duration / steps)
            progress(Double(step) / Double(steps))
        }
        return DomainFixtures.placeholderDirectory.appendingPathComponent("FinalCoverVideo.mp4")
    }
}
