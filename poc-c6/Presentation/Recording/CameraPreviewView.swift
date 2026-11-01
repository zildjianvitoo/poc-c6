//
//  CameraPreviewView.swift
//  poc-c6
//
//  Full-screen front camera preview, portrait and mirrored like a selfie (PRD §5.5, §7.3).
//  The rotation comes from AVCaptureDevice.RotationCoordinator, which knows the front camera's
//  sensor orientation and the screen's, instead of a hard-coded angle.
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var angleObservation: NSKeyValueObservation?

        func attach(_ session: AVCaptureSession, device: AVCaptureDevice?) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            if let device {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                angleObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.orient() }
                }
                self.coordinator = coordinator
            }
            orient()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            orient()
        }

        func orient() {
            guard let connection = previewLayer.connection else { return }
            let angle = coordinator?.videoRotationAngleForHorizonLevelPreview ?? 90
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.attach(session, device: device)
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        view.orient()
    }
}
