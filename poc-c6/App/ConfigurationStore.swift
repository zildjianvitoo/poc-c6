//
//  ConfigurationStore.swift
//  poc-c6
//
//  Keeps PoCConfiguration edits from Debug Settings across launches (ZV-15). Owner: Zildjian Vito.
//

import Foundation

nonisolated struct ConfigurationStore: @unchecked Sendable {
    static let key = "PoCConfiguration"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Saved configuration, or the defaults when nothing is saved or the saved data no longer decodes.
    func load() -> PoCConfiguration {
        guard let data = defaults.data(forKey: Self.key),
              let configuration = try? JSONDecoder().decode(PoCConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    func save(_ configuration: PoCConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
