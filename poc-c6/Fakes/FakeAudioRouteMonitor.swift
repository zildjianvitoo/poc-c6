//
//  FakeAudioRouteMonitor.swift
//  poc-c6
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

import Foundation
import Synchronization

/// Route and interruptions are driven manually, e.g. from Debug Settings or previews.
nonisolated final class FakeAudioRouteMonitor: AudioRouteMonitor, Sendable {
    private struct State {
        var route: AudioOutputRoute
        var routeContinuations: [UUID: AsyncStream<AudioOutputRoute>.Continuation] = [:]
        var interruptionContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    }

    private let state: Mutex<State>

    init(route: AudioOutputRoute = .wired) {
        state = Mutex(State(route: route))
    }

    var currentRoute: AudioOutputRoute {
        state.withLock { $0.route }
    }

    func routeChanges() -> AsyncStream<AudioOutputRoute> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0.routeContinuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.routeContinuations.removeValue(forKey: id) }
            }
        }
    }

    func interruptions() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0.interruptionContinuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.interruptionContinuations.removeValue(forKey: id) }
            }
        }
    }

    func simulateRoute(_ route: AudioOutputRoute) {
        let continuations = state.withLock {
            $0.route = route
            return Array($0.routeContinuations.values)
        }
        continuations.forEach { $0.yield(route) }
    }

    func simulateInterruption() {
        state.withLock { Array($0.interruptionContinuations.values) }.forEach { $0.yield() }
    }
}
