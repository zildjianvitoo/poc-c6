// Standalone regression checks. Compile with Domain, AudioExcerptRenderer and the
// vocal-range/key-selection view models; see docs/test-reports/vocal-key-selection.md.
import AVFoundation
import Foundation
import Synchronization

nonisolated final class ScriptedPitchSource: LivePitchSource {
    var notes: [Float?]
    private var index = 0
    private var frames: [Float?]?
    init(_ notes: [Float?]) { self.notes = notes }
    init(frames: [Float?]) { self.notes = [nil]; self.frames = frames }
    func start() async throws -> AsyncStream<PitchSample> {
        let note = notes[min(index, notes.count - 1)]
        index += 1
        return AsyncStream { continuation in
            for frame in 0..<(frames?.count ?? 141) {
                let midi = frames.map { $0[frame] } ?? note.map { $0 + (frame.isMultiple(of: 2) ? Float(0.1) : -0.1) }
                continuation.yield(PitchSample(captureTime: CMTime(seconds: Double(frame) * 0.05, preferredTimescale: 60000),
                    frequency: midi.map { Float(440 * pow(2, Double($0 - 69) / 12)) }, rmsDecibels: -20))
            }
            continuation.finish()
        }
    }
    func stop() {}
}

nonisolated final class UnavailableMicrophone: LivePitchSource {
    func start() async throws -> AsyncStream<PitchSample> { throw HeadsetMicrophoneError.unavailable }
    func stop() {}
}

nonisolated final class PreviewSpy: AudioPreviewing {
    var playedURL: URL?
    var interval: ClosedRange<TimeInterval>?
    var completion: (@Sendable () -> Void)?
    var fails = false
    func play(_ url: URL) throws { playedURL = url }
    func play(_ url: URL, excerpt: ClosedRange<TimeInterval>, onCompletion: @escaping @Sendable () -> Void) async throws {
        if fails { throw CocoaError(.fileReadUnknown) }
        playedURL = url
        interval = excerpt
        completion = onCompletion
    }
    func stop() { playedURL = nil }
}

actor RenderSpy: AudioTranspositionRepository {
    var calls: [(URL, Int)] = []
    func renderTransposed(_ audioURL: URL, semitones: Int) async throws -> URL {
        calls.append((audioURL, semitones))
        return audioURL.appendingPathExtension("shift\(semitones)")
    }
}

actor PipelineSpy: StemSeparationRepository, AudioAnalysisRepository {
    let stems: SeparatedStems
    let notes: [TargetMIDINote]
    var separationCalls = 0
    var analysisCalls = 0
    init(stems: SeparatedStems, notes: [TargetMIDINote]) { self.stems = stems; self.notes = notes }
    func separateStems(from: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        separationCalls += 1
        return stems
    }
    func extractVocalGuideNotes(from: URL) async throws -> [TargetMIDINote] {
        analysisCalls += 1
        return notes
    }
}

