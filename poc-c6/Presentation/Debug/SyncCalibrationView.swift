//
//  SyncCalibrationView.swift
//  poc-c6
//
//  Debug screen for the click test: measure the sync error and apply it as latency calibration.
//

import SwiftUI

struct SyncCalibrationView: View {
    @State private var viewModel: SyncCalibrationViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SyncCalibrationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                content
                Spacer()
                actions
            }
            .padding()
            .navigationTitle("Audio Sync Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isMeasuring)
    }

    private var isMeasuring: Bool {
        if case .measuring = viewModel.status { true } else { false }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .idle:
            VStack(alignment: .leading, spacing: 12) {
                Text("Plays 8 clicks and listens for them with the microphone, the same way a recording session does.")
                Label("Earphones: hold one earbud against the microphone at the bottom of the iPhone.", systemImage: "earbuds")
                Label("Speaker: turn on \"Allow recording without earphones\" first, put the volume up and keep quiet.", systemImage: "speaker.wave.3")
                Text("Current calibration: \(milliseconds(viewModel.currentCalibration))")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        case .measuring(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                Text("Listening… keep quiet")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
        case .finished(let result):
            VStack(spacing: 12) {
                Image(systemName: result.isReliable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(result.isReliable ? .green : .orange)
                Text(summary(result))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("\(result.detectedClicks) of \(result.expectedClicks) clicks heard · spread \(milliseconds(result.spread))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let suggested = viewModel.suggestedCalibration {
                    Text("New calibration: \(milliseconds(suggested)) (was \(milliseconds(viewModel.currentCalibration)))")
                        .font(.callout)
                } else {
                    Text("Not reliable enough to apply. Make it louder or quieter around you and try again.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 24)
        case .failed(let message):
            ContentUnavailableView("Couldn't run the test", systemImage: "waveform.slash", description: Text(message))
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch viewModel.status {
        case .idle, .failed:
            Button("Start Test") { Task { await viewModel.measure() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .measuring:
            EmptyView()
        case .finished:
            VStack(spacing: 12) {
                if viewModel.suggestedCalibration != nil {
                    Button("Apply") {
                        viewModel.apply()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Button("Test Again") { Task { await viewModel.measure() } }
            }
        }
    }

    private func summary(_ result: MeasureSyncUseCase.Result) -> String {
        guard result.detectedClicks > 0 else { return "No clicks heard" }
        let error = result.medianError
        if abs(error) < 0.01 { return "In sync (\(milliseconds(error)))" }
        return error > 0 ? "Sound is heard \(milliseconds(error)) later than expected"
                         : "Sound is heard \(milliseconds(-error)) earlier than expected"
    }

    private func milliseconds(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}
