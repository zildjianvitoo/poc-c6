//
//  ExportPreviewView.swift
//  poc-c6
//
//  Final screen: export progress, preview, Share and Save to Photos (PRD §5.9). Owner: Zildjian Vito (ZV-13).
//

import AVKit
import SwiftUI
import UIKit

struct ExportPreviewView: View {
    @State private var viewModel: CompingViewModel
    @State private var player: AVPlayer?
    let onStartOver: () -> Void

    init(viewModel: CompingViewModel, onStartOver: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onStartOver = onStartOver
    }

    var body: some View {
        VStack(spacing: 20) {
            content
            Spacer(minLength: 0)
            Button("Start Over", action: onStartOver)
                .buttonStyle(.bordered)
        }
        .padding()
        .task { await viewModel.export() }
        .onChange(of: viewModel.exportedURL) { _, url in
            player = url.flatMap { viewModel.hasPlayableFile ? AVPlayer(url: $0) : nil }
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.exportState {
        case .idle, .exporting:
            exportingView
        case .finished(let url):
            finishedView(url: url)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var exportingView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Creating your cover…")
                .font(.title2.bold())
            ProgressView(value: progress)
                .frame(maxWidth: 280)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func finishedView(url: URL) -> some View {
        VStack(spacing: 16) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ContentUnavailableView("No preview",
                                           systemImage: "film",
                                           description: Text("Running on fakes, so no video file was written."))
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 16))
            .frame(maxHeight: 480)

            Text(viewModel.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await viewModel.saveToPhotos() }
                } label: {
                    saveLabel
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.saveState == .saving || viewModel.saveState == .saved)
            }
            .controlSize(.large)
            .disabled(!viewModel.hasPlayableFile)

            saveMessage
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ErrorStateView(error: .exportFailed(details: message), actionTitle: "Try Again") {
                Task { await viewModel.export() }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var saveLabel: some View {
        switch viewModel.saveState {
        case .saving: Label("Saving…", systemImage: "hourglass")
        case .saved: Label("Saved", systemImage: "checkmark")
        default: Label("Save to Photos", systemImage: "square.and.arrow.down")
        }
    }

    @ViewBuilder
    private var saveMessage: some View {
        switch viewModel.saveState {
        case .denied:
            VStack(spacing: 4) {
                Text("Allow access to Photos to save your cover.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .font(.footnote)
        case .failed(let message):
            Text("Couldn't save: \(message)")
                .font(.footnote)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private var progress: Double {
        if case .exporting(let value) = viewModel.exportState { value } else { 0 }
    }
}

#Preview {
    let container = AppContainer.fakes()
    ExportPreviewView(
        viewModel: CompingViewModel(
            plan: DomainFixtures.compingPlan(),
            useCase: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            videoLibrary: FakeVideoLibrarySaver()),
        onStartOver: {})
}
