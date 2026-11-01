//
//  PitchPoint.swift
//  poc-c6
//

import Foundation

nonisolated struct PitchPoint: Identifiable {
  let id = UUID()
  let time: Double
  let frequency: Double?
}

// Small synthesized piano-like melody + arpeggiated chords. One WAV per phrase.
