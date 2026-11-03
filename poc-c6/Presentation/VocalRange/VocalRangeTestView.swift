//
//  VocalRangeTestView.swift
//  poc-c6
//
//  Speaking baseline, comfortable limits and repeated sung confirmation.
//

import SwiftUI

struct VocalRangeTestView: View {
    @State private var viewModel: VocalRangeViewModel

    init(viewModel: VocalRangeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                Spacer()
                noteReadout
                Spacer()
                actions
            }
            .padding()
        }
        .onDisappear { viewModel.stopListening() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Vocal Range Test")
                .font(.largeTitle.bold())
            Text("Step \(viewModel.prompt.rawValue + 1) of \(VocalRangeViewModel.Prompt.allCases.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let baseline = viewModel.baselineMIDI, viewModel.prompt != .speaking {
                Text("Speaking note: \(name(baseline)) · starting point only")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(viewModel.instructions)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private var noteReadout: some View {
        switch viewModel.status {
        case .idle:
            VStack(spacing: 12) {
                Image(systemName: viewModel.prompt == .lowest ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(viewModel.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }
        case .listening:
            VStack(spacing: 16) {
                Text(viewModel.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(viewModel.liveNoteName ?? "—")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                ProgressView(value: viewModel.holdProgress) {
                    Text(viewModel.prompt == .speaking ? "Keep reading naturally…" : (viewModel.liveNoteName == nil ? "Listening…" : "Hold it…"))
                        .font(.footnote)
                }
                .frame(maxWidth: 240)
            }
        case .captured(let note):
            result(title: viewModel.prompt == .speaking ? "Speaking note" : "Note captured", note: note)
        case .finished(let range):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Your range")
                    .font(.headline)
                Text("\(name(range.lowestMIDI)) – \(name(range.highestMIDI))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
            }
        case .failed(let error):
            ErrorStateView(error: error)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            switch viewModel.status {
            case .idle:
                Button("Start") { viewModel.listen() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .listening:
                Button("Cancel", role: .cancel) {
                    viewModel.stopListening()
                    viewModel.restart()
                }
            case .captured:
                Button(viewModel.nextTitle) { viewModel.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Retry") { viewModel.listen() }
            case .finished:
                Button("Save and Continue") { viewModel.save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Start Over") { viewModel.restart() }
            case .failed:
                Button("Retry") { viewModel.listen() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Start Over") { viewModel.restart() }
            }
        }
    }

    private func result(title: String, note: Float) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(title)
                .font(.headline)
            Text(name(note))
                .font(.system(size: 64, weight: .bold, design: .rounded))
        }
    }

    private func name(_ midi: Float) -> String {
        PitchMath.noteName(midi: Int(midi.rounded()))
    }
}

#Preview {
    VocalRangeTestView(viewModel: VocalRangeViewModel(
        source: FakeLivePitchSource(notes: [57, 48, 48, 67, 67]), repository: FakeVocalRangeRepository(),
        configuration: .default, onSaved: {}))
}
