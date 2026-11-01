//
//  Phrase.swift
//  poc-c6
//

import Foundation

nonisolated struct Phrase: Identifiable {
  let id: Int
  let words: [String]
  var notes: [ReferenceNote] { Array(Twinkle.notes[(id * 7)..<(id * 7 + 7)]) }
  var start: Double { notes[0].start }
  var duration: Double { notes.reduce(0) { $0 + $1.duration } }
  var lyric: String {
    words.joined(separator: " ").replacingOccurrences(of: "Twin kle", with: "Twinkle")
      .replacingOccurrences(of: "twin kle", with: "twinkle").replacingOccurrences(
        of: "won der", with: "wonder"
      ).replacingOccurrences(of: "a bove", with: "above").replacingOccurrences(
        of: "dia mond", with: "diamond"
      ).replacingOccurrences(of: "lit tle", with: "little")
  }
  static let all = [
    Phrase(id: 0, words: ["Twin", "kle,", "twin", "kle,", "lit", "tle", "star"]),
    Phrase(id: 1, words: ["How", "I", "won", "der", "what", "you", "are"]),
    Phrase(id: 2, words: ["Up", "a", "bove", "the", "world", "so", "high"]),
    Phrase(id: 3, words: ["Like", "a", "dia", "mond", "in", "the", "sky"]),
    Phrase(id: 4, words: ["Twin", "kle,", "twin", "kle,", "lit", "tle", "star"]),
    Phrase(id: 5, words: ["How", "I", "won", "der", "what", "you", "are"]),
  ]
  func score(_ evaluator: SegmentEvaluator) -> Double {
    min(1, notes.reduce(0) { $0 + evaluator.matched[$1.id] } / notes.reduce(0.0) { $0 + max(0, $1.duration - PoCConfiguration.default.attackIgnore) })
  }
}