@main
struct VocalKeyChecks {
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw ContractViolation(contract: "VocalKeyChecks", message: message) }
    }
    static func note(_ midi: Int, _ start: Double = 0, _ duration: Double = 1) -> TargetMIDINote {
        TargetMIDINote(midiNote: midi, startTime: start, duration: duration)
    }
    @MainActor static func capture(_ model: VocalRangeViewModel) async {
        model.listen()
        for _ in 0..<1000 {
            if model.status != .listening { return }
            await Task.yield()
        }
    }
    @MainActor static func main() async throws {
        let recommender = RecommendKeysUseCase()
        let exact = try recommender.execute(notes: [note(60), note(72)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 72))
        try check(exact.count == 1 && exact[0].plan == .none && exact[0].penalty == 100, "exact range: one candidate, both edges penalised")
        let two = try recommender.execute(notes: [note(60), note(72)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 73))
        try check(two.count == 2, "do not manufacture three candidates")
        let impossible = try recommender.execute(notes: [note(60), note(80)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 72))
        try check(impossible.isEmpty, "wide melody has no recommendation")
        let octaveOnly = try recommender.execute(notes: [note(80)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 64))
        try check(octaveOnly.isEmpty, "do not recommend target-only octave shifts")
        let tied = try recommender.execute(notes: [note(64)], vocalRange: VocalRange(lowestMIDI: 48, highestMIDI: 80))
        try check(tied.map(\.plan.semitoneShift) == [0, -1, 1], "equal penalties prefer the smallest shift, then the lower key")
        let lowLong = try recommender.execute(notes: [note(60, 0, 9), note(72, 9, 1)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 76))
        let highLong = try recommender.execute(notes: [note(60, 0, 1), note(72, 1, 9)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 76))
        try check(lowLong[0].plan.semitoneShift > highLong[0].plan.semitoneShift, "duration weights change the best key")
        let weighted = try recommender.execute(notes: [note(61, 0, 1), note(67, 1, 3)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 68))
        try check(weighted[0].plan == .none && abs(weighted[0].penalty - 25) < 0.000001, "quadratic penalty is duration-weighted and uses span/4 for a narrow range")
        let narrow = try recommender.execute(notes: [note(61)], vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 64))
        try check(narrow[0].plan.semitoneShift == 0 && narrow[0].penalty == 0, "narrow ranges use span/4 band and deterministic zero-penalty ties")
        for bounds in [(Float(60),Float(60)), (.nan,72), (60,.infinity), (72,60)] {
            var rejected = false
            do {
                _ = try recommender.execute(notes: [note(64)], vocalRange: VocalRange(lowestMIDI: bounds.0, highestMIDI: bounds.1))
            } catch is ContractViolation { rejected = true }
            try check(rejected, "invalid range must fail")
        }
        let phraseNotes = [note(60, 1), note(67, 2.2, 0.5), note(72, 8), note(70, 9.1), note(72, 14, 2)]
        let phrase = recommender.highestPhrase(notes: phraseNotes, duration: 20)!
        try check(abs(phrase.lowerBound - 13.6) < 0.0001 && abs(phrase.upperBound - 16.4) < 0.0001, "longest highest note selects its complete phrase")
        let clipped = recommender.highestPhrase(notes: [note(72, 0, 3)], duration: 3)!
        try check(clipped == 0...3, "phrase is clamped to clip boundaries")

        let renderer = RenderSpy()
        let stems = SeparatedStems(mixURL: URL(fileURLWithPath: "/mix"), vocalGuideURL: URL(fileURLWithPath: "/vocal"), instrumentalURL: URL(fileURLWithPath: "/instrumental"), method: .coreML)
        let melody = [note(60, 1, 1), note(64, 2.2, 1), note(72, 8, 0.14)]
        let pipeline = PipelineSpy(stems: stems, notes: melody)
        let prepare = PrepareSongUseCase(separation: pipeline, analysis: pipeline, fallbackAnalysis: nil, transposition: renderer)
        let choices = try await prepare.executeChoices(audioURL: URL(fileURLWithPath: "/song"), trimRange: 0...16, vocalRange: VocalRange(lowestMIDI: 58, highestMIDI: 76))
        let separationCount = await pipeline.separationCalls
        let analysisCount = await pipeline.analysisCalls
        try check(separationCount == 1 && analysisCount == 1, "all three keys share one separation and one analysis")
        try check(choices.options.count == 3, "pipeline produces three choices")
        let calls = await renderer.calls
        try check(calls.count == 6, "one mix and one instrumental render per key")
        for (index, option) in choices.options.enumerated() {
            let shift = option.recommendation.plan.semitoneShift
            try check(calls[index * 2].0 == stems.mixURL && calls[index * 2 + 1].0 == stems.instrumentalURL, "render from original stems")
            try check(calls[index * 2].1 == shift && calls[index * 2 + 1].1 == shift && option.song.transposition.totalSemitones == shift, "audio and targets use exactly the same shift")
            try check(option.song.validate().isEmpty, "selected song satisfies handoff contract")
            try check(option.recommendation.highestMIDI == 72 + shift, "score and guide retain validated short high notes")
        }
        let preview = PreviewSpy()
        var chosen: PreparedSong?
        let selection = KeySelectionViewModel(choices: choices, previewer: preview, onChoose: { chosen = $0 })
        selection.confirm()
        try check(chosen == nil, "explicit choice is required")
        selection.listen(1)
        for _ in 0..<1000 { if selection.loadingIndex == nil { break }; await Task.yield() }
        try check(preview.playedURL == choices.options[1].song.instrumentalURL && preview.interval == choices.excerpt, "preview plays instrumental, at the same highest phrase")
        let oldCompletion = preview.completion
        selection.listen(2)
        for _ in 0..<1000 { if selection.loadingIndex == nil { break }; await Task.yield() }
        oldCompletion?()
        for _ in 0..<20 { await Task.yield() }
        try check(selection.playingIndex == 2, "stale playback completion cannot clear a newer preview")
        preview.completion?()
        for _ in 0..<20 { await Task.yield() }
        try check(selection.playingIndex == nil, "preview completion resets the play button")
        selection.select(1)
        selection.confirm()
        try check(chosen?.transposition == choices.options[1].song.transposition, "user selection reaches recording unchanged")
        preview.fails = true
        selection.listen(0)
        for _ in 0..<1000 { if selection.loadingIndex == nil { break }; await Task.yield() }
        try check(selection.error == .keyPreviewFailed, "preview failures are visible")

        let store = FakeVocalRangeRepository()
        let rangeModel = VocalRangeViewModel(source: ScriptedPitchSource([57,48,67]), repository: store, configuration: .default, onSaved: {})
        await capture(rangeModel)
        try check(abs((rangeModel.baselineMIDI ?? 0) - 57) < 0.2, "speaking baseline uses median")
        for _ in 0..<2 { rangeModel.next(); await capture(rangeModel) }
        rangeModel.save()
        try check(abs((store.load()?.lowestMIDI ?? 0) - 48) < 0.2 && abs((store.load()?.highestMIDI ?? 0) - 67) < 0.2, "three-step range is persisted after stable holds")
        try check(VocalRangeViewModel.Prompt.allCases.count == 3, "range flow contains exactly three steps")
        let narrowRange = VocalRangeViewModel(source: ScriptedPitchSource([57,48,49]), repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {})
        await capture(narrowRange); narrowRange.next(); await capture(narrowRange); narrowRange.next(); await capture(narrowRange)
        try check(narrowRange.status == .failed(.vocalRangeTooNarrow), "high note must still be above the low note")
        let missingMic = VocalRangeViewModel(source: UnavailableMicrophone(), repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {})
        await capture(missingMic)
        try check(missingMic.status == .failed(.headsetMicrophoneRequired), "missing headset produces an actionable error")
        let unstableSource = ScriptedPitchSource(frames: (0...140).map { $0.isMultiple(of: 2) ? Float(48) : Float(52) })
        let unstable = VocalRangeViewModel(source: unstableSource, repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {})
        await capture(unstable)
        unstable.next()
        await capture(unstable)
        try check(unstable.status == .failed(.vocalRangeCaptureFailed), "display smoothing cannot make an unstable held note pass the range test")
        let silence = VocalRangeViewModel(source: ScriptedPitchSource([nil]), repository: FakeVocalRangeRepository(), configuration: .default, onSaved: {})
        await capture(silence)
        try check(silence.status == .failed(.vocalRangeCaptureFailed), "silence cannot establish a speaking baseline")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("excerpt-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000)!
        buffer.frameLength = 8000
        for frame in 0..<8000 {
            buffer.floatChannelData![0][frame] = Float(frame) / 10000
            buffer.floatChannelData![1][frame] = -Float(frame) / 10000
        }
        let input = directory.appendingPathComponent("original.caf")
        do { let file = try AVAudioFile(forWriting: input, settings: format.settings); try file.write(from: buffer) }
        let clipURL = try AudioExcerptRenderer().render(input, excerpt: 0.25...0.75)
        defer { try? FileManager.default.removeItem(at: clipURL) }
        let clip = try AVAudioFile(forReading: clipURL)
        try check(clip.length == 4000, "preview contains exact requested frame count")
        let samples = AVAudioPCMBuffer(pcmFormat: clip.processingFormat, frameCapacity: 4000)!
        try clip.read(into: samples)
        try check(abs(samples.floatChannelData![0][0] - 0.2) < 0.0001 && abs(samples.floatChannelData![1][3999] + 0.5999) < 0.0001, "preview preserves original stereo PCM and starts at correct song time")
        print("PASS VocalKeyChecks (\(checks) checks)")
    }
}
