//
//  ReferenceVocalPlayback.swift
//  poc-c6
//

import Foundation

/// Optional playback capability; both tracks share the reference playback anchor.
nonisolated protocol ReferenceVocalPlayback: AnyObject {
    func loadKaraoke(mixURL: URL, instrumentalURL: URL) throws
    func setReferenceVocalEnabled(_ enabled: Bool)
}
