//
//  DomainFixtures.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//
//  Small, valid sample data so each owner can build and test their part
//  without waiting for the others. Every fixture passes `validate()`.
//  Not DEBUG-only: the fakes and placeholder screens use it in every build until real implementations land.
//

import CoreMedia
import Foundation

nonisolated enum DomainFixtures {
    static let placeholderDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("fixtures", isDirectory: true)

    /// 16 s song, 3 segments: vocal (0–6 s), instrumental-only (6–9 s), vocal (9–16 s).
    static let segments: [SongSegment] = [
        SongSegment(index: 0, audioStartTime: 0, audioDuration: 6, targetNotes: [
            TargetMIDINote(midiNote: 60, startTime: 0.5, duration: 1.0),
            TargetMIDINote(midiNote: 62, startTime: 1.6, duration: 1.0),
            TargetMIDINote(midiNote: 64, startTime: 2.7, duration: 2.0),
        ]),
        SongSegment(index: 1, audioStartTime: 6, audioDuration: 3, targetNotes: []),
        SongSegment(index: 2, audioStartTime: 9, audioDuration: 7, targetNotes: [
            TargetMIDINote(midiNote: 67, startTime: 9.5, duration: 1.5),
            TargetMIDINote(midiNote: 65, startTime: 11.2, duration: 1.5),
            TargetMIDINote(midiNote: 64, startTime: 12.9, duration: 2.5),
        ]),
    ]

    static let preparedSong = PreparedSong(
        earphoneMixURL: placeholderDirectory.appendingPathComponent("mix.m4a"),
        instrumentalURL: placeholderDirectory.appendingPathComponent("instrumental.m4a"),
        segments: segments,
        transposition: TranspositionPlan(octaveShift: -1, semitoneShift: 2),
        duration: 16,
        separationMethod: .synthesized
    )

    /// Passed takes for segments 0 and 1 (partial session), as Takin would hand them over.
    static func passedTakes(crossfade: TimeInterval = PoCConfiguration.default.crossfade) -> [TakeAttemptLog] {
        // Segment 0 passed on attempt 2 starting at 14 s in the raw file; segment 1 follows right after.
        let starts: [TimeInterval] = [14.0, 14.0 + segments[0].audioDuration]
        return starts.enumerated().map { index, start in
            let segment = segments[index]
            return TakeAttemptLog(
                segmentIndex: index,
                attemptNumber: index == 0 ? 2 : 1,
                videoTimeRange: CMTimeRange(
                    start: CMTime(seconds: start - crossfade, preferredTimescale: 600),
                    duration: CMTime(seconds: segment.audioDuration + 2 * crossfade, preferredTimescale: 600)
                ),
                accuracyScore: segment.isInstrumentalOnly ? 1.0 : 0.82,
                missedNoteIDs: [],
                status: .passed
            )
        }
    }

    static func compingPlan(configuration: PoCConfiguration = .default) -> CompingCompositionPlan {
        let takes = passedTakes(crossfade: configuration.crossfade)
        return CompingCompositionPlan(
            rawVideoURL: placeholderDirectory.appendingPathComponent("RawMasterVideo.mov"),
            instrumentalURL: preparedSong.instrumentalURL,
            segments: segments,
            validTakes: takes,
            endTime: segments[takes.count - 1].audioEndTime,
            crossfadeDuration: CMTime(seconds: configuration.crossfade, preferredTimescale: 600),
            instrumentalFadeOut: configuration.partialExportFadeOut,
            vocalGain: configuration.vocalGain,
            instrumentalGain: configuration.instrumentalGain
        )
    }
}
