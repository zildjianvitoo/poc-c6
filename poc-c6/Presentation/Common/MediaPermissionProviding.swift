//
//  MediaPermissionProviding.swift
//  poc-c6
//
//  Presentation-side capability, not a Domain contract. Owner: Zildjian Vito (ZV-14).
//

import Foundation

nonisolated enum MediaPermission: String, CaseIterable, Sendable {
    case camera
    case microphone

    var displayName: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        }
    }

    var reason: String {
        switch self {
        case .camera: "to record your cover video"
        case .microphone: "to hear your voice and check your pitch"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        }
    }
}

nonisolated enum PermissionStatus: Sendable {
    case notDetermined
    case granted
    case denied
}

nonisolated protocol MediaPermissionProviding: Sendable {
    func status(for permission: MediaPermission) -> PermissionStatus
    /// Shows the system prompt when the status is `.notDetermined`. Returns whether access is granted.
    func request(_ permission: MediaPermission) async -> Bool
}
