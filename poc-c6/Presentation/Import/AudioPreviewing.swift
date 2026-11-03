//
//  AudioPreviewing.swift
//  poc-c6
//
//  Plays a prepared track on the Ready screen, e.g. the instrumental, so the vocal removal
//  can be judged before recording. Implemented by AudioPreviewPlayer (Data).
//

import Foundation

nonisolated protocol AudioPreviewing: AnyObject {
    func play(_ url: URL) throws
    /// Plays only this song-timeline interval; completion also fires after an interruption.
    func play(_ url: URL, excerpt: ClosedRange<TimeInterval>,
              onCompletion: @escaping @Sendable () -> Void) async throws
    func stop()
}
