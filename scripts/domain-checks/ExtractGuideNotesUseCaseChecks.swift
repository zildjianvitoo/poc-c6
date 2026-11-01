//
//  ExtractGuideNotesUseCaseChecks.swift
//  poc-c6
//
//  Executable checks for ExtractGuideNotesUseCase (IK-07, PRD §5.3 CREPE fallback). Not part of the app target.
//

import Foundation

nonisolated enum ExtractGuideNotesUseCaseChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "ExtractGuideNotesUseCase", message: message) }
        }
        func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

        /// Frames at `hop` spacing for a pitch `shape(t)` between `from` and `to` (frame centres at from + hop/2 + k*hop).
        func frames(_ from: Double, _ to: Double, hop: Double, confidence: Double = 0.9,
                    _ shape: (Double) -> Float?) -> [GuidePitchFrame] {
            let n = Int(((to - from) / hop).rounded())
            return (0..<n).map { k in
                let t = from + hop / 2 + Double(k) * hop
                return GuidePitchFrame(time: t, midi: shape(t - from), confidence: confidence)
            }
        }
        func extract(_ input: [GuidePitchFrame], hop: Double = 0.05) -> [TargetMIDINote] {
            ExtractGuideNotesUseCase(hop: hop).execute(frames: input)
        }
        func monophonic(_ notes: [TargetMIDINote]) -> Bool {
            zip(notes, notes.dropFirst()).allSatisfy { $0.endTime <= $1.startTime + 1e-9 && $0.startTime <= $1.startTime }
                && notes.allSatisfy { $0.duration > 0 && $0.startTime >= 0 }
        }

        // Empty input
        try check(extract([]).isEmpty, "empty input -> []")

        // Steady notes with gaps
        let steady = frames(0.2, 1.2, hop: 0.05) { _ in 60 }
            + frames(1.4, 2.0, hop: 0.05) { _ in 64 }
            + frames(2.2, 3.4, hop: 0.05) { _ in 67 }
        let steadyNotes = extract(steady)
        try check(steadyNotes.map(\.midiNote) == [60, 64, 67], "steady notes MIDI \(steadyNotes.map(\.midiNote))")
        try check(near(steadyNotes[0].startTime, 0.2) && near(steadyNotes[0].endTime, 1.2), "note 1 bounds")
        try check(near(steadyNotes[2].startTime, 2.2) && near(steadyNotes[2].endTime, 3.4), "note 3 bounds")
        try check(monophonic(steadyNotes), "steady notes monophonic")

        // Fractional pitch rounds to the median
        let sharp = extract(frames(0, 0.5, hop: 0.05) { _ in 60.3 })
        try check(sharp.map(\.midiNote) == [60], "60.3 rounds to 60")

        // Vibrato +-30 cents stays one note
        let vibrato = extract(frames(0, 2, hop: 0.05) { 62 + 0.3 * Float(sin(2 * .pi * 5.5 * $0)) })
        try check(vibrato.count == 1 && vibrato[0].midiNote == 62, "vibrato stays one note: \(vibrato.map(\.midiNote))")

        // Glide (2 semitones/s... fast: 12 semitones in 0.6 s) produces no long note
        let glide = extract(frames(0, 0.6, hop: 0.05) { 60 + Float($0 / 0.6 * 12) })
        try check(glide.allSatisfy { $0.duration < 0.2 }, "glide gives no long note")
        try check(monophonic(glide), "glide monophonic")

        // Blip of 100 ms dropped; 150 ms kept
        let blip = extract(frames(0.5, 0.6, hop: 0.05) { _ in 70 })
        try check(blip.isEmpty, "100 ms blip dropped")
        let short = extract(frames(0.5, 0.65, hop: 0.05) { _ in 70 })
        try check(short.count == 1 && near(short[0].duration, 0.15), "150 ms note kept")

        // Same pitch: 40 ms apart merged, 80 ms apart kept (hop 10 ms)
        let merged = extract(frames(0, 0.5, hop: 0.01) { _ in 65 } + frames(0.54, 1.0, hop: 0.01) { _ in 65 }, hop: 0.01)
        try check(merged.count == 1 && near(merged[0].startTime, 0) && near(merged[0].endTime, 1.0),
                  "40 ms gap merged: \(merged.count)")
        let kept = extract(frames(0, 0.5, hop: 0.01) { _ in 65 } + frames(0.58, 1.0, hop: 0.01) { _ in 65 }, hop: 0.01)
        try check(kept.count == 2 && near(kept[1].startTime - kept[0].endTime, 0.08), "80 ms gap kept: \(kept.count)")

        // Different pitch separated by a short gap are never merged
        let different = extract(frames(0, 0.5, hop: 0.01) { _ in 65 } + frames(0.54, 1.0, hop: 0.01) { _ in 67 }, hop: 0.01)
        try check(different.map(\.midiNote) == [65, 67], "different pitches not merged")

        // Single missing frame tolerated inside a region
        var holey = frames(0, 1, hop: 0.05) { _ in 60 }
        holey.remove(at: 8)
        let holeyNotes = extract(holey)
        try check(holeyNotes.count == 1 && near(holeyNotes[0].startTime, 0) && near(holeyNotes[0].endTime, 1),
                  "single missing frame tolerated")
        // Two missing frames split the note (gap 100 ms < 120 ms merge rule does not apply: gap is 100 ms >= 50 ms)
        var split = frames(0, 1, hop: 0.05) { _ in 60 }
        split.removeSubrange(8..<10)
        try check(extract(split).count == 2, "two missing frames split")

        // Low confidence ignored
        let weak = extract(frames(0, 1, hop: 0.05, confidence: 0.3) { _ in 60 })
        try check(weak.isEmpty, "low confidence ignored")
        let mixed = extract(frames(0, 0.5, hop: 0.05) { _ in 60 } + frames(0.5, 1.0, hop: 0.05, confidence: 0.2) { _ in 72 })
        try check(mixed.count == 1 && mixed[0].midiNote == 60 && near(mixed[0].endTime, 0.5), "weak tail dropped")

        // Unvoiced frames (nil midi) ignored
        try check(extract(frames(0, 1, hop: 0.05) { _ in nil }).isEmpty, "nil midi ignored")

        // Note start clamped at 0
        let early = extract([0.0, 0.05, 0.1, 0.15].map { GuidePitchFrame(time: $0, midi: 60, confidence: 1) })
        try check(early.count == 1 && early[0].startTime == 0, "start clamped at 0")

        // Unsorted input and sorted output
        let shuffled = (steady).reversed()
        let shuffledNotes = extract(Array(shuffled))
        try check(shuffledNotes.map(\.midiNote) == [60, 64, 67], "unsorted input sorted output")

        // Octave jump between adjacent regions is two notes, no overlap
        let jump = extract(frames(0, 0.5, hop: 0.05) { _ in 60 } + frames(0.5, 1.0, hop: 0.05) { _ in 72 })
        try check(jump.map(\.midiNote) == [60, 72] && monophonic(jump), "jump gives two notes")

        return count
    }
}
