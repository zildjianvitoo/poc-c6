//
//  FakeStemSeparationRepository.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation

nonisolated final class FakeStemSeparationRepository: StemSeparationRepository {
    let delay: Duration

    init(delay: Duration = .milliseconds(300)) {
        self.delay = delay
    }

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        try await Task.sleep(for: delay)
        let directory = DomainFixtures.placeholderDirectory
        return SeparatedStems(
            mixURL: directory.appendingPathComponent("mix.m4a"),
            vocalGuideURL: directory.appendingPathComponent("vocal.m4a"),
            instrumentalURL: directory.appendingPathComponent("instrumental.m4a"),
            method: .synthesized
        )
    }
}
