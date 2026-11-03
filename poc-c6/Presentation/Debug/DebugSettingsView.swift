//
//  DebugSettingsView.swift
//  poc-c6
//
//  Tune PoCConfiguration on the device without rebuilding (PRD §8, ZV-15). Owner: Zildjian Vito.
//

import SwiftUI

struct DebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: PoCConfiguration
    @State private var allowsSpeakerRecording = DebugOptions.allowsSpeakerRecording
    @State private var usesHTDemucs = !DebugOptions.skipsHTDemucs
    private let onSave: (PoCConfiguration) -> Void
    private let onRetestVocalRange: () -> Void
    private let onMeasureSync: () -> Void

    init(configuration: PoCConfiguration,
         onSave: @escaping (PoCConfiguration) -> Void,
         onRetestVocalRange: @escaping () -> Void,
         onMeasureSync: @escaping () -> Void = {}) {
        _configuration = State(initialValue: configuration)
        self.onSave = onSave
        self.onRetestVocalRange = onRetestVocalRange
        self.onMeasureSync = onMeasureSync
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Evaluation") {
                    row("Pass threshold", $configuration.passThreshold, in: 0.5...1, step: 0.05, format: .percent)
                    row("Hit tolerance", $configuration.hitToleranceCents, in: 10...100, step: 5, unit: " cents")
                    row("Noise gate", $configuration.noiseGateDBFS, in: -70 ... -20, step: 5, unit: " dBFS")
                    row("Attack ignored", $configuration.attackIgnore, in: 0...0.3, step: 0.02, unit: " s")
                    row("Timing tolerance", $configuration.timingTolerance, in: 0...0.3, step: 0.02, unit: " s")
                    row("Missed note below", $configuration.missedNoteThreshold, in: 0.1...0.9, step: 0.05, format: .percent)
                }
                Section {
                    row("Split on gaps over", $configuration.segmentGap, in: 0.3...2, step: 0.1, unit: " s")
                    row("Min segment", $configuration.minSegment, in: 1...6, step: 0.5, unit: " s")
                    row("Max segment", $configuration.maxSegment, in: 4...15, step: 0.5, unit: " s")
                } header: {
                    Text("Segmentation")
                } footer: {
                    Text("Applies to the next song you prepare.")
                }
                Section("Session") {
                    row("Pre-roll", $configuration.preRoll, in: 0...4, step: 0.5, unit: " s")
                    Stepper(value: $configuration.countdownSeconds, in: 0...5) {
                        LabeledContent("Countdown", value: "\(configuration.countdownSeconds) s")
                    }
                    row("Latency calibration", $configuration.manualLatencyCalibration, in: -0.3...0.3, step: 0.01, unit: " s")
                    row("Evaluation tail", $configuration.evaluationTail, in: 0...0.5, step: 0.05, unit: " s")
                    row("Max session", $configuration.maxSessionDuration, in: 60...1800, step: 60, unit: " s")
                }
                Section("Comping") {
                    row("Crossfade", $configuration.crossfade, in: 0.01...0.1, step: 0.01, unit: " s")
                    row("Partial fade-out", $configuration.partialExportFadeOut, in: 0...3, step: 0.5, unit: " s")
                    row("Vocal gain", $configuration.vocalGain, in: 0...2, step: 0.1)
                    row("Instrumental gain", $configuration.instrumentalGain, in: 0...2, step: 0.1)
                }
                Section("Feature flags") {
                    Toggle("CoreML stem separation (Track B)", isOn: $configuration.useCoreMLSeparation)
                }
                Section {
                    Toggle("Separate with htdemucs", isOn: $usesHTDemucs)
                        .disabled(!configuration.useCoreMLSeparation)
                } footer: {
                    Text("Off uses Open-Unmix, to compare the two. Each method reuses its stems for the same song and trim, so pick a new trim to measure again. Debug builds only.")
                }
                Section {
                    Toggle("Allow recording without earphones", isOn: $allowsSpeakerRecording)
                } header: {
                    Text("Device testing")
                } footer: {
                    Text("Plays the song through the loudspeaker. The song leaks into the microphone, so scores and the final mix are not representative. Debug builds only.")
                }
                Section {
                    Button("Measure Audio Sync…") {
                        onMeasureSync()
                        dismiss()
                    }
                    Button("Re-test Vocal Range") {
                        onRetestVocalRange()
                        dismiss()
                    }
                    Button("Reset to Defaults", role: .destructive) {
                        configuration = .default
                    }
                    .disabled(configuration == .default)
                }
            }
            .navigationTitle("Debug Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        DebugOptions.allowsSpeakerRecording = allowsSpeakerRecording
                        DebugOptions.skipsHTDemucs = !usesHTDemucs
                        onSave(configuration)
                        dismiss()
                    }
                }
            }
        }
    }

    private func row<Value: BinaryFloatingPoint & Strideable>(
        _ title: String, _ value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride,
        unit: String = "", format: ValueFormat = .number
    ) -> some View where Value.Stride: BinaryFloatingPoint {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: format.text(Double(value.wrappedValue)) + unit)
        }
    }

    enum ValueFormat {
        case number
        case percent

        func text(_ value: Double) -> String {
            switch self {
            case .number: value.formatted(.number.precision(.fractionLength(0...2)))
            case .percent: value.formatted(.percent.precision(.fractionLength(0)))
            }
        }
    }
}

#Preview {
    DebugSettingsView(configuration: .default, onSave: { _ in }, onRetestVocalRange: {})
}
