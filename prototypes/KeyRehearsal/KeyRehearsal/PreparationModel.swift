import SwiftUI
import AVFoundation

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
    var guideShift: Int?
    var manualShift: Bool?
}
struct AnalysisJob: Decodable {
    var id: String
    var status: String
    var message: String
    var result: PracticePackage?
}

@MainActor final class PreparationModel: ObservableObject {
    @Published var projects: [PreparedSong] = []
    @Published var current: PreparedSong?
    @Published var waveform: [Float] = []
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var position = 0.0
    @Published var playing = false
    @Published var selectedSegment: Int?
    @Published var track = "Referensi"
    private let playbackEngine = AVAudioEngine()
    private let playbackNode = AVAudioPlayerNode()
    private let pitchShift = AVAudioUnitTimePitch()
    private var playbackGeneration = UUID()
    @Published var voiceRange: PitchRange?
    var guideShift: Int { current?.guideShift ?? 0 }
    var adjustedPackage: PracticePackage? {
        guard var package = current?.package else { return nil }
        package.notes = package.notes.map { note in
            var adjusted = note; adjusted.pitch += guideShift; return adjusted
        }
        return package
    }
    var fitsVoice: Bool {
        guard let range = voiceRange, let package = adjustedPackage else { return false }
        return package.notes.allSatisfy { $0.pitch >= range.low && $0.pitch <= range.high }
    }
    func setVoiceRange(_ range: PitchRange?) { stop(); voiceRange = range; adaptGuide() }
    func changeShift(_ value: Int) {
        guard !busy else { return }
        stop(); current?.guideShift = min(12, max(-12, value)); current?.manualShift = true
        do { try save() } catch { self.error = error.localizedDescription }
    }
    func useAutomaticShift() { stop(); current?.manualShift = false; adaptGuide() }
    private func adaptGuide() {
        guard current?.manualShift != true else { return }
        guard let range = voiceRange, let notes = current?.package?.notes, !notes.isEmpty else { return }
        current?.guideShift = Self.chooseShift(pitches: notes.map(\.pitch), range: range)
        do { try save() } catch { self.error = error.localizedDescription }
    }
    nonisolated static func chooseShift(pitches: [Int], range: PitchRange) -> Int {
        guard !pitches.isEmpty else { return 0 }
        func cost(_ shift: Int) -> (Int, Int, Int) {
            let distances = pitches.map { max(0, range.low - ($0 + shift), ($0 + shift) - range.high) }
            return (distances.filter { $0 > 0 }.count, distances.reduce(0,+), abs(shift))
        }
        return (-12...12).min { a, b in
            let ca = cost(a), cb = cost(b)
            return ca == cb ? a < b : ca < cb
        } ?? 0
    }
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var playbackEnd = 0.0
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Preparation", isDirectory: true)
    init() {
        playbackEngine.attach(playbackNode); playbackEngine.attach(pitchShift)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let index = directory.appendingPathComponent("projects.json")
            if FileManager.default.fileExists(atPath: index.path) {
                projects = try JSONDecoder().decode([PreparedSong].self, from: Data(contentsOf: index))
            }
        } catch { self.error = "Proyek tersimpan tidak dapat dibaca: \(error.localizedDescription)" }
    }
    func save() throws {
        guard let current else { return }
        var next = projects
        if let i = next.firstIndex(where: { $0.id == current.id }) { next[i] = current }
        else { next.insert(current, at: 0) }
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("projects.json"), options: .atomic)
        projects = next
    }
    func open(_ song: PreparedSong) {
        stop(); current = song; adaptGuide(); selectedSegment = nil; track = "Referensi"; waveform = []
        loadWaveform(directory.appendingPathComponent(song.sourceFile))
    }
    func importFile(_ url: URL) {
        guard !busy else { return }
        stop(); busy = true; status = "Membaca audio…"
        work = Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; busy = false }
            var target: URL?
            do {
                let file = directory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                target = file
                try FileManager.default.copyItem(at: url, to: file)
                let audio = try AVAudioPlayer(contentsOf: file)
                guard audio.duration >= 1, audio.duration <= 1800 else { throw failure("Pilih audio berdurasi 1 detik hingga 30 menit.") }
                current = PreparedSong(id: UUID(), name: url.deletingPathExtension().lastPathComponent, sourceFile: file.lastPathComponent, duration: audio.duration, start: 0, end: min(30, audio.duration))
                selectedSegment = nil; track = "Referensi"
                try save()
                waveform = try await Task.detached { try Self.readWaveform(file) }.value
            } catch {
                self.error = "Impor gagal: \(error.localizedDescription)"
                if current?.sourceFile != target?.lastPathComponent, let target { try? FileManager.default.removeItem(at: target) }
            }
        }
    }
    private func loadWaveform(_ url: URL) {
        Task { do { let values = try await Task.detached { try Self.readWaveform(url) }.value
            if current?.sourceFile == url.lastPathComponent { waveform = values }
        } catch { self.error = "Waveform tidak dapat dibaca." } }
    }
    nonisolated static func readWaveform(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return [] }
        var peaks = [Float](repeating: 0, count: 180)
        while file.framePosition < file.length {
            let offset = file.framePosition
            try file.read(into: buffer, frameCount: 8192)
            guard let channels = buffer.floatChannelData else { continue }
            for i in Swift.stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                let bin = min(179, Int((offset + Int64(i)) * 180 / max(1, file.length)))
                for c in 0..<Int(buffer.format.channelCount) { peaks[bin] = max(peaks[bin], abs(channels[c][i])) }
            }
        }
        let peak = max(0.001, peaks.max() ?? 1)
        return peaks.map { $0 / peak }
    }
    func selectRange(start: Double, end: Double) {
        stop(); current?.start = start; current?.end = end
        current?.package = nil; current?.guideShift = nil; current?.manualShift = nil; current?.backingFile = nil; current?.vocalFile = nil; selectedSegment = nil
        do { try save() } catch { self.error = error.localizedDescription }
    }
    func stop() {
        playbackGeneration = UUID(); playbackNode.stop(); playbackEngine.stop()
        timer?.invalidate(); timer = nil; playing = false
    }
    func play() {
        guard !busy, let song = current else { return }
        if playing { stop(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let segment = song.package?.segments.first { $0.id == selectedSegment }
            let isSource = track == "Referensi" || song.package?.demo == true
            let filename = isSource ? song.sourceFile : (track == "Vokal" ? song.vocalFile : song.backingFile)
            guard let filename else { throw failure("Track belum tersedia. Jalankan analisis terlebih dahulu.") }
            let offset = isSource ? song.start : 0
            let start = segment?.start ?? 0
            let end = segment?.end ?? (song.end - song.start)
            let file = try AVAudioFile(forReading: directory.appendingPathComponent(filename))
            let rate = file.processingFormat.sampleRate
            let firstFrame = AVAudioFramePosition((offset + start) * rate)
            let endFrame = min(file.length, AVAudioFramePosition((offset + end) * rate))
            guard endFrame > firstFrame else { throw failure("Potongan audio tidak tersedia.") }
            playbackEngine.disconnectNodeOutput(playbackNode)
            playbackEngine.disconnectNodeOutput(pitchShift)
            playbackEngine.connect(playbackNode, to: pitchShift, format: file.processingFormat)
            playbackEngine.connect(pitchShift, to: playbackEngine.mainMixerNode, format: file.processingFormat)
            pitchShift.pitch = Float(guideShift * 100); pitchShift.rate = 1; pitchShift.bypass = guideShift == 0
            let generation = UUID(); playbackGeneration = generation
            playbackNode.scheduleSegment(file, startingFrame: firstFrame, frameCount: AVAudioFrameCount(endFrame-firstFrame), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.position = end; self.stop()
                }
            }
            position = start
            try playbackEngine.start(); playbackNode.play(); playing = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playbackGeneration == generation, self.playing,
                          let render = self.playbackNode.lastRenderTime,
                          let time = self.playbackNode.playerTime(forNodeTime: render) else { return }
                    self.position = min(end, start + Double(time.sampleTime) / time.sampleRate)
                }
            }
        } catch { stop(); self.error = error.localizedDescription }
    }
    func cancel() { work?.cancel(); stop() }
    func analyze(endpoint: String, token: String) {
        guard !busy, let song = current else { return }
        guard let base = URL(string: endpoint), ["http", "https"].contains(base.scheme ?? ""), base.host != nil, !token.isEmpty else {
            error = "Isi alamat service dan token koneksi terlebih dahulu."; return
        }
        stop(); busy = true; status = "Mengirim audio ke Mac…"
        work = Task {
            defer { busy = false }
            do {
                var components = URLComponents(url: base.appendingPathComponent("jobs"), resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "start", value: String(song.start)), URLQueryItem(name: "end", value: String(song.end))]
                var request = URLRequest(url: components.url!); request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 180
                let (data, response) = try await URLSession.shared.upload(for: request, fromFile: directory.appendingPathComponent(song.sourceFile))
                try check(response, data: data)
                var job = try JSONDecoder().decode(AnalysisJob.self, from: data)
                let deadline = Date().addingTimeInterval(1800)
                while job.status != "complete" {
                    try Task.checkCancellation()
                    if job.status == "failed" { throw failure(job.message) }
                    guard Date() < deadline else { throw failure("Analisis terlalu lama. Cek service di Mac lalu coba lagi.") }
                    status = job.message
                    try await Task.sleep(for: .seconds(2))
                    var poll = URLRequest(url: base.appendingPathComponent("jobs/\(job.id)"))
                    poll.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (body, reply) = try await URLSession.shared.data(for: poll)
                    try check(reply, data: body)
                    job = try JSONDecoder().decode(AnalysisJob.self, from: body)
                }
                guard let package = job.result, !package.notes.isEmpty, !package.segments.isEmpty else { throw failure("Tidak ada nada yang cukup jelas. Coba vokal solo.") }
                status = "Menyimpan paket latihan…"
                var files: [String] = []
                for track in ["backing", "vocals"] {
                    try Task.checkCancellation()
                    var download = URLRequest(url: base.appendingPathComponent("jobs/\(job.id)/\(track)"))
                    download.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (temp, reply) = try await URLSession.shared.download(for: download)
                    guard (reply as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Unduhan track gagal. Coba analisis ulang.") }
                    let name = "\(UUID().uuidString)-\(track).wav"
                    try FileManager.default.moveItem(at: temp, to: directory.appendingPathComponent(name)); files.append(name)
                }
                try Task.checkCancellation()
                current?.package = package; current?.backingFile = files[0]; current?.vocalFile = files[1]; adaptGuide()
                selectedSegment = nil; track = "Referensi"; position = 0
                try save()
            } catch is CancellationError { status = "Dibatalkan. Pekerjaan di Mac mungkin masih berjalan." }
            catch { self.error = "Analisis gagal: \(error.localizedDescription)" }
        }
    }
    func updateSegment(_ id: Int, start: Double? = nil, end: Double? = nil, lyrics: String? = nil) {
        guard var package = current?.package, let i = package.segments.firstIndex(where: { $0.id == id }) else { return }
        stop()
        if let start { package.segments[i].start = min(package.segments[i].end - 0.1, max(i == 0 ? 0 : package.segments[i-1].end, start)) }
        if let end { package.segments[i].end = max(package.segments[i].start + 0.1, min(i+1 == package.segments.count ? package.duration : package.segments[i+1].start, end)) }
        if let lyrics {
            package.segments[i].lyrics = lyrics
            package.segments[i].lyricsEdited = true
        } else if package.segments[i].lyricsEdited != true, let words = package.words {
            let segment = package.segments[i]
            package.segments[i].lyrics = words.filter {
                let midpoint = ($0.start + $0.end) / 2
                return midpoint >= segment.start && midpoint < segment.end
            }.map(\.text).joined(separator: " ")
        }
        current?.package = package
        do { try save() } catch { self.error = error.localizedDescription }
    }
    func demo() {
        guard !busy else { return }
        do {
            stop()
            let name = "demo.wav", url = directory.appendingPathComponent(name)
            let rate = 22050.0, duration = 12.0
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(rate * duration))!
            buffer.frameLength = buffer.frameCapacity
            buffer.floatChannelData![0].update(repeating: 0, count: Int(buffer.frameLength))
            let pitches = [60, 62, 64, 67, 64, 62, 60, 64]
            var notes: [GuideNote] = []
            for (i, pitch) in pitches.enumerated() {
                let start = Double(i) * 1.5 + 0.15, end = Double(i) * 1.5 + 1.2
                notes.append(GuideNote(id: i, pitch: pitch, start: start, end: end))
                let frequency = 440 * pow(2, Double(pitch - 69) / 12)
                for frame in Int(start * rate)..<Int(end * rate) {
                    let t = Double(frame) / rate
                    let envelope = min(1, min((t-start)/0.02, (end-t)/0.04))
                    buffer.floatChannelData![0][frame] = Float(0.2 * envelope * sin(2 * .pi * frequency * t))
                }
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer)
            let package = PracticePackage(duration: duration, notes: notes, segments: [GuideSegment(id: 0, start: 0, end: 6, lyrics: ""), GuideSegment(id: 1, start: 6, end: 12, lyrics: "")], sourceOffset: 0, demo: true)
            current = PreparedSong(id: UUID(), name: "Demo • Melodi sintetis", sourceFile: name, duration: duration, start: 0, end: duration, package: package)
            selectedSegment = nil; track = "Referensi"; position = 0; adaptGuide(); try save(); loadWaveform(url)
        } catch { self.error = error.localizedDescription }
    }
    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw failure("Service menolak permintaan. Periksa token, alamat, dan batas audio. \(String(data: data, encoding: .utf8)?.prefix(180) ?? "")")
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "Preparation", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
