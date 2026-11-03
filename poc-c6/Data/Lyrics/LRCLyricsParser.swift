//
//  LRCLyricsParser.swift
//  poc-c6
//
//  Turns LRC text ("[01:02.50] words…") into timed lines, and estimates word times inside each
//  line from syllable counts (LRC only times whole lines).
//

import Foundation

nonisolated enum LRCLyricsParser {
    /// A held note rarely lasts longer than this per syllable; caps how far a line's words stretch
    /// into the pause or instrumental break before the next line.
    static let maxSecondsPerSyllable = 0.8

    static func lines(from lrc: String, duration: TimeInterval) -> [LyricLine] {
        var offset: TimeInterval = 0
        var stamped: [(time: TimeInterval, text: String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            if let value = tag("offset", in: rest) {
                // [offset:+250] shifts lyrics earlier by 250 ms (LRC convention).
                offset = (Double(value) ?? 0) / 1000
                continue
            }
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                guard let time = seconds(rest[rest.index(after: rest.startIndex)..<close]) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { stamped.append((time, text)) }
        }
        stamped = stamped.map { ($0.time - offset, $0.text) }
            .filter { $0.time >= 0 && $0.time < duration }
            .sorted { $0.time < $1.time }

        var result: [LyricLine] = []
        for (index, entry) in stamped.enumerated() where !entry.text.isEmpty {
            let end = index + 1 < stamped.count ? stamped[index + 1].time : duration
            guard end > entry.time else { continue }
            result.append(LyricLine(id: result.count, text: entry.text, start: entry.time, end: end,
                                    words: words(in: entry.text, start: entry.time, end: end)))
        }
        return result
    }

    /// Spreads a line's words over its time by syllable count, capped at `maxSecondsPerSyllable`.
    static func words(in text: String, start: TimeInterval, end: TimeInterval) -> [LyricWord] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let weights = tokens.map { Double(syllables($0)) }
        let total = weights.reduce(0, +)
        let span = min(end - start, total * maxSecondsPerSyllable)
        var time = start
        return zip(tokens, weights).map { token, weight in
            let length = span * weight / total
            defer { time += length }
            return LyricWord(text: token, start: time, end: time + length)
        }
    }

    /// Vowel groups (English and Indonesian spelling), at least 1.
    static func syllables(_ word: String) -> Int {
        var count = 0
        var previousWasVowel = false
        for character in word.lowercased() {
            let isVowel = "aeiouyàáâäèéêëìíîïòóôöùúûü".contains(character)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        return max(1, count)
    }

    /// "mm:ss.xx" or "mm:ss" → seconds.
    private static func seconds(_ stamp: Substring) -> TimeInterval? {
        let parts = stamp.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }

    /// Value of a metadata tag such as "[offset:+250]".
    private static func tag(_ name: String, in line: Substring) -> Substring? {
        let prefix = "[\(name):"
        guard line.lowercased().hasPrefix(prefix), line.hasSuffix("]") else { return nil }
        return line.dropFirst(prefix.count).dropLast().trimmingCharacters(in: .whitespaces)[...]
    }
}
