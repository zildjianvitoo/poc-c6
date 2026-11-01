//
//  CameraPreviewView.swift
//  poc-c6
//
//  Full-screen front camera preview, portrait and mirrored like a selfie (PRD §5.5, §7.3).
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var observer: NSObjectProtocol?

        /// The layer's connection only exists once the session has its camera input, which can be
        /// after this view appears; orient it whenever the session starts and on every layout.
        func attach(_ session: AVCaptureSession) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            observer = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.orient() }
            }
            orient()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            orient()
        }

        func orient() {
            guard let connection = previewLayer.connection else { return }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.attach(session)
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        view.orient()
    }
}
