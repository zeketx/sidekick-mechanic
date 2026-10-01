import Foundation

/// Replays a `TelemetryScenario` on an `AsyncStream`.
///
/// Readings are the scripted placeholder values. `seed` only changes `sequenceStamp`,
/// so two runs with the same seed match and the seed cannot invent sensor curves.
public actor SimulatedTelemetrySource: TelemetrySource {
    public nonisolated let origin: TelemetryOrigin = .simulated

    private let readings: [TelemetryReading]
    private let clock: any TelemetryClock
    private var session: Session?
    private var nextSessionID: UInt64 = 0

    public init(
        scenario: TelemetryScenario,
        seed: UInt64? = nil,
        clock: any TelemetryClock = WallClockTelemetryClock()
    ) {
        self.readings = TelemetryReplay.readings(for: scenario, seed: seed)
        self.clock = clock
    }

    public func start() async throws -> AsyncStream<TelemetryReading> {
        if session != nil {
            throw TelemetrySourceError.alreadyRunning
        }
        let sessionID = nextSessionID
        nextSessionID += 1
        let readings = self.readings
        let clock = self.clock
        let (stream, madeContinuation) = AsyncStream.makeStream(
            of: TelemetryReading.self,
            bufferingPolicy: .unbounded
        )
        let continuation = madeContinuation
        let task = Task {
            var previousOffset = 0
            do {
                for reading in readings {
                    let delta = reading.timestamp.offsetMilliseconds - previousOffset
                    previousOffset = reading.timestamp.offsetMilliseconds
                    if delta > 0 {
                        try await clock.sleep(milliseconds: delta)
                    }
                    try Task.checkCancellation()
                    continuation.yield(reading)
                }
            } catch {
                // Cancellation and a failing clock both end the session.
            }
            self.markIdle(sessionID)
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        session = Session(id: sessionID, task: task, continuation: continuation)
        return stream
    }

    public func stop() {
        guard let ending = session else { return }
        session = nil
        ending.task.cancel()
        ending.continuation.finish()
    }

    private func markIdle(_ sessionID: UInt64) {
        guard session?.id == sessionID else { return }
        session = nil
    }
}

private struct Session: Sendable {
    let id: UInt64
    let task: Task<Void, Never>
    let continuation: AsyncStream<TelemetryReading>.Continuation
}
