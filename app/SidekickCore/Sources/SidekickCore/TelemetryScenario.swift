import Foundation

public enum TelemetryScenarioError: Error, Equatable, Sendable {
    case idMustBePlaceholder
    case emptyDisplayName
    case noteMustSayNotASpec
    case noChannels
    case duplicateChannel(String)
    case channelIDMustBePlaceholder(String)
    case displayNameMustSayPlaceholder(String)
    case unitMustBePlaceholder(String)
    case noFrames
    case emptySamples
    case offsetMustBeNonNegative(Int)
    case offsetsMustIncrease
    case unknownChannel(String)
    case duplicateSample(String)
    case nonFiniteValue(String)
    case missingBundle
}

public struct TelemetryChannel: Hashable, Sendable {
    public let id: TelemetryChannelID
    public let displayName: String
    public let unit: TelemetryUnit

    public init(id: TelemetryChannelID, displayName: String, unit: TelemetryUnit) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
    }
}

public struct TelemetrySample: Hashable, Sendable {
    public let channelID: TelemetryChannelID
    public let value: Double

    public init(channelID: TelemetryChannelID, value: Double) {
        self.channelID = channelID
        self.value = value
    }
}

public struct TelemetryFrame: Hashable, Sendable {
    public let timestamp: TelemetryTimestamp
    public let samples: [TelemetrySample]

    public init(timestamp: TelemetryTimestamp, samples: [TelemetrySample]) {
        self.timestamp = timestamp
        self.samples = samples
    }
}

/// Scripted placeholder scenario. Values are illustrative, not engine specs.
public struct TelemetryScenario: Hashable, Sendable, Decodable {
    public let id: String
    public let displayName: String
    public let note: String
    public let seed: UInt64
    public let channels: [TelemetryChannel]
    public let frames: [TelemetryFrame]

    public init(
        id: String,
        displayName: String,
        note: String,
        seed: UInt64,
        channels: [TelemetryChannel],
        frames: [TelemetryFrame]
    ) throws {
        guard id.hasPrefix(Self.placeholderPrefix), id.count > Self.placeholderPrefix.count else {
            throw TelemetryScenarioError.idMustBePlaceholder
        }
        guard !displayName.isEmpty else { throw TelemetryScenarioError.emptyDisplayName }
        guard note.localizedCaseInsensitiveContains("not a spec") else {
            throw TelemetryScenarioError.noteMustSayNotASpec
        }
        guard !channels.isEmpty else { throw TelemetryScenarioError.noChannels }

        var seenChannels: Set<String> = []
        for channel in channels {
            let rawID = channel.id.rawValue
            guard rawID.hasPrefix(Self.placeholderPrefix), rawID.count > Self.placeholderPrefix.count else {
                throw TelemetryScenarioError.channelIDMustBePlaceholder(rawID)
            }
            guard channel.displayName.contains("Placeholder") else {
                throw TelemetryScenarioError.displayNameMustSayPlaceholder(rawID)
            }
            let unit = channel.unit.rawValue
            guard unit.hasPrefix(Self.placeholderPrefix), unit.count > Self.placeholderPrefix.count else {
                throw TelemetryScenarioError.unitMustBePlaceholder(unit)
            }
            guard seenChannels.insert(rawID).inserted else {
                throw TelemetryScenarioError.duplicateChannel(rawID)
            }
        }

        guard !frames.isEmpty else { throw TelemetryScenarioError.noFrames }
        var previousOffset: Int?
        let known = Set(channels.map(\.id))
        for frame in frames {
            let offset = frame.timestamp.offsetMilliseconds
            guard offset >= 0 else { throw TelemetryScenarioError.offsetMustBeNonNegative(offset) }
            if let previousOffset, offset <= previousOffset {
                throw TelemetryScenarioError.offsetsMustIncrease
            }
            previousOffset = offset
            guard !frame.samples.isEmpty else { throw TelemetryScenarioError.emptySamples }
            var seenSamples: Set<String> = []
            for sample in frame.samples {
                let rawID = sample.channelID.rawValue
                guard known.contains(sample.channelID) else {
                    throw TelemetryScenarioError.unknownChannel(rawID)
                }
                guard seenSamples.insert(rawID).inserted else {
                    throw TelemetryScenarioError.duplicateSample(rawID)
                }
                guard sample.value.isFinite else {
                    throw TelemetryScenarioError.nonFiniteValue(rawID)
                }
            }
        }

        self.id = id
        self.displayName = displayName
        self.note = note
        self.seed = seed
        self.channels = channels
        self.frames = frames
    }

