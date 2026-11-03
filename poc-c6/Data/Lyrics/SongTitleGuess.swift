//
//  SongTitleGuess.swift
//  poc-c6
//
//  Title and artist for the lyrics search when a file has no metadata, guessed from names like
//  "Dendi Nata - Abadi (Indo Version) Lyric Video" → ("Abadi (Indo Version)", "Dendi Nata").
//

import Foundation

nonisolated enum SongTitleGuess {
    /// Video and upload noise that is never part of a song title.
    private static let noise = [
        "official music video", "official video", "official audio", "official lyric video", "lyric video",
        "lyrics video", "with lyrics", "lyrics", "lirik", "video lirik", "audio", "mv", "hd", "hq", "4k",
    ]

    static func from(fileName: String) -> (title: String, artist: String?) {
        var name = fileName.replacingOccurrences(of: "_", with: " ")
        // "AWholeNewWorld" → "A Whole New World" (only names without any spaces).
        if !name.contains(" ") {
            name = name.replacingOccurrences(of: #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#, with: " ",
                                             options: .regularExpression)
        }
        // Bracketed noise such as "[Official Video]" or "(Lyrics)"; keep "(Indo Version)".
        for pattern in [#"\[[^\]]*\]"#, #"\((?:[^)]*(?:video|lyric|lirik|audio|official)[^)]*)\)"#] {
            name = name.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        for phrase in noise {
            name = name.replacingOccurrences(of: #"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#, with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–|")))
        // "Artist - Title" is the usual upload format.
        for separator in [" - ", " – ", " | "] {
            if let range = name.range(of: separator) {
                let artist = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let title = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty, !title.isEmpty { return (title, artist) }
            }
        }
        return (name, nil)
    }
}
