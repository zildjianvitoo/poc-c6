//
//  AudioRouteMonitorImpl.swift
//  poc-c6
//

import AVFoundation

nonisolated final class AudioRouteMonitorImpl: AudioRouteMonitor, @unchecked Sendable {
    private nonisolated final class Observer: @unchecked Sendable {
        let token: NSObjectProtocol
        init(_ token: NSObjectProtocol) { self.token = token }
        func cancel() { NotificationCenter.default.removeObserver(token) }
    }

    var currentRoute: AudioOutputRoute {
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
        if ports.contains(.builtInSpeaker) || ports.contains(.builtInReceiver) { return .speaker }
        if ports.contains(.bluetoothA2DP) || ports.contains(.bluetoothLE) { return .bluetooth }
        if ports.contains(.headphones) || ports.contains(.usbAudio) { return .wired }
        return .other
    }
    var isEarphoneConnected: Bool { currentRoute == .wired || currentRoute == .bluetooth }

    func routeChanges() -> AsyncStream<AudioOutputRoute> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(currentRoute)
            let observer = Observer(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
                if let self { continuation.yield(self.currentRoute) }
            })
            continuation.onTermination = { _ in observer.cancel() }
        }
    }
    func interruptions() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = Observer(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if type == AVAudioSession.InterruptionType.began.rawValue { continuation.yield(()) }
            })
            continuation.onTermination = { _ in observer.cancel() }
        }
    }
}
