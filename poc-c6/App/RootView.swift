//
//  RootView.swift
//  poc-c6
//
//  Shows the screen for the current AppFlow step. Owner: Zildjian Vito (ZV-04).
//  To plug in your screen, replace its placeholder case below with your view
//  and call the matching AppFlow method when your step is done.
//

import SwiftUI

struct RootView: View {
    let flow: AppFlow

    var body: some View {
        Group {
            switch flow.step {
            case .vocalRange:
                PlaceholderScreen(title: "Vocal Range Test", owner: "Ikzaz", backlogID: "IK-10",
                                  actionTitle: "Use sample range") {
                    flow.container.vocalRange.save(VocalRange(lowestMIDI: 48, highestMIDI: 67))
                    flow.vocalRangeSaved()
                }
            case .importSong:
                PlaceholderScreen(title: "Import Song", owner: "Ikzaz", backlogID: "IK-11",
                                  actionTitle: "Use sample song") {
                    flow.songPrepared(DomainFixtures.preparedSong)
                }
            case .ready:
                PlaceholderScreen(title: "Ready", owner: "Ikzaz", backlogID: "IK-11",
                                  detail: readyDetail, actionTitle: "Record") {
                    flow.startRecording()
                }
            case .recording:
                PlaceholderScreen(title: "Recording", owner: "Takin", backlogID: "TK-10, TK-11",
                                  actionTitle: "Simulate session (2 of 3 passed)") {
                    flow.sessionEnded(with: DomainFixtures.compingPlan(configuration: flow.container.configuration))
                }
            case .export:
                PlaceholderScreen(title: "Export", owner: "Zildjian", backlogID: "ZV-13",
                                  detail: exportDetail, actionTitle: "Start over") {
                    flow.startOver()
                }
            }
        }
        .animation(.default, value: flow.step)
    }

    private var readyDetail: String? {
        guard let song = flow.preparedSong else { return nil }
        let shift = song.transposition.totalSemitones
        return "\(song.segments.count) segments · \(shift >= 0 ? "+" : "")\(shift) semitones"
    }

    private var exportDetail: String? {
        guard let plan = flow.compingPlan else { return nil }
        return "\(plan.validTakes.count) of \(plan.segments.count) segments\(plan.isPartial ? " (partial)" : "")"
    }
}

#Preview {
    RootView(flow: AppFlow(container: .fakes()))
}
