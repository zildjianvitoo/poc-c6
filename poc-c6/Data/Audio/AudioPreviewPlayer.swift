//
//  AudioPreviewPlayer.swift
//  poc-c6
//
//  Plays one file through the speaker or earphones for the trim and Ready screen previews.
//

import AVFoundation

nonisolated final class AudioPreviewPlayer: AudioPreviewing, @unchecked Sendable {
    private let lock = NSLock()
    private var player: AVAudioPlayer?

    func play(_ url: URL, from start: TimeInterval) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        player.currentTime = start
        player.play()
        lock.withLock { self.player = player }
    }

    var currentTime: TimeInterval? {
        lock.withLock { player.flatMap { $0.isPlaying ? $0.currentTime : nil } }
    }

    func stop() {
        let player = lock.withLock { () -> AVAudioPlayer? in
            defer { self.player = nil }
            return self.player
        }
        player?.stop()
    }
}
