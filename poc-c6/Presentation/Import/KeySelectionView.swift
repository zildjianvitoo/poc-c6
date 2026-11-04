//
//  KeySelectionView.swift
//  poc-c6
//

import SwiftUI

struct KeySelectionView: View {
    @State var viewModel: KeySelectionViewModel
    let routeMonitor: any AudioRouteMonitor
    let onChooseAnother: () -> Void
    let onRetest: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Find Your Key").font(.largeTitle.bold())
                Text("Your range: \(name(Int(viewModel.choices.vocalRange.lowestMIDI.rounded())))–\(name(Int(viewModel.choices.vocalRange.highestMIDI.rounded())))")
                    .font(.headline)
                if viewModel.choices.options.isEmpty {
                    ContentUnavailableView("No key fits this range", systemImage: "music.note.list",
                        description: Text("This section doesn't fit your tested range within the supported −6 to +6 semitones. Try another section or test your comfortable range again."))
                    Button("Re-test Vocal Range", action: onRetest).buttonStyle(.borderedProminent)
                } else {
                    Text("Sing along with the original backing music in each key, then choose the one that feels easiest.")
                        .foregroundStyle(.secondary)
                    if let excerpt = viewModel.choices.excerpt {
                        Text("Highest vocal phrase · \(time(excerpt.lowerBound))–\(time(excerpt.upperBound)) in your selected clip")
                            .font(.subheadline.bold())
                    }
                    if viewModel.choices.options.count < PoCConfiguration.default.keyRecommendationCount {
                        Text("Only \(viewModel.choices.options.count) keys keep every detected note inside your range.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.choices.options.indices, id: \.self) { index in
                        card(index)
                    }
                    Text("Ranked by time spent near your range limits. This is an estimate; choose by how it feels when you sing. Phrase boundaries are estimated from the vocal melody, and some original vocals may remain in the backing.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = viewModel.error { ErrorStateView(error: error) }
                    Button("Use Selected Key") { viewModel.confirm() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(viewModel.selectedIndex == nil)
                    Button("Re-test Vocal Range") {
                        viewModel.stop()
                        onRetest()
                    }
                }
                Button("Choose Another Section or Song") {
                    viewModel.stop()
                    onChooseAnother()
                }
            }
            .padding()
        }
        .onDisappear { viewModel.stop() }
        .task {
            for await _ in routeMonitor.interruptions() { viewModel.stop() }
        }
        .task {
            var previous = routeMonitor.currentRoute
            for await route in routeMonitor.routeChanges() {
                if route != previous { viewModel.stop() }
                previous = route
            }
        }
    }

    private func card(_ index: Int) -> some View {
        let option = viewModel.choices.options[index]
        let recommendation = option.recommendation
        let shift = recommendation.plan.semitoneShift
        let selected = viewModel.selectedIndex == index
        let active = viewModel.playingIndex == index || viewModel.loadingIndex == index
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(index + 1). \(shift == 0 ? "Original key" : "\(shift > 0 ? "+" : "−")\(abs(shift)) semitones")")
                    .font(.headline)
                Spacer()
                if index == 0 { Text("Recommended").font(.caption).foregroundStyle(.tint) }
            }
            LabeledContent("Vocal notes", value: "\(name(recommendation.lowestMIDI))–\(name(recommendation.highestMIDI))")
            LabeledContent("Range-edge penalty", value: recommendation.penalty.formatted(.number.precision(.fractionLength(1))) + " / 100")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button { viewModel.listen(index) } label: {
                    Label(viewModel.loadingIndex == index ? "Preparing…" : (active ? "Stop" : "Listen to Phrase"),
                          systemImage: active ? "stop.fill" : "play.fill")
                }
                .disabled(viewModel.choices.excerpt == nil)
                Spacer()
                Button { viewModel.select(index) } label: {
                    Label(selected ? "Selected" : "Choose", systemImage: selected ? "checkmark.circle.fill" : "circle")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private func name(_ midi: Int) -> String { PitchMath.noteName(midi: midi) }
    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
