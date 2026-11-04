//
//  SimplifyGuideUseCase.swift
//  poc-c6
//
//  Repair brief guide fragmentation while preserving real melody changes and short notes.
//

import Foundation

nonisolated struct SimplifyGuideUseCase: Sendable {
    var configuration: PoCConfiguration = .default

    func execute(_ notes: [TargetMIDINote]) -> [TargetMIDINote] {
        let repaired = notes.filter {
            $0.startTime.isFinite && $0.duration.isFinite && $0.endTime.isFinite
                && $0.duration >= ExtractGuideNotesUseCase.minimumNoteDuration - ContractTolerance.timeline
        }.sorted { $0.startTime < $1.startTime }

        // Merge only equal pitches. A semitone difference can be a real melody change,
        // even in a short note, so it must not be flattened into its neighbours.
        var merged: [TargetMIDINote] = []
        for note in repaired {
            if let last = merged.last, last.midiNote == note.midiNote,
               note.startTime - last.endTime <= configuration.guideMergeGap {
                merged[merged.count - 1] = TargetMIDINote(id: last.id, midiNote: last.midiNote,
                    startTime: last.startTime, duration: max(last.endTime, note.endTime) - last.startTime)
            } else { merged.append(note) }
        }
        // Keep existing legato repair for short pauses. Long rests remain empty.
        for index in merged.indices.dropLast() {
            let note = merged[index], next = merged[index + 1]
            let gap = next.startTime - note.endTime
            if gap >= 0, gap <= configuration.guideBridgeGap {
                merged[index] = TargetMIDINote(id: note.id, midiNote: note.midiNote,
                                               startTime: note.startTime, duration: next.startTime - note.startTime)
            }
        }
        return merged
    }
}
