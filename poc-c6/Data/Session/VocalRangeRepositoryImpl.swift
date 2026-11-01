//
//  VocalRangeRepositoryImpl.swift
//  poc-c6
//

import Foundation

nonisolated final class VocalRangeRepositoryImpl: VocalRangeRepository {
    private let defaults: UserDefaults
    private let key = "c6.vocalRange"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> VocalRange? {
        guard let data = defaults.data(forKey: key),
              let range = try? JSONDecoder().decode(VocalRange.self, from: data),
              range.lowestMIDI.isFinite, range.highestMIDI.isFinite,
              range.lowestMIDI <= range.highestMIDI else { return nil }
        return range
    }

    func save(_ range: VocalRange) {
        guard range.lowestMIDI.isFinite, range.highestMIDI.isFinite,
              range.lowestMIDI <= range.highestMIDI,
              let data = try? JSONEncoder().encode(range) else { return }
        defaults.set(data, forKey: key)
    }
}
