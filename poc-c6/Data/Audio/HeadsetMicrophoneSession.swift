//
//  HeadsetMicrophoneSession.swift
//  poc-c6
//

import AVFoundation

nonisolated enum HeadsetMicrophoneSession {
    static func kind(of port: AVAudioSession.Port) -> SelectHeadsetMicrophoneUseCase.InputKind {
        switch port {
        case .headsetMic: .wiredHeadset
        case .usbAudio: .usb
        case .bluetoothHFP, .bluetoothLE: .bluetooth
        default: .unsupported
        }
    }

    static var currentInput: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first { kind(of: $0.portType) != .unsupported }
    }

    /// HFP is needed for Bluetooth microphone input; A2DP alone provides output only.
    @discardableResult
    static func activate(mode: AVAudioSession.Mode, sampleRate: Double? = nil) throws -> String {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .allowBluetoothHFP]
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        if let sampleRate { try session.setPreferredSampleRate(sampleRate) }
        try session.setActive(true)
        do {
            let inputs = session.availableInputs ?? []
            guard let index = SelectHeadsetMicrophoneUseCase().execute(inputs.map { kind(of: $0.portType) }) else {
                throw HeadsetMicrophoneError.unavailable
            }
            let microphone = inputs[index]
            try session.setPreferredInput(microphone)
            return microphone.uid
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    static func verify(_ selectedUID: String) throws {
        guard currentInput?.uid == selectedUID else { throw HeadsetMicrophoneError.unavailable }
    }
}
