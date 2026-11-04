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

        // A phrase that came out as fragments of the same pitch becomes one block.
        let fragments = [note(60, 0.0, 0.2), note(60, 0.35, 0.2), note(60, 0.75, 0.3), note(60, 1.3, 0.25)]
        let one = simplify.execute(fragments)
        try check(one.count == 1 && one[0].midiNote == 60, "fragments → one block: \(one.map(\.midiNote))")
        try check(abs(one[0].startTime) < 1e-9 && abs(one[0].endTime - 1.55) < 1e-9, "block spans the phrase")

        // Different pitches stay separate but short gaps are closed (legato).
        let steps = simplify.execute([note(60, 0, 0.5), note(64, 0.7, 0.5), note(67, 1.4, 0.5)])
        try check(steps.map(\.midiNote) == [60, 64, 67], "steps keep their pitches")
        try check(abs(steps[0].endTime - steps[1].startTime) < 1e-9, "gap bridged")

        // A valid short note is retained; a long gap is kept.
        let blip = simplify.execute([note(60, 0, 1.0), note(72, 2.0, 0.15), note(62, 4.0, 1.0)])
        try check(blip.map(\.midiNote) == [60, 72, 62], "short note retained: \(blip.map(\.midiNote))")
        try check(blip[0].endTime < blip[2].startTime - 1, "long gap kept")
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

        // Voiced-only scoring: breaths/consonants don't fail a segment, silence still does.
        let phrase = SongSegment(index: 0, audioStartTime: 0, audioDuration: 4, targetNotes: [note(60, 0, 4)])
        func evaluations(voicedShare: Double, inTune: Bool) -> [PitchEvaluation] {
            (0..<80).map { slot in
                let time = Double(slot) * 0.05 + 1e-6
                let voiced = Double(slot % 10) < voicedShare * 10
                return PitchEvaluation(referenceTime: time, detectedMIDINote: voiced ? 60 : nil, targetNoteID: nil,
                                       centDeviation: voiced ? 0 : nil, isHit: voiced && inTune)
            }
        }
        let evaluate = EvaluateSegmentUseCase()
        let breathy = evaluate.execute(segment: phrase, evaluations: evaluations(voicedShare: 0.7, inTune: true)).score
        try check(breathy >= 0.99, "70% voiced, all in tune → passes (\(breathy))")
        let sparse = evaluate.execute(segment: phrase, evaluations: evaluations(voicedShare: 0.4, inTune: true)).score
        try check(sparse < 0.5, "40% voiced → silence counts, fails (\(sparse))")
        let offKey = evaluate.execute(segment: phrase, evaluations: evaluations(voicedShare: 0.9, inTune: false)).score
        try check(offKey == 0, "voiced but out of tune → 0 (\(offKey))")
        return count
    }
}
