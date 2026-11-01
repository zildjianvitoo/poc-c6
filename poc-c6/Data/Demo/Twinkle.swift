//
//  Twinkle.swift
//  poc-c6
//

import Foundation

nonisolated enum Twinkle {
  static let notes: [ReferenceNote] = {
    // Six phrases, C major, 100 BPM. Longer phrase endings last two beats.
    let phrases = [
      [60, 60, 67, 67, 69, 69, 67], [65, 65, 64, 64, 62, 62, 60],
      [67, 67, 65, 65, 64, 64, 62], [67, 67, 65, 65, 64, 64, 62],
      [60, 60, 67, 67, 69, 69, 67], [65, 65, 64, 64, 62, 62, 60],
    ]
    var result: [ReferenceNote] = []
    var start = 0.0
    for phrase in phrases {
      for (index, midi) in phrase.enumerated() {
        let duration = index == 6 ? 1.2 : 0.6
        result.append(ReferenceNote(id: result.count, midi: midi, start: start, duration: duration))
        start += duration
      }
    }
    return result
  }()
  static let duration = notes.last!.start + notes.last!.duration
  static func note(at time: Double) -> ReferenceNote? {
    notes.first { time >= $0.start && time < $0.start + $0.duration }
  }
}
