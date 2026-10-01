import Foundation
import XCTest
@testable import SidekickCore

final class TelemetrySourceTests: XCTestCase {
    func testBundledScenariosArePlaceholderScripts() throws {
        let scenarios = try BundledTelemetryScenarios.load()
        XCTAssertEqual(scenarios.map(\.id), ["FAKE-COLD-START", "FAKE-WARM-IDLE"])
        XCTAssertEqual(scenarios.map(\.displayName), ["Cold start", "Warm idle"])
        XCTAssertEqual(scenarios.map(\.seed), [35, 70])
        for scenario in scenarios {
            XCTAssertEqual(scenario.note, "Illustrative placeholder. Not a spec for this engine.")
            XCTAssertEqual(scenario.channels.map(\.id.rawValue), ["FAKE-CHANNEL-A", "FAKE-CHANNEL-B"])
            XCTAssertEqual(
                scenario.channels.map(\.displayName),
                ["Placeholder channel A", "Placeholder channel B"]
            )
            XCTAssertEqual(scenario.channels.map(\.unit.rawValue), ["FAKE-UNIT-A", "FAKE-UNIT-B"])
        }
    }

    func testColdStartReplayIsLiteralForSeed35() throws {
        let readings = TelemetryReplay.readings(for: try coldStart())
        XCTAssertEqual(readings.count, 4)
        XCTAssertEqual(readings.map(\.channelID.rawValue), [
            "FAKE-CHANNEL-A", "FAKE-CHANNEL-B", "FAKE-CHANNEL-A", "FAKE-CHANNEL-B",
        ])
        XCTAssertEqual(readings.map(\.value), [11, 22, 33, 44])
        XCTAssertEqual(readings.map(\.unit.rawValue), [
            "FAKE-UNIT-A", "FAKE-UNIT-B", "FAKE-UNIT-A", "FAKE-UNIT-B",
        ])
        XCTAssertEqual(readings.map(\.timestamp.offsetMilliseconds), [0, 0, 1000, 1000])
        XCTAssertEqual(readings.map(\.origin), [.simulated, .simulated, .simulated, .simulated])
        XCTAssertEqual(readings.map(\.isSimulated), [true, true, true, true])
        XCTAssertEqual(readings.map(\.seed), [35, 35, 35, 35])
        XCTAssertEqual(readings.map(\.sequenceStamp), [
            5_574_532_911_583_637_595,
            16_839_827_797_137_734_171,
            14_387_688_016_129_665_287,
            16_934_044_424_796_929_712,
        ])
    }

