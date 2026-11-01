//
//  AttemptHistoryView.swift
//  poc-c6
//

import SwiftUI

struct AttemptHistoryView: View {
  let history: AttemptHistory
  let error: String?
  @Environment(\.dismiss) private var dismiss
  @State private var showExample = false
  init(history: AttemptHistory, error: String?) {
    self.history = history
    self.error = error
    #if DEBUG
      _showExample = State(
        initialValue: ProcessInfo.processInfo.arguments.contains("--preview-history"))
    #endif
  }
  private var sessions: [PracticeSessionRecord] {
    showExample ? AttemptHistory.example.sessions : history.sessions
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Hasil akhir & riwayat percobaan").font(.title2.bold())
          Text(
            "Waktu dihitung dari awal sesi, termasuk countdown dan pengulangan. Belum ada rekaman video."
          )
          .font(.callout).foregroundStyle(.secondary)
          Toggle("Tampilkan contoh POC", isOn: $showExample)
          if showExample {
            Label(
              "DATA CONTOH · bukan hasil nyanyianmu · tidak disimpan", systemImage: "info.circle"
            )
            .font(.caption.bold()).foregroundStyle(.orange)
          }
          if let error { Text(error).font(.caption).foregroundStyle(.red) }
          if sessions.isEmpty {
            ContentUnavailableView(
              "Belum ada riwayat", systemImage: "list.clipboard",
              description: Text(
                "Selesaikan satu bait untuk melihat catatan, atau aktifkan contoh POC."))
          }
          ForEach(Array(sessions.reversed())) { session in
            SessionHistoryCard(session: session)
          }
        }.padding(20)
      }.navigationTitle("Hasil latihan").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } } }
    }
  }
}
