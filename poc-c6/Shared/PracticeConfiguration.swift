//
//  PracticeConfiguration.swift
//  poc-c6
//

import Foundation

/// Existing PoC values, preserved during migration. These are not the new PRD defaults.
nonisolated enum PracticeConfiguration {
  static let passThreshold = 0.75
  static let legacyPassThreshold = 0.75
  static let hitToleranceCents = 50.0
  static let maeThreshold = 34.5
  static let minimumRMS = 0.01
  static let yinThreshold = 0.15
  static let crepeConfidence = 0.5
  static let countdownSeconds = 3.0
  static let resultSeconds = 2.0
  static let displayInterval = 0.03
  static let stalePitchSeconds = 0.25
  static let evaluationTail = 0.15
  static let traceGap = 0.2
  static let preferredSampleRate = 48000.0
  static let preferredIOBufferDuration = 0.02
  static let minimumRecordingStorageBytes: Int64 = 1_500_000_000
  static let storageReserveBytes: Int64 = 128_000_000
  static let storageCheckInterval = 5.0
  static let captureBufferSize: UInt32 = 4096
}
