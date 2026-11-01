//
//  SimplifyGuideUseCase.swift
//  poc-c6
//
//  Turns raw extracted guide notes into fewer, longer blocks that a singer can follow
//  (feedback from device testing 2026-11-01: a phrase came out as many tiny, separated
//  blocks). Neighbours within a semitone are merged, short gaps are bridged, and isolated
//  blips are dropped. Applied after ExtractGuideNotesUseCase for imported songs.
//

import Foundation

nonisolated struct SimplifyGuideUseCase: Sendable {
    /// Notes this close in time and within `mergeInterval` semitones become one block.
    static let mergeGap: TimeInterval = 0.35
    static let mergeInterval = 1
    /// Gaps up to this long between different notes are closed (legato), so the block runs on.
    static let bridgeGap: TimeInterval = 0.3
    /// An isolated note shorter than this (after merging) is dropped as a blip.
    static let minimumIsolatedDuration: TimeInterval = 0.25

    private struct Block {
        var start: TimeInterval
        var end: TimeInterval
        /// Total duration per MIDI note inside the block, to pick its dominant pitch.
        var weights: [Int: TimeInterval]
        var midi: Int { weights.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? 0 }
    }

    /// Input sorted or not; output sorted by `startTime`, monophonic, original key.
    func execute(_ notes: [TargetMIDINote]) -> [TargetMIDINote] {
        var blocks = notes.sorted { $0.startTime < $1.startTime }.map {
            Block(start: $0.startTime, end: $0.endTime, weights: [$0.midiNote: $0.duration])
        }

        // 1. Merge neighbours that are close in time and pitch, until nothing changes.
        var merged = true
        while merged {
            merged = false
            var result: [Block] = []
            for block in blocks {
                if var last = result.last, block.start - last.end <= Self.mergeGap,
                   abs(block.midi - last.midi) <= Self.mergeInterval {
                    last.end = max(last.end, block.end)
                    for (midi, weight) in block.weights { last.weights[midi, default: 0] += weight }
                    result[result.count - 1] = last
                    merged = true
                } else {
                    result.append(block)
                }
            }
            blocks = result
        }

        // 2. Drop isolated blips (far from both neighbours and short).
        blocks = blocks.enumerated().filter { index, block in
            guard block.end - block.start < Self.minimumIsolatedDuration else { return true }
            let gapBefore = index > 0 ? block.start - blocks[index - 1].end : .infinity
            let gapAfter = index + 1 < blocks.count ? blocks[index + 1].start - block.end : .infinity
            return gapBefore <= Self.bridgeGap || gapAfter <= Self.bridgeGap
        }.map(\.element)

        // 3. Bridge short gaps so consecutive blocks run on (legato).
        for index in blocks.indices.dropLast() where blocks[index + 1].start - blocks[index].end <= Self.bridgeGap {
            blocks[index].end = blocks[index + 1].start
        }

        return blocks.compactMap { block in
            guard block.end > block.start else { return nil }
            return TargetMIDINote(midiNote: block.midi, startTime: block.start, duration: block.end - block.start)
        }
    }
}
