import Foundation

/// Opaque channel name.
///
/// Simulator scenarios use a `FAKE-` id. Later hardware sources choose their own
/// ids. This type does not encode PIDs, connector IDs, or pinouts.
public struct TelemetryChannelID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

extension TelemetryChannelID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let id = TelemetryChannelID(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "channel id must be non-empty"
            )
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Unit label stored with a reading. Simulator scenarios use a `FAKE-` unit.
public struct TelemetryUnit: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

extension TelemetryUnit: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let unit = TelemetryUnit(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unit must be non-empty"
            )
        }
        self = unit
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Milliseconds since this session started.
///
/// Scripted offsets stay deterministic in tests. A wall-clock `Date` is not a vehicle fact.
public struct TelemetryTimestamp: Hashable, Sendable, Comparable {
    public let offsetMilliseconds: Int

    public init?(offsetMilliseconds: Int) {
        guard offsetMilliseconds >= 0 else { return nil }
        self.offsetMilliseconds = offsetMilliseconds
    }

    public static func < (lhs: TelemetryTimestamp, rhs: TelemetryTimestamp) -> Bool {
        lhs.offsetMilliseconds < rhs.offsetMilliseconds
    }
}

/// Who produced a reading.
///
/// `elm327` and `obd1` name future sources (issues #44 and #45). This package
/// only emits `simulated`. The truck's OBD protocol is TBD in `docs/vehicle/TRUCK.md`.
public enum TelemetryOrigin: String, Codable, Hashable, Sendable, CaseIterable {
    case simulated
    case elm327
    case obd1
}

/// One typed sample from a `TelemetrySource`.
public struct TelemetryReading: Hashable, Sendable {
    public let channelID: TelemetryChannelID
    public let value: Double
    public let unit: TelemetryUnit
    public let timestamp: TelemetryTimestamp
    public let origin: TelemetryOrigin
    /// Scenario seed that produced this sample. Not a measurement.
    public let seed: UInt64
    /// Deterministic tag from `seed` and the reading index. Not a measurement.
    public let sequenceStamp: UInt64

    public var isSimulated: Bool { origin == .simulated }

    public init(
        channelID: TelemetryChannelID,
        value: Double,
        unit: TelemetryUnit,
        timestamp: TelemetryTimestamp,
        origin: TelemetryOrigin,
        seed: UInt64,
        sequenceStamp: UInt64
    ) {
        self.channelID = channelID
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.origin = origin
        self.seed = seed
        self.sequenceStamp = sequenceStamp
    }
}

/// Copy the UI must show on every simulated reading.
public enum SimulatedReadingCopy {
    public static let banner = "Simulated readings. Not engine specs."
    public static let row = "Simulated"
}

enum SeededSequence {
    static func stamp(seed: UInt64, index: Int) -> UInt64 {
        splitmix64(seed &+ UInt64(index))
    }

    /// SplitMix64. Same seed and index always return the same stamp.
    private static func splitmix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
