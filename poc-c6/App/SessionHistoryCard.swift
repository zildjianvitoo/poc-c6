//
//  SessionHistoryCard.swift
//  poc-c6
//

import SwiftUI

nonisolated struct SessionHistoryCard: View {
  let session: PracticeSessionRecord
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(session.startedAt, format: .dateTime.day().month().hour().minute()).font(.headline)
      Text("Hasil akhir per bait").font(.subheadline.bold())
      ForEach(Phrase.all) { phrase in
        let final = session.finalResults.first { $0.phraseIndex == phrase.id }
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Bait \(phrase.id + 1)").bold()
            Spacer()
            Text(final == nil ? "BELUM" : "SUDAH").bold()
              .foregroundStyle(final == nil ? Color.secondary : Color.green)
          }
          if let final {
            Text("LOLOS · \(final.metricText) · percobaan \(final.attempt)")
            Text("Waktu sesi \(time(final.sessionStart)) – \(time(final.sessionEnd))")
              .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
          } else {
            Text(
              "\(session.attempts.filter { $0.phraseIndex == phrase.id }.count) percobaan selesai · belum ada hasil lolos"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.font(.subheadline)
      }
      Divider()
      Text("Semua percobaan (\(session.attempts.count))").font(.subheadline.bold())
      if session.attempts.isEmpty {
        Text(
          "Belum ada bait yang selesai dinilai. Bait yang dihentikan di tengah tidak ditandai gagal."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      ForEach(session.attempts) { attempt in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Bait \(attempt.phraseIndex + 1) · Percobaan \(attempt.attempt)").bold()
            Spacer()
            Text(attempt.label).bold().foregroundStyle(attempt.passed ? .green : .orange)
          }
          Text(attempt.metricText)
          if attempt.usesMAE == true {
            Text(
              "\(attempt.sampleCount ?? 0) sampel valid · batas MAE \(String(format: "%.1f", attempt.maeLimit ?? 34.5)) cents"
            )
          }
          Text("Waktu sesi: \(time(attempt.sessionStart)) – \(time(attempt.sessionEnd))")
            .monospacedDigit()
          Text("Posisi lagu: \(time(attempt.songStart)) – \(time(attempt.songEnd))")
            .monospacedDigit().foregroundStyle(.secondary)
        }.font(.caption).padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            attempt.passed ? Color.green.opacity(0.08) : Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12))
      }
    }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
  }
  private func time(_ seconds: Double) -> String {
    String(format: "%02d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
  }
  private func percent(_ score: Double) -> String { String(format: "%.1f%%", score * 100) }
}
