import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@main struct KeyRehearsalApp: App {
    @StateObject private var model = AudioModel()
    var body: some Scene { WindowGroup { CoverFlowView().environmentObject(model).tint(.blue) } }
}
struct ContentView: View {
    @EnvironmentObject var model: AudioModel
    @AppStorage("chosenKey") private var chosenKey = 0
    @AppStorage("chosenSong") private var chosenSong = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var test = false
    @State private var showRecorder = false
    var body: some View {
        TabView {
            PreparationView().tabItem { Label("Siapkan", systemImage: "music.note.list") }
            NavigationStack {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.blue)
                            Text("Temukan key yang terasa pas.").font(.title2.bold())
                            Text("Dengarkan, coba nyanyikan, lalu pilih berdasarkan kenyamananmu.").foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                        Button { model.selectedKey = 0; test = false; showRecorder = true } label: { Label("Rekam latihan baru", systemImage: "mic.fill") }.disabled(model.busy || model.recording)
                        Button { importing = true } label: { Label("Impor seluruh rekaman", systemImage: "square.and.arrow.down") }.disabled(model.busy || model.recording)
                    }
                    Section("Pilihan rehearsal") {
                        Text(chosenSong.isEmpty ? "Belum ada lagu yang dipilih" : chosenSong).font(.headline)
                        LabeledContent("Key tersimpan", value: "\(chosenKey > 0 ? "+" : "")\(chosenKey) semitone")
                        Text("Relatif terhadap rekaman yang kamu coba; 0 berarti key asli.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Range suaramu") {
                        HStack { Label(model.voiceRange?.label ?? "Belum dites", systemImage: "music.note"); Spacer(); Button("Tes range") { test = true; showRecorder = true }.disabled(model.busy || model.recording) }
                        Text("Nyanyikan nada rendah dan tinggi yang nyaman. Range ini hasil tesmu, bukan label tipe suara.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Rekaman latihan") {
                        if model.busy { HStack { ProgressView(); Text("Menganalisis nada…") } }
                        if model.takes.isEmpty { ContentUnavailableView("Mulai dari suaramu", systemImage: "waveform", description: Text("Rekam vokal sendiri atau impor audio dari Files.")) }
                        ForEach(model.takes) { take in
                            NavigationLink { TakeView(id: take.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(take.name).font(.headline)
                                    Text(take.range?.label ?? "Range belum tersedia").font(.subheadline).foregroundStyle(.secondary)
                                    if let comfort = take.comfort { Text(comfort).font(.caption).foregroundStyle(.blue) }
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                }.navigationTitle("Key Rehearsal")
            }.tabItem { Label("Latihan", systemImage: "waveform") }
            NavigationStack {
                List {
                    Section("Sebelum tampil") {
                        Text("1. Tes range yang nyaman.")
                        Text("2. Dengarkan seluruh rekaman dan coba key alternatif.")
                        Text("3. Rekam ulang, nilai kenyamanan, cek bagian tinggi dan rendah.")
                    }
                    Section("Tentang PoC") {
                        Text("Transpose menggeser seluruh suara dan instrumen. Ini bukan auto-tune.")
                        Text("Rentang memakai persentil 5–95% dari nada terdeteksi agar bunyi singkat tidak mendominasi. Estimasi bisa salah pada musik polifonik, noise, atau perubahan register.")
                        Text("Ukuran deviasi nada hanya menunjukkan jarak dari semitone terdekat. Tanpa melodi target, app tidak menilai ketepatan bernyanyi.")
                        Text("Audio diproses lokal dan tersimpan di perangkat. Gunakan headphone saat mencoba key lalu merekam ulang.")
                    }
                }.navigationTitle("Panduan")
            }.tabItem { Label("Panduan", systemImage: "info.circle") }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            model.stopPlayback()
            if model.recording { model.finishRecording(); showRecorder = false; model.message = "Rekaman terhenti oleh sistem. Take yang terekam sudah disimpan; coba rekam ulang." }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in model.stopPlayback() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.cancelPendingRecording() }
            if phase != .active { model.stopPlayback(); if model.recording { model.finishRecording(); showRecorder = false } }
        }
        .sheet(isPresented: $showRecorder) { RecorderView(rangeTest: test).environmentObject(model) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result { case .success(let url): model.importAudio(url); case .failure(let error): model.message = error.localizedDescription }
        }
        .alert("Key Rehearsal", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }
}
struct RecorderView: View {
    @EnvironmentObject var model: AudioModel
    @Environment(\.dismiss) var dismiss
    var rangeTest: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: model.recording ? "waveform" : "mic.circle.fill").font(.system(size: 80)).foregroundStyle(model.recording ? .red : .blue).accessibilityHidden(true)
                Text(rangeTest ? "Kenali range-mu" : "Rekam latihanmu").font(.title.bold())
                Text(rangeTest ? "Nyanyikan perlahan dari nada rendah ke tinggi yang nyaman, lalu kembali. Jangan memaksa suara." : "Nyanyikan seluruh lagu. Rekam vokal tanpa pengiring untuk analisis yang lebih jelas.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60)).font(.largeTitle.monospacedDigit())
                Button {
                    if model.recording { model.finishRecording(); dismiss() }
                    else { Task { await model.startRecording(test: rangeTest) } }
                } label: { Label(model.recording ? "Selesai & analisis" : "Mulai merekam", systemImage: model.recording ? "stop.fill" : "mic.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).disabled(model.busy || model.requestingPermission)
                Spacer()
            }.padding(24).navigationTitle("Rekaman").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() }.disabled(model.recording || model.requestingPermission) } }
        }.interactiveDismissDisabled(model.recording || model.requestingPermission)
    }
}
struct TakeView: View {
    @EnvironmentObject var model: AudioModel
    var id: UUID
    @State private var key = 0
    @State private var record = false
    @State private var highChecked = false
    @State private var fullChecked = false
    var take: Take? { model.takes.first { $0.id == id } }
    var body: some View {
        if let take {
            List {
                Section("Rentang rekaman") {
                    Text(take.range?.label ?? "Belum terdeteksi").font(.largeTitle.bold()).foregroundStyle(.blue)
                    if let voice = model.voiceRange { LabeledContent("Range nyamanmu", value: voice.label) }
                    Text("Perbedaan jangkauan bukan diagnosis fals. Analisis vokal tunggal lebih dapat diandalkan.").font(.footnote).foregroundStyle(.secondary)
                    if take.range == nil { Button("Analisis ulang") { model.analyze(url: model.directory.appendingPathComponent(take.filename), id: id) }.disabled(model.busy) }
                }
                Section("Coba key alternatif") {
                    Stepper(value: $key, in: -12...12) { LabeledContent("Transpose", value: "\(key > 0 ? "+" : "")\(key) semitone") }.onChange(of: key) { _, _ in model.stopPlayback() }
                    if let range = take.range {
                        LabeledContent("Hasil setelah transpose", value: PitchRange(low: range.low + key, high: range.high + key).label)
                        if let voice = model.voiceRange {
                            let fits = range.low + key >= voice.low && range.high + key <= voice.high
                            Label(fits ? "Masuk range tes; coba kenyamanannya." : "Sebagian nada masih di luar range tes.", systemImage: fits ? "checkmark.circle" : "exclamationmark.circle").font(.footnote).foregroundStyle(fits ? .green : .orange)
                        }
                        if let suggestion = model.suggestion(for: range) { Button("Coba usulan \(suggestion) semitone") { key = suggestion; model.stopPlayback() } }
                        else { Text("Tes range di halaman Latihan untuk mendapatkan usulan.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section("Dengarkan A / B") {
                    Button { model.play(take, semitones: 0) } label: { Label("A · Rekaman asli", systemImage: "play.circle.fill") }
                    Button { model.play(take, semitones: key) } label: { Label("B · Transpose \(key) semitone", systemImage: "play.circle.fill") }
                    if model.playing { Button("Hentikan", systemImage: "stop.circle") { model.stopPlayback() } }
                    Text("A dan B mulai dari awal agar kamu mendengar seluruh rekaman. Tempo dipertahankan; karakter suara bisa berubah.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Nyanyikan & rekam ulang") {
                    Button("Rekam take baru", systemImage: "mic.fill") { model.selectedKey = key; model.stopPlayback(); record = true }.disabled(model.busy)
                    LabeledContent("Key saat direkam", value: "\(take.key) semitone")
                    Text("Bagaimana kenyamanan take ini?").font(.subheadline)
                    ForEach(["Nyaman", "Masih sulit", "Tidak nyaman"], id: \.self) { value in Button { model.comfort(value, id: id) } label: { HStack { Text(value); Spacer(); if take.comfort == value { Image(systemName: "checkmark") } } } }
                    if let stability = take.stability { LabeledContent("Deviasi ke semitone terdekat", value: String(format: "%.0f cents", stability)); Text("Bukan skor akurasi melodi. Bandingkan bersama kenyamanan dan dengarkan hasilnya.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Cek lagu penuh") {
                    Toggle("Bagian tinggi dan rendah nyaman", isOn: $highChecked)
                    Toggle("Sudah mencoba seluruh lagu", isOn: $fullChecked)
                    Button("Simpan key rehearsal") { model.saveChoice(key, take: take) }.disabled(!highChecked || !fullChecked)
                }
            }.navigationTitle(take.name).navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $record) { RecorderView(rangeTest: false).environmentObject(model) }
                .onDisappear { model.stopPlayback() }
        }
    }
}


struct CoverFlowView: View {
    @EnvironmentObject var voice: AudioModel
    @State private var importingSong = false
    @State private var testing = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if importingSong, voice.voiceRange != nil {
                PreparationView(onRetest: { importingSong = false })
            } else {
                NavigationStack {
                    List {
                        Section {
                            Label("Mulai dari suaramu", systemImage: "mic.fill").font(.title2.bold())
                            Text("Tes rentang nada yang nyaman terlebih dahulu. Setelah itu, pilih lagu dan kami sesuaikan panduan nadanya.")
                        }
                        Section("1. Tes vocal range") {
                            if let range = voice.voiceRange {
                                LabeledContent("Range tersimpan", value: range.label)
                                Text("Range ini dipakai untuk memilih transposisi seluruh melodi, bukan mengubah tiap nada secara terpisah.").font(.footnote).foregroundStyle(.secondary)
                            }
                            Button(voice.voiceRange == nil ? "Mulai tes vocal range" : "Tes ulang vocal range") { testing = true }
                                .disabled(voice.busy || voice.recording)
                            if voice.busy { HStack { ProgressView(); Text("Menganalisis range…") } }
                        }
                        Section("2. Pilih lagu") {
                            Button { importingSong = true } label: {
                                Text("Lanjut ke impor lagu").frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent).disabled(voice.voiceRange == nil || voice.busy || voice.recording)
                            Text("Berikutnya: impor → analisis vokal → sesuaikan guide → tinjau → siap latihan.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.navigationTitle("Siapkan cover")
                }
            }
        }
        .sheet(isPresented: $testing) { RecorderView(rangeTest: true).environmentObject(voice) }
        .alert("Tes vocal range", isPresented: Binding(get: { voice.message != nil }, set: { if !$0 { voice.message = nil } })) {
            Button("OK") { voice.message = nil }
        } message: { Text(voice.message ?? "") }
        .onChange(of: phase) { _, value in
            if value != .active {
                voice.cancelPendingRecording(); voice.stopPlayback()
                if voice.recording { voice.finishRecording(); testing = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            if voice.recording { voice.finishRecording(); testing = false }
        }
    }
}
