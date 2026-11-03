//
//  AudioPreviewPlayer.swift
//  poc-c6
//
//  Plays one file through the speaker or earphones for the Ready screen preview.
//

import AVFoundation

nonisolated final class AudioPreviewPlayer: NSObject, AudioPreviewing, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var excerptURL: URL?
    private var completion: (@Sendable () -> Void)?
    private var generation = UUID()

    func play(_ url: URL) throws {
        stop()
        let token = lock.withLock { generation }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        try lock.withLock {
            guard generation == token else { throw CancellationError() }
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            self.player = player
        }
    }

    func play(_ url: URL, excerpt: ClosedRange<TimeInterval>,
              onCompletion: @escaping @Sendable () -> Void) async throws {
        stop()
        let token = lock.withLock { generation }
        let render = Task.detached(priority: .userInitiated) {
            try AudioExcerptRenderer().render(url, excerpt: excerpt)
        }
        let clip = try await withTaskCancellationHandler {
            try await render.value
        } onCancel: { render.cancel() }
        do {
            try Task.checkCancellation()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: clip)
            player.delegate = self
            try lock.withLock {
                guard generation == token else { throw CancellationError() }
                guard player.play() else { throw CocoaError(.fileReadUnknown) }
                self.player = player
                excerptURL = clip
                completion = onCompletion
            }
        } catch {
            try? FileManager.default.removeItem(at: clip)
            throw error
        }
    }

    func stop() {
        let stopped = lock.withLock { () -> (AVAudioPlayer?, URL?) in
            generation = UUID()
            defer { player = nil; excerptURL = nil; completion = nil }
            return (player, excerptURL)
        }
        stopped.0?.stop()
        if let url = stopped.1 { try? FileManager.default.removeItem(at: url) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        finish(player)
    }

    private func finish(_ finishedPlayer: AVAudioPlayer) {
        let finished = lock.withLock { () -> (URL?, (@Sendable () -> Void)?) in
            guard player === finishedPlayer else { return (nil, nil) }
            defer { player = nil; excerptURL = nil; completion = nil }
            return (excerptURL, completion)
        }
        if let url = finished.0 { try? FileManager.default.removeItem(at: url) }
        finished.1?()
    }
}
