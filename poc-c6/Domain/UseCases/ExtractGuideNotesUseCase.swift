//
//  ExtractGuideNotesUseCase.swift
//  poc-c6
//
//  Turns a fixed-hop pitch track of the vocal guide into monophonic target notes
//  (PRD §5.3, CREPE fallback): unvoiced below the confidence threshold, stable regions
//  (±50 cents around their median) of at least 120 ms become notes, same-pitch notes
//  closer than 50 ms are merged. Pure: no audio or CoreML here.
//

import Foundation

/// One analysis frame of the guide: `time` is the centre of the analysed window (song timeline).
nonisolated struct GuidePitchFrame: Sendable, Equatable {
    let time: TimeInterval
    /// Fractional MIDI note, nil = unvoiced.
    let midi: Float?
    let confidence: Double

    init(time: TimeInterval, midi: Float?, confidence: Double) {
        self.time = time
        self.midi = midi
        self.confidence = confidence
    }
}

nonisolated struct ExtractGuideNotesUseCase: Sendable {
    /// PRD §5.3: CREPE's voicing threshold; frames below it are unvoiced.
    static let confidenceThreshold = 0.5
    /// PRD §5.3: a stable region must last at least this long to become a note.
    static let minimumNoteDuration: TimeInterval = 0.12
    /// PRD §5.3: allowed variation around the region median, in semitones (±50 cents).
    static let stabilityTolerance: Float = 0.5
    /// PRD §5.3: consecutive same-pitch notes closer than this are merged.
    static let mergeGap: TimeInterval = 0.05
    /// PRD §5.3: frame spacing used when extracting from audio.
    static let defaultHop: TimeInterval = 0.05
    /// A single missing/unvoiced frame inside a region is tolerated (gap up to 2 hops).
    private static let maxFrameSkip = 2.0
    /// Float/time rounding slack.
    private static let epsilon: TimeInterval = 1e-6

    let hop: TimeInterval

    init(hop: TimeInterval = ExtractGuideNotesUseCase.defaultHop) {
        self.hop = hop
    }

    /// Notes in the original key, sorted by `startTime`, non-overlapping, each with `duration > 0`.
    func execute(frames: [GuidePitchFrame]) -> [TargetMIDINote] {
        guard hop > 0 else { return [] }
        let voiced = frames
            .filter { frame in
                guard let midi = frame.midi, midi.isFinite else { return false }
                return frame.confidence >= Self.confidenceThreshold && frame.time.isFinite
            }
            .sorted { $0.time < $1.time }

        var regions: [[GuidePitchFrame]] = []
        var current: [GuidePitchFrame] = []
        for frame in voiced {
            if let last = current.last {
                let contiguous = frame.time - last.time <= hop * Self.maxFrameSkip + Self.epsilon
                if contiguous, fitsRegion(current + [frame]) {
                    current.append(frame)
                    continue
                }
                regions.append(current)
                current = []
            }
            current = [frame]
        }
        if !current.isEmpty { regions.append(current) }

        var notes: [(midi: Int, start: TimeInterval, end: TimeInterval)] = []
        for region in regions {
            guard let first = region.first, let last = region.last else { continue }
            let start = max(0, first.time - hop / 2)
            let end = last.time + hop / 2
            guard end - start >= Self.minimumNoteDuration - Self.epsilon else { continue }
            notes.append((Int(median(region).rounded()), start, end))
        }

        var merged: [(midi: Int, start: TimeInterval, end: TimeInterval)] = []
        for note in notes {
            if let last = merged.last, last.midi == note.midi, note.start - last.end < Self.mergeGap {
                merged[merged.count - 1].end = max(last.end, note.end)
            } else {
                merged.append(note)
            }
        }

        // Monophonic: trim any overlap (only possible with duplicated input times).
        var result: [TargetMIDINote] = []
        var previousEnd = 0.0
        for note in merged {
            let start = max(note.start, previousEnd)
            guard note.end - start > 0 else { continue }
            result.append(TargetMIDINote(midiNote: note.midi, startTime: start, duration: note.end - start))
            previousEnd = note.end
        }
        return result
    }

    private func fitsRegion(_ region: [GuidePitchFrame]) -> Bool {
        let center = median(region)
        return region.allSatisfy { abs(($0.midi ?? center) - center) <= Self.stabilityTolerance }
    }

    private func median(_ region: [GuidePitchFrame]) -> Float {
        let values = region.compactMap(\.midi).sorted()
        guard !values.isEmpty else { return 0 }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }
}
