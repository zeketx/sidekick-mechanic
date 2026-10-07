import XCTest

/// Taps launch arguments cannot reach: Garage sheet, sheet detents, scrim, composer typing.
///
/// Jobs (`chat.jobs`, `jobHistory.list`) and Scan log (`scanLog.grid`) are PR #114
/// and later. Those tests XCTSkip when the identifier is missing, the same way
/// Garage skipped before #111.
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
        try skipIfMissing(
            app,
            "chat.jobs",
            feature: "job-history",
            reason: "chat.jobs is PR #114 (later). This checkout has Garage, not Jobs / Scan log."
        )
        let jobs = element(app, "chat.jobs")
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
        try skipIfMissing(
            app,
            "chat.garage",
            feature: "onboarding",
            reason: "chat.garage is compiled with onboarding (#111). This checkout does not show Garage."
        )
        let garage = element(app, "chat.garage")
        garage.tap()
        XCTAssertTrue(element(app, "onboarding.garage").waitForExistence(timeout: 5))
        try writeShot("taps-garage.png")
        let done = app.buttons["garage.done"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
        }
    }

    func testSkipOnboardingIfPresent() throws {
        let app = launchApp(arguments: [
            "-resetOnboarding",
            "-screen", "onboarding-1",
        ])
        try skipIfMissing(
            app,
            "onboarding.welcome",
            feature: "onboarding",
            reason: "OnboardingFlow.swift is not in this checkout. Use -resetOnboarding after #111."
        )
        XCTAssertTrue(element(app, "onboarding.welcome").waitForExistence(timeout: 5))
        try writeShot("taps-onboarding-1.png")
        let skip = element(app, "onboarding.skip")
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "onboarding.skip is missing")
        skip.tap()
        XCTAssertTrue(element(app, "chat.composer").waitForExistence(timeout: 5), "Skip should land on chat")
        try writeShot("taps-onboarding-skip.png")
    }

    func testScanLogFromJobsHeader() throws {
        let app = launchApp(arguments: [
            "-screen", "job-history",
        ])
        try skipIfMissing(
            app,
            "jobHistory.list",
            feature: "scan-log",
            reason: "jobHistory.list / scanLog.grid are PR #114 (later). Skip until that screen is in the checkout."
        )
        let scanLog = element(app, "jobHistory.scanLog")
        XCTAssertTrue(scanLog.waitForExistence(timeout: 5), "jobHistory.scanLog is missing")
        scanLog.tap()
        XCTAssertTrue(element(app, "scanLog.grid").waitForExistence(timeout: 5))
        try writeShot("taps-scan-log.png")
    }

    func testRecordLayoutFrames() throws {
        let cases: [(String, [String], [String], Bool)] = [
            (
                "chat",
                ["-sidekick.onboarding.completed", "YES"],
                ["chat.composer", "chat.garage", "chat.send"],
                false
            ),
            (
                "job-history",
                ["-screen", "job-history"],
                ["jobHistory.list", "lookBack.back", "jobHistory.scanLog"],
                true
            ),
            (
                "job-sheet-collapsed",
                ["-screen", "job-sheet-collapsed", "-demoPhoto", "hilux"],
                ["jobSheet.collapsed", "jobSheet.handle", "jobSheet.title"],
                false
            ),
            (
                "job-sheet-half",
                ["-screen", "job-sheet-half", "-demoPhoto", "hilux"],
                ["jobSheet.half", "jobSheet.handle", "jobSheet.close", "jobSheet.dim"],
                false
            ),
            (
                "job-sheet-full",
                ["-screen", "job-sheet-full", "-demoPhoto", "hilux"],
                ["jobSheet.full", "jobSheet.handle", "jobSheet.close"],
                false
            ),
        ]
        var screens: [String: Any] = [:]
        for (name, arguments, identifiers, laterOnly) in cases {
            let app = launchApp(arguments: arguments)
            if laterOnly, !element(app, identifiers[0]).waitForExistence(timeout: 3) {
                screens[name] = [
                    "skipped": true,
                    "reason": "\(identifiers[0]) is not on this checkout (PR #114, later).",
                ]
                app.terminate()
                continue
            }
            screens[name] = try recordFrames(app, identifiers: identifiers, required: identifiers[0])
            app.terminate()
        }
        try writeJSON("layout-frames.json", ["screens": screens])
    }

    /// Every identifier SKILL.md documents for this checkout must be reachable.
    /// Later-only screens (Jobs / Scan log until #114) are recorded as skipped, not missing.
    func testIdentifierAudit() throws {
        let cases: [(String, [String], [String], Bool)] = [
            (
                "onboarding-1",
                ["-resetOnboarding", "-screen", "onboarding-1"],
                ["onboarding.welcome", "onboarding.skip", "onboarding.next"],
                false
            ),
            (
                "onboarding-2",
                ["-resetOnboarding", "-screen", "onboarding-2"],
                ["onboarding.howItWorks", "onboarding.skip", "onboarding.next"],
                false
            ),
            (
                "onboarding-3",
                ["-resetOnboarding", "-screen", "onboarding-3"],
                ["onboarding.garage", "onboarding.skip", "onboarding.start"],
                false
            ),
            (
                "chat",
                ["-sidekick.onboarding.completed", "YES"],
                ["chat.garage", "chat.composer", "chat.send", "chat.messageList"],
                false
            ),
            (
                "job-sheet-collapsed",
                ["-screen", "job-sheet-collapsed", "-demoPhoto", "hilux"],
                ["jobSheet.collapsed", "jobSheet.handle", "jobSheet.title", "jobSheet.peek", "jobSheet.open"],
                false
            ),
            (
                "job-sheet-half",
                ["-screen", "job-sheet-half", "-demoPhoto", "hilux"],
                [
                    "jobSheet.half", "jobSheet.handle", "jobSheet.title", "jobSheet.close", "jobSheet.dim",
                    "jobSheet.body", "jobSheet.answer", "jobSheet.photo", "jobSheet.chips", "jobSheet.steps",
                    "jobSheet.outcome", "jobSheet.outcome.worked", "jobSheet.outcome.partly", "jobSheet.outcome.didnt",
                ],
                false
            ),
            (
                "job-sheet-full",
                ["-screen", "job-sheet-full", "-demoPhoto", "hilux"],
                [
                    "jobSheet.full", "jobSheet.handle", "jobSheet.title", "jobSheet.close",
                    "jobSheet.body", "jobSheet.notes", "jobSheet.tags", "jobSheet.tags.add",
                    "jobSheet.outcome", "jobSheet.outcome.worked", "jobSheet.outcome.partly",
                    "jobSheet.outcome.didnt", "jobSheet.whatFixed",
                ],
                false
            ),
            (
                "highlight-confident",
                ["-screen", "highlight-confident", "-demoPhoto", "hilux"],
                ["highlightViewer", "highlightViewer.close", "highlightViewer.photo"],
                false
            ),
            (
                "job-history",
                ["-screen", "job-history"],
                ["jobHistory.list", "lookBack.back", "jobHistory.scanLog", "jobHistory.row.cold-idle"],
                true
            ),
            (
                "scan-log",
                ["-screen", "scan-log"],
                ["scanLog.grid", "lookBack.back", "scanLog.cell.scan-log-0"],
                true
            ),
        ]
        var report: [String: Any] = [:]
        var allMissing: [String] = []
        for (name, arguments, identifiers, laterOnly) in cases {
            let app = launchApp(arguments: arguments)
            if laterOnly, !element(app, identifiers[0]).waitForExistence(timeout: 3) {
                report[name] = [
                    "skipped": true,
                    "reason": "\(identifiers[0]) is not on this checkout (PR #114, later).",
                ]
                app.terminate()
                continue
            }
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
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 2) {
            XCTAssertLessThanOrEqual(
                composer.frame.maxY,
                keyboard.frame.minY + 2,
                "Keyboard covers the composer. Overlay must ignore .container only, not .keyboard."
            )
        }
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

    /// XCTSkip later-only screens the way Garage skipped before #111.
    private func skipIfMissing(
        _ app: XCUIApplication,
        _ identifier: String,
        feature: String,
        reason: String
    ) throws {
        if element(app, identifier).waitForExistence(timeout: 3) {
            return
        }
        try writeSkip("\(feature)-unmet.json", feature: feature, reason: reason)
        throw XCTSkip(reason)
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
        // Skip first-run onboarding unless a test opts in with -resetOnboarding.
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
