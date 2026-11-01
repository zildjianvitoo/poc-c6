//
//  AttemptRecord.swift
//  poc-c6
//

import Foundation

nonisolated struct AttemptRecord: Codable, Identifiable {
  let id: UUID
  let phraseIndex: Int
  let attempt: Int
  let sessionStart: Double
  let sessionEnd: Double
  let songStart: Double
  let songEnd: Double
  let score: Double
  var mae: Double? = nil
  var usesMAE: Bool? = nil
  var sampleCount: Int? = nil
  var maeLimit: Double? = nil
  var metricText: String {
    if usesMAE == true {
      return mae.map { String(format: "MAE %.1f cents", $0) } ?? "Tidak ada sampel valid"
    }
    return String(format: "Skor lama %.1f%%", score * 100)
  }
  var threshold: Double? = nil
  // Older saved attempts used 75%; preserve their original result.
  var passed: Bool {
    if usesMAE == true {
      guard let mae, mae.isFinite, mae >= 0 else { return false }
      return mae <= (maeLimit ?? PracticeConfiguration.maeThreshold) + 1e-9
    }
    return score + 1e-9 >= (threshold ?? PracticeConfiguration.legacyPassThreshold)
  }
  var label: String { passed ? "LOLOS" : "GAGAL" }
}
