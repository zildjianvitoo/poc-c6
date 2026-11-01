//
//  PoCConfiguration.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Every tunable number lives here. Never hard-code these values elsewhere.
//

import Foundation

nonisolated struct PoCConfiguration: Sendable, Equatable, Codable {
    // Evaluation
    var passThreshold: Float = 0.75
    var hitToleranceCents: Float = 80
    var noiseGateDBFS: Float = -40
    var pitchHop: TimeInterval = 0.05
    var attackIgnore: TimeInterval = 0.10
    var timingTolerance: TimeInterval = 0.10
    var missedNoteThreshold: Float = 0.50

    // Segmentation
    var segmentGap: TimeInterval = 0.8
    var minSegment: TimeInterval = 3.0
    var maxSegment: TimeInterval = 8.0

    // Session
    var preRoll: TimeInterval = 2.0
    var countdownSeconds: Int = 3
    var maxSessionDuration: TimeInterval = 15 * 60
    var manualLatencyCalibration: TimeInterval = 0
    var evaluationTail: TimeInterval = 0.15

    // Comping
    var crossfade: TimeInterval = 0.03
    var partialExportFadeOut: TimeInterval = 1.0
    var vocalGain: Float = 1.0
    var instrumentalGain: Float = 0.8

    // Feature flags
    var useCoreMLSeparation = false

    static let `default` = PoCConfiguration()
}
