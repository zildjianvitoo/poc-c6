//
//  SeparatedStems.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

nonisolated enum StemSeparationMethod: String, Sendable, Codable {
    case bundled
    case coreML
    case centerChannelCancellation
    case synthesized
}

/// Output of stem separation. All files are already trimmed and start at t = 0.
nonisolated struct SeparatedStems: Sendable {
    /// Full mix with the original vocals, used as the earphone guide.
    let mixURL: URL
    /// Vocal stem (or mid channel for the fallback), used for guide extraction.
    let vocalGuideURL: URL
    /// Music without the original vocals, used in the final mix.
    let instrumentalURL: URL
    let method: StemSeparationMethod
}
