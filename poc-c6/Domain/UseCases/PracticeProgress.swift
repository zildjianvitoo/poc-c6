//
//  PracticeProgress.swift
//  poc-c6
//

import Foundation

nonisolated struct PracticeProgress {
  private(set) var maeValues: [Double?] = Array(repeating: nil, count: 6)
  private(set) var evaluated = Array(repeating: false, count: 6)
  @discardableResult mutating func resolveMAE(_ value: Double?) -> Bool {
    guard !finished else { return true }
    maeValues[index] = value
    evaluated[index] = true
    let pass = SegmentEvaluator.passesMAE(value)
    if pass {
      if index == Phrase.all.count - 1 { finished = true } else { index += 1 }
    }
    return pass
  }
  private(set) var index = 0
  private(set) var attempts = [Int](repeating: 0, count: 6)
  private(set) var scores: [Double?] = Array(repeating: nil, count: 6)
  private(set) var finished = false
  mutating func beginAttempt() { attempts[index] += 1 }
  // A failed attempt never advances the phrase or overwrites a passed phrase.
  @discardableResult mutating func resolve(score: Double) -> Bool {
    guard !finished else { return true }
    let pass = score.isFinite && score + 1e-9 >= SegmentEvaluator.passThreshold
    scores[index] = score.isFinite ? min(1, max(0, score)) : 0
    if pass {
      if index == Phrase.all.count - 1 { finished = true } else { index += 1 }
    }
    return pass
  }
}
