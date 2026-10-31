//
//  PermissionGateModel.swift
//  poc-c6
//
//  Decides whether PermissionGate shows its content, an explanation, or a denied screen.
//  Owner: Zildjian Vito (ZV-14).
//

import Foundation
import Observation

@Observable
final class PermissionGateModel {
    enum State: Equatable {
        case checking
        case needsRequest([MediaPermission])
        case denied([MediaPermission])
        case granted
    }

    let permissions: [MediaPermission]
    private(set) var state: State = .checking
    private let provider: any MediaPermissionProviding

    init(permissions: [MediaPermission], provider: any MediaPermissionProviding) {
        self.permissions = permissions
        self.provider = provider
    }

    func refresh() {
        let statuses = permissions.map { ($0, provider.status(for: $0)) }
        let denied = statuses.filter { $0.1 == .denied }.map(\.0)
        let undetermined = statuses.filter { $0.1 == .notDetermined }.map(\.0)
        if !denied.isEmpty {
            state = .denied(denied)
        } else if !undetermined.isEmpty {
            state = .needsRequest(undetermined)
        } else {
            state = .granted
        }
    }

    /// Asks for every undetermined permission, one system prompt at a time.
    func requestMissing() async {
        for permission in permissions where provider.status(for: permission) == .notDetermined {
            _ = await provider.request(permission)
        }
        refresh()
    }
}
