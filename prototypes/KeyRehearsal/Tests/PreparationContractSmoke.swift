import Foundation
struct GuideNote: Codable, Identifiable {
    var id: Int
    var pitch: Int
    var start: Double
    var end: Double
}
struct LyricWord: Codable {
    var start: Double
    var end: Double
    var text: String
    var probability: Double
}
struct GuideSegment: Codable, Identifiable {
    var id: Int
    var start: Double
    var end: Double
    var lyrics: String
    var lyricsEdited: Bool?
}
struct PracticePackage: Codable {
    var duration: Double
    var notes: [GuideNote]
    var segments: [GuideSegment]
    var sourceOffset: Double
    var demo: Bool
    // Optional so projects saved before automatic lyrics remain decodable.
    var words: [LyricWord]?
    var language: String?
    var lyricsStatus: String?
    var warnings: [String]?
}
struct PreparedSong: Codable, Identifiable {
    var id: UUID
    var name: String
    var sourceFile: String
    var duration: Double
    var start: Double
    var end: Double
    var package: PracticePackage?
    var backingFile: String?
    var vocalFile: String?
}
struct AnalysisJob: Decodable {
    var id: String
    var status: String
    var message: String
    var result: PracticePackage?
}


let legacy = Data(#"{"duration":2,"notes":[{"id":0,"pitch":60,"start":0,"end":1}],"segments":[{"id":0,"start":0,"end":2,"lyrics":""}],"sourceOffset":60,"demo":false}"#.utf8)
let old = try JSONDecoder().decode(PracticePackage.self, from: legacy)
assert(old.words == nil && old.segments[0].lyricsEdited == nil)
let modern = Data(#"{"duration":2,"notes":[{"id":0,"pitch":60,"start":0,"end":1}],"segments":[{"id":0,"start":0,"end":2,"lyrics":"halo","lyricsEdited":false}],"sourceOffset":60,"demo":false,"words":[{"start":0,"end":1,"text":"halo","probability":0.9}],"language":"id","lyricsStatus":"available","warnings":[]}"#.utf8)
let new = try JSONDecoder().decode(PracticePackage.self, from: modern)
assert(new.words?.first?.text == "halo" && new.sourceOffset == 60)
let saved = try JSONEncoder().encode(new)
let reopened = try JSONDecoder().decode(PracticePackage.self, from: saved)
assert(reopened.words?.first?.end == 1 && reopened.segments[0].lyrics == "halo")
print("Swift contracts passed: legacy decode, lyric timestamps decode, save/reopen.")
