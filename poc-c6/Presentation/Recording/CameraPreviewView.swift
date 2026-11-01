//
//  CameraPreviewView.swift
//  poc-c6
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: Preview, context: Context) {
        if let connection = view.previewLayer.connection {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}
