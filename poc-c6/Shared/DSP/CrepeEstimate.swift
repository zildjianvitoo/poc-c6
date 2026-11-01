//
//  CrepeEstimate.swift
//  poc-c6
//
//  One CREPE analysis window: pitch (nil = unvoiced), confidence and loudness.
//

import Foundation

nonisolated struct CrepeEstimate: Sendable {
    var frequency: Double?
    var confidence = 0.0
    /// Root-mean-square amplitude of the analysed window (linear, 0…1).
    var rms = 0.0
    /// Seconds from the start of the input window to the centre of the analysed frame.
    var centerOffset = 0.0
}
