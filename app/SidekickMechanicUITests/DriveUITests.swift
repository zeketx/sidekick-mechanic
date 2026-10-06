import XCTest

/// Taps launch arguments cannot reach: Jobs, a history row, sheet detents, scrim.
///
/// Garage (`chat.garage`) lives on PR #111. This stack has Jobs / Scan log instead;
/// `testOpenGarageIfPresent` records that skip instead of inventing a button.
///
/// The helper writes the evidence directory to
/// `/tmp/sidekick-verify-sidekick/evidence-path` before `xcodebuild test`.
///
/// `testRecordLayoutFrames` and `testComposerStaysPillWhenMultiline` write element
/// frames (points) to `layout-*.json` so `design_checks.py` can measure the sheet
/// inset, the composer pill and the nav buttons from the screenshots.
final class DriveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpenJobsThenColdIdleRow() throws {
        let app = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
        ])
        let jobs = element(app, "chat.jobs")
        XCTAssertTrue(jobs.waitForExistence(timeout: 8), "chat.jobs is missing")
        jobs.tap()

        let list = element(app, "jobHistory.list")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jobs"].exists, "Jobs title missing on the history screen")
        try writeShot("taps-jobs-list.png")

        let row = element(app, "jobHistory.row.cold-idle")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let half = element(app, "jobSheet.half")
        XCTAssertTrue(half.waitForExistence(timeout: 5), "Cold idle row should open the job sheet at half")
        XCTAssertTrue(element(app, "jobSheet.title").exists)
        try writeShot("taps-job-row-opened.png")
    }

    func testDragSheetCollapsedToHalf() throws {
        let app = launchApp(arguments: [
            "-screen", "job-sheet-collapsed",
            "-demoPhoto", "hilux",
        ])
        let collapsed = element(app, "jobSheet.collapsed")
        XCTAssertTrue(collapsed.waitForExistence(timeout: 8))

        let handle = element(app, "jobSheet.handle")
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "jobSheet.handle is missing")
        try writeShot("taps-sheet-before-drag.png")
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -220))
        start.press(forDuration: 0.15, thenDragTo: end)

        let half = element(app, "jobSheet.half")
        XCTAssertTrue(half.waitForExistence(timeout: 5), "Dragging the handle up should move collapsed → half")
        try writeShot("taps-sheet-after-drag.png")
    }

    func testTapScrimCollapsesHalfSheet() throws {
        let app = launchApp(arguments: [
            "-screen", "job-sheet-half",
            "-demoPhoto", "hilux",
        ])
        let half = element(app, "jobSheet.half")
        XCTAssertTrue(half.waitForExistence(timeout: 8))

        let scrim = element(app, "jobSheet.dim")
        XCTAssertTrue(scrim.waitForExistence(timeout: 5), "jobSheet.dim should be hittable at half")
        try writeShot("taps-sheet-before-scrim.png")
        scrim.tap()

        let collapsed = element(app, "jobSheet.collapsed")
        XCTAssertTrue(collapsed.waitForExistence(timeout: 5), "Tapping the scrim should collapse the sheet")
        try writeShot("taps-sheet-after-scrim.png")
    }

    func testOpenGarageIfPresent() throws {
        let app = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
        ])
        let garage = element(app, "chat.garage")
        if !garage.waitForExistence(timeout: 3) {
            try writeSkip(
                "garage-unmet.json",
                feature: "onboarding",
                reason: "chat.garage is compiled on PR #111 (cursor/v1-onboarding-5c2a), not this stack. Jobs is chat.jobs."
            )
            throw XCTSkip("Garage sheet is not on this branch. Use -screen job-history or merge #111.")
        }
        garage.tap()
        XCTAssertTrue(element(app, "onboarding.garage").waitForExistence(timeout: 5))
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
        let list = element(app, "jobHistory.list")
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let scanLog = element(app, "jobHistory.scanLog")
        XCTAssertTrue(scanLog.waitForExistence(timeout: 5), "jobHistory.scanLog is missing")
        scanLog.tap()
        XCTAssertTrue(element(app, "scanLog.grid").waitForExistence(timeout: 5))
        try writeShot("taps-scan-log.png")
    }

    func testRecordLayoutFrames() throws {
        let cases: [(String, [String], [String])] = [
            (
                "chat",
                ["-sidekick.onboarding.completed", "YES"],
                ["chat.composer", "chat.jobs", "chat.scanLog", "chat.send"]
            ),
            ("job-history", ["-screen", "job-history"], ["jobHistory.list", "lookBack.back", "jobHistory.scanLog"]),
            (
                "job-sheet-collapsed",
                ["-screen", "job-sheet-collapsed", "-demoPhoto", "hilux"],
                ["jobSheet.collapsed", "jobSheet.handle", "jobSheet.title"]
            ),
            (
                "job-sheet-half",
                ["-screen", "job-sheet-half", "-demoPhoto", "hilux"],
                ["jobSheet.half", "jobSheet.handle", "jobSheet.close", "jobSheet.dim"]
            ),
            (
                "job-sheet-full",
                ["-screen", "job-sheet-full", "-demoPhoto", "hilux"],
                ["jobSheet.full", "jobSheet.handle", "jobSheet.close"]
            ),
        ]
        var screens: [String: Any] = [:]
        for (name, arguments, identifiers) in cases {
            let app = launchApp(arguments: arguments)
            screens[name] = try recordFrames(app, identifiers: identifiers, required: identifiers[0])
            app.terminate()
        }
        try writeJSON("layout-frames.json", ["screens": screens])
    }

    /// Every identifier SKILL.md documents must be reachable. Writes identifiers.json with
    /// found / missing per screen so a stale map or a container identifier that swallows its
    /// children shows up as evidence, not as a mystery tap failure.
    func testIdentifierAudit() throws {
        let cases: [(String, [String], [String])] = [
            (
                "chat",
                ["-sidekick.onboarding.completed", "YES"],
                ["chat.jobs", "chat.scanLog", "chat.composer", "chat.send", "chat.messageList"]
            ),
            (
                "job-sheet-collapsed",
                ["-screen", "job-sheet-collapsed", "-demoPhoto", "hilux"],
                ["jobSheet.collapsed", "jobSheet.handle", "jobSheet.title", "jobSheet.peek", "jobSheet.open"]
            ),
            (
                "job-sheet-half",
                ["-screen", "job-sheet-half", "-demoPhoto", "hilux"],
                [
                    "jobSheet.half", "jobSheet.handle", "jobSheet.title", "jobSheet.close", "jobSheet.dim",
                    "jobSheet.body", "jobSheet.answer", "jobSheet.photo", "jobSheet.chips", "jobSheet.steps",
                    "jobSheet.outcome", "jobSheet.outcome.worked", "jobSheet.outcome.partly", "jobSheet.outcome.didnt",
                ]
            ),
            (
                "highlight-confident",
                ["-screen", "highlight-confident", "-demoPhoto", "hilux"],
                ["highlightViewer", "highlightViewer.close", "highlightViewer.photo"]
            ),
            (
                "job-history",
                ["-screen", "job-history"],
                ["jobHistory.list", "lookBack.back", "jobHistory.scanLog", "jobHistory.row.cold-idle"]
            ),
            ("scan-log", ["-screen", "scan-log"], ["scanLog.grid", "lookBack.back", "scanLog.cell.scan-log-0"]),
        ]
        var report: [String: Any] = [:]
        var allMissing: [String] = []
        for (name, arguments, identifiers) in cases {
            let app = launchApp(arguments: arguments)
            _ = element(app, identifiers[0]).waitForExistence(timeout: 8)
            var found: [String] = []
            var missing: [String] = []
            for identifier in identifiers {
                if element(app, identifier).waitForExistence(timeout: 1.5) {
                    found.append(identifier)
                } else {
                    missing.append(identifier)
                    allMissing.append("\(name): \(identifier)")
                }
            }
            report[name] = ["found": found, "missing": missing]
            app.terminate()
        }
        try writeJSON("identifiers.json", ["screens": report])
        XCTAssertTrue(allMissing.isEmpty, "Documented identifiers missing: \(allMissing.joined(separator: ", "))")
    }

    func testComposerStaysPillWhenMultiline() throws {
        let app = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
        ])
        let composer = element(app, "chat.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 8), "chat.composer is missing")
        composer.tap()
        composer.typeText(
            "Engine cranks but will not start after sitting overnight. "
                + "Battery is new and the fuel pump primes when I turn the key to on."
        )
        // Let the vertical TextField grow to its wrapped height before measuring.
        Thread.sleep(forTimeInterval: 0.6)
        try writeShot("taps-composer-multiline.png")
        let frames = try recordFrames(app, identifiers: ["chat.composer", "chat.send"], required: "chat.composer")
        try writeJSON("layout-composer-multiline.json", ["screens": ["chat-multiline": frames]])
    }

    /// First element with this identifier, any type. An identifier on a SwiftUI container without
    /// `.accessibilityElement(children: .contain)` overwrites every child identifier (that is why
    /// chat.jobs, jobSheet.handle and jobHistory.scanLog went missing). With `.contain` a plain
    /// VStack container may not appear at all, so tests target leaf identifiers.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func recordFrames(
        _ app: XCUIApplication,
        identifiers: [String],
        required: String
    ) throws -> [String: Any] {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(element(app, required).waitForExistence(timeout: 8), "\(required) is missing")
        var elements: [String: Any] = [:]
        for identifier in identifiers {
            let match = element(app, identifier)
            if match.waitForExistence(timeout: 3) {
                elements[identifier] = rect(match.frame)
            }
        }
        return ["window": rect(window.frame), "elements": elements]
    }

    private func rect(_ frame: CGRect) -> [Double] {
        [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height].map { Double($0) }
    }

    private func writeJSON(_ name: String, _ payload: [String: Any]) throws {
        let directory = try evidenceDirectory()
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Skip first-run onboarding on stacks that have it (#111) unless a test opts in.
        let onboarding = arguments.contains("-resetOnboarding") || arguments.contains("-sidekick.onboarding.completed")
        app.launchArguments = onboarding ? arguments : arguments + ["-sidekick.onboarding.completed", "YES"]
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
