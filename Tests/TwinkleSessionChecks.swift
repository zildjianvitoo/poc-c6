import Foundation

@main
struct TwinkleSessionChecks {
    static func main() {
        let guide = TwinkleSessionGuide()
        let scorer = EvaluateSegmentUseCase()
        precondition(guide.segments.count == 6)
        precondition(abs(guide.segments.last!.audioEndTime - Twinkle.duration) < 0.001)
        for segment in guide.segments {
            var frames: [PitchEvaluation] = []
            var time = segment.audioStartTime
            while time < segment.audioEndTime {
                let frequency = Twinkle.note(at: time + 0.000001)?.frequency
                frames.append(guide.evaluate(frequency: frequency, time: time + 0.000001))
                time += PoCConfiguration.default.pitchHop
            }
            let perfect = scorer.execute(segment: segment, evaluations: frames)
            precondition(perfect.score >= 0.95, "Perfect singing must pass every Twinkle segment")
            precondition(perfect.missedNoteIDs.isEmpty)
            precondition(scorer.execute(segment: segment, evaluations: []).score == 0)
            let wrong = frames.map { guide.evaluate(frequency: 55, time: $0.referenceTime) }
            precondition(scorer.execute(segment: segment, evaluations: wrong).score == 0)
        }
        var buffer = PitchFrameBuffer()
        let first = buffer.append(Array(repeating: 0.1, count: 4096), sampleRate: 48000, start: 0)
        precondition(first.count == 1 && first[0].samples.count == 4096)
        let second = buffer.append(Array(repeating: 0.2, count: 4096), sampleRate: 48000, start: 4096.0 / 48000)
        precondition(second.count == 1)
        precondition(abs(second[0].start - 0.05) < 0.000001)
        let third = buffer.append(Array(repeating: 0.2, count: 4096), sampleRate: 48000, start: 8192.0 / 48000)
        precondition(third.count == 2)
        precondition(abs(third[0].start - 0.10) < 0.000001)
        precondition(abs(third[1].start - 0.15) < 0.000001)
        let gap = buffer.append(Array(repeating: 0.3, count: 4096), sampleRate: 48000, start: 1)
        precondition(gap.count == 1 && gap[0].start == 1)
        precondition(gap[0].samples.allSatisfy { $0 == 0.3 })
        precondition(buffer.append([], sampleRate: 0, start: 0).isEmpty)
        print("PASS: all six Twinkle segments, correct/silent/wrong singing, missed notes, 50 ms frame spacing, discontinuity reset")
    }
}
