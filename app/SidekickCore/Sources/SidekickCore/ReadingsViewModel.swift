import Foundation
import Observation

public struct ScenarioChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum ReadingsPhase: String, Equatable, Sendable {
    case idle
    case running
    case stopped
}

public struct ReadingRow: Identifiable, Equatable, Sendable {
    public let channelID: String
    public let displayName: String
    public var valueText: String
    public var unit: String
    public var simulatedLabel: String?
    public var offsetMilliseconds: Int?

    public var id: String { channelID }

    public init(
        channelID: String,
        displayName: String,
        valueText: String,
        unit: String,
        simulatedLabel: String?,
        offsetMilliseconds: Int?
    ) {
        self.channelID = channelID
        self.displayName = displayName
        self.valueText = valueText
        self.unit = unit
        self.simulatedLabel = simulatedLabel
        self.offsetMilliseconds = offsetMilliseconds
    }
}

/// Latest reading per channel for the readings screen.
@MainActor
@Observable
public final class ReadingsViewModel {
    public private(set) var scenarioChoices: [ScenarioChoice]
    public private(set) var selectedScenarioID: String
    public private(set) var scenarioNote: String
    public private(set) var showsSimulatedBanner: Bool
    public private(set) var rows: [ReadingRow]
    public private(set) var phase: ReadingsPhase
    public private(set) var errorMessage: String?

    @ObservationIgnored private let scenarios: [TelemetryScenario]
    @ObservationIgnored private let sourceFor: @Sendable (TelemetryScenario) -> any TelemetrySource
    @ObservationIgnored private var source: any TelemetrySource
    @ObservationIgnored private var generation = 0

    public var canStart: Bool { phase != .running }
    public var canStop: Bool { phase == .running }

    public var bannerText: String? {
        showsSimulatedBanner ? SimulatedReadingCopy.banner : nil
    }

    public init(
        scenarios: [TelemetryScenario],
        sourceFor: @escaping @Sendable (TelemetryScenario) -> any TelemetrySource
    ) {
        precondition(!scenarios.isEmpty, "readings need at least one scenario")
        self.scenarios = scenarios
        self.sourceFor = sourceFor
        let first = scenarios[0]
        let source = sourceFor(first)
        self.source = source
        self.selectedScenarioID = first.id
        self.scenarioNote = first.note
        self.showsSimulatedBanner = source.origin == .simulated
        self.scenarioChoices = scenarios.map {
            ScenarioChoice(id: $0.id, displayName: $0.displayName)
        }
        self.rows = Self.placeholderRows(for: first, simulated: source.origin == .simulated)
        self.phase = .idle
        self.errorMessage = nil
    }

    public convenience init(
        scenarios: [TelemetryScenario],
        clock: any TelemetryClock = WallClockTelemetryClock()
    ) {
        self.init(scenarios: scenarios) { scenario in
            SimulatedTelemetrySource(scenario: scenario, clock: clock)
        }
    }

    /// Bundled cold-start and warm-idle scripts. The default clock waits between frames.
    public static func bundled(
        clock: any TelemetryClock = WallClockTelemetryClock()
    ) throws -> ReadingsViewModel {
        ReadingsViewModel(scenarios: try BundledTelemetryScenarios.load(), clock: clock)
    }

    public func start() async {
        guard phase != .running else { return }
        let generation = generation
        let source = source
        phase = .running
        errorMessage = nil
        do {
            let stream = try await source.start()
            guard self.generation == generation else {
                await source.stop()
                return
            }
            for await reading in stream {
                guard self.generation == generation else { return }
                apply(reading)
            }
            guard self.generation == generation, phase == .running else { return }
            phase = .stopped
        } catch is CancellationError {
            guard self.generation == generation else { return }
            if phase == .running { phase = .stopped }
        } catch let error as TelemetrySourceError {
            guard self.generation == generation else { return }
            phase = .idle
            errorMessage = Self.message(for: error)
        } catch {
            guard self.generation == generation else { return }
            phase = .idle
            errorMessage = "Readings stopped unexpectedly."
        }
    }

    public func stop() async {
        guard phase == .running else { return }
        await source.stop()
        if phase == .running {
            phase = .stopped
        }
    }

    public func select(scenarioID: String) async {
        guard scenarioID != selectedScenarioID,
              let scenario = scenarios.first(where: { $0.id == scenarioID })
        else { return }
        generation += 1
        let previous = source
        if phase == .running {
            await previous.stop()
        }
        let next = sourceFor(scenario)
        source = next
        selectedScenarioID = scenario.id
        scenarioNote = scenario.note
        showsSimulatedBanner = next.origin == .simulated
        rows = Self.placeholderRows(for: scenario, simulated: next.origin == .simulated)
        phase = .idle
        errorMessage = nil
    }

    private func apply(_ reading: TelemetryReading) {
        guard let index = rows.firstIndex(where: { $0.channelID == reading.channelID.rawValue }) else {
            return
        }
        rows[index].valueText = Self.valueText(reading.value)
        rows[index].unit = reading.unit.rawValue
        rows[index].offsetMilliseconds = reading.timestamp.offsetMilliseconds
        rows[index].simulatedLabel = reading.isSimulated ? SimulatedReadingCopy.row : nil
    }

    private static func placeholderRows(for scenario: TelemetryScenario, simulated: Bool) -> [ReadingRow] {
        scenario.channels.map { channel in
            ReadingRow(
                channelID: channel.id.rawValue,
                displayName: channel.displayName,
                valueText: "—",
                unit: channel.unit.rawValue,
                simulatedLabel: simulated ? SimulatedReadingCopy.row : nil,
                offsetMilliseconds: nil
            )
        }
    }

    nonisolated static func valueText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value.rounded() == value, abs(value) < 1_000_000_000_000 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func message(for error: TelemetrySourceError) -> String {
        switch error {
        case .alreadyRunning:
            "Readings are already running."
        case .seamNotImplemented:
            "This telemetry source is not available yet."
        }
    }
}
