// Regression cases reproduced from the realtime/guide pipeline before the 4 Nov fixes.
import CoreMedia
import Foundation

@main
struct RealtimeRegressionChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw ContractViolation(contract: "RealtimeRegression", message: message) }
        }
        let hop = 0.05
        let vibrato = (0..<80).map { i in
            GuidePitchFrame(time: Double(i) * hop + hop / 2,
                midi: Float(60 + 0.7 * sin(2 * .pi * 5 * Double(i) * hop)), confidence: 0.95)
        }
        let guide = ExtractGuideNotesUseCase().execute(frames: vibrato)
        let repaired = SimplifyGuideUseCase().execute(guide)
        try check(repaired.count == 1 && repaired[0].midiNote == 60, "vibrato does not erase a sustained guide note")
        try check(abs(repaired[0].duration - 4) < 0.001, "4 s voiced phrase retains its entire note block")
        for frequency in [4.0,4.5,5,5.5,6,6.5,7] {
            for phase in [0.0,0.4,0.8,1.2,1.6,2,2.4,2.8] {
                let frames = (0..<80).map { index in
                    GuidePitchFrame(time: Double(index) * hop + hop / 2,
                        midi: Float(60 + 0.7 * sin(2 * .pi * frequency * Double(index) * hop + phase)), confidence: 0.95)
                }
                let notes = SimplifyGuideUseCase().execute(ExtractGuideNotesUseCase().execute(frames: frames))
                try check(notes.count == 1 && notes[0].midiNote == 60 && abs(notes[0].duration - 4) < 0.001,
                          "vibrato remains complete at \(frequency) Hz, phase \(phase)")
            }
        }
        let shortStepFrames = (0..<23).map { index in
            GuidePitchFrame(time: Double(index) * hop + hop / 2,
                            midi: (10..<13).contains(index) ? 61 : 60, confidence: 0.95)
        }
        let shortStep = SimplifyGuideUseCase().execute(ExtractGuideNotesUseCase().execute(frames: shortStepFrames))
        try check(shortStep.map(\.midiNote) == [60,61,60] && abs(shortStep[1].duration - 0.15) < 0.001,
                  "offline smoothing preserves a real 150 ms semitone turn with its original timing")
        let minimumNote = TargetMIDINote(midiNote: 60, startTime: 0, duration: 0.12 - 1e-10)
        try check(SimplifyGuideUseCase().execute([minimumNote]).count == 1,
                  "floating-point noise at the minimum note length does not erase a valid block")
        let scale = [60,61,62,63].enumerated().map { i,p in
            TargetMIDINote(midiNote: p, startTime: Double(i) * 1.05, duration: 1)
        }
        let scaleGuide = SimplifyGuideUseCase().execute(scale)
        try check(scaleGuide.map(\.midiNote) == [60,61,62,63], "real semitone transitions are never merged into a different note")
        let neighbour = [TargetMIDINote(midiNote: 60, startTime: 0, duration: 0.5),
                         TargetMIDINote(midiNote: 61, startTime: 0.5, duration: 0.15),
                         TargetMIDINote(midiNote: 60, startTime: 0.65, duration: 0.5)]
        try check(SimplifyGuideUseCase().execute(neighbour).map(\.midiNote) == [60,61,60], "a real short neighbour tone is also preserved")
        let short = TargetMIDINote(midiNote: 72, startTime: 2, duration: 0.15)
        try check(SimplifyGuideUseCase().execute([short]).map(\.midiNote) == [72], "validated short notes are not filtered out a second time")
        let rests = [TargetMIDINote(midiNote: 60, startTime: 0, duration: 0.5),
                     TargetMIDINote(midiNote: 60, startTime: 2, duration: 0.5)]
        let withRest = SimplifyGuideUseCase().execute(rests)
        try check(withRest.count == 2 && withRest[0].endTime == 0.5 && withRest[1].startTime == 2, "a real rest stays empty")
        let silence = (0..<40).map { GuidePitchFrame(time: Double($0) * hop, midi: nil, confidence: 0.1) }
        try check(ExtractGuideNotesUseCase().execute(frames: silence).isEmpty, "no guide is fabricated from silence")
        var oneSpike = (0..<40).map { GuidePitchFrame(time: Double($0) * hop + hop / 2, midi: 60, confidence: 0.95) }
        oneSpike[20] = GuidePitchFrame(time: oneSpike[20].time, midi: 72, confidence: 0.95)
        let noSpike = ExtractGuideNotesUseCase().execute(frames: oneSpike)
        try check(noSpike.count == 1 && noSpike[0].midiNote == 60, "one-frame salience spike does not fragment the offline guide")

        for rate in [8000.0,16000,24000,48000] {
            var clean = PitchFrameBuffer(), jittered = PitchFrameBuffer()
            var expected: [(samples: [Float], start: Double)] = [], actual: [(samples: [Float], start: Double)] = []
            let count = Int(rate * 0.02)
            for index in 0..<100 {
                let pcm = (0..<count).map { Float(sin(2 * .pi * 220 * (Double(index * count + $0) / rate))) }
                let time = Double(index) * 0.02
                expected += clean.append(pcm, sampleRate: rate, start: time)
                actual += jittered.append(pcm, sampleRate: rate, start: time + (index.isMultiple(of: 2) ? 0 : 0.00075))
            }
            try check(actual.count == expected.count && actual.count == 39, "small timestamp jitter preserves pitch cadence at \(rate) Hz")
            try check(zip(actual, expected).allSatisfy { $0.samples == $1.samples && abs($0.start - $1.start) < 0.000001 }, "timestamps remain sample-anchored without waveform changes at \(rate) Hz")
        }
        var discontinuity = PitchFrameBuffer()
        _ = discontinuity.append([Float](repeating: 1, count: 640), sampleRate: 16000, start: 0)
        let afterGap = discontinuity.append([Float](repeating: 2, count: 1600), sampleRate: 16000, start: 0.2)
        try check(afterGap.first?.samples.allSatisfy({ $0 == 2 }) == true && afterGap.first?.start == 0.2,
                  "true gaps discard old audio instead of joining unrelated waveforms")
        var rateChange = PitchFrameBuffer()
        _ = rateChange.append([Float](repeating: 1, count: 640), sampleRate: 16000, start: 0)
        let afterRate = rateChange.append([Float](repeating: 2, count: 2400), sampleRate: 24000, start: 0.04)
        try check(afterRate.first?.samples.allSatisfy({ $0 == 2 }) == true, "sample-rate changes still reset the buffer")
        var display = StabilizePitchDisplayUseCase()
        for (index, note) in [Float(60),64,60,67,61,72].enumerated() {
            try check(display.execute(midi: note, time: Double(index) * hop) == note, "the first measured frame of each new note is shown on time")
        }
        try check(display.execute(midi: nil, time: 0.3) == nil, "silence still breaks the live trail")
        print("PASS RealtimeRegressionChecks (\(checks) checks)")
    }
}
