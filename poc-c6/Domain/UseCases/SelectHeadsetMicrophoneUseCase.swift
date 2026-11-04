//
//  SelectHeadsetMicrophoneUseCase.swift
//  poc-c6
//

import Foundation

/// Choose a real external microphone. Built-in and output-only ports are ineligible.
nonisolated struct SelectHeadsetMicrophoneUseCase {
    enum InputKind: Int, Sendable {
        case wiredHeadset, usb, bluetooth, unsupported
    }

    func execute(_ inputs: [InputKind]) -> Int? {
        inputs.indices.filter { inputs[$0] != .unsupported }.min {
            inputs[$0].rawValue == inputs[$1].rawValue ? $0 < $1 : inputs[$0].rawValue < inputs[$1].rawValue
        }
    }
}
