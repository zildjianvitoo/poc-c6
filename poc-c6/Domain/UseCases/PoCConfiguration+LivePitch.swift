//
//  PoCConfiguration+LivePitch.swift
//  poc-c6
//

import Foundation

extension PoCConfiguration {
    nonisolated var pitchDisplaySmoothing: Float { 0.5 }
    nonisolated var pitchDisplayDeadband: Float { 0.1 }
    nonisolated var pitchDisplayJumpThreshold: Float { 0.75 }
    nonisolated var pitchDisplayMaximumGap: TimeInterval { 0.2 }
    nonisolated var guideMergeGap: TimeInterval { 0.35 }
    nonisolated var guideBridgeGap: TimeInterval { 0.3 }
    nonisolated var guideMedianRadius: Int { 2 }
    /// Buffer timestamps can contain sub-millisecond jitter without missing audio samples.
    nonisolated var pitchTimestampJitterTolerance: TimeInterval { 0.002 }
}
