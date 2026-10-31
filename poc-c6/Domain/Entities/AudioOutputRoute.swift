//
//  AudioOutputRoute.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//

import Foundation

nonisolated enum AudioOutputRoute: Sendable, Equatable {
    case wired
    case bluetooth
    case speaker
    case other

    /// Record is blocked on the built-in speaker/receiver.
    var allowsRecording: Bool { self != .speaker }
}
