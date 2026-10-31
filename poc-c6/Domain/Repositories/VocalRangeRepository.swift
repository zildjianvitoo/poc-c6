//
//  VocalRangeRepository.swift
//  poc-c6
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Implemented by: Ikzaz
//

import Foundation

nonisolated protocol VocalRangeRepository: AnyObject {
    func load() -> VocalRange?
    func save(_ range: VocalRange)
}
