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
    func stop()
}
