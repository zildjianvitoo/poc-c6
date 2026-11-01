//
//  ReferenceNote.swift
//  poc-c6
//

import Foundation

nonisolated struct ReferenceNote: Identifiable {
  let id: Int
  let midi: Int
  let start: Double
  let duration: Double
  var frequency: Double { 440 * pow(2, Double(midi - 69) / 12) }
  var name: String { PitchDetector.noteName(frequency) }
}
