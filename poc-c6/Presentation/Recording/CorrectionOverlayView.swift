//
//  CorrectionOverlayView.swift
//  poc-c6
//

import SwiftUI

struct CorrectionOverlayView: View {
    let passed: Bool
    let score: Double
    let missedNotes: [String]

    var body: some View {
        VStack(spacing: 8) {
            Label(passed ? "PASSED" : "TRY AGAIN", systemImage: passed ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                .font(.title2.bold()).foregroundStyle(passed ? .green : .red)
            Text(score, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            if !passed && !missedNotes.isEmpty {
                Text("Practice these notes: " + missedNotes.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity).padding()
        .background(passed ? Color.green.opacity(0.1) : Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
