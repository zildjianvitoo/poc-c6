//
//  AttemptHistory.swift
//  poc-c6
//

import Foundation

nonisolated struct AttemptHistory: Codable {
  var sessions: [PracticeSessionRecord] = []
  mutating func begin() -> UUID {
    let session = PracticeSessionRecord(id: UUID(), startedAt: Date())
    sessions.append(session)
    return session.id
  }
  mutating func record(
    sessionID: UUID, phrase: Phrase, attempt: Int, start: Double, score: Double, mae: Double? = nil,
    useMAE: Bool = false, sampleCount: Int = 0
  ) {
    guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
    sessions[index].record(
      phrase: phrase, attempt: attempt, start: start, score: score, mae: mae, useMAE: useMAE,
      sampleCount: sampleCount)
  }
  static func fileURL() throws -> URL {
    let folder = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return folder.appendingPathComponent("practice-history.json")
  }
  static func load() throws -> Self {
    let url = try fileURL()
    guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
  func save() throws {
    try JSONEncoder().encode(self).write(to: Self.fileURL(), options: .atomic)
  }
  static var example: Self {
    var history = Self()
    let id = history.begin()
    history.record(sessionID: id, phrase: Phrase.all[0], attempt: 1, start: 3, score: 0.10)
    history.record(sessionID: id, phrase: Phrase.all[0], attempt: 2, start: 12.8, score: 0.83)
    history.record(sessionID: id, phrase: Phrase.all[1], attempt: 1, start: 17.6, score: 0.91)
    return history
  }
}
