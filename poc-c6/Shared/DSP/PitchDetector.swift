//
//  PitchDetector.swift
//  poc-c6
//

import Foundation

nonisolated enum PitchDetector {
  static func cents(_ frequency: Double, from reference: Double) -> Double {
    1200 * log2(frequency / reference)
  }
  static func noteName(_ frequency: Double) -> String {
    guard frequency > 0, frequency.isFinite else { return "—" }
    let midi = Int((69 + 12 * log2(frequency / 440)).rounded())
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return "\(names[(midi % 12 + 12) % 12])\(midi / 12 - 1)"
  }
  // YIN cumulative mean normalized difference; silence/noise rejected.
  static func detect(_ input: [Float], sampleRate: Double) -> Double? {
    guard sampleRate > 0, input.count >= 512 else { return nil }
    let stride = max(1, Int(sampleRate / 12000))
    var x: [Double] = []
    for offset in Swift.stride(from: 0, to: input.count - stride + 1, by: stride) {
      var sum = 0.0
      for i in 0..<stride { sum += Double(input[offset + i]) }
      x.append(sum / Double(stride))
    }
    let rate = sampleRate / Double(stride)
    let mean = x.reduce(0, +) / Double(x.count)
    for i in x.indices { x[i] -= mean }
    let rms = sqrt(x.reduce(0) { $0 + $1 * $1 } / Double(x.count))
    guard rms > PracticeConfiguration.minimumRMS else { return nil }
    let maxLag = min(Int(rate / 80), x.count / 2 - 1)
    let minLag = max(2, Int(rate / 1000))
    guard maxLag > minLag else { return nil }
    let window = x.count - maxLag
    var difference = [Double](repeating: 1, count: maxLag + 1)
    var running = 0.0
    for lag in 1...maxLag {
      var sum = 0.0
      for i in 0..<window {
        let delta = x[i] - x[i + lag]
        sum += delta * delta
      }
      running += sum
      difference[lag] = running > 0 ? sum * Double(lag) / running : 1
    }
    var lag = minLag
    while lag < maxLag {
      if difference[lag] < PracticeConfiguration.yinThreshold {
        while lag + 1 <= maxLag && difference[lag + 1] < difference[lag] { lag += 1 }
        guard lag < maxLag else { return nil }
        let a = difference[lag - 1]
        let b = difference[lag]
        let c = difference[lag + 1]
        let denominator = a - 2 * b + c
        let adjustment = abs(denominator) > 1e-10 ? 0.5 * (a - c) / denominator : 0
        let frequency = rate / (Double(lag) + adjustment)
        return (80...1000).contains(frequency) ? frequency : nil
      }
      lag += 1
    }
    return nil
  }
}
