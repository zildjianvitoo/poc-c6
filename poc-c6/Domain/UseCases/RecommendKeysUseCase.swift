//
//  RecommendKeysUseCase.swift
//  poc-c6
//

import Foundation

/// Duration-weighted edge penalty. Only keys whose entire melody fits are returned.
nonisolated struct RecommendKeysUseCase: Sendable {
    struct Recommendation: Sendable, Equatable {
        let plan: TranspositionPlan
        let penalty: Double
        let lowestMIDI: Int
        let highestMIDI: Int
    }

    var configuration: PoCConfiguration = .default

    func execute(notes: [TargetMIDINote], vocalRange: VocalRange) throws -> [Recommendation] {
        let low = Double(vocalRange.lowestMIDI), high = Double(vocalRange.highestMIDI)
        guard low.isFinite, high.isFinite, high > low else {
            throw ContractViolation(contract: "KeyRecommendations", message: "Invalid vocal range.")
        }
        guard !notes.isEmpty else { return [] }
        guard notes.allSatisfy({ (0...127).contains($0.midiNote) && $0.duration.isFinite && $0.duration > 0 }) else {
            throw ContractViolation(contract: "KeyRecommendations", message: "Invalid guide notes.")
        }
        let band = min(configuration.rangePenaltyBand, (high - low) / configuration.rangePenaltySpanDivisor)
        let totalDuration = notes.reduce(0) { $0 + $1.duration }
        guard band > 0, totalDuration.isFinite else {
            throw ContractViolation(contract: "KeyRecommendations", message: "Invalid scoring configuration.")
        }
        // Audio and targets must use exactly the same shift. Target-only octave shifts
        // from the legacy planner are deliberately not candidates for this feature.
        let candidates = TranspositionPlan.semitoneRange.compactMap { shift -> Recommendation? in
            let pitches = notes.map { $0.midiNote + shift }
            guard pitches.allSatisfy({ (0...127).contains($0) && Double($0) >= low && Double($0) <= high }) else { return nil }
            let weighted = zip(notes, pitches).reduce(0.0) { sum, pair in
                let distance = min(Double(pair.1) - low, high - Double(pair.1))
                let edge = max(0, 1 - distance / band)
                return sum + edge * edge * pair.0.duration
            }
            return Recommendation(plan: TranspositionPlan(octaveShift: 0, semitoneShift: shift),
                                  penalty: 100 * weighted / totalDuration,
                                  lowestMIDI: pitches.min()!, highestMIDI: pitches.max()!)
        }
        return Array(candidates.sorted {
            if $0.penalty != $1.penalty { return $0.penalty < $1.penalty }
            if abs($0.plan.semitoneShift) != abs($1.plan.semitoneShift) {
                return abs($0.plan.semitoneShift) < abs($1.plan.semitoneShift)
            }
            return $0.plan.semitoneShift < $1.plan.semitoneShift
        }.prefix(configuration.keyRecommendationCount))
    }

    /// A breath-delimited vocal phrase, including breathing room, in the trimmed song.
    /// Equal highest notes prefer the longest held occurrence, then the earliest.
    func highestPhrase(notes: [TargetMIDINote], duration: TimeInterval) -> ClosedRange<TimeInterval>? {
        let sorted = notes.sorted { $0.startTime < $1.startTime }
        guard duration.isFinite, duration > 0, let peak = sorted.max(by: {
            if $0.midiNote != $1.midiNote { return $0.midiNote < $1.midiNote }
            if $0.duration != $1.duration { return $0.duration < $1.duration }
            return $0.startTime > $1.startTime
        }), let index = sorted.firstIndex(where: { $0.id == peak.id }) else { return nil }
        var first = index, last = index
        while first > 0, sorted[first].startTime - sorted[first - 1].endTime <= configuration.segmentGap { first -= 1 }
        while last + 1 < sorted.count, sorted[last + 1].startTime - sorted[last].endTime <= configuration.segmentGap { last += 1 }
        let start = max(0, sorted[first].startTime - configuration.segmentGap / 2)
        let end = min(duration, sorted[last].endTime + configuration.segmentGap / 2)
        return end > start ? start...end : nil
    }
}
