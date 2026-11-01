//
//  PreparationChecks.swift
//  poc-c6
//


import Foundation

nonisolated enum PreparationChecks {
    nonisolated struct Stems: StemSeparationRepository {
        func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
            SeparatedStems(mixURL: audioURL, vocalGuideURL: audioURL, instrumentalURL: audioURL, method: .synthesized)
        }
    }
    nonisolated struct Guide: AudioAnalysisRepository {
        var empty = false
        func extractVocalGuideNotes(from vocalGuideURL: URL) async throws -> [TargetMIDINote] {
            empty ? [] : DomainFixtures.segments.flatMap(\.targetNotes)
        }
    }
    nonisolated struct Renderer: AudioTranspositionRepository {
        func renderTransposed(_ audioURL: URL, semitones: Int) async throws -> URL {
            guard semitones == 0 else {
                throw ContractViolation(contract: "Checks", message: "Octave shift leaked into audio rendering.")
            }
            return audioURL
        }
    }
    static func run() async throws {
        let compute = ComputeTranspositionUseCase()
        let notes = DomainFixtures.segments.flatMap(\.targetNotes)
        let low = VocalRange(lowestMIDI: 48, highestMIDI: 55)
        let down = try compute.execute(notes: notes, vocalRange: low)
        assert(down.octaveShift == -1 && down.semitoneShift == 0)
        let same = try compute.execute(notes: notes, vocalRange: VocalRange(lowestMIDI: 60, highestMIDI: 67))
        assert(same == .none)
        for bottom in 40...80 {
            let plan = try compute.execute(notes: notes, vocalRange: VocalRange(lowestMIDI: Float(bottom), highestMIDI: Float(bottom + 7)))
            assert(TranspositionPlan.semitoneRange.contains(plan.semitoneShift))
            assert(TranspositionPlan.totalRange.contains(plan.totalSemitones))
            let count = notes.filter { Float(plan.transposed($0)) < Float(bottom) || Float(plan.transposed($0)) > Float(bottom + 7) }.count
            for k in TranspositionPlan.totalRange {
                let alternative = notes.filter { Float($0.midiNote + k) < Float(bottom) || Float($0.midiNote + k) > Float(bottom + 7) }.count
                assert(count <= alternative)
            }
        }
        let fixture = DomainFixtures.preparedSong
        let pipeline = PrepareSongUseCase(separation: Stems(), analysis: Guide(empty: true),
                                         fallbackAnalysis: Guide(), transposition: Renderer())
        let output = try await pipeline.execute(audioURL: fixture.earphoneMixURL, trimRange: 0...fixture.duration, vocalRange: low)
        assert(output.transposition == down)
        assert(output.segments.flatMap(\.targetNotes).map(\.midiNote) == SimplifyGuideUseCase().execute(notes).map(\.midiNote))
        assert(output.validate().isEmpty)
        let silent = PrepareSongUseCase(separation: Stems(), analysis: Guide(empty: true),
                                       fallbackAnalysis: Guide(empty: true), transposition: Renderer())
        do {
            _ = try await silent.execute(audioURL: fixture.earphoneMixURL, trimRange: 0...fixture.duration, vocalRange: low)
            preconditionFailure("Empty guide should fail preparation")
        } catch is ContractViolation { }
    }
}

