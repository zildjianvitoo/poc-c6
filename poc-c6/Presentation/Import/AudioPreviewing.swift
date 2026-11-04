//
//  AudioPreviewing.swift
//  poc-c6
//
//  Plays a track for a quick listen: the imported song from the trim start (with lyrics), a key's
//  phrase excerpt on the key choice screen, or a prepared track on the Ready screen to judge the
//  vocal removal. Implemented by AudioPreviewPlayer (Data).
//

import Foundation

nonisolated protocol AudioPreviewing: AnyObject {
    /// Plays `url` from `start` seconds.
    func play(_ url: URL, from start: TimeInterval) throws
    /// Plays only this song-timeline interval; completion also fires after an interruption.
    func play(_ url: URL, excerpt: ClosedRange<TimeInterval>,
              onCompletion: @escaping @Sendable () -> Void) async throws
    func stop()
    /// Position in the file while playing, nil when stopped or finished.
    var currentTime: TimeInterval? { get }
}

nonisolated extension AudioPreviewing {
    func play(_ url: URL) throws { try play(url, from: 0) }
}
