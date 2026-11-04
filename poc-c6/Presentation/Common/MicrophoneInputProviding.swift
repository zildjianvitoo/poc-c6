//
//  MicrophoneInputProviding.swift
//  poc-c6
//

import Foundation

/// Actual active input, so screens can show which microphone is being used.
nonisolated protocol MicrophoneInputProviding: AnyObject {
    var microphoneName: String? { get }
    var isHeadsetMicrophoneActive: Bool { get }
}