    public static func decode(_ data: Data) throws -> TelemetryScenario {
        try JSONDecoder().decode(TelemetryScenario.self, from: data)
    }

    public init(from decoder: Decoder) throws {
        let raw = try RawScenario(from: decoder)
        guard let channels = raw.channels else { throw TelemetryScenarioError.noChannels }
        guard let frames = raw.frames else { throw TelemetryScenarioError.noFrames }
        let builtChannels = try channels.map { try $0.makeChannel() }
        let builtFrames = try frames.map { try $0.makeFrame() }
        try self.init(
            id: raw.id,
            displayName: raw.displayName,
            note: raw.note,
            seed: raw.seed,
            channels: builtChannels,
            frames: builtFrames
        )
    }

    static let placeholderPrefix = "FAKE-"
}

/// Pure replay. The same scenario and seed always return the same readings.
public enum TelemetryReplay {
    public static func readings(for scenario: TelemetryScenario, seed: UInt64? = nil) -> [TelemetryReading] {
        let seed = seed ?? scenario.seed
        let units = Dictionary(uniqueKeysWithValues: scenario.channels.map { ($0.id, $0.unit) })
        var readings: [TelemetryReading] = []
        readings.reserveCapacity(scenario.frames.reduce(0) { $0 + $1.samples.count })
        for frame in scenario.frames {
            for sample in frame.samples {
                guard let unit = units[sample.channelID] else {
                    preconditionFailure("scenario validation rejects unknown channels")
                }
                readings.append(
                    TelemetryReading(
                        channelID: sample.channelID,
                        value: sample.value,
                        unit: unit,
                        timestamp: frame.timestamp,
                        origin: .simulated,
                        seed: seed,
                        sequenceStamp: SeededSequence.stamp(seed: seed, index: readings.count)
                    )
                )
            }
        }
        return readings
    }
}

public enum BundledTelemetryScenarios {
    /// JSON scenarios copied into the SidekickCore bundle.
    public static func load() throws -> [TelemetryScenario] {
        try load(from: .module)
    }

    public static func load(from bundle: Bundle) throws -> [TelemetryScenario] {
        let paths = bundle.paths(forResourcesOfType: "json", inDirectory: "Scenarios")
        guard !paths.isEmpty else { throw TelemetryScenarioError.missingBundle }
        let scenarios = try paths.sorted().map { path in
            try TelemetryScenario.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        }
        return scenarios.sorted { $0.id < $1.id }
    }
}

private struct RawScenario: Decodable {
    let id: String
    let displayName: String
    let note: String
    let seed: UInt64
    let channels: [RawChannel]?
    let frames: [RawFrame]?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case note
        case seed
        case channels
        case frames
    }
}

private struct RawChannel: Decodable {
    let id: String
    let displayName: String
    let unit: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case unit
    }

    func makeChannel() throws -> TelemetryChannel {
        guard let channelID = TelemetryChannelID(rawValue: id) else {
            throw TelemetryScenarioError.channelIDMustBePlaceholder(id)
        }
        guard let telemetryUnit = TelemetryUnit(rawValue: unit) else {
            throw TelemetryScenarioError.unitMustBePlaceholder(unit)
        }
        return TelemetryChannel(id: channelID, displayName: displayName, unit: telemetryUnit)
    }
}

private struct RawFrame: Decodable {
    let offsetMilliseconds: Int
    let samples: [RawSample]

    enum CodingKeys: String, CodingKey {
        case offsetMilliseconds = "offset_ms"
        case samples
    }

    func makeFrame() throws -> TelemetryFrame {
        guard let timestamp = TelemetryTimestamp(offsetMilliseconds: offsetMilliseconds) else {
            throw TelemetryScenarioError.offsetMustBeNonNegative(offsetMilliseconds)
        }
        return TelemetryFrame(timestamp: timestamp, samples: try samples.map { try $0.makeSample() })
    }
}

private struct RawSample: Decodable {
    let channel: String
    let value: Double

    func makeSample() throws -> TelemetrySample {
        guard let channelID = TelemetryChannelID(rawValue: channel) else {
            throw TelemetryScenarioError.unknownChannel(channel)
        }
        return TelemetrySample(channelID: channelID, value: value)
    }
}
