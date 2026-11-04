//
//  VocalRangeViewModel.swift
//  poc-c6
//

import CoreMedia
import Foundation
import Observation

@Observable
final class VocalRangeViewModel {
    enum Prompt: Int, Equatable, CaseIterable {
        case speaking, lowest, highest
    }

    enum Status: Equatable {
        case idle
        case listening
        case captured(Float)
        case finished(VocalRange)
        case failed(UserFacingError)
    }

    private(set) var prompt: Prompt = .speaking
    private(set) var status: Status = .idle
    private(set) var liveMIDI: Float?
    private(set) var holdProgress: Double = 0
    private(set) var baselineMIDI: Float?
    private(set) var lowestMIDI: Float?
    private(set) var highestMIDI: Float?
    private(set) var microphoneName: String?

    @ObservationIgnored private let source: any LivePitchSource
    @ObservationIgnored private let repository: any VocalRangeRepository
    @ObservationIgnored private let configuration: PoCConfiguration
    @ObservationIgnored private let onSaved: () -> Void
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(source: any LivePitchSource, repository: any VocalRangeRepository,
         configuration: PoCConfiguration, onSaved: @escaping () -> Void) {
        self.source = source
        self.repository = repository
        self.configuration = configuration
        self.onSaved = onSaved
    }

    var title: String {
        switch prompt {
        case .speaking: "Read aloud in your normal speaking voice"
        case .lowest: "Hum your lowest comfortable note"
        case .highest: "Sing your highest comfortable note"
        }
    }

    var instructions: String {
        switch prompt {
        case .speaking:
            "The sky looks so beautiful this morning, with soft clouds floating across the blue sky. A gentle breeze comes through the trees, and the air feels cool and refreshing."
        case .lowest:
            "Start near your speaking note and gently hum downward. Hold a comfortable low note for about 1 second."
        case .highest:
            "Try a gentle ‘woo-hoo’, then hold a comfortable high note for about 1 second. Don't shout or strain."
        }
    }

    var liveNoteName: String? { liveMIDI.map { PitchMath.noteName(midi: Int($0.rounded())) } }
    var nextTitle: String {
        switch prompt {
        case .speaking: "Next: Lowest Note"
        case .lowest: "Next: Highest Note"
        case .highest: "Save and Continue"
        }
    }

    func listen() {
        stopListening()
        let token = generation
        status = .listening
        microphoneName = nil
        holdProgress = 0
        liveMIDI = nil
        listening = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await source.start()
                microphoneName = (source as? any MicrophoneInputProviding)?.microphoneName
                var display = StabilizePitchDisplayUseCase(configuration: configuration)
                var detector = DetectVocalRangeUseCase(configuration: configuration)
                var speech: [Float] = []
                var start: TimeInterval?
                for await sample in samples {
                    guard !Task.isCancelled, generation == token else { return }
                    if prompt == .speaking {
                        let time = sample.captureTime.seconds
                        guard time.isFinite else { continue }
                        if start == nil { start = time }
                        holdProgress = min(1, max(0, time - (start ?? time)) / configuration.speakingSampleDuration)
                        var spokenMIDI: Float?
                        if let frequency = sample.frequency, frequency.isFinite, frequency > 0,
                           sample.rmsDecibels >= configuration.noiseGateDBFS {
                            let midi = 69 + 12 * log2(frequency / 440)
                            spokenMIDI = midi
                            speech.append(midi)
                        }
                        liveMIDI = display.execute(midi: spokenMIDI, time: time)
                        if holdProgress >= 1 {
                            guard Double(speech.count) * configuration.pitchHop >= configuration.minimumSpeakingVoicedDuration else {
                                status = .failed(.vocalRangeCaptureFailed)
                                break
                            }
                            let sorted = speech.sorted(), middle = speech.count / 2
                            let median = speech.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
                            captured(median)
                            break
                        }
                    } else {
                        let note = detector.ingest(sample)
                        liveMIDI = display.execute(midi: detector.latestMIDI, time: sample.captureTime.seconds)
                        holdProgress = min(1, detector.stableDuration / DetectVocalRangeUseCase.requiredDuration)
                        if let note { captured(note); break }
                    }
                }
                guard generation == token, !Task.isCancelled else { return }
                if case .listening = status {
                    let input = source as? any MicrophoneInputProviding
                    status = .failed(input?.isHeadsetMicrophoneActive == false ? .headsetMicrophoneRequired : .vocalRangeCaptureFailed)
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                status = .failed((error as? any UserFacingConvertible)?.userFacingError ?? .vocalRangeCaptureFailed)
            }
            if generation == token { source.stop() }
        }
    }

    func next() {
        guard case .captured = status,
              let next = Prompt(rawValue: prompt.rawValue + 1) else { return }
        prompt = next
        status = .idle
        holdProgress = 0
        liveMIDI = nil
    }

    func save() {
        guard case .finished(let range) = status else { return }
        repository.save(range)
        onSaved()
    }

    func restart() {
        stopListening()
        prompt = .speaking
        baselineMIDI = nil
        lowestMIDI = nil
        highestMIDI = nil
        microphoneName = nil
        status = .idle
    }

    func stopListening() {
        generation = UUID()
        listening?.cancel()
        listening = nil
        source.stop()
    }

    private func captured(_ note: Float) {
        holdProgress = 1
        switch prompt {
        case .speaking:
            baselineMIDI = note
        case .lowest:
            lowestMIDI = note
        case .highest:
            guard let low = lowestMIDI, note - low >= configuration.minimumVocalRangeSpan else {
                status = .failed(.vocalRangeTooNarrow)
                return
            }
            highestMIDI = note
            status = .finished(VocalRange(lowestMIDI: low, highestMIDI: note))
            return
        }
        status = .captured(note)
    }
}
