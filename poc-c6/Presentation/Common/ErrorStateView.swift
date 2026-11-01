//
//  ErrorStateView.swift
//  poc-c6
//
//  Full-screen error with an optional action, using the wording from UserFacingError.
//  Owner: Zildjian Vito (ZV-14).
//

import SwiftUI

struct ErrorStateView: View {
    let error: UserFacingError
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    ErrorStateView(error: .permissionDenied([.camera, .microphone]), actionTitle: "Open Settings") {}
}
