//
//  CameraPreviewSource.swift
//  poc-c6
//
//  Gives the recording screen the live camera session without putting AVCaptureSession
//  into the Domain layer (PRD §6.1). Implemented by CaptureRepositoryImpl.
//

import AVFoundation

nonisolated protocol CameraPreviewSource: AnyObject {
    var previewSession: AVCaptureSession { get }
    /// The camera being previewed, for AVCaptureDevice.RotationCoordinator. nil before setup.
    var previewDevice: AVCaptureDevice? { get }
}
