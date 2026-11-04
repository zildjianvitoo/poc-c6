// Standalone checks for display stability and headset-input selection.
import Foundation

@main
struct RealtimePitchChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "RealtimePitchChecks", message: message) }
        }
        var filter = StabilizePitchDisplayUseCase()
        try check(filter.execute(midi: 60, time: 0) == 60, "first note displays immediately")
        try check(filter.execute(midi: 90, time: 0) == 60, "duplicate capture timestamps cannot introduce a spike")
        try check(filter.execute(midi: 72, time: 0.05) == 72, "a real octave change is shown without confirmation delay")
        try check(filter.execute(midi: 60, time: 0.10) == 60, "correct pitch resumes without a visible spike")
        try check(filter.execute(midi: 67, time: 0.15) == 67, "first frame of a new note is shown immediately")
        try check(abs((filter.execute(midi: 67.1, time: 0.20) ?? 0) - 67) <= 0.1, "small jitter within the new note remains bounded")
        try check(filter.execute(midi: nil, time: 0.25) == nil, "silence immediately breaks the trail")
        try check(filter.execute(midi: 48, time: 0.30) == 48, "new phrase does not inherit a previous note")
        try check(filter.execute(midi: 80, time: 1) == 80, "long callback gap resets smoothing")
        try check(filter.execute(midi: 55, time: 0.5) == 55, "rewind resets smoothing")
        try check(filter.execute(midi: .nan, time: 0.55) == nil, "invalid pitch cannot enter display")
        try check(filter.execute(midi: 60, time: .infinity) == nil, "invalid capture time is rejected")
        _ = filter.execute(midi: 60, time: 2)
        try check(filter.execute(midi: 60.05, time: 2.05) == 60, "tiny jitter stays in the display deadband")
        let smallChange = filter.execute(midi: 60.5, time: 2.10)!
        try check(smallChange > 60 && smallChange < 60.5, "small changes are smoothed without semitone snapping")
        let following = filter.execute(midi: 60.5, time: 2.15)!
        try check(following > smallChange, "a sustained small change is tracked")
        filter.reset()
        var raw: [Float] = [], displayed: [Float] = []
        for frame in 0..<60 {
            let midi: Float = frame.isMultiple(of: 2) ? 59.65 : 60.35
            raw.append(midi)
            displayed.append(filter.execute(midi: midi, time: Double(frame) * 0.05)!)
        }
        let rawSpread = raw.dropFirst(10).max()! - raw.dropFirst(10).min()!
        let displaySpread = displayed.dropFirst(10).max()! - displayed.dropFirst(10).min()!
        try check(displaySpread < rawSpread / 2, "steady-note display fluctuates less than raw detections")
        filter.reset()
        _ = filter.execute(midi: 60, time: 0)
        _ = filter.execute(midi: 72, time: 0.05)
        try check(filter.execute(midi: 48, time: 0.10) == 48, "consecutive large note changes stay on time")
        try check(filter.execute(midi: 48, time: 0.15) == 48, "actual octave changes are preserved, not folded toward a target")

        let select = SelectHeadsetMicrophoneUseCase()
        try check(select.execute([]) == nil, "no input cannot be selected")
        try check(select.execute([.unsupported]) == nil, "built-in/output-only input is rejected")
        try check(select.execute([.unsupported, .bluetooth]) == 1, "Bluetooth microphone is selectable")
        try check(select.execute([.bluetooth, .wiredHeadset]) == 1, "wired headset is preferred")
        try check(select.execute([.unsupported, .usb]) == 1, "USB microphone is selectable")
        try check(select.execute([.bluetooth, .usb]) == 1, "USB microphone is preferred over Bluetooth")
        try check(select.execute([.bluetooth, .bluetooth]) == 0, "selection is deterministic for equal input kinds")
        print("PASS RealtimePitchChecks (\(count) checks)")
    }
}
