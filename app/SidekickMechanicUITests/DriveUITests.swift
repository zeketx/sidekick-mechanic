import XCTest

/// Taps launch arguments cannot reach: Jobs, a history row, sheet detents, scrim.
///
/// Garage (`chat.garage`) lives on PR #111. This stack has Jobs / Scan log instead;
/// `testOpenGarageIfPresent` records that skip instead of inventing a button.
///
/// The helper writes the evidence directory to
/// `/tmp/sidekick-verify-sidekick/evidence-path` before `xcodebuild test`.
final class DriveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpenJobsThenColdIdleRow() throws {
        let app = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
        ])
        let jobs = app.buttons["chat.jobs"]
        XCTAssertTrue(jobs.waitForExistence(timeout: 8), "chat.jobs is missing")
        jobs.tap()

        let list = app.descendants(matching: .any)["jobHistory.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jobs"].exists)
        try writeShot("taps-jobs-list.png")

        let row = app.descendants(matching: .any)["jobHistory.row.cold-idle"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let half = app.descendants(matching: .any)["jobSheet.half"]
        XCTAssertTrue(half.waitForExistence(timeout: 5), "Cold idle row should open the job sheet at half")
        XCTAssertTrue(app.descendants(matching: .any)["jobSheet.title"].exists)
        try writeShot("taps-job-row-opened.png")
    }

    func testDragSheetCollapsedToHalf() throws {
        let app = launchApp(arguments: [
            "-screen", "job-sheet-collapsed",
            "-demoPhoto", "hilux",
        ])
        let collapsed = app.descendants(matching: .any)["jobSheet.collapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 8))

        let handle = app.descendants(matching: .any)["jobSheet.handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -220))
        start.press(forDuration: 0.15, thenDragTo: end)

        let half = app.descendants(matching: .any)["jobSheet.half"]
        XCTAssertTrue(half.waitForExistence(timeout: 5), "Dragging the handle up should move collapsed → half")
        try writeShot("taps-sheet-after-drag.png")
    }

    func testTapScrimCollapsesHalfSheet() throws {
        let app = launchApp(arguments: [
            "-screen", "job-sheet-half",
            "-demoPhoto", "hilux",
        ])
        let half = app.descendants(matching: .any)["jobSheet.half"]
        XCTAssertTrue(half.waitForExistence(timeout: 8))

        let scrim = app.descendants(matching: .any)["jobSheet.dim"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 5), "jobSheet.dim should be hittable at half")
        scrim.tap()

        let collapsed = app.descendants(matching: .any)["jobSheet.collapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 5), "Tapping the scrim should collapse the sheet")
        try writeShot("taps-sheet-after-scrim.png")
    }

    func testOpenGarageIfPresent() throws {
        let app = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
        ])
        let garage = app.descendants(matching: .any)["chat.garage"]
        if !garage.waitForExistence(timeout: 3) {
            try writeSkip(
                "garage-unmet.json",
                feature: "onboarding",
                reason: "chat.garage is compiled on PR #111 (cursor/v1-onboarding-5c2a), not this stack. Jobs is chat.jobs."
            )
            throw XCTSkip("Garage sheet is not on this branch. Use -screen job-history or merge #111.")
        }
        garage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.garage"].waitForExistence(timeout: 5))
        try writeShot("taps-garage.png")
        let done = app.buttons["garage.done"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
        }
    }

    func testScanLogFromJobsHeader() throws {
        let app = launchApp(arguments: [
            "-screen", "job-history",
        ])
        let list = app.descendants(matching: .any)["jobHistory.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let scanLog = app.descendants(matching: .any)["jobHistory.scanLog"]
        XCTAssertTrue(scanLog.waitForExistence(timeout: 5))
        scanLog.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanLog.grid"].waitForExistence(timeout: 5))
        try writeShot("taps-scan-log.png")
    }

    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func writeShot(_ name: String) throws {
        let directory = try evidenceDirectory()
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func writeSkip(_ name: String, feature: String, reason: String) throws {
        let directory = try evidenceDirectory()
        let payload: [String: String] = [
            "feature_id": feature,
            "result": "skipped",
            "reason": reason,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func evidenceDirectory() throws -> URL {
        let pointer = URL(fileURLWithPath: "/tmp/sidekick-verify-sidekick/evidence-path")
        let path = try String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
