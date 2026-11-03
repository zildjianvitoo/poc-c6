//
//  LyricsProviding.swift
//  poc-c6
//
//  Time-synced lyrics for the trim screen, so the user can see what is sung in the part they pick.
//  Times are seconds on the whole imported song. Implemented by LRCLibLyricsProvider (Data).
//

import Foundation

nonisolated struct LyricWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

nonisolated struct LyricLine: Equatable, Sendable, Identifiable {
    let id: Int
    let text: String
    let start: TimeInterval
    /// Start of the next line or break (or the song's end).
    let end: TimeInterval
    /// Estimated: the source only times whole lines.
    let words: [LyricWord]
}

nonisolated struct SongLyrics: Equatable, Sendable {
    let lines: [LyricLine]
    /// What the source matched, e.g. "Abadi (Indo Version) – Dendi Nata".
    let matchedTitle: String
    let matchedArtist: String
}

nonisolated enum LyricsLookupError: Error, Equatable {
    /// No connection, timeout, or the service is busy or down.
    case unavailable
}

nonisolated protocol LyricsProviding: Sendable {
    /// Synced lyrics for a song of `duration` seconds, or nil if none match.
    func lyrics(title: String, artist: String?, duration: TimeInterval) async throws -> SongLyrics?
}
