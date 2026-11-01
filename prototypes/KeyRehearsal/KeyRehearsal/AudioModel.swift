import SwiftUI
import AVFoundation

struct PitchRange: Codable {
    var low: Int
    var high: Int
    var label: String { "\(note(low)) – \(note(high))" }
}
func note(_ midi: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
}
struct Take: Identifiable, Codable {
    var id = UUID()
    var name: String
    var filename: String
    var range: PitchRange?
    var comfort: String?
    var key: Int = 0
    var stability: Double?
}

@MainActor final class AudioModel: ObservableObject {
    @Published var takes: [Take] = []
    @Published var voiceRange: PitchRange?
    @Published var recording = false
    @Published var requestingPermission = false
    @Published var busy = false
    @Published var playing = false
    @Published var message: String?
    @Published var elapsed: TimeInterval = 0
    @Published var selectedKey = 0
    private var recorder: AVAudioRecorder?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let shift = AVAudioUnitTimePitch()
    private var timer: Timer?
    private var recordingURL: URL?
    private var rangeTest = false
    private var recordingRequest = UUID()
    private var generation = UUID()
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    init() {
        if let data = UserDefaults.standard.data(forKey: "takes"), let saved = try? JSONDecoder().decode([Take].self, from: data) { takes = saved }
        if let data = UserDefaults.standard.data(forKey: "range") { voiceRange = try? JSONDecoder().decode(PitchRange.self, from: data) }
        engine.attach(player); engine.attach(shift)
    }
    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(takes), forKey: "takes")
        UserDefaults.standard.set(try? JSONEncoder().encode(voiceRange), forKey: "range")
    }
    func startRecording(test: Bool) async {
        guard !busy && !recording && !requestingPermission else { return }
        requestingPermission = true
        let request = UUID(); recordingRequest = request
        defer { requestingPermission = false }
        stopPlayback()
        let granted = await AVAudioApplication.requestRecordPermission()
        guard request == recordingRequest else { return }
        guard granted else { message = "Izinkan mikrofon di Settings → Privacy & Security → Microphone."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = directory.appendingPathComponent(UUID().uuidString + ".m4a")
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder?.record() == true else { throw CocoaError(.fileWriteUnknown) }
            recordingURL = url; rangeTest = test; elapsed = 0; recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 } }
        } catch { message = error.localizedDescription }
    }
    func cancelPendingRecording() { recordingRequest = UUID() }
    func finishRecording() {
        recorder?.stop(); timer?.invalidate(); timer = nil; recording = false
        guard let url = recordingURL else { return }
        if rangeTest { analyze(url: url, rangeOnly: true) }
        else { let take = Take(name: "Latihan \(takes.count + 1)", filename: url.lastPathComponent, key: selectedKey); takes.insert(take, at: 0); save(); analyze(url: url, id: take.id) }
    }
    func importAudio(_ url: URL) {
        guard !recording && !busy else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let target = directory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: target)
            _ = try AVAudioFile(forReading: target)
            let take = Take(name: url.deletingPathExtension().lastPathComponent, filename: target.lastPathComponent)
            takes.insert(take, at: 0); save(); analyze(url: target, id: take.id)
        } catch { message = "Audio tidak dapat dibaca. Coba file M4A, WAV, atau MP3. \(error.localizedDescription)" }
    }
    func analyze(url: URL, id: UUID? = nil, rangeOnly: Bool = false) {
        busy = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try PitchAnalyzer.read(url) }.value
                if rangeOnly { voiceRange = result.0 }
                else if let index = takes.firstIndex(where: { $0.id == id }) { takes[index].range = result.0; takes[index].stability = result.1 }
                save()
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    func suggestion(for range: PitchRange) -> Int? {
        guard let voiceRange else { return nil }
        return (-12...12).min { a, b in
            func cost(_ k: Int) -> Int { max(0, voiceRange.low - range.low - k) * 3 + max(0, range.high + k - voiceRange.high) * 3 + abs(k) }
            return cost(a) < cost(b)
        }
    }
    func play(_ take: Take, semitones: Int) {
        guard !recording else { return }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let file = try AVAudioFile(forReading: directory.appendingPathComponent(take.filename))
            engine.disconnectNodeOutput(player); engine.disconnectNodeOutput(shift)
            engine.connect(player, to: shift, format: file.processingFormat)
            engine.connect(shift, to: engine.mainMixerNode, format: file.processingFormat)
            shift.pitch = Float(semitones * 100); shift.rate = 1
            let token = UUID(); generation = token
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in Task { @MainActor in if self?.generation == token { self?.playing = false } } }
            try engine.start(); player.play(); playing = true
        } catch { message = error.localizedDescription }
    }
    func stopPlayback() { generation = UUID(); player.stop(); engine.stop(); playing = false }
    func comfort(_ value: String, id: UUID) { if let i = takes.firstIndex(where: { $0.id == id }) { takes[i].comfort = value; save() } }
    func saveChoice(_ key: Int, take: Take) { UserDefaults.standard.set(take.id.uuidString, forKey: "chosenTakeID"); UserDefaults.standard.set(take.name, forKey: "chosenSong"); UserDefaults.standard.set(key, forKey: "chosenKey"); message = "Key \(key > 0 ? "+" : "")\(key) semitone disimpan untuk rehearsal." }
}

