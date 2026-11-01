import CoreMedia
import Foundation

@main
struct SegmentEvaluationChecks {
    static func main() {
        let note = TargetMIDINote(midiNote: 69, startTime: 0, duration: 1)
        let segment = SongSegment(index: 0, audioStartTime: 0, audioDuration: 1, targetNotes: [note])
        let useCase = EvaluateSegmentUseCase()
        precondition(useCase.execute(segment: segment, evaluations: []).score == 0)
        let frames = (0..<20).map { index in
            PitchEvaluation(referenceTime: Double(index) * 0.05 + 0.001, detectedMIDINote: 69, targetNoteID: note.id, centDeviation: 0, isHit: true)
        }
        precondition(useCase.execute(segment: segment, evaluations: frames).score >= 0.95)
        let instrumental = SongSegment(index: 0, audioStartTime: 0, audioDuration: 1, targetNotes: [])
        precondition(useCase.execute(segment: instrumental, evaluations: []).score == 1)
        let repo = SessionTakeLogRepositoryImpl()
        func take(_ index: Int) -> TakeAttemptLog {
            TakeAttemptLog(segmentIndex: index, attemptNumber: 1, videoTimeRange: CMTimeRange(start: CMTime(seconds: Double(index) * 2, preferredTimescale: 600), duration: CMTime(seconds: 1.06, preferredTimescale: 600)), accuracyScore: 1, missedNoteIDs: [], status: .passed)
        }
        repo.logAttempt(take(1))
        precondition(repo.passedTakesPrefix().isEmpty)
        let first = take(0)
        repo.logAttempt(first)
        repo.logAttempt(first)
        precondition(repo.allAttempts().count == 2)
        precondition(repo.passedTakesPrefix().map(\.segmentIndex) == [0, 1])
        let song = DomainFixtures.preparedSong
        let target = song.segments.flatMap(\.targetNotes)[0]
        let time = target.startTime + 0.11
        let midi = Float(song.transposition.transposed(target))
        let frequency = 440 * pow(2, (midi - 69) / 12)
        let sample = PitchSample(captureTime: CMTime(seconds: time, preferredTimescale: 60000), frequency: frequency, rmsDecibels: -20)
        let evaluation = TrackLivePitchUseCase().execute(sample: sample, playbackAnchor: .zero, song: song)
        precondition(evaluation.isHit)
        let range = TakeRangeBuilder().execute(segment: segment, referenceZeroFileTime: CMTime(seconds: 2, preferredTimescale: 60000))!
        precondition(abs(range.start.seconds - 1.97) < 0.00001)
        precondition(abs(range.duration.seconds - 1.06) < 0.00001)
        precondition(TakeRangeBuilder().execute(segment: segment, referenceZeroFileTime: .zero) == nil)
        precondition(TakeRangeBuilder().execute(segment: segment, referenceZeroFileTime: .invalid) == nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let segments = [segment, SongSegment(index: 1, audioStartTime: 1, audioDuration: 1, targetNotes: [])]
        let metadata = try! RecordingHandoff.write(videoURL: folder.appendingPathComponent("RawMasterVideo.mov"), takes: repo.passedTakesPrefix(), segments: segments)
        let decoded = try! JSONDecoder().decode(RecordingHandoff.self, from: Data(contentsOf: metadata))
        precondition(decoded.passedTakes.count == 2 && decoded.rawVideoFile == "RawMasterVideo.mov")
        precondition(decoded.passedTakes[0].fileDuration == 1.06)
        print("PASS: silence, correct pitch, instrumental auto-pass, take prefix, duplicate protection, transposed pitch, file-time handles, invalid anchors, handoff JSON round-trip")
    }
}
