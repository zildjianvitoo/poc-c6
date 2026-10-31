//
//  StemSeparationRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Ikzaz
//

import Foundation

nonisolated protocol StemSeparationRepository: Sendable {
    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems
}
