//
//  PracticeSessionRecord.swift
//  poc-c6
//

import Foundation

nonisolated struct PracticeSessionRecord: Codable, Identifiable {
  let id: UUID
  let startedAt: Date
  var attempts: [AttemptRecord] = []
  var finalResults: [AttemptRecord] {
    (0..<6).compactMap { index in attempts.last { $0.phraseIndex == index && $0.passed } }
  }
  mutating func record(
    phrase: Phrase, attempt: Int, start: Double, score: Double, mae: Double? = nil,
    useMAE: Bool = false, sampleCount: Int = 0
  ) {
    guard start.isFinite, start >= 0, score.isFinite,
      !attempts.contains(where: { $0.phraseIndex == phrase.id && $0.attempt == attempt })
    else { return }
    attempts.append(
      AttemptRecord(
        id: UUID(), phraseIndex: phrase.id, attempt: attempt,
        sessionStart: start, sessionEnd: start + phrase.duration,
        songStart: phrase.start, songEnd: phrase.start + phrase.duration,
        score: min(1, max(0, score)), mae: mae, usesMAE: useMAE, sampleCount: sampleCount,
        maeLimit: useMAE ? SegmentEvaluator.maeThreshold : nil,
        threshold: SegmentEvaluator.passThreshold))
  }
}
