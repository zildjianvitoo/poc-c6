//
//  ChorusFinder.swift
//  poc-c6
//
//  Finds the chorus (reff) in synced lyrics: the block of consecutive lines that repeats most in
//  the song. The trim screen suggests its first occurrence as the part to sing.
//

import Foundation

nonisolated enum ChorusFinder {
    /// Vocal fillers that repeat everywhere and say nothing about the chorus.
    private static let fillers: Set<String> = ["oh", "uh", "ah", "ooh", "yeah", "hey", "ho", "na", "la", "hmm", "mm"]

    /// Line indices of the chosen occurrence, or nil when no block of 2+ lines repeats.
    static func chorus(in lines: [LyricLine]) -> Range<Int>? {
        let keys = lines.map { key(for: $0.text) }
        var best: (start: Int, length: Int, score: Double)?
        for start in keys.indices where keys[start] != nil {
            var length = 2
            while start + length <= keys.count {
                let block = Array(keys[start..<(start + length)])
                guard !block.contains(nil) else { break }
                let starts = occurrences(of: block, in: keys)
                guard starts.count >= 2 else { break }
                // Coverage of the song: how much singing the repeated block accounts for.
                let duration = lines[start + length - 1].end - lines[start].start
                let score = Double(starts.count) * duration
                if starts.first == start, score > (best?.score ?? 0) {
                    best = (start, length, score)
                }
                length += 1
            }
        }
        return best.map { $0.start..<($0.start + $0.length) }
    }

    /// Non-overlapping starts of `block` in `keys`.
    private static func occurrences(of block: [String?], in keys: [String?]) -> [Int] {
        var starts: [Int] = []
        var index = 0
        while index + block.count <= keys.count {
            if Array(keys[index..<(index + block.count)]) == block {
                starts.append(index)
                index += block.count
            } else {
                index += 1
            }
        }
        return starts
    }

    /// Lowercased words without punctuation or accents; nil for filler-only lines.
    private static func key(for text: String) -> String? {
        let words = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard words.contains(where: { !fillers.contains($0) }) else { return nil }
        return words.joined(separator: " ")
    }
}
