//
//  CrepeEstimate.swift
//  poc-c6
//

import Foundation

nonisolated struct CrepeEstimate {
  var frequency: Double? = nil
  var confidence = 0.0
  var rms = 0.0
  var reason = "Audio terlalu pendek"
  var centerOffset = 0.0
}

// Confined to PitchWorker serial queue. No target-note correction or YIN fallback.
