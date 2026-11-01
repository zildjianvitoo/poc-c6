import Foundation

@main
struct CoreChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        for rate in [44100.0, 48000.0] {
            for hz in [110.0, 261.6256, 329.6276, 391.9954, 440.0, 880.0] {
                let signal = (0..<4096).map { Float(0.25 * sin(2 * .pi * hz * Double($0) / rate)) }
                let pitch = PitchDetector.detect(signal, sampleRate: rate)
                check(pitch != nil && abs(PitchDetector.cents(pitch!, from: hz)) < 10, "Pitch error at \(hz), rate \(rate): \(String(describing: pitch))")
            }
        }
        let harmonic = (0..<4096).map { i -> Float in
            let phase = 2 * Double.pi * 261.6256 * Double(i) / 48000
            return Float(0.12 * sin(phase) + 0.25 * sin(2 * phase) + 0.08 * sin(3 * phase))
        }
        check(abs(PitchDetector.cents(PitchDetector.detect(harmonic, sampleRate: 48000) ?? 1, from: 261.6256)) < 10, "Harmonic signal")
        check(PitchDetector.detect([Float](repeating: 0, count: 4096), sampleRate: 48000) == nil, "Silence")
        check(PitchDetector.detect([Float](repeating: 0.2, count: 4096), sampleRate: 48000) == nil, "DC")
        var seed: UInt64 = 42
        let noise = (0..<4096).map { _ -> Float in
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5)
        }
        check(PitchDetector.detect(noise, sampleRate: 48000) == nil, "Noise rejection")
        check(Twinkle.notes.count == 42 && abs(Twinkle.duration - 28.8) < 1e-9, "Reference structure")
        var perfect = SegmentEvaluator()
        var wrongOctave = SegmentEvaluator()
        var boundary = SegmentEvaluator()
        var below = SegmentEvaluator()
        var silence = SegmentEvaluator()
        for note in Twinkle.notes {
            perfect.ingest(frequency: note.frequency, start: note.start, duration: note.duration)
            wrongOctave.ingest(frequency: note.frequency * 2, start: note.start, duration: note.duration)
            boundary.ingest(frequency: note.frequency, start: note.start, duration: note.duration * 0.75)
            below.ingest(frequency: note.frequency, start: note.start, duration: note.duration * 0.749)
            silence.ingest(frequency: nil, start: note.start, duration: note.duration)
        }
        check(abs(perfect.score - 1) < 1e-9 && perfect.passed, "Perfect performance")
        check(wrongOctave.score == 0 && !wrongOctave.passed, "Wrong octave")
        check(abs(boundary.score - 0.75) < 1e-9 && boundary.passed, "75% passes")
        check(!below.passed, "74.9% fails")
        check(silence.score == 0 && !silence.passed, "Silence fails")
        var overlap = SegmentEvaluator()
        let first = Twinkle.notes[0]
        overlap.ingest(frequency: first.frequency, start: -1, duration: 1.6)
        overlap.ingest(frequency: first.frequency, start: 0, duration: 0.6)
        check(abs(overlap.matched[0] - 0.6) < 1e-9, "Count-in clipped and duplicate ignored")
        var tolerance = SegmentEvaluator()
        tolerance.ingest(frequency: first.frequency * pow(2, 50.0 / 1200), start: 0, duration: 0.3)
        tolerance.ingest(frequency: first.frequency * pow(2, 51.0 / 1200), start: 0.3, duration: 0.3)
        check(abs(tolerance.matched[0] - 0.3) < 1e-9, "50 cents accepted; 51 rejected")
        var progress = PracticeProgress()
        progress.beginAttempt()
        check(!progress.resolve(score: 0.749) && progress.index == 0, "Failed phrase rewinds")
        progress.beginAttempt()
        check(progress.attempts[0] == 2, "Retry count")
        check(progress.resolve(score: 0.75) && progress.index == 1, "75% advances")
        progress.beginAttempt()
        check(!progress.resolve(score: 0) && progress.index == 1 && progress.scores[0] == 0.75, "Retry preserves earlier pass")
        for _ in 1..<6 { progress.beginAttempt(); progress.resolve(score: 1) }
        check(progress.finished && progress.index == 5, "Completion after all six phrases")
        for phrase in Phrase.all {
            check(phrase.words.count == phrase.notes.count, "Lyric alignment")
            check(abs(phrase.score(perfect) - 1) < 1e-9, "Per-phrase full score")
            check(phrase.score(SegmentEvaluator()) == 0, "Fresh retry has no old credit")
            let wav = Accompaniment.wav(phrase: phrase)
            check(wav.count == 44 + Int((phrase.duration * 22050).rounded()) * 2, "Audio duration matches phrase")
            check(String(data: wav.prefix(4), encoding: .utf8) == "RIFF", "Valid WAV header")
        }
        var section = SegmentEvaluator()
        for note in Phrase.all[2].notes {
            section.ingest(frequency: note.frequency, start: note.start, duration: note.duration * 0.75)
        }
        check(abs(Phrase.all[2].score(section) - 0.75) < 1e-9, "Offset phrase scoring")
        check(Phrase.all[1].score(section) == 0, "No score leaks into other phrase")
        func trace(_ values: [Double?]) -> [PitchPoint] {
            values.enumerated().map { PitchPoint(time: Double($0.offset) * 0.085, frequency: $0.element) }
        }
        let singleSpike = PitchTrace.smoothed(trace([261.63, 261.63, 523.26, 261.63, 261.63]))
        check(singleSpike.allSatisfy { $0.frequency == 261.63 }, "Single octave spike removed from display")
        check(singleSpike[1].time == 0.17, "Display preserves timestamps")
        let transition = PitchTrace.smoothed(trace([261.63, 261.63, 392, 392, 392]))
        check(transition.map(\.frequency) == [261.63, 392, 392], "Real note transition preserved")
        let silenceTrace = PitchTrace.smoothed(trace([261.63, nil, 261.63]))
        check(silenceTrace[0].frequency == nil, "No interpolation over silence")
        check(PitchTrace.smoothed(trace([523.26, 523.26, 523.26]))[0].frequency == 523.26, "Sustained wrong octave is not corrected")
        check(PitchTrace.smoothed(trace([261.63, 261.63])).isEmpty, "Wait for confirmation sample")
        let gap = [PitchPoint(time: 0, frequency: 261.63), PitchPoint(time: 0.1, frequency: 261.63), PitchPoint(time: 0.6, frequency: 261.63)]
        check(PitchTrace.smoothed(gap)[0].frequency == nil, "Dropped buffer creates gap")
        check(PitchTrace.smoothed(trace([261.63, .nan, 261.63]))[0].frequency == nil, "Reject invalid display frequency")
        check(PitchTrace.lowerMIDI == 48 && PitchTrace.upperMIDI == 72, "Stable axis independent of voice")
        let fullAudio = Accompaniment.songWAV()
        let expectedBytes = Phrase.all.reduce(0) { $0 + Accompaniment.wav(phrase: $1).count - 44 }
        check(fullAudio.count == expectedBytes + 44, "Continuous audio contains every phrase without gaps")
        func read32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(fullAudio[offset + $1]) << (8 * $1) }
        }
        check(read32(4) == fullAudio.count - 8 && read32(40) == expectedBytes, "Continuous WAV header")
        check(abs(Double(expectedBytes) / 44100 - Twinkle.duration) < 0.001, "Full audio synchronized to song timeline")
        var continuous = SegmentEvaluator()
        // One buffer straddles the boundary between phrase 1 and 2.
        continuous.ingest(frequency: 440 * pow(2, Double(67 - 69) / 12), start: 4.7, duration: 0.2)
        check(abs(continuous.matched[6] - 0.1) < 1e-8 && continuous.matched[7] == 0, "Cross-boundary audio assigned by target time")
        let before = continuous.matched.reduce(0, +)
        continuous.ingest(frequency: 440 * pow(2, Double(67 - 69) / 12), start: 4.7, duration: 0.2)
        check(abs(continuous.matched.reduce(0, +) - before) < 1e-8, "Boundary buffer not double counted")
        print("PASS: \(checks) pitch and evaluator checks")
    }
}
