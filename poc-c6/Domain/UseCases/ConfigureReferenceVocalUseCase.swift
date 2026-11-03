//
//  ConfigureReferenceVocalUseCase.swift
//  poc-c6
//

import Foundation

nonisolated struct ConfigureReferenceVocalUseCase {
    let playback: (any ReferenceVocalPlayback)?
    var isAvailable: Bool { playback != nil }
    func load(song: PreparedSong) throws {
        try playback?.loadKaraoke(mixURL: song.earphoneMixURL, instrumentalURL: song.instrumentalURL)
    }
    func execute(enabled: Bool) { playback?.setReferenceVocalEnabled(enabled) }
}
