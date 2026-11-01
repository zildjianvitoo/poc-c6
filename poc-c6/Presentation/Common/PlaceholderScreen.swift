//
//  PlaceholderScreen.swift
//  poc-c6
//
//  Stand-in for a screen that is not built yet, so the whole flow can be
//  clicked through with fakes. Owner: Zildjian Vito (ZV-04).
//

import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let owner: String
    let backlogID: String
    var detail: String?
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title)
                .font(.largeTitle.bold())
            Text("Placeholder · \(owner) · \(backlogID)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.body.monospacedDigit())
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    PlaceholderScreen(title: "Recording", owner: "Takin", backlogID: "TK-10",
                      detail: "3 segments", actionTitle: "Continue") {}
}
