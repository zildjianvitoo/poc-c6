//
//  CoreMLSeparationError.swift
//  poc-c6
//
//  Why on-device (CoreML) separation of an imported song failed. File problems (DRM, unreadable,
//  bad trim) are shown to the user; a missing or failing model falls back to center-channel.
//

import Foundation

nonisolated enum CoreMLSeparationError: Error, Equatable {
    case modelUnavailable
    case unreadable
    case drmProtected
    case invalidTrim
}
