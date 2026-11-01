//
//  PitchMath.swift
//  poc-c6
//
//  Frequency ↔ MIDI ↔ note name, implemented once (PRD §5.3).
//

import Foundation

nonisolated enum PitchMath {
    static func midi(fromFrequency frequency: Double) -> Double? {
        guard frequency.isFinite, frequency > 0 else { return nil }
        return 69 + 12 * log2(frequency / 440)
    }

    static func frequency(fromMIDI midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    static func cents(_ frequency: Double, from reference: Double) -> Double {
        1200 * log2(frequency / reference)
    }

    /// "C4", "F♯3", … for a MIDI note number.
    static func noteName(midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[(midi % 12 + 12) % 12])\(midi / 12 - 1)"
    }
}