    func testSameSeedReplaysIdenticalReadings() throws {
        let scenario = try coldStart()
        let first = TelemetryReplay.readings(for: scenario, seed: 35)
        let second = TelemetryReplay.readings(for: scenario, seed: 35)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.value), [11, 22, 33, 44])
    }

    func testDifferentSeedChangesStampsNotScriptedValues() throws {
        let scenario = try coldStart()
        let readings = TelemetryReplay.readings(for: scenario, seed: 99)
        XCTAssertEqual(readings.map(\.value), [11, 22, 33, 44])
        XCTAssertEqual(readings.map(\.seed), [99, 99, 99, 99])
        XCTAssertEqual(readings.map(\.sequenceStamp), [
            4_824_385_676_517_010_403,
            2_532_601_429_470_541_124,
            15_060_681_878_671_775_511,
            1_243_045_329_627_533_100,
        ])
        XCTAssertNotEqual(
            readings.map(\.sequenceStamp),
            TelemetryReplay.readings(for: scenario, seed: 35).map(\.sequenceStamp)
        )
    }

    func testWarmIdleReplayIsLiteralForSeed70() throws {
        let readings = TelemetryReplay.readings(for: try warmIdle())
        XCTAssertEqual(readings.map(\.value), [55, 66, 77, 88])
        XCTAssertEqual(readings.map(\.timestamp.offsetMilliseconds), [0, 0, 500, 500])
        XCTAssertEqual(readings.map(\.sequenceStamp), [
            7_424_157_817_344_609_039,
            15_037_995_407_070_714_543,
            10_260_536_580_878_929_050,
            15_028_230_723_423_410_763,
        ])
    }

    func testRejectsNoteThatDoesNotSayItIsNotASpec() {
        let json = """
        {
          "id": "FAKE-COLD-START",
          "display_name": "Cold start",
          "note": "Illustrative placeholder.",
          "seed": 35,
          "channels": [
            {"id": "FAKE-CHANNEL-A", "display_name": "Placeholder channel A", "unit": "FAKE-UNIT-A"}
          ],
          "frames": [
            {"offset_ms": 0, "samples": [{"channel": "FAKE-CHANNEL-A", "value": 11}]}
          ]
        }
        """
        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(error as? TelemetryScenarioError, .noteMustSayNotASpec)
        }
    }

    func testRejectsChannelThatIsNotAPlaceholder() {
        XCTAssertThrowsError(try decode(coldStartJSON(channelID: "RPM"))) { error in
            XCTAssertEqual(error as? TelemetryScenarioError, .channelIDMustBePlaceholder("RPM"))
        }
    }

    func testRejectsUnitThatIsNotAPlaceholder() {
        XCTAssertThrowsError(try decode(coldStartJSON(unit: "celsius"))) { error in
            XCTAssertEqual(error as? TelemetryScenarioError, .unitMustBePlaceholder("celsius"))
        }
    }

    func testRejectsDisplayNameThatIsNotAPlaceholder() {
        XCTAssertThrowsError(try decode(coldStartJSON(displayName: "Coolant temperature"))) { error in
            XCTAssertEqual(
                error as? TelemetryScenarioError,
                .displayNameMustSayPlaceholder("FAKE-CHANNEL-A")
            )
        }
    }

    func testRejectsDecreasingOffsets() {
        let json = """
        {
          "id": "FAKE-COLD-START",
          "display_name": "Cold start",
          "note": "Illustrative placeholder. Not a spec for this engine.",
          "seed": 35,
          "channels": [
            {"id": "FAKE-CHANNEL-A", "display_name": "Placeholder channel A", "unit": "FAKE-UNIT-A"}
          ],
          "frames": [
            {"offset_ms": 1000, "samples": [{"channel": "FAKE-CHANNEL-A", "value": 11}]},
            {"offset_ms": 500, "samples": [{"channel": "FAKE-CHANNEL-A", "value": 33}]}
          ]
        }
        """
        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(error as? TelemetryScenarioError, .offsetsMustIncrease)
        }
    }

    func testRejectsUnknownChannelInAFrame() {
        let json = """
        {
          "id": "FAKE-COLD-START",
          "display_name": "Cold start",
          "note": "Illustrative placeholder. Not a spec for this engine.",
          "seed": 35,
          "channels": [
            {"id": "FAKE-CHANNEL-A", "display_name": "Placeholder channel A", "unit": "FAKE-UNIT-A"}
          ],
          "frames": [
            {"offset_ms": 0, "samples": [{"channel": "FAKE-OTHER", "value": 11}]}
          ]
        }
        """
        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(error as? TelemetryScenarioError, .unknownChannel("FAKE-OTHER"))
        }
    }

    func testSimulatorStreamMatchesReplayAndCanRestart() async throws {
        let scenario = try coldStart()
        let source = SimulatedTelemetrySource(scenario: scenario, clock: ImmediateTelemetryClock())
        let first = try await collect(source)
        let second = try await collect(source)
        XCTAssertEqual(first, TelemetryReplay.readings(for: scenario))
        XCTAssertEqual(second, first)
        XCTAssertEqual(source.origin, .simulated)
    }

    func testStopFinishesTheStreamBeforeTheNextFrame() async throws {
        let gate = GateTelemetryClock()
        let source = SimulatedTelemetrySource(scenario: try coldStart(), clock: gate)
        let stream = try await source.start()
        let collector = Task { await collectReadings(stream) }
        await gate.waitUntilSleeping()
        await source.stop()
        let readings = await collector.value
        XCTAssertEqual(readings.map(\.value), [11, 22])
        XCTAssertEqual(readings.map(\.timestamp.offsetMilliseconds), [0, 0])
        await source.stop()
    }

    func testStartWhileRunningThrows() async throws {
        let gate = GateTelemetryClock()
        let source = SimulatedTelemetrySource(scenario: try coldStart(), clock: gate)
        let stream = try await source.start()
        let collector = Task { await collectReadings(stream) }
        await gate.waitUntilSleeping()
        do {
            _ = try await source.start()
            XCTFail("expected alreadyRunning")
        } catch {
            XCTAssertEqual(error as? TelemetrySourceError, .alreadyRunning)
        }
        await source.stop()
        let readings = await collector.value
        XCTAssertEqual(readings.map(\.value), [11, 22])
    }

    func testHardwareSeamsAreNotImplemented() {
        XCTAssertThrowsError(try TelemetrySources.elm327()) { error in
            XCTAssertEqual(error as? TelemetrySourceError, .seamNotImplemented(.elm327))
        }
        XCTAssertThrowsError(try TelemetrySources.obd1()) { error in
            XCTAssertEqual(error as? TelemetrySourceError, .seamNotImplemented(.obd1))
        }
    }

    func testValueTextUsesAStableFormat() {
        XCTAssertEqual(ReadingsViewModel.valueText(11), "11")
        XCTAssertEqual(ReadingsViewModel.valueText(11.5), "11.5")
        XCTAssertEqual(ReadingsViewModel.valueText(.infinity), "—")
    }

    private func coldStart() throws -> TelemetryScenario {
        try XCTUnwrap(try BundledTelemetryScenarios.load().first { $0.id == "FAKE-COLD-START" })
    }

    private func warmIdle() throws -> TelemetryScenario {
        try XCTUnwrap(try BundledTelemetryScenarios.load().first { $0.id == "FAKE-WARM-IDLE" })
    }

    private func decode(_ json: String) throws -> TelemetryScenario {
        try TelemetryScenario.decode(Data(json.utf8))
    }

    private func coldStartJSON(channelID: String = "FAKE-CHANNEL-A", unit: String = "FAKE-UNIT-A", displayName: String = "Placeholder channel A") -> String {
        """
        {
          "id": "FAKE-COLD-START",
          "display_name": "Cold start",
          "note": "Illustrative placeholder. Not a spec for this engine.",
          "seed": 35,
          "channels": [
            {"id": "\(channelID)", "display_name": "\(displayName)", "unit": "\(unit)"}
          ],
          "frames": [
            {"offset_ms": 0, "samples": [{"channel": "\(channelID)", "value": 11}]}
          ]
        }
        """
    }

    private func collect(_ source: SimulatedTelemetrySource) async throws -> [TelemetryReading] {
        let stream = try await source.start()
        return await collectReadings(stream)
    }
}

