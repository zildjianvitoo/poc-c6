//
//  LyricsChecks.swift
//  poc-c6
//
//  Checks for the trim-screen lyrics: LRC parsing, word-time estimates, title/artist guesses from
//  file names, picking the LRCLIB version that matches the file's duration, and finding the chorus.
//  No network.
//

import Foundation

nonisolated enum LyricsChecks {
    static func run() async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "Lyrics", message: message) }
        }
        func near(_ a: TimeInterval, _ b: TimeInterval) -> Bool { abs(a - b) < 1e-6 }

        // LRC: offset tag, one text with two stamps, an empty stamp (instrumental break), out of order.
        let lrc = """
            [ar:Someone]
            [offset:+500]
            [00:10.50] First line here
            [00:14.00][01:00.00] Repeated chorus line
            [00:20.00]
            [00:40.00] After the break
            [00:05.00] Intro words
            """
        let lines = LRCLyricsParser.lines(from: lrc, duration: 70)
        try check(lines.map(\.text) == ["Intro words", "First line here", "Repeated chorus line", "After the break", "Repeated chorus line"],
                  "lines sorted, repeated stamp duplicated, break not a line: \(lines.map(\.text))")
        try check(near(lines[0].start, 4.5) && near(lines[1].start, 10.0), "offset +500 ms moves lines earlier")
        try check(near(lines[2].end, 19.5), "a line ends where the break starts")
        try check(near(lines[4].end, 70), "the last line ends at the song's end")
        try check(lines.map(\.id) == Array(0..<lines.count), "ids are 0-based positions")

        let words = lines[1].words
        try check(words.map(\.text) == ["First", "line", "here"], "words split on spaces")
        try check(near(words.first!.start, lines[1].start) && zip(words, words.dropFirst()).allSatisfy { near($0.end, $1.start) },
                  "words are back to back from the line start")
        let capped = lines[2].words  // 5.5 s line before a long break, 7 syllables
        try check(capped.last!.end <= lines[2].start + 7 * LRCLyricsParser.maxSecondsPerSyllable + 1e-6,
                  "words don't stretch into the break: ends at \(capped.last!.end)")
        let full = LRCLyricsParser.words(in: "a b", start: 0, end: 0.5)
        try check(near(full.last!.end, 0.5), "a short line uses its whole time")
        try check([LRCLyricsParser.syllables("abadi"), LRCLyricsParser.syllables("selamanya"),
                   LRCLyricsParser.syllables("world"), LRCLyricsParser.syllables("fantastic"), LRCLyricsParser.syllables("hmm")] == [3, 4, 1, 3, 1],
                  "syllable counts")
        try check(LRCLyricsParser.lines(from: "plain text, no stamps", duration: 60).isEmpty, "unsynced text gives no lines")

        // File names → (title, artist).
        let guesses: [(String, String, String?)] = [
            ("Dendi Nata - Abadi (Indo Version) Lyric Video", "Abadi (Indo Version)", "Dendi Nata"),
            ("Tulus – Hati-Hati di Jalan [Official Music Video]", "Hati-Hati di Jalan", "Tulus"),
            ("Raisa_-_Kali_Kedua_(Official_Audio)", "Kali Kedua", "Raisa"),
            ("A Whole New World Lyric Video", "A Whole New World", nil),
            ("AWholeNewWorld", "A Whole New World", nil),
        ]
        for (fileName, title, artist) in guesses {
            let guess = SongTitleGuess.from(fileName: fileName)
            try check(guess.title == title && guess.artist == artist, "\(fileName) → \(guess)")
        }

        // Chorus: the most repeated block of 2+ lines, first occurrence; fillers and single lines don't count.
        func song(_ texts: [String]) -> [LyricLine] {
            texts.enumerated().map { LyricLine(id: $0.offset, text: $0.element, start: Double($0.offset) * 4,
                                               end: Double($0.offset + 1) * 4, words: []) }
        }
        let verse = ["Walking down the road", "Thinking of you"]
        let chorus = ["This is the chorus,", "SING it loud", "Every night"]
        let structure = verse + chorus + ["Second verse here", "Something new"] + chorus + ["Oh oh oh", "Oh oh oh"]
            + ["Bridge line"] + chorus.map { $0.lowercased() } + ["Outro"]
        try check(ChorusFinder.chorus(in: song(structure)) == 2..<5, "chorus = repeated 3-line block, case/punctuation ignored")
        try check(ChorusFinder.chorus(in: song(["Oh oh", "Oh oh", "Oh oh", "Oh oh", "Line a", "Line b"])) == nil,
                  "filler-only repeats are not a chorus")
        try check(ChorusFinder.chorus(in: song(["Same line", "Other", "Same line", "Different"])) == nil,
                  "a single repeated line is not a chorus")
        try check(ChorusFinder.chorus(in: song(verse + ["Ábadi untuk selamanya", "Selama-lamanya"] + verse + ["Abadi untuk selamanya", "selama lamanya"])) != nil,
                  "accents and hyphens are ignored when matching")

        // Version choice: synced, not instrumental, closest duration within the tolerance.
        func record(_ duration: Double, synced: Bool = true, instrumental: Bool = false) -> LRCLibLyricsProvider.Record {
            .init(trackName: "Abadi", artistName: "Dendi Nata", duration: duration, instrumental: instrumental,
                  syncedLyrics: synced ? "[00:01.00] x" : nil)
        }
        let records = [record(257), record(276.5, synced: false), record(279), record(275.8, instrumental: true), record(274)]
        try check(LRCLibLyricsProvider.bestMatch(records, duration: 276)?.duration == 274, "closest synced, non-instrumental version")
        try check(LRCLibLyricsProvider.bestMatch([record(257), record(290)], duration: 276) == nil,
                  "no version within \(LRCLibLyricsProvider.durationTolerance) s → no lyrics")
        return count
    }
}
