//
//  HeadsetMicrophoneErrors.swift
//  poc-c6
//

import Foundation

extension HeadsetMicrophoneError: UserFacingConvertible {
    var userFacingError: UserFacingError { .headsetMicrophoneRequired }
}