private func collectReadings(_ stream: AsyncStream<TelemetryReading>) async -> [TelemetryReading] {
    var readings: [TelemetryReading] = []
    for await reading in stream {
        readings.append(reading)
    }
    return readings
}

@MainActor
final class ReadingsViewModelTests: XCTestCase {
    func testIdleRowsAreLabeledSimulated() throws {
        let model = try makeModel(clock: ImmediateTelemetryClock())
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.selectedScenarioID, "FAKE-COLD-START")
        XCTAssertEqual(model.bannerText, "Simulated readings. Not engine specs.")
        XCTAssertTrue(model.showsSimulatedBanner)
        XCTAssertEqual(model.scenarioNote, "Illustrative placeholder. Not a spec for this engine.")
        XCTAssertEqual(model.rows.map(\.displayName), ["Placeholder channel A", "Placeholder channel B"])
        XCTAssertEqual(model.rows.map(\.valueText), ["—", "—"])
        XCTAssertEqual(model.rows.map(\.unit), ["FAKE-UNIT-A", "FAKE-UNIT-B"])
        XCTAssertEqual(model.rows.map(\.simulatedLabel), ["Simulated", "Simulated"])
        XCTAssertTrue(model.canStart)
        XCTAssertFalse(model.canStop)
    }

    func testStartReplaysTheLastFrameThenStops() async throws {
        let model = try makeModel(clock: ImmediateTelemetryClock())
        await model.start()
        XCTAssertEqual(model.phase, .stopped)
        XCTAssertEqual(model.rows.map(\.valueText), ["33", "44"])
        XCTAssertEqual(model.rows.map(\.unit), ["FAKE-UNIT-A", "FAKE-UNIT-B"])
        XCTAssertEqual(model.rows.map(\.simulatedLabel), ["Simulated", "Simulated"])
        XCTAssertEqual(model.rows.map(\.offsetMilliseconds), [1000, 1000])
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.canStart)
    }

    func testStopKeepsTheFirstFrame() async throws {
        let gate = GateTelemetryClock()
        let model = try makeModel(clock: gate)
        let task = Task { await model.start() }
        await waitUntil { model.rows.map(\.valueText) == ["11", "22"] }
        await model.stop()
        await task.value
        XCTAssertEqual(model.phase, .stopped)
        XCTAssertEqual(model.rows.map(\.valueText), ["11", "22"])
        XCTAssertEqual(model.rows.map(\.simulatedLabel), ["Simulated", "Simulated"])
        XCTAssertNotEqual(model.rows.map(\.valueText), ["33", "44"])
    }

    func testSelectingWarmIdleResetsThenReplaysThatScript() async throws {
        let model = try makeModel(clock: ImmediateTelemetryClock())
        await model.start()
        XCTAssertEqual(model.rows.map(\.valueText), ["33", "44"])
        await model.select(scenarioID: "FAKE-WARM-IDLE")
        XCTAssertEqual(model.selectedScenarioID, "FAKE-WARM-IDLE")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.rows.map(\.valueText), ["—", "—"])
        XCTAssertEqual(model.rows.map(\.simulatedLabel), ["Simulated", "Simulated"])
        await model.start()
        XCTAssertEqual(model.rows.map(\.valueText), ["77", "88"])
        XCTAssertEqual(model.rows.map(\.offsetMilliseconds), [500, 500])
    }

    func testNonSimulatedOriginHidesTheBanner() throws {
        let scenarios = try BundledTelemetryScenarios.load()
        let model = ReadingsViewModel(scenarios: scenarios) { _ in
            IdleOriginSource(origin: .elm327)
        }
        XCTAssertFalse(model.showsSimulatedBanner)
        XCTAssertNil(model.bannerText)
        XCTAssertEqual(model.rows.map(\.simulatedLabel), [nil, nil])
    }

    private func makeModel(clock: any TelemetryClock) throws -> ReadingsViewModel {
        ReadingsViewModel(scenarios: try BundledTelemetryScenarios.load(), clock: clock)
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out", file: file, line: line)
    }
}

