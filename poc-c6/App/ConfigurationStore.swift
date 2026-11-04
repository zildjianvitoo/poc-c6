//
//  ConfigurationStore.swift
//  poc-c6
//
//  Keeps PoCConfiguration edits from Debug Settings across launches (ZV-15). Owner: Zildjian Vito.
//

import Foundation

nonisolated struct ConfigurationStore: @unchecked Sendable {
    static let key = "PoCConfiguration"
    static let versionKey = "PoCConfiguration.version"
    /// Bump when a default changes in a way saved settings must pick up.
    /// 2 (2026-11-01): hit tolerance 50 → 80 cents, CoreML separation on.
    /// 3 (2026-11-04): crossfade 30 → 150 ms (video dissolve + equal-power vocal crossfade).
    static let currentVersion = 3

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Saved configuration, or the defaults when nothing is saved or the saved data no longer decodes.
    func load() -> PoCConfiguration {
        guard let data = defaults.data(forKey: Self.key),
              var configuration = try? JSONDecoder().decode(PoCConfiguration.self, from: data) else {
            return .default
        }
        let version = defaults.integer(forKey: Self.versionKey)
        if version < Self.currentVersion {
            configuration = Self.migrate(configuration, from: version)
            save(configuration)
        }
        return configuration
    }

    /// Old saved settings kept old defaults: the 50-cent tolerance and Track B off (before 2),
    /// the 30 ms crossfade (before 3). Values the user changed themselves are kept.
    static func migrate(_ old: PoCConfiguration, from version: Int) -> PoCConfiguration {
        var configuration = old
        if version < 2 {
            if configuration.hitToleranceCents == 50 { configuration.hitToleranceCents = PoCConfiguration.default.hitToleranceCents }
            configuration.useCoreMLSeparation = PoCConfiguration.default.useCoreMLSeparation
        }
        if version < 3, abs(configuration.crossfade - 0.03) < 1e-9 {
            configuration.crossfade = PoCConfiguration.default.crossfade
        }
        return configuration
    }

    func save(_ configuration: PoCConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Self.key)
            defaults.set(Self.currentVersion, forKey: Self.versionKey)
        }
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
