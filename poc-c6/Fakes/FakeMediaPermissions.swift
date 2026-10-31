//
//  FakeMediaPermissions.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-14).
//

import Foundation
import Synchronization

/// Starts with the given statuses; a request for a `.notDetermined` permission resolves to `answer`.
nonisolated final class FakeMediaPermissions: MediaPermissionProviding, Sendable {
    private let statuses: Mutex<[MediaPermission: PermissionStatus]>
    let answer: Bool

    init(statuses: [MediaPermission: PermissionStatus] = [:], answer: Bool = true) {
        self.statuses = Mutex(statuses)
        self.answer = answer
    }

    func status(for permission: MediaPermission) -> PermissionStatus {
        statuses.withLock { $0[permission] ?? .granted }
    }

    func request(_ permission: MediaPermission) async -> Bool {
        statuses.withLock { statuses in
            if statuses[permission, default: .granted] == .notDetermined {
                statuses[permission] = answer ? .granted : .denied
            }
            return statuses[permission, default: .granted] == .granted
        }
    }

    func set(_ status: PermissionStatus, for permission: MediaPermission) {
        statuses.withLock { $0[permission] = status }
    }
}
