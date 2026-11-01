//
//  GuideAndPitchChecks.swift
//  poc-c6
//
//  Checks for SimplifyGuideUseCase and the octave-agnostic TrackLivePitchUseCase.
//

import CoreMedia
import Foundation

nonisolated enum GuideAndPitchChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "GuideAndPitch", message: message) }
        }
        func note(_ midi: Int, _ start: Double, _ length: Double) -> TargetMIDINote {
            TargetMIDINote(midiNote: midi, startTime: start, duration: length)
        }
        let simplify = SimplifyGuideUseCase()

        // A phrase that came out as fragments of nearly the same pitch becomes one block.
        let fragments = [note(60, 0.0, 0.2), note(61, 0.35, 0.2), note(60, 0.75, 0.3), note(60, 1.3, 0.25)]
        let one = simplify.execute(fragments)
        try check(one.count == 1 && one[0].midiNote == 60, "fragments → one block: \(one.map(\.midiNote))")
        try check(abs(one[0].startTime) < 1e-9 && abs(one[0].endTime - 1.55) < 1e-9, "block spans the phrase")

        // Different pitches stay separate but short gaps are closed (legato).
        let steps = simplify.execute([note(60, 0, 0.5), note(64, 0.7, 0.5), note(67, 1.4, 0.5)])
        try check(steps.map(\.midiNote) == [60, 64, 67], "steps keep their pitches")
        try check(abs(steps[0].endTime - steps[1].startTime) < 1e-9, "gap bridged")

        // A lonely short blip is dropped; a long gap is kept.
        let blip = simplify.execute([note(60, 0, 1.0), note(72, 2.0, 0.15), note(62, 4.0, 1.0)])
        try check(blip.map(\.midiNote) == [60, 62], "blip dropped: \(blip.map(\.midiNote))")
        try check(blip[0].endTime < blip[1].startTime - 1, "long gap kept")
        try check(simplify.execute([]).isEmpty, "empty stays empty")

        // Octave-agnostic scoring.
        let song = DomainFixtures.preparedSong
        let target = song.segments[0].targetNotes[0]
        let targetMIDI = Double(song.transposition.transposed(target))
        let anchor = CMTime(seconds: 100, preferredTimescale: 600)
        func evaluate(_ midi: Double) -> PitchEvaluation {
            let frequency = Float(440 * pow(2, (midi - 69) / 12))
            let sample = PitchSample(captureTime: anchor + CMTime(seconds: target.startTime + 0.3, preferredTimescale: 600),
                                     frequency: frequency, rmsDecibels: -20)
            return TrackLivePitchUseCase().execute(sample: sample, playbackAnchor: anchor, song: song)
        }
        for octave in [-12.0, 0, 12] {
            let evaluation = evaluate(targetMIDI + octave + 0.2)
            try check(evaluation.isHit && abs((evaluation.centDeviation ?? 99) - 20) < 0.5, "octave \(octave): hit at +20 cents")
            try check(abs(Double(evaluation.detectedMIDINote ?? 0) - (targetMIDI + 0.2)) < 0.01, "trail drawn in the target octave")
        }
        try check(!evaluate(targetMIDI + 1).isHit, "a semitone off is a miss")
        try check(!evaluate(targetMIDI - 13).isHit, "an octave and a semitone off is a miss")
        try check(TrackLivePitchUseCase.octaveFolded(7) == -5 && TrackLivePitchUseCase.octaveFolded(-7) == 5, "folding wraps")
        return count
    }
}
