import Foundation
@main struct Checks {
 static func main() throws {
  var h = AttemptHistory(); let id = h.begin()
  h.record(sessionID: id, phrase: Phrase.all[0], attempt: 1, start: 3, score: 0.60)
  precondition(h.sessions[0].finalResults.isEmpty)
  h.record(sessionID: id, phrase: Phrase.all[0], attempt: 2, start: 13, score: 0.80)
  precondition(h.sessions[0].attempts.count == 2 && h.sessions[0].finalResults.count == 1)
  precondition(h.sessions[0].attempts[0].label == "GAGAL" && h.sessions[0].finalResults[0].label == "LOLOS")
  precondition(h.sessions[0].finalResults[0].attempt == 2)
  precondition(abs(h.sessions[0].finalResults[0].sessionEnd - 17.8) < 1e-9)
  precondition(h.sessions[0].attempts[0].songStart == h.sessions[0].attempts[1].songStart)
  h.record(sessionID: id, phrase: Phrase.all[0], attempt: 2, start: 13, score: 0.80)
  precondition(h.sessions[0].attempts.count == 2)
  h.record(sessionID: id, phrase: Phrase.all[1], attempt: 1, start: 17.8, score: 0.75)
  precondition(h.sessions[0].finalResults.count == 2)
  let second = h.begin()
  h.record(sessionID: second, phrase: Phrase.all[0], attempt: 1, start: 3, score: 0.749)
  precondition(h.sessions[1].finalResults.isEmpty && h.sessions[0].attempts.count == 3)
  let path = FileManager.default.temporaryDirectory.appendingPathComponent("history-check-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: path) }
  try JSONEncoder().encode(h).write(to: path, options: .atomic)
  let restored = try JSONDecoder().decode(AttemptHistory.self, from: Data(contentsOf: path))
  precondition(restored.sessions.count == 2 && restored.sessions[0].finalResults.count == 2)
  precondition(AttemptHistory.example.sessions[0].attempts.count == 3 && h.sessions[1].attempts.count == 1)
  print("PASS: 11 history checks (fail/pass, final result, timestamps, duplicate prevention, threshold, sessions, JSON round-trip, isolated example)")
 }
}
