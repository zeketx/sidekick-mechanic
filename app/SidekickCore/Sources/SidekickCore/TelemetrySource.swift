import Foundation

/// Swappable live readings. The simulator, a future ELM327 source, and a future
/// OBD1 source all use this shape. Nothing here opens Bluetooth or speaks to hardware.
public protocol TelemetrySource: Sendable {
    nonisolated var origin: TelemetryOrigin { get }

    /// Opens one session and returns its reading stream.
    ///
    /// A second call before `stop()` throws `TelemetrySourceError.alreadyRunning`.
    /// The stream finishes when the session ends or `stop()` is called.
    func start() async throws -> AsyncStream<TelemetryReading>

    /// Ends the current session and finishes its stream. Safe to call when idle.
    func stop() async
}

public enum TelemetrySourceError: Error, Equatable, Sendable {
    case alreadyRunning
    /// Reserved origin. The truck's OBD protocol is still TBD, so no hardware source exists.
    case seamNotImplemented(TelemetryOrigin)
}

/// Pacing for scripted replay. Tests use `ImmediateTelemetryClock` so they do not sleep.
public protocol TelemetryClock: Sendable {
    func sleep(milliseconds: Int) async throws
}

public struct ImmediateTelemetryClock: TelemetryClock {
    public init() {}

    public func sleep(milliseconds: Int) async throws {}
}

public struct WallClockTelemetryClock: TelemetryClock {
    public init() {}

    public func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// Factories for sources that are not built yet.
///
/// `elm327()` is the issue #44 seam: BLE ELM327, only if `TRUCK.md` later confirms OBD-II.
/// `obd1()` is the issue #45 seam: a fallback if `TRUCK.md` later records an OBD1 ECU.
/// Both throw until those issues build a real `TelemetrySource`. This package does not
/// import CoreBluetooth and does not invent PIDs, pinouts, or part numbers.
public enum TelemetrySources {
    public static func elm327() throws -> any TelemetrySource {
        throw TelemetrySourceError.seamNotImplemented(.elm327)
    }

    public static func obd1() throws -> any TelemetrySource {
        throw TelemetrySourceError.seamNotImplemented(.obd1)
    }
}
