//
//  PermissionGate.swift
//  poc-c6
//
//  Shows `content` only when the given permissions are granted; otherwise explains why
//  they are needed or how to turn them on in Settings. Owner: Zildjian Vito (ZV-14).
//
//  Usage (in RootView, so feature screens never deal with permissions):
//      PermissionGate([.camera, .microphone], provider: container.permissions) { RecordingView() }
//

import SwiftUI
import UIKit

struct PermissionGate<Content: View>: View {
    @State private var model: PermissionGateModel
    @Environment(\.scenePhase) private var scenePhase
    private let content: () -> Content

    init(_ permissions: [MediaPermission], provider: any MediaPermissionProviding,
         @ViewBuilder content: @escaping () -> Content) {
        _model = State(initialValue: PermissionGateModel(permissions: permissions, provider: provider))
        self.content = content
    }

    var body: some View {
        Group {
            switch model.state {
            case .checking:
                ProgressView()
            case .granted:
                content()
            case .needsRequest(let missing):
                requestView(missing)
            case .denied(let missing):
                ErrorStateView(error: .permissionDenied(missing), actionTitle: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .onAppear { model.refresh() }
        // Coming back from Settings.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    private func requestView(_ missing: [MediaPermission]) -> some View {
        VStack(spacing: 24) {
            Spacer()
            HStack(spacing: 16) {
                ForEach(missing, id: \.self) { permission in
                    Image(systemName: permission.systemImage)
                        .font(.largeTitle)
                }
            }
            .foregroundStyle(.tint)
            Text("Allow access")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                ForEach(missing, id: \.self) { permission in
                    Text("**\(permission.displayName)** \(permission.reason).")
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            Spacer()
            Button("Continue") {
                Task { await model.requestMissing() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview("Needs request") {
    PermissionGate([.camera, .microphone],
                   provider: FakeMediaPermissions(statuses: [.camera: .notDetermined, .microphone: .notDetermined])) {
        Text("Recording")
    }
}

#Preview("Denied") {
    PermissionGate([.camera, .microphone], provider: FakeMediaPermissions(statuses: [.microphone: .denied])) {
        Text("Recording")
    }
}
