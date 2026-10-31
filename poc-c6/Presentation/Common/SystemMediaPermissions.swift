//
//  SystemMediaPermissions.swift
//  poc-c6
//
//  Camera and microphone permissions through AVFoundation. Owner: Zildjian Vito (ZV-14).
//

import AVFoundation

nonisolated final class SystemMediaPermissions: MediaPermissionProviding {
    func status(for permission: MediaPermission) -> PermissionStatus {
        switch permission {
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .granted
            case .notDetermined: .notDetermined
            default: .denied
            }
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: .granted
            case .undetermined: .notDetermined
            default: .denied
            }
        }
    }

    func request(_ permission: MediaPermission) async -> Bool {
        switch permission {
        case .camera: await AVCaptureDevice.requestAccess(for: .video)
        case .microphone: await AVAudioApplication.requestRecordPermission()
        }
    }
}
