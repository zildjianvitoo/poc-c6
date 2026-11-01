//
//  AudioPreviewPlayer.swift
//  poc-c6
//
//  Plays one file through the speaker or earphones for the Ready screen preview.
//

import AVFoundation

nonisolated final class AudioPreviewPlayer: AudioPreviewing, @unchecked Sendable {
    private let lock = NSLock()
    private var player: AVAudioPlayer?

    func play(_ url: URL) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        player.play()
        lock.withLock { self.player = player }
    }

    func stop() {
        let player = lock.withLock { () -> AVAudioPlayer? in
            defer { self.player = nil }
            return self.player
        }
        player?.stop()
    }
}
