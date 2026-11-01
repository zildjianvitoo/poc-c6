import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct PreparationView: View {
    var onRetest: () -> Void = {}
    @EnvironmentObject var voice: AudioModel
    @StateObject private var model = PreparationModel()
    @AppStorage("analysisEndpoint") private var endpoint = "http://mac-name.local:8765"
    @AppStorage("analysisToken") private var token = ""
    @State private var importing = false
    @State private var settings = false
    @State private var ready = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            List {
                Section("1. Vocal range") {
                    LabeledContent("Range suaramu", value: voice.voiceRange?.label ?? "Belum dites")
                    Button("Kembali ke tes range") { model.stop(); onRetest() }.disabled(model.busy)
                }
                if let song = model.current {
                    Section {
                        Label(song.name, systemImage: "music.note").font(.headline)
                        Text("\(stamp(song.duration)) • Audio tersimpan di iPhone").font(.subheadline).foregroundStyle(.secondary)
                        WaveformView(values: model.waveform, start: song.start / song.duration, end: song.end / song.duration)
                            .frame(height: 72).accessibilityLabel("Waveform audio, pilihan \(stamp(song.start)) sampai \(stamp(song.end))")
                        Button { model.play() } label: { Label(model.playing ? "Hentikan preview" : "Dengarkan pilihan", systemImage: model.playing ? "stop.fill" : "play.fill") }.disabled(model.busy)
                    }
                    if song.package == nil {
                        Section("Pilih bagian lagu") {
                            Text("PoC memproses hingga 60 detik per latihan.").font(.footnote).foregroundStyle(.secondary)
                            LabeledContent("Mulai", value: stamp(song.start))
                            Slider(value: Binding(get: { model.current?.start ?? 0 }, set: { value in model.selectRange(start: value, end: min(song.duration, max(value + 1, min(song.end, value + 60)))) }), in: 0...max(0.01, song.duration - 1), step: 0.1).accessibilityLabel("Awal potongan")
                            LabeledContent("Selesai", value: stamp(song.end))
                            Slider(value: Binding(get: { model.current?.end ?? 1 }, set: { model.selectRange(start: song.start, end: $0) }), in: (song.start + 1)...max(song.start + 1.01, min(song.duration, song.start + 60)), step: 0.1).accessibilityLabel("Akhir potongan")
                            if song.duration <= 60 { Button("Pilih seluruh lagu") { model.selectRange(start: 0, end: song.duration) } }
                        }.disabled(model.busy)
                        Section {
                            Button { model.analyze(endpoint: endpoint, token: token) } label: { Text("Siapkan panduan").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(model.busy)
                            Text("Pilih lagu asli dengan vokal dan instrumen. Mac memisahkan vokal, lalu membaca nada dan liriknya.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if model.busy {
                        Section { HStack { ProgressView(); Text(model.status) }; Button("Batalkan", role: .cancel) { model.cancel() } }
                    }
                    if let package = model.adjustedPackage {
                        Section("3. Guide sesuai range") {
                            LabeledContent("Transposisi", value: "\(model.guideShift > 0 ? "+" : "")\(model.guideShift) semitone")
                            HStack {
                                Button { model.changeShift(model.guideShift - 1) } label: { Label("Turunkan", systemImage: "minus").frame(minHeight: 44) }.disabled(model.busy || model.guideShift <= -12)
                                Spacer()
                                Button { model.changeShift(model.guideShift + 1) } label: { Label("Naikkan", systemImage: "plus").frame(minHeight: 44) }.disabled(model.busy || model.guideShift >= 12)
                            }.buttonStyle(.bordered)
                            Button("Key asli · 0 semitone") { model.changeShift(0) }.disabled(model.busy)
                            Button("Otomatis sesuai range") { model.useAutomaticShift() }.disabled(model.busy)
                            Text("Perubahan 1 semitone per tekan. Putar ulang untuk mendengar hasilnya. Pergeseran besar dapat membuat suara kurang alami.").font(.footnote).foregroundStyle(.secondary)
                            Text(model.fitsVoice ? "Semua target nada berada dalam range tesmu." : "Sebagian nada masih di luar range. Jangkauan melodi ini belum sepenuhnya cocok dengan range tesmu.").font(.footnote).foregroundStyle(.secondary)
                            Text("Guide, vokal referensi, dan pengiring diputar dengan transposisi yang sama; tempo tetap.").font(.footnote).foregroundStyle(.secondary)
                            if package.demo { Label("Demo sintetis • bukan hasil analisis lagu", systemImage: "info.circle").font(.footnote) }
                            else { Text("Hasil otomatis. Dengarkan dan periksa sebelum latihan.").font(.footnote).foregroundStyle(.secondary) }
                            PianoRollView(package: package, position: model.position, selected: model.selectedSegment)
                            LabeledContent("Posisi latihan", value: stamp(model.position))
                            if let active = package.segments.first(where: { model.position >= $0.start && model.position < $0.end }), !active.lyrics.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Lirik frasa \(active.id + 1)").font(.caption).foregroundStyle(.secondary)
                                    Text(active.lyrics).font(.headline)
                                    if active.lyricsEdited != true,
                                       let word = package.words?.first(where: { model.position >= $0.start && model.position < $0.end }) {
                                        Label(word.text, systemImage: "music.mic").foregroundStyle(.blue)
                                    }
                                }.accessibilityElement(children: .combine)
                            }
                            if package.lyricsStatus == "available" {
                                Text("Lirik otomatis dari vokal referensi. Periksa kata dan waktunya; hasil nyanyian bisa keliru.").font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(package.warnings ?? [], id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.bubble").font(.footnote)
                            }
                            if !package.demo {
                                Picker("Dengarkan", selection: $model.track) { Text("Referensi").tag("Referensi"); Text("Vokal").tag("Vokal"); Text("Pengiring").tag("Pengiring") }
                                .onChange(of: model.track) { _, _ in model.stop() }
                            }
                            Button("Putar seluruh pilihan") { model.stop(); model.selectedSegment = nil; model.play() }
                        }
                        Section("Frasa latihan • \(package.segments.count)") {
                            ForEach(package.segments) { segment in
                                DisclosureGroup {
                                    TextField("Periksa atau isi lirik frasa", text: Binding(get: { model.current?.package?.segments.first(where: { $0.id == segment.id })?.lyrics ?? "" }, set: { model.updateSegment(segment.id, lyrics: $0) }), axis: .vertical)
                                    Stepper("Mulai \(stamp(segment.start))", onIncrement: { model.updateSegment(segment.id, start: segment.start + 0.1) }, onDecrement: { model.updateSegment(segment.id, start: segment.start - 0.1) })
                                    Stepper("Selesai \(stamp(segment.end))", onIncrement: { model.updateSegment(segment.id, end: segment.end + 0.1) }, onDecrement: { model.updateSegment(segment.id, end: segment.end - 0.1) })
                                    Button { model.stop(); model.selectedSegment = segment.id; model.play() } label: { Label("Dengarkan frasa", systemImage: "play.fill") }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Frasa \(segment.id + 1) · \(stamp(segment.start))–\(stamp(segment.end))")
                                        Text(segment.lyrics.isEmpty ? "Lirik belum diisi" : segment.lyrics).font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                        Section {
                            Button { model.stop(); ready = true } label: { Text("Selesai meninjau").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent)
                            Text("Perubahan frasa dan lirik tersimpan otomatis.").font(.footnote).foregroundStyle(.secondary)
                            Button("Ubah potongan dan analisis ulang") { model.selectRange(start: song.start, end: song.end) }
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.blue)
                            Text("Dari lagu ke panduan nada.").font(.title2.bold())
                            Text("Pilih audio, tentukan bagian yang ingin dinyanyikan, lalu siapkan frasa latihan.").foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                        Button { importing = true } label: { Label("Pilih file audio", systemImage: "folder") }.disabled(model.busy)
                        Button("Coba demo 12 detik") { model.demo() }.disabled(model.busy)
                        Text("Demo memakai melodi sintetis dan bisa dicoba tanpa service.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.busy { Section { HStack { ProgressView(); Text(model.status) } } }
                }
                if !model.projects.isEmpty {
                    Section("Proyek tersimpan") {
                        ForEach(model.projects) { song in
                            Button { model.open(song) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.name).foregroundStyle(.primary)
                                    Text(song.package == nil ? "Menunggu analisis" : "Panduan tersimpan").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }.disabled(model.busy)
                        }
                    }
                }
            }
            .navigationTitle("2. Pilih lagu")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Label("Koneksi Mac", systemImage: "network") }.disabled(model.busy) }
                ToolbarItem(placement: .topBarTrailing) { Button { importing = true } label: { Label("Impor audio", systemImage: "plus") }.disabled(model.busy) }
            }
            .navigationDestination(isPresented: $ready) {
                List {
                    Section {
                        Label(model.current?.package?.demo == true ? "Demo panduan siap" : "Panduan siap", systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(.blue)
                        Text(model.current?.name ?? "")
                        Text("Audio, target nada, dan frasa latihan sudah tersimpan di perangkat.")
                    }
                    Section { Text("PoC ini berhenti di persiapan. Rekaman kamera, penilaian langsung, dan auto-loop belum dihubungkan.").foregroundStyle(.secondary)
                        Button("Kembali ke panduan") { ready = false }
                    }
                }.navigationTitle("Siap untuk latihan").navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            model.setVoiceRange(voice.voiceRange)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--pre-demo") { model.demo() }
            #endif
        }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("Service analisis di Mac") {
                        TextField("http://nama-mac.local:8765", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Token koneksi", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Hubungkan iPhone dan Mac ke Wi-Fi yang sama. Masukkan alamat dan token yang dicetak service. Izinkan akses Local Network saat diminta.").font(.footnote)
                    }
                    Section("Yang diproses") { Text("Vokal dipisahkan dari lagu asli di Mac. Target nada dan lirik otomatis dibaca dari vokal referensi, lalu bisa kamu periksa dan koreksi. Audio tetap disimpan pada Mac sampai folder pekerjaan dihapus.") }
                }.navigationTitle("Koneksi Mac").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { settings = false } } }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result { case .success(let url): model.importFile(url); case .failure(let error): model.error = error.localizedDescription }
        }
        .alert("Perlu diperiksa", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: phase) { _, value in if value != .active { model.stop() } }
        .onChange(of: voice.voiceRange?.low) { _, _ in model.setVoiceRange(voice.voiceRange) }
        .onChange(of: voice.voiceRange?.high) { _, _ in model.setVoiceRange(voice.voiceRange) }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in model.stop() }
    }
}
func stamp(_ value: Double) -> String { String(format: "%02d:%04.1f", Int(max(0, value)) / 60, max(0, value).truncatingRemainder(dividingBy: 60)) }
struct WaveformView: View {
    var values: [Float]; var start: Double; var end: Double
    var body: some View {
        Canvas { context, size in
            for (i, value) in values.enumerated() {
                let fraction = Double(i) / Double(max(1, values.count))
                let height = max(2, CGFloat(value) * size.height)
                let rect = CGRect(x: fraction * size.width, y: (size.height-height)/2, width: max(1, size.width / Double(max(1, values.count)) - 1), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(fraction >= start && fraction <= end ? .blue : .secondary.opacity(0.3)))
            }
        }
    }
}
struct PianoRollView: View {
    var package: PracticePackage; var position: Double; var selected: Int?
    var body: some View {
        let segment = package.segments.first { $0.id == selected }
        let start = segment?.start ?? 0, end = segment?.end ?? package.duration
        let notes = package.notes.filter { $0.end > start && $0.start < end }
        let low = (notes.map(\.pitch).min() ?? 60) - 1, high = (notes.map(\.pitch).max() ?? 72) + 1
        VStack(alignment: .leading, spacing: 6) {
            Text("\(note(low)) – \(note(high)) · waktu →").font(.caption).foregroundStyle(.secondary)
            Canvas { context, size in
                let rows = Double(high - low + 1), span = max(0.1, end-start)
                for pitch in low...high {
                    let y = Double(high-pitch) / rows * size.height
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.25)))
                }
                for n in notes {
                    let x = (max(start, n.start)-start) / span * size.width
                    let width = (min(end, n.end)-max(start, n.start)) / span * size.width
                    let y = Double(high-n.pitch) / rows * size.height
                    let rect = CGRect(x: x, y: y+1, width: max(2, width), height: max(3, size.height/rows-2))
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.blue))
                    if position >= n.start && position < n.end {
                        context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.primary), lineWidth: 2)
                    }
                }
                if position >= start && position <= end {
                    let x = (position-start)/span * size.width
                    context.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(.primary))
                }
            }.frame(height: 180).accessibilityLabel("Panduan \(notes.count) nada dari \(note(low+1)) hingga \(note(high-1)), mulai \(stamp(start)), selesai \(stamp(end))")
            HStack { Text(stamp(start)); Spacer(); Text(stamp(end)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
