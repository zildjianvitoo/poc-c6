//
//  MemoryFootprint.swift
//  poc-c6
//
//  The process's memory footprint (what iOS counts towards the jetsam limit, as Xcode's memory
//  gauge shows) and the memory left before that limit. For device-test logging only.
//

import Foundation
import os

nonisolated enum MemoryFootprint {
    struct Snapshot: Sendable {
        let currentMB: Double
        /// Highest footprint since the process started.
        let peakMB: Double
        /// Memory left before iOS terminates the app (0 on macOS).
        let availableMB: Double
    }

    static func snapshot() -> Snapshot {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let mb = 1.0 / 1_048_576
        #if os(iOS)
        let available = Double(os_proc_available_memory()) * mb
        #else
        let available = 0.0
        #endif
        guard result == KERN_SUCCESS else { return Snapshot(currentMB: 0, peakMB: 0, availableMB: available) }
        return Snapshot(currentMB: Double(info.phys_footprint) * mb,
                        peakMB: Double(info.ledger_phys_footprint_peak) * mb,
                        availableMB: available)
    }
}
