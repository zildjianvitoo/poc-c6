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
    static let currentVersion = 2

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
        if defaults.integer(forKey: Self.versionKey) < Self.currentVersion {
            configuration = Self.migrate(configuration)
            save(configuration)
        }
        return configuration
    }

    /// Settings saved before version 2 kept the old tolerance and had Track B off.
    static func migrate(_ old: PoCConfiguration) -> PoCConfiguration {
        var configuration = old
        if configuration.hitToleranceCents == 50 { configuration.hitToleranceCents = PoCConfiguration.default.hitToleranceCents }
        configuration.useCoreMLSeparation = PoCConfiguration.default.useCoreMLSeparation
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