enum PitchAnalyzer {
    static func read(_ url: URL) throws -> (PitchRange, Double) {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw CocoaError(.fileReadUnknown) }
        var pitches: [Double] = []
        // Streaming analysis bounds memory even for long imported audio.
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: 8192)
            guard let channels = buffer.floatChannelData else { continue }
            let stride = max(1, Int(rate / 8000))
            let count = Int(buffer.frameLength) / stride
            if count < 512 { continue }
            let samples = (0..<count).map { i -> Float in
                var sum: Float = 0
                for c in 0..<Int(buffer.format.channelCount) { sum += channels[c][i * stride] }
                return sum / Float(buffer.format.channelCount)
            }
            let sr = rate / Double(stride)
            for start in Swift.stride(from: 0, through: count - 512, by: 512) {
                let x = Array(samples[start..<start + 512])
                let energy = x.reduce(0) { $0 + $1 * $1 }
                if energy / 512 < 0.00008 { continue }
                let minLag = max(2, Int(sr / 1000)), maxLag = min(256, Int(sr / 70))
                var scores = [Double](repeating: 0, count: maxLag + 1)
                for lag in minLag...maxLag {
                    var dot: Double = 0, e1: Double = 0, e2: Double = 0
                    for i in 0..<(512 - lag) { let a = Double(x[i]), b = Double(x[i + lag]); dot += a*b; e1 += a*a; e2 += b*b }
                    scores[lag] = dot / max(1e-12, sqrt(e1 * e2))
                }
                // First strong local maximum reduces octave-down errors.
                let best = (minLag...maxLag).max(by: { scores[$0] < scores[$1] })!
                guard scores[best] > 0.80 else { continue }
                let threshold = max(0.80, scores[best] * 0.94)
                var lag = best
                if maxLag > minLag + 2 {
                    for l in (minLag + 1)..<maxLag where scores[l] >= threshold && scores[l] > scores[l-1] && scores[l] >= scores[l+1] { lag = l; break }
                }
                pitches.append(69 + 12 * log2((sr / Double(lag)) / 440))
            }
        }
        guard pitches.count >= 8 else { throw NSError(domain: "Pitch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nada belum cukup jelas. Rekam minimal 5 detik di tempat tenang, tanpa musik pengiring."]) }
        let sorted = pitches.sorted()
        let low = Int(sorted[Int(Double(sorted.count - 1) * 0.05)].rounded())
        let high = Int(sorted[Int(Double(sorted.count - 1) * 0.95)].rounded())
        let deviations = pitches.map { abs($0 - $0.rounded()) * 100 }
        return (PitchRange(low: low, high: high), deviations.reduce(0,+) / Double(deviations.count))
    }
}
