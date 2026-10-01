import SidekickCore
import SwiftUI

/// Live readings from a `TelemetrySource`. The bundled source is the simulator.
struct ReadingsScreen: View {
    @Bindable var model: ReadingsViewModel

    var body: some View {
        NavigationStack {
            List {
                if let banner = model.bannerText {
                    Section {
                        Text(banner)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("readings.banner")
                        Text(model.scenarioNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Scenario") {
                    ForEach(model.scenarioChoices) { choice in
                        Button {
                            Task { await model.select(scenarioID: choice.id) }
                        } label: {
                            HStack {
                                Text(choice.displayName)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if choice.id == model.selectedScenarioID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("readings.scenario.\(choice.id)")
                        .modifier(SelectedTrait(isSelected: choice.id == model.selectedScenarioID))
                    }
                }
                Section("Channels") {
                    ForEach(model.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                Text(row.valueText)
                                Text(row.unit)
                                    .foregroundStyle(.secondary)
                                if let simulatedLabel = row.simulatedLabel {
                                    Text(simulatedLabel)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.body)
                            if let offset = row.offsetMilliseconds {
                                Text("\(offset) ms")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("readings.row.\(row.channelID)")
                        .accessibilityLabel(accessibilityLabel(for: row))
                    }
                }
                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("readings.error")
                    }
                }
            }
            .accessibilityIdentifier("readings.list")
            .navigationTitle("Readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.canStop {
                        Button("Stop") {
                            Task { await model.stop() }
                        }
                        .accessibilityIdentifier("readings.stop")
                    } else {
                        Button("Start") {
                            Task { await model.start() }
                        }
                        .disabled(!model.canStart)
                        .accessibilityIdentifier("readings.start")
                    }
                }
            }
        }
    }

    private func accessibilityLabel(for row: ReadingRow) -> String {
        var parts = [row.displayName, row.valueText, row.unit]
        if let simulatedLabel = row.simulatedLabel {
            parts.append(simulatedLabel)
        }
        return parts.joined(separator: ", ")
    }
}

private struct SelectedTrait: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

@MainActor
private enum ReadingsScreenPreview {
    static func model(liveClock: Bool) -> ReadingsViewModel {
        do {
            let clock: any TelemetryClock = liveClock
                ? WallClockTelemetryClock()
                : ImmediateTelemetryClock()
            return try ReadingsViewModel.bundled(clock: clock)
        } catch {
            preconditionFailure("bundled telemetry scenarios failed to load: \(error)")
        }
    }
}

/// Starts the simulator so the preview lands on scripted values.
private struct ReadingsPreviewHost: View {
    let liveClock: Bool
    @State private var model: ReadingsViewModel?

    var body: some View {
        Group {
            if let model {
                ReadingsScreen(model: model)
            }
        }
        .task {
            guard model == nil else { return }
            let created = ReadingsScreenPreview.model(liveClock: liveClock)
            model = created
            await created.start()
        }
    }
}

#Preview("Idle light") {
    ReadingsScreen(model: ReadingsScreenPreview.model(liveClock: false))
        .preferredColorScheme(.light)
}

#Preview("Idle dark") {
    ReadingsScreen(model: ReadingsScreenPreview.model(liveClock: false))
        .preferredColorScheme(.dark)
}

#Preview("Idle accessibility XL") {
    ReadingsScreen(model: ReadingsScreenPreview.model(liveClock: false))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Readings light") {
    ReadingsPreviewHost(liveClock: false)
        .preferredColorScheme(.light)
}

#Preview("Readings dark") {
    ReadingsPreviewHost(liveClock: false)
        .preferredColorScheme(.dark)
}

#Preview("Readings accessibility XL") {
    ReadingsPreviewHost(liveClock: false)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Playing") {
    ReadingsPreviewHost(liveClock: true)
}
