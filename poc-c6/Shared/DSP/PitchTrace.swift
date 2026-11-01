//
//  PitchTrace.swift
//  poc-c6
//

import Foundation

nonisolated enum PitchTrace {
  static let lowerMIDI = 48.0
  static let upperMIDI = 72.0
  static func smoothed(_ points: [PitchPoint]) -> [PitchPoint] {
    guard points.count >= 3 else { return [] }
    return (1..<(points.count - 1)).map { index in
      let center = points[index]
      let window = Array(points[(index - 1)...(index + 1)])
      let validTimes =
        window[1].time > window[0].time && window[2].time > window[1].time
        && window[1].time - window[0].time < PracticeConfiguration.traceGap
        && window[2].time - window[1].time < PracticeConfiguration.traceGap
      let values = window.compactMap(\.frequency).filter { $0.isFinite && $0 > 0 }
      // Do not invent a pitch over silence or missing buffers.
      guard validTimes, values.count == 3 else {
        return PitchPoint(time: center.time, frequency: nil)
      }
      return PitchPoint(time: center.time, frequency: values.sorted()[1])
    }
  }
}
