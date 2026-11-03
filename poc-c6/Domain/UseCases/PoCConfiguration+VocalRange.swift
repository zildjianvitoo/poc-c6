//
//  PoCConfiguration+VocalRange.swift
//  poc-c6
//

import Foundation

// Feature defaults are computed so existing persisted configuration remains compatible.
extension PoCConfiguration {
    nonisolated var keyRecommendationCount: Int { 3 }
    nonisolated var rangePenaltyBand: Double { 3 }
    nonisolated var rangePenaltySpanDivisor: Double { 4 }
    nonisolated var speakingSampleDuration: TimeInterval { 6 }
    nonisolated var minimumSpeakingVoicedDuration: TimeInterval { 2 }
    nonisolated var rangeConfirmationTolerance: Float { 1 }
    nonisolated var minimumVocalRangeSpan: Float { 3 }
}
