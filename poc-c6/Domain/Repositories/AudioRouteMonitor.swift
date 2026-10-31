//
//  AudioRouteMonitor.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Takin
//

import Foundation

nonisolated protocol AudioRouteMonitor: AnyObject {
    var currentRoute: AudioOutputRoute { get }
    func routeChanges() -> AsyncStream<AudioOutputRoute>
    /// Emits when a phone call, Siri, or another app interrupts the audio session.
    func interruptions() -> AsyncStream<Void>
}
