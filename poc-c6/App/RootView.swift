//
//  RootView.swift
//  poc-c6
//
//  Shows the screen for the current AppFlow step. Owner: Zildjian Vito (ZV-04).
//  To plug in your screen, replace its placeholder below with your view
//  and call the matching AppFlow method when your step is done.
//  Keep the PermissionGate around it: permissions are handled here, not in feature screens.
//

import SwiftUI

struct RootView: View {
    let flow: AppFlow
    @State private var showsDebugSettings = false

    var body: some View {
        Group {
            switch flow.step {
            case .vocalRange:
                PermissionGate([.microphone], provider: flow.container.permissions) {
                    PlaceholderScreen(title: "Vocal Range Test", owner: "Ikzaz", backlogID: "IK-10",
                                      actionTitle: "Use sample range") {
                        flow.container.vocalRange.save(VocalRange(lowestMIDI: 48, highestMIDI: 67))
                        flow.vocalRangeSaved()
                    }
                }
            case .importSong:
                PlaceholderScreen(title: "Import Song", owner: "Ikzaz", backlogID: "IK-11",
                                  actionTitle: "Use synthesized demo") {
                    Task { await flow.loadDemoSong() }
                }
            case .ready:
                PlaceholderScreen(title: "Ready", owner: "Ikzaz", backlogID: "IK-11",
                                  detail: readyDetail, actionTitle: "Record") {
                    flow.startRecording()
                }
            case .recording:
                PermissionGate([.camera, .microphone], provider: flow.container.permissions) {
                    if let song = flow.preparedSong {
                        RecordingView(viewModel: makeRecordingViewModel(song: song))
                    }
                }
            case .export:
                if let plan = flow.compingPlan {
                    ExportPreviewView(viewModel: makeCompingViewModel(plan: plan), onStartOver: flow.startOver)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: flow.step)
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            // Hidden while recording: the top bar's End Session button lives there.
            if flow.step != .recording {
                Button("Debug Settings", systemImage: "slider.horizontal.3") {
                    showsDebugSettings = true
                }
                .labelStyle(.iconOnly)
                .padding()
            }
            #endif
        }
        .sheet(isPresented: $showsDebugSettings) {
            DebugSettingsView(configuration: flow.container.configuration,
                              onSave: { flow.updateConfiguration($0) },
                              onRetestVocalRange: { flow.retestVocalRange() })
        }
    }

    private var readyDetail: String? {
        guard let song = flow.preparedSong else { return nil }
        let shift = song.transposition.totalSemitones
        return "\(song.segments.count) segments · \(shift >= 0 ? "+" : "")\(shift) semitones"
    }

    private func makeRecordingViewModel(song: PreparedSong) -> RecordingViewModel {
        let container = flow.container
        return RecordingViewModel(
            song: song,
            capture: container.capture,
            playback: container.referencePlayback,
            routeMonitor: container.audioRoute,
            takeLog: container.takeLog,
            planner: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            configuration: container.configuration,
            allowsSpeaker: DebugOptions.allowsSpeakerRecording,
            onFinish: flow.sessionEnded,
            onDiscard: flow.sessionDiscarded)
    }

    private func makeCompingViewModel(plan: CompingCompositionPlan) -> CompingViewModel {
        let container = flow.container
        return CompingViewModel(
            plan: plan,
            useCase: AutoCompingVideoUseCase(takeLog: container.takeLog, videoComposition: container.videoComposition),
            videoLibrary: container.videoLibrary)
    }
}

#Preview {
    RootView(flow: AppFlow(container: .fakes()))
}
