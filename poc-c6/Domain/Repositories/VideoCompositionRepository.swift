//
//  VideoCompositionRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Zildjian Vito
//

import Foundation

nonisolated protocol VideoCompositionRepository: Sendable {
    /// Returns the URL of FinalCoverVideo.mp4. `progress` is 0.0 ... 1.0.
    func stitchAndExport(plan: CompingCompositionPlan,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}