private final class GateTelemetryClock: TelemetryClock, @unchecked Sendable {
    private let gate = Gate()

    func sleep(milliseconds: Int) async throws {
        if milliseconds <= 0 { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.gate.enter(continuation)
            }
        } onCancel: {
            self.gate.resumeOnce(throwing: CancellationError())
        }
    }

    func waitUntilSleeping() async {
        await gate.waitUntilEntered()
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var resumed = false
    private var cancelled = false
    private var didEnter = false
    private var onEntered: CheckedContinuation<Void, Never>?

    func enter(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled || resumed {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        didEnter = true
        let pending = onEntered
        onEntered = nil
        lock.unlock()
        pending?.resume()
    }

    func resumeOnce(throwing error: Error?) {
        lock.lock()
        if error != nil { cancelled = true }
        guard !resumed, let continuation else {
            if error != nil { resumed = true }
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didEnter {
                lock.unlock()
                continuation.resume()
            } else {
                onEntered = continuation
                lock.unlock()
            }
        }
    }
}

private actor IdleOriginSource: TelemetrySource {
    nonisolated let origin: TelemetryOrigin

    init(origin: TelemetryOrigin) {
        self.origin = origin
    }

    func start() async throws -> AsyncStream<TelemetryReading> {
        let (stream, continuation) = AsyncStream.makeStream(of: TelemetryReading.self)
        continuation.finish()
        return stream
    }

    func stop() async {}
}
