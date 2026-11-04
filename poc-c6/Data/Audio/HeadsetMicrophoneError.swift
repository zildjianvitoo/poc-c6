//
//  HeadsetMicrophoneError.swift
//  poc-c6
//

import Foundation

nonisolated enum HeadsetMicrophoneError: Error {
    case unavailable
}

extension Notification.Name {
    nonisolated static let headsetMicrophoneChanged = Notification.Name("HeadsetMicrophoneChanged")
}
