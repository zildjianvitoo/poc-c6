//
//  SimulatedSinger.swift
//  poc-c6
//
//  Simulator only: a "singer" that follows the fake reference playback, so the real recording
//  loop (evaluation, TRY AGAIN, rewind, partial export) runs without a camera or microphone.
//  It sings every note in tune, except the first attempt of the second segment that has notes
//  (instrumental-only segments auto-pass), sung 2 semitones sharp so one TRY AGAIN always happens.
//

import CoreMedia
import Foundation
import Synchronization

nonisolated final class SimulatedSinger: Sendable {
    private struct State {
        var notes: [(start: TimeInterval, end: TimeInterval, midi: Int)] = []
        var segment: (start: TimeInterval, end: TimeInterval)?
        var songZero: CMTime?
        var sharpSung = false
    }

    private let state = Mutex(State())

    /// Call when a recording session starts.
    func prepare(song: PreparedSong) {
        let notes = song.segments.flatMap(\.targetNotes).map {
            (start: $0.startTime, end: $0.endTime, midi: song.transposition.transposed($0))
        }
        let vocalSegments = song.segments.filter { !$0.targetNotes.isEmpty }
        let segment = vocalSegments.count > 1 ? vocalSegments[1] : vocalSegments.first
        state.withLock {
            $0 = State(notes: notes, segment: segment.map { ($0.audioStartTime, $0.audioEndTime) })
        }
    }

    /// Hook for FakeReferencePlaybackRepository(onPlay:).
    func playbackStarted(from referenceTime: TimeInterval, heard: CMTime) {
        state.withLock {
            $0.songZero = heard - CMTime(seconds: referenceTime, preferredTimescale: heard.timescale)
            // A rewind after the sharp attempt: sing it right this time.
            if $0.sharpSung { $0.segment = nil }
        }
    }

    /// Voice for FakeCaptureRepository: the frequency sung right now (host clock = fake capture clock).
    func frequencyNow() -> Float? {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        return state.withLock { state -> Float? in
            guard let songZero = state.songZero else { return nil }
            let songTime = (now - songZero).seconds
            guard let note = state.notes.first(where: { songTime >= $0.start && songTime < $0.end }) else { return nil }
            var midi = Double(note.midi)
            if let segment = state.segment, songTime >= segment.start, songTime < segment.end {
                midi += 2
                state.sharpSung = true
            }
            return Float(440 * pow(2, (midi - 69) / 12))
        }
    }
}
