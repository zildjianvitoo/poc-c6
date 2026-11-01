//
//  Accompaniment.swift
//  poc-c6
//

import Foundation

nonisolated enum Accompaniment {
  // Join PCM payloads into a single WAV so playback never restarts on success.
  static func songWAV() -> Data {
    let parts = Phrase.all.map { wav(phrase: $0) }
    var data = Data(parts[0].prefix(44))
    for part in parts { data.append(part.dropFirst(44)) }
    func write(_ number: UInt32, at offset: Int) {
      var value = number.littleEndian
      withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
    }
    write(UInt32(data.count - 8), at: 4)
    write(UInt32(data.count - 44), at: 40)
    return data
  }

  static func wav(phrase: Phrase) -> Data {
    let rate = 22050
    let count = Int((phrase.duration * Double(rate)).rounded())
    let chord = phrase.id == 1 || phrase.id == 5 ? [48, 53, 57, 60] : [48, 52, 55, 60]
    let notes = phrase.notes
    var pcm = Data(capacity: count * 2)
    for i in 0..<count {
      let t = Double(i) / Double(rate)
      let absolute = phrase.start + t
      let note = notes.first { absolute < $0.start + $0.duration } ?? notes.last!
      let nt = absolute - note.start
      let envelope =
        min(1, nt / 0.008) * exp(-2.5 * nt) * max(0, min(1, (note.duration - nt) / 0.025))
      let phase = 2 * Double.pi * note.frequency * nt
      let melody = (sin(phase) + 0.25 * sin(2 * phase)) * envelope * 0.16
      let beat = Int(t / 0.3)
      let bt = t - Double(beat) * 0.3
      let hz = 440 * pow(2, Double(chord[beat % chord.count] - 69) / 12)
      let backing = sin(2 * .pi * hz * bt) * min(1, bt / 0.008) * exp(-10 * bt) * 0.09
      let fade = min(1, max(0, (phrase.duration - t) / 0.03))
      var value = Int16((melody + backing) * fade * 32767).littleEndian
      withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
    }
    var data = Data()
    func text(_ s: String) { data.append(contentsOf: s.utf8) }
    func u32(_ n: UInt32) {
      var v = n.littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    func u16(_ n: UInt16) {
      var v = n.littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    text("RIFF")
    u32(UInt32(pcm.count + 36))
    text("WAVEfmt ")
    u32(16)
    u16(1)
    u16(1)
    u32(UInt32(rate))
    u32(UInt32(rate * 2))
    u16(2)
    u16(16)
    text("data")
    u32(UInt32(pcm.count))
    data.append(pcm)
    return data
  }
}

// Display only. Never feed these values into SegmentEvaluator.
// Centered median keeps sample timestamps and waits one buffer for confirmation.
