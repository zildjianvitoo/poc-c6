//
//  SegmentEvaluator.swift
//  poc-c6
//

import Foundation

nonisolated struct SegmentEvaluator {
  static let maeThreshold = PracticeConfiguration.maeThreshold
  static func passesMAE(_ value: Double?) -> Bool {
    guard let value, value.isFinite, value >= 0 else { return false }
    return value <= maeThreshold + 1e-9
  }
  private(set) var errorSum = [Double](repeating: 0, count: Twinkle.notes.count)
  private(set) var errorCount = [Int](repeating: 0, count: Twinkle.notes.count)
  func meanAbsoluteError(for notes: [ReferenceNote]) -> Double? {
    let count = notes.reduce(0) { $0 + errorCount[$1.id] }
    guard count > 0 else { return nil }
    return notes.reduce(0) { $0 + errorSum[$1.id] } / Double(count)
  }
  static let tolerance = PracticeConfiguration.hitToleranceCents
  static let passThreshold = PracticeConfiguration.passThreshold
  private(set) var matched = [Double](repeating: 0, count: Twinkle.notes.count)
  private(set) var voiced = [Double](repeating: 0, count: Twinkle.notes.count)
  private var lastEnd = 0.0
  var score: Double { min(1, matched.reduce(0, +) / Twinkle.duration) }
  var passed: Bool { score + 1e-9 >= Self.passThreshold }
  mutating func ingest(
    frequency: Double?, start: Double, duration: Double, sampleTime: Double? = nil
  ) {
    let end = min(Twinkle.duration, start + duration)
    let begin = max(0, max(start, lastEnd))
    guard end > begin else { return }
    lastEnd = end
    guard let frequency, frequency.isFinite, frequency > 0 else { return }
    let center = sampleTime ?? (begin + end) / 2
    if let reference = Twinkle.note(at: center), center >= begin && center < end {
      errorSum[reference.id] += abs(PitchDetector.cents(frequency, from: reference.frequency))
      errorCount[reference.id] += 1
    }
    for note in Twinkle.notes {
      let overlap = max(0, min(end, note.start + note.duration) - max(begin, note.start + PoCConfiguration.default.attackIgnore))
      voiced[note.id] += overlap
      let targets = Twinkle.notes.filter {
        center >= $0.start - PoCConfiguration.default.timingTolerance && center < $0.start + $0.duration + PoCConfiguration.default.timingTolerance
      }
      if targets.contains(where: { abs(PitchDetector.cents(frequency, from: $0.frequency)) <= Self.tolerance + 1e-9 }) {
        matched[note.id] += overlap
      }
    }
  }
}
