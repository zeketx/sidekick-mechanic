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

    func testOpenCitationFromJobChip() throws {
        let app = launchApp(arguments: [
            "-screen", "job-sheet-half",
            "-demoPhoto", "hilux",
        ])
        XCTAssertTrue(element(app, "jobSheet.half").waitForExistence(timeout: 8))
        let chip = element(app, "jobSheet.chip.0")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "jobSheet.chip.0 is missing")
        chip.tap()

        XCTAssertTrue(element(app, "citation.viewer").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "citation.goDeeper").waitForExistence(timeout: 5))
        try writeShot("taps-citation-page.png")
        element(app, "citation.close").tap()

        XCTAssertTrue(
            element(app, "jobSheet.half").waitForExistence(timeout: 5),
            "Close should return to the job sheet"
        )
        XCTAssertTrue(element(app, "jobSheet.chip.0").waitForExistence(timeout: 5))
        try writeShot("taps-citation-closed.png")
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
        assertHeaderClearsTopSafeArea(app, screen: "job-sheet-half")
        XCTAssertGreaterThan(
            half.frame.minY,
            300,
            "Default half sheet should stay a half sheet, not grow to the island. minY \(half.frame.minY)"
        )
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
                [
                    "jobSheet.full", "jobSheet.handle", "jobSheet.close",
                    "jobSheet.outcome.worked", "jobSheet.outcome.partly", "jobSheet.outcome.didnt",
                ],
                false
            ),
            (
                "job-sheet-closeout",
                ["-screen", "job-sheet-closeout", "-demoPhoto", "hilux"],
                [
                    "jobSheet.half", "jobSheet.handle", "jobSheet.close",
                    "jobSheet.outcome.worked", "jobSheet.outcome.partly", "jobSheet.outcome.didnt",
                ],
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
                ["onboarding.welcome", "onboarding.title", "onboarding.skip", "onboarding.next"],
                false
            ),
            (
                "onboarding-2",
                ["-resetOnboarding", "-screen", "onboarding-2"],
                ["onboarding.howItWorks", "onboarding.title", "onboarding.skip", "onboarding.next"],
                false
            ),
            (
                "onboarding-3",
                ["-resetOnboarding", "-screen", "onboarding-3"],
                ["onboarding.garage", "onboarding.title", "onboarding.skip", "onboarding.start"],
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
                    "jobSheet.body", "jobSheet.answer", "jobSheet.photo", "jobSheet.chips", "jobSheet.chip.0",
                    "jobSheet.steps",
                    "jobSheet.step.2",
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
                    "jobSheet.howDidItGo", "jobSheet.outcome", "jobSheet.outcome.worked",
                    "jobSheet.outcome.partly", "jobSheet.outcome.didnt", "jobSheet.whatFixed",
                ],
                false
            ),
            (
                "job-sheet-closeout",
                ["-screen", "job-sheet-closeout", "-demoPhoto", "hilux"],
                [
                    "jobSheet.half", "jobSheet.handle", "jobSheet.title", "jobSheet.close",
                    "jobSheet.outcome", "jobSheet.outcome.worked", "jobSheet.outcome.partly",
                    "jobSheet.outcome.didnt",
                ],
                false
            ),
            (
                "citation-page",
                ["-screen", "citation-page", "-demoPhoto", "hilux"],
                [
                    "citation.viewer", "citation.close", "citation.title", "citation.goDeeper",
                    "citation.pageImage", "citation.document", "jobSheet.half",
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

    /// Accessibility XXXL on every main screen. Fit violations are collected for every
    /// screen, then asserted once, so `layout-axxxl.json` still has full, closeout, and citation.
    func testAccessibilityXXXLHeaderAndHalfSheet() throws {
        continueAfterFailure = true
        var screens: [String: Any] = [:]
        var fitFailures: [String] = []

        let chat = launchAXXXL([
            "-sidekick.onboarding.completed", "YES",
        ])
        let garage = element(chat, "chat.garage")
        XCTAssertTrue(garage.waitForExistence(timeout: 8), "chat.garage is missing at Accessibility XXXL")
        XCTAssertTrue(garage.isHittable, "Garage must stay hittable at Accessibility XXXL")
        let title = element(chat, "chat.title")
        if title.waitForExistence(timeout: 1) {
            XCTAssertFalse(
                garage.frame.intersects(title.frame),
                "Garage overlaps Sidekick at Accessibility XXXL: \(garage.frame) vs \(title.frame)"
            )
        }
        try keepAXXXL("chat", chat, into: &screens, failures: &fitFailures)
        chat.terminate()

        let onboarding: [(String, String, String)] = [
            ("onboarding-1", "onboarding.welcome", "onboarding.next"),
            ("onboarding-2", "onboarding.howItWorks", "onboarding.next"),
            ("onboarding-3", "onboarding.garage", "onboarding.start"),
        ]
        for (name, root, nextID) in onboarding {
            let app = launchAXXXL(["-resetOnboarding", "-screen", name])
            XCTAssertTrue(element(app, root).waitForExistence(timeout: 8), "\(root) missing at Accessibility XXXL")
            assertControlInsideWindow(app, "onboarding.skip", screen: name)
            assertControlInsideWindow(app, nextID, screen: name)
            try keepAXXXL(name, app, into: &screens, failures: &fitFailures)
            app.terminate()
        }

        let app = launchAXXXL([
            "-screen", "job-sheet-half",
            "-demoPhoto", "hilux",
        ])
        let sheet = element(app, "jobSheet.half")
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "jobSheet.half is missing at Accessibility XXXL")
        let step = element(app, "jobSheet.step.2")
        XCTAssertTrue(step.waitForExistence(timeout: 5), "jobSheet.step.2 is missing at Accessibility XXXL")
        let outcome = element(app, "jobSheet.outcome")
        XCTAssertTrue(outcome.waitForExistence(timeout: 3))
        let body = element(app, "jobSheet.body")
        for _ in 0..<8 {
            if stepFullyVisible(step, in: sheet, above: outcome) {
                break
            }
            if body.exists {
                body.swipeUp()
            } else {
                sheet.swipeUp()
            }
        }
        XCTAssertTrue(
            stepFullyVisible(step, in: sheet, above: outcome),
            "jobSheet.step.2 is clipped at Accessibility XXXL even after scrolling. "
                + "step \(step.frame) sheet \(sheet.frame) outcome \(outcome.frame)"
        )
        let worked = element(app, "jobSheet.outcome.worked")
        XCTAssertTrue(worked.waitForExistence(timeout: 3), "Worked is missing at Accessibility XXXL")
        XCTAssertTrue(worked.isHittable, "Worked must be tappable at Accessibility XXXL")
        XCTAssertGreaterThan(
            worked.frame.width,
            160,
            "Worked is truncated at Accessibility XXXL (width \(worked.frame.width))"
        )
        assertHeaderClearsTopSafeArea(app, screen: "job-sheet-half axxxl")
        assertHalfSheetLeavesChatSliver(app, sheetID: "jobSheet.half", screen: "job-sheet-half axxxl")
        assertControlInsideWindow(app, "jobSheet.close", screen: "job-sheet-half")
        assertControlInsideWindow(app, "jobSheet.outcome.worked", screen: "job-sheet-half")
        try keepAXXXL("job-sheet-half", app, into: &screens, failures: &fitFailures)
        app.terminate()

        let full = launchAXXXL([
            "-screen", "job-sheet-full",
            "-demoPhoto", "hilux",
        ])
        XCTAssertTrue(element(full, "jobSheet.full").waitForExistence(timeout: 8), "jobSheet.full is missing at Accessibility XXXL")
        assertHeaderClearsTopSafeArea(full, screen: "job-sheet-full axxxl")
        scrollUntilOnScreen(full, id: "jobSheet.outcome.worked", containerID: "jobSheet.body")
        XCTAssertTrue(element(full, "jobSheet.outcome.worked").isHittable, "Worked must be tappable on the full sheet at Accessibility XXXL")
        assertControlInsideWindow(full, "jobSheet.close", screen: "job-sheet-full")
        assertControlInsideWindow(full, "jobSheet.outcome.worked", screen: "job-sheet-full")
        try keepAXXXL("job-sheet-full", full, into: &screens, failures: &fitFailures)
        full.terminate()

        let closeout = launchAXXXL([
            "-screen", "job-sheet-closeout",
            "-demoPhoto", "hilux",
        ])
        let closeoutSheet = element(closeout, "jobSheet.half")
        XCTAssertTrue(
            closeoutSheet.waitForExistence(timeout: 8),
            "job-sheet-closeout is missing at Accessibility XXXL"
        )
        assertHeaderClearsTopSafeArea(closeout, screen: "job-sheet-closeout axxxl")
        assertHalfSheetLeavesChatSliver(
            closeout,
            sheetID: "jobSheet.half",
            screen: "job-sheet-closeout axxxl"
        )
        assertControlInsideWindow(closeout, "jobSheet.outcome.worked", screen: "job-sheet-closeout")
        try keepAXXXL("job-sheet-closeout", closeout, into: &screens, failures: &fitFailures)
        closeout.terminate()

        let defaultCitation = launchApp(arguments: [
            "-screen", "citation-page",
            "-demoPhoto", "hilux",
        ])
        XCTAssertTrue(
            element(defaultCitation, "citation.viewer").waitForExistence(timeout: 8),
            "citation.viewer is missing at default size"
        )
        let defaultDoc = element(defaultCitation, "citation.document")
        XCTAssertTrue(defaultDoc.waitForExistence(timeout: 5), "citation.document is missing at default size")
        let defaultDocHeight = defaultDoc.frame.height
        defaultCitation.terminate()

        let citation = launchAXXXL([
            "-screen", "citation-page",
            "-demoPhoto", "hilux",
        ])
        XCTAssertTrue(
            element(citation, "citation.viewer").waitForExistence(timeout: 8),
            "citation.viewer is missing at Accessibility XXXL"
        )
        assertCitationHeaderAtAccessibilitySize(
            citation,
            defaultDocumentHeight: defaultDocHeight,
            screen: "citation-page axxxl"
        )
        scrollUntilOnScreen(citation, id: "citation.goDeeper", containerID: "citation.viewer")
        let deeper = element(citation, "citation.goDeeper")
        XCTAssertTrue(deeper.waitForExistence(timeout: 3), "citation.goDeeper is missing at Accessibility XXXL")
        XCTAssertLessThan(
            deeper.frame.minY,
            citation.windows.firstMatch.frame.maxY - 20,
            "Go deeper is below the citation sheet at Accessibility XXXL"
        )
        assertControlInsideWindow(citation, "citation.close", screen: "citation-page")
        try keepAXXXL("citation-page", citation, into: &screens, failures: &fitFailures)
        citation.terminate()

        try recordAXXXLIfPresent(
            "job-history",
            arguments: ["-screen", "job-history"],
            required: "jobHistory.list",
            controls: ["lookBack.back", "jobHistory.scanLog"],
            into: &screens,
            failures: &fitFailures
        )
        try recordAXXXLIfPresent(
            "scan-log",
            arguments: ["-screen", "scan-log"],
            required: "scanLog.grid",
            controls: ["lookBack.back"],
            into: &screens,
            failures: &fitFailures
        )

        XCTAssertTrue(
            fitFailures.isEmpty,
            "Accessibility XXXL fit:\n\(fitFailures.joined(separator: "\n"))"
        )
    }

    private func assertCitationHeaderAtAccessibilitySize(
        _ app: XCUIApplication,
        defaultDocumentHeight: CGFloat,
        screen: String
    ) {
        let inset = topSafeAreaInset(app)
        XCTAssertFalse(
            element(app, "citation.title").waitForExistence(timeout: 1),
            "\(screen): Manual page title should be hidden at Accessibility XXXL"
        )
        let close = element(app, "citation.close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "\(screen): citation.close is missing")
        XCTAssertGreaterThanOrEqual(
            close.frame.minY,
            inset,
            "\(screen): Close minY \(close.frame.minY) sits under the status bar / island (safe area \(inset))"
        )
        XCTAssertTrue(close.isHittable, "\(screen): Close must stay hittable at Accessibility XXXL")
        let document = element(app, "citation.document")
        XCTAssertTrue(document.waitForExistence(timeout: 5), "\(screen): citation.document is missing")
        XCTAssertTrue(document.isHittable, "\(screen): document name must stay visible at Accessibility XXXL")
        XCTAssertGreaterThan(
            document.frame.height,
            defaultDocumentHeight,
            "\(screen): citation.document height \(document.frame.height) did not grow vs default \(defaultDocumentHeight); launch-arg Dynamic Type may not have reached the sheet"
        )
        let pageNumber = element(app, "citation.pageNumber")
        XCTAssertTrue(pageNumber.waitForExistence(timeout: 3), "\(screen): citation.pageNumber is missing")
    }

    private func stepFullyVisible(
        _ step: XCUIElement,
        in sheet: XCUIElement,
        above outcome: XCUIElement
    ) -> Bool {
        let stepFrame = step.frame
        let sheetFrame = sheet.frame
        let limitY = outcome.exists ? outcome.frame.minY : sheetFrame.maxY
        return stepFrame.minY >= sheetFrame.minY - 4
            && stepFrame.maxY <= limitY + 4
            && stepFrame.height >= 48
    }

    /// Status-bar / Dynamic Island band. XCTest does not expose window safeAreaInsets.
    private func topSafeAreaInset(_ app: XCUIApplication) -> CGFloat {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let statusBar = app.statusBars.firstMatch
        if statusBar.exists {
            let fromBar = statusBar.frame.maxY - window.frame.minY
            if fromBar >= 44 {
                return fromBar
            }
        }
        return 59
    }

    private func assertHeaderClearsTopSafeArea(_ app: XCUIApplication, screen: String) {
        let inset = topSafeAreaInset(app)
        let title = element(app, "jobSheet.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "\(screen): jobSheet.title is missing")
        XCTAssertGreaterThanOrEqual(
            title.frame.minY,
            inset,
            "\(screen): title minY \(title.frame.minY) sits under the status bar / island (safe area \(inset))"
        )
        let close = element(app, "jobSheet.close")
        XCTAssertTrue(close.waitForExistence(timeout: 3), "\(screen): jobSheet.close is missing")
        XCTAssertGreaterThanOrEqual(
            close.frame.minY,
            inset,
            "\(screen): Close minY \(close.frame.minY) sits under the status bar / island (safe area \(inset))"
        )
    }

    /// Accessibility half / closeout stay below the island with a real strip of dimmed chat.
    private func assertHalfSheetLeavesChatSliver(
        _ app: XCUIApplication,
        sheetID: String,
        screen: String
    ) {
        let window = app.windows.firstMatch
        let inset = topSafeAreaInset(app)
        let sheet = element(app, sheetID)
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "\(screen): \(sheetID) is missing")
        let minGap = inset + 24
        XCTAssertGreaterThanOrEqual(
            sheet.frame.minY,
            minGap,
            "\(screen): sheet minY \(sheet.frame.minY) does not leave a chat sliver below the island (need >= \(minGap))"
        )
        XCTAssertLessThan(
            sheet.frame.minY,
            window.frame.height * 0.45,
            "\(screen): accessibility half should still grow; sheet minY \(sheet.frame.minY)"
        )
        XCTAssertTrue(
            element(app, "jobSheet.dim").waitForExistence(timeout: 2),
            "\(screen): scrim should still show so this reads as a sheet over chat"
        )
        let garage = element(app, "chat.garage")
        XCTAssertTrue(
            garage.waitForExistence(timeout: 3),
            "\(screen): chat.garage should peek above the sheet"
        )
        XCTAssertLessThan(
            garage.frame.minY,
            sheet.frame.minY,
            "\(screen): Garage minY \(garage.frame.minY) is not above the sheet (\(sheet.frame.minY))"
        )
    }

    func testSelectedOutcomeIsFilledOnFullAndCloseout() throws {
        for screen in ["job-sheet-full", "job-sheet-closeout"] {
            let app = launchApp(arguments: [
                "-screen", screen,
                "-demoPhoto", "hilux",
            ])
            let worked = element(app, "jobSheet.outcome.worked")
            XCTAssertTrue(
                worked.waitForExistence(timeout: 8),
                "\(screen): jobSheet.outcome.worked is missing"
            )
            XCTAssertTrue(
                worked.isSelected,
                "\(screen): Worked must be selected so the segment renders filled"
            )
            let partly = element(app, "jobSheet.outcome.partly")
            XCTAssertTrue(partly.waitForExistence(timeout: 2))
            XCTAssertFalse(partly.isSelected, "\(screen): Partly should not be selected")
            let didnt = element(app, "jobSheet.outcome.didnt")
            XCTAssertTrue(didnt.waitForExistence(timeout: 2))
            XCTAssertFalse(didnt.isSelected, "\(screen): Didn't should not be selected")
            assertHeaderClearsTopSafeArea(app, screen: screen)
            if screen == "job-sheet-closeout" {
                let sheet = element(app, "jobSheet.half")
                XCTAssertGreaterThan(
                    sheet.frame.minY,
                    300,
                    "\(screen): default closeout should stay half height. minY \(sheet.frame.minY)"
                )
            }
            try writeShot("taps-\(screen)-outcome.png")
            app.terminate()
        }
    }

    /// New screen tests call this at Accessibility XXXL. Thresholds match
    /// `measure_axxxl` in `design_checks.py` (see docs/DYNAMIC_TYPE.md).
    @discardableResult
    func assertFitsOnScreen(
        _ app: XCUIApplication,
        screen: String = "screen",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String: Any] {
        let fit = measureScreenFit(app, screen: screen)
        assertScreenFit(fit, screen: screen, file: file, line: line)
        return fit.payload
    }

    private func launchAXXXL(_ arguments: [String]) -> XCUIApplication {
        var args = arguments
        if !args.contains("-dynamicTypeSize") {
            args += ["-dynamicTypeSize", "accessibility5"]
        }
        return launchApp(arguments: args)
    }

    private func keepAXXXL(
        _ name: String,
        _ app: XCUIApplication,
        into screens: inout [String: Any],
        failures: inout [String]
    ) throws {
        let fit = measureScreenFit(app, screen: name)
        screens[name] = fit.payload
        try writeJSON("layout-axxxl.json", ["screens": screens])
        try writeShot("taps-\(name)-axxxl.png")
        failures.append(contentsOf: fit.reasons.map { "\(name): \($0)" })
    }

    private func recordAXXXLIfPresent(
        _ name: String,
        arguments: [String],
        required: String,
        controls: [String],
        into screens: inout [String: Any],
        failures: inout [String]
    ) throws {
        let app = launchAXXXL(arguments)
        if !element(app, required).waitForExistence(timeout: 3) {
            screens[name] = [
                "skipped": true,
                "reason": "\(required) is not on this checkout (PR #114, later).",
            ]
            try writeJSON("layout-axxxl.json", ["screens": screens])
            app.terminate()
            return
        }
        for control in controls {
            assertControlInsideWindow(app, control, screen: name)
        }
        try keepAXXXL(name, app, into: &screens, failures: &failures)
        app.terminate()
    }

    private func scrollUntilOnScreen(_ app: XCUIApplication, id: String, containerID: String) {
        let target = element(app, id)
        let container = element(app, containerID)
        let window = app.windows.firstMatch.frame
        for _ in 0..<10 {
            if target.exists, target.frame.minY < window.maxY - 20, target.frame.maxY > window.minY + 20 {
                return
            }
            if container.exists {
                container.swipeUp()
            } else {
                app.swipeUp()
            }
        }
    }

    private func assertControlInsideWindow(
        _ app: XCUIApplication,
        _ identifier: String,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch.frame
        let control = element(app, identifier)
        XCTAssertTrue(control.waitForExistence(timeout: 5), "\(screen): \(identifier) missing", file: file, line: line)
        let frame = control.frame
        let inset = topSafeAreaInset(app)
        XCTAssertGreaterThanOrEqual(
            frame.minX, window.minX - 2,
            "\(screen): \(identifier) minX \(frame.minX) is off the left edge",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxX, window.maxX + 2,
            "\(screen): \(identifier) maxX \(frame.maxX) is off the right edge",
            file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(
            frame.minY, inset - 2,
            "\(screen): \(identifier) minY \(frame.minY) is under the status bar / island (\(inset))",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxY, window.maxY + 2,
            "\(screen): \(identifier) maxY \(frame.maxY) is below the screen",
            file: file, line: line
        )
    }

    private struct ScreenFit {
        var payload: [String: Any]
        var reasons: [String]
    }

    private struct Viewport {
        var id: String
        var frame: CGRect
    }

    private struct FittedControl {
        var id: String
        var label: String
        var type: String
        var frame: CGRect
        var inStatusBar: Bool
        var hittable: Bool
        var islandExempt = false

        var describe: String {
            let name = id.isEmpty ? label : id
            return "\(type) \(name) \(frame)"
        }
    }

    /// Geometry shared with `design_checks.measure_axxxl`. Off-screen scroll content and
    /// chat behind the scrim are not measured. A label of "Today" that draws as "Tod…"
    /// still fails only when the accessibility label contains an ellipsis or the frame
    /// is a narrow column. Screenshot review covers the rest.
    private func measureScreenFit(_ app: XCUIApplication, screen: String) -> ScreenFit {
        let windowElement = app.windows.firstMatch
        guard windowElement.waitForExistence(timeout: 8) else {
            return ScreenFit(payload: ["screen": screen, "error": "window missing"], reasons: ["\(screen): window missing"])
        }
        let window = windowElement.frame
        let inset = topSafeAreaInset(app)
        let status = app.statusBars.firstMatch
        let statusFrame = status.exists ? status.frame : CGRect.null
        let controls = fittedControls(app, window: window, statusBar: statusFrame)
        let dimmed = element(app, "jobSheet.dim").exists
        let sheet = sheetPort(app)
        let scrolls = scrollViewPorts(app)
        let clips = clipPorts(app)
        var measured: [FittedControl] = []
        var reasons: [String] = []
        for item in controls {
            let decision = visibility(
                item,
                dimmed: dimmed,
                sheet: sheet,
                scrolls: scrolls,
                clips: clips,
                window: window
            )
            guard decision.keep else { continue }
            var visible = item
            visible.islandExempt = decision.islandExempt
            measured.append(visible)
            reasons += decision.reasons.map { "\(visible.describe) \($0)" }
            if let reason = horizontalOverflow(visible.frame, window: window) {
                reasons.append("\(visible.describe) \(reason)")
            }
            if let reason = islandOverlap(visible, inset: inset, window: window) {
                reasons.append("\(visible.describe) \(reason)")
            }
            if let reason = truncationProxy(visible) {
                reasons.append("\(visible.describe) \(reason)")
            }
        }
        reasons += headerOverlapReasons(measured, inset: inset)
        reasons += textOverControlReasons(measured, controls: controls, window: window)
        var payload: [String: Any] = [
            "window": rect(window),
            "safeAreaTop": Double(inset),
            "dimmed": dimmed,
            "scrollViews": scrolls.map { ["id": $0.id, "frame": rect($0.frame)] as [String: Any] },
            "clips": clips.map { ["id": $0.id, "frame": rect($0.frame)] as [String: Any] },
            "elements": controls.map { item in
                [
                    "id": item.id,
                    "label": item.label,
                    "type": item.type,
                    "inStatusBar": item.inStatusBar,
                    "hittable": item.hittable,
                    "frame": rect(item.frame),
                ] as [String: Any]
            },
        ]
        if let sheet {
            payload["sheet"] = rect(sheet)
        }
        return ScreenFit(payload: payload, reasons: reasons)
    }

    private func assertScreenFit(
        _ fit: ScreenFit,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            fit.reasons.isEmpty,
            "\(screen) Accessibility XXXL: \(fit.reasons.joined(separator: "; "))",
            file: file,
            line: line
        )
    }

    private func fittedControls(_ app: XCUIApplication, window: CGRect, statusBar: CGRect) -> [FittedControl] {
        let queries: [(XCUIElementQuery, String)] = [
            (app.buttons, "button"),
            (app.staticTexts, "staticText"),
            (app.textFields, "textField"),
            (app.textViews, "textView"),
        ]
        var found: [FittedControl] = []
        for (query, type) in queries {
            for item in query.allElementsBoundByIndex where item.exists {
                if let control = fittedControl(item, type: type, window: window, statusBar: statusBar) {
                    found.append(control)
                }
            }
        }
        // Page dots are an accessibility element, not a button. Overlap checks need their frame.
        for item in app.otherElements.allElementsBoundByIndex where item.exists && item.identifier.contains("pageDots") {
            if let control = fittedControl(item, type: "other", window: window, statusBar: statusBar) {
                found.append(control)
            }
        }
        return found
    }

    private func fittedControl(
        _ item: XCUIElement,
        type: String,
        window: CGRect,
        statusBar: CGRect
    ) -> FittedControl? {
        let frame = item.frame
        guard frame.width > 1, frame.height > 1, frame.intersects(window) else { return nil }
        let inBar = !statusBar.isNull && statusBar.insetBy(dx: -1, dy: -1).contains(CGPoint(x: frame.midX, y: frame.midY))
        return FittedControl(
            id: item.identifier,
            label: item.label,
            type: type,
            frame: frame,
            inStatusBar: inBar,
            hittable: item.isHittable
        )
    }

    private struct VisibilityDecision {
        var keep: Bool
        var reasons: [String]
        var islandExempt: Bool
    }

    /// Same rules as `design_checks._axxxl_keep`. Non-hittable and fully scrolled-away
    /// elements are dropped. Text inside a scroll view may continue below the fold.
    /// Text cut off by a fixed card, or by the window when it is not in a scroll view, fails.
    private func visibility(
        _ item: FittedControl,
        dimmed: Bool,
        sheet: CGRect?,
        scrolls: [Viewport],
        clips: [Viewport],
        window: CGRect
    ) -> VisibilityDecision {
        if item.id == "jobSheet.dim" {
            return VisibilityDecision(keep: false, reasons: [], islandExempt: false)
        }
        if behindSheet(item, dimmed: dimmed, sheet: sheet) {
            return VisibilityDecision(keep: false, reasons: [], islandExempt: false)
        }
        if mostlyAboveWindow(item.frame, window: window) {
            return VisibilityDecision(keep: false, reasons: [], islandExempt: false)
        }
        if scrolledAway(item, scrolls: scrolls, window: window) {
            return VisibilityDecision(keep: false, reasons: [], islandExempt: false)
        }
        var reasons: [String] = []
        if enclosingScroll(item.frame, scrolls: scrolls) == nil, let clip = windowClipReason(item.frame, window: window) {
            reasons.append(clip)
        }
        if let fixed = fixedClipReason(item, clips: clips) {
            reasons.append(fixed)
        }
        if !item.hittable && reasons.isEmpty {
            return VisibilityDecision(keep: false, reasons: [], islandExempt: false)
        }
        return VisibilityDecision(
            keep: true,
            reasons: reasons,
            islandExempt: dimmed && item.id == "chat.garage"
        )
    }

    private func behindSheet(_ item: FittedControl, dimmed: Bool, sheet: CGRect?) -> Bool {
        guard dimmed else { return false }
        if item.id == "jobSheet.dim" || item.id == "chat.garage" || item.id.hasPrefix("jobSheet.") {
            return false
        }
        if item.id.hasPrefix("answerCard.") || item.id.hasPrefix("chat.") {
            return true
        }
        if let sheet, !sheet.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) {
            return true
        }
        return !item.hittable
    }

    /// A chip at y=-128 still intersects the window by about a point. That is not on screen.
    private func mostlyAboveWindow(_ frame: CGRect, window: CGRect) -> Bool {
        let visible = frame.intersection(window)
        if visible.isNull || visible.isInfinite { return true }
        return frame.minY < window.minY - 2 && visible.height <= 8
    }

    private func scrolledAway(_ item: FittedControl, scrolls: [Viewport], window: CGRect) -> Bool {
        guard !scrolls.isEmpty else { return false }
        let inViewport = scrolls.contains { scroll in
            let inter = item.frame.intersection(scroll.frame)
            return !inter.isNull && !inter.isInfinite && inter.width > 2 && inter.height > 2
        }
        if inViewport { return false }
        let onWindow = item.frame.intersection(window)
        let windowHeight = onWindow.isNull || onWindow.isInfinite ? 0 : onWindow.height
        return !item.hittable || windowHeight <= 2
    }

    /// Smallest `.scrollView` whose viewport contains the text's first line.
    /// `scrollViews` in layout-axxxl.json are user-scrollable. See docs/DYNAMIC_TYPE.md.
    private func enclosingScroll(_ frame: CGRect, scrolls: [Viewport]) -> Viewport? {
        var best: Viewport?
        var bestArea = CGFloat.greatestFiniteMagnitude
        for scroll in scrolls {
            let outer = scroll.frame
            guard outer.minX <= frame.midX, frame.midX <= outer.maxX else { continue }
            guard frame.minY >= outer.minY - 2, frame.minY < outer.maxY else { continue }
            let area = outer.width * outer.height
            if area < bestArea {
                best = scroll
                bestArea = area
            }
        }
        return best
    }

    /// Text with no scroll view, starting in the top 80% of the window, that still runs off the bottom.
    /// A peek of the next row (minY in the bottom 20%) is not a clip.
    private func windowClipReason(_ frame: CGRect, window: CGRect) -> String? {
        let visible = frame.intersection(window)
        guard !visible.isNull, !visible.isInfinite, visible.height > 48 else { return nil }
        if frame.minY >= window.minY + window.height * 0.80 { return nil }
        let pastBottom = frame.maxY - window.maxY
        guard pastBottom > 80, frame.height > 0, pastBottom > frame.height * 0.35 else { return nil }
        return String(
            format: "clipped by its container (minY %.0f, %.0fpt past the bottom of %.0fpt)",
            frame.minY,
            pastBottom,
            frame.height
        )
    }

    private func fixedClipReason(_ item: FittedControl, clips: [Viewport]) -> String? {
        for clip in clips {
            let outer = clip.frame
            guard outer.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) else { continue }
            let frame = item.frame
            let name = clip.id.isEmpty ? "clip" : clip.id
            let pastBottom = frame.maxY - outer.maxY
            if pastBottom > 4 {
                return String(
                    format: "clipped by its container \(name) (%.0fpt past the bottom)",
                    pastBottom
                )
            }
            if frame.minX < outer.minX - 4
                || frame.minY < outer.minY - 4
                || frame.maxX > outer.maxX + 4
            {
                return "extends outside fixed container \(name)"
            }
        }
        return nil
    }

    /// Hittable buttons and the page dots. Full-screen scrims are not controls.
    private func isOverlapControl(_ item: FittedControl, window: CGRect) -> Bool {
        if item.id.contains("pageDots") { return true }
        if item.id == "jobSheet.dim" { return false }
        if item.type != "button" || !item.hittable { return false }
        return item.frame.height < window.height * 0.45
    }

    /// Text that starts above a button or the page dots and runs into it.
    /// A row that starts at or below the control (scrolled up under Close) does not count.
    private func textOverControlReasons(
        _ texts: [FittedControl],
        controls all: [FittedControl],
        window: CGRect
    ) -> [String] {
        let controls = all.filter { isOverlapControl($0, window: window) }
        var reasons: [String] = []
        for text in texts where text.type == "staticText" || text.type == "textView" || text.type == "textField" {
            for control in controls {
                if text.id == control.id && text.frame == control.frame { continue }
                // A button that contains its own label is not an overlap.
                // Text that covers the page dots does contain that control, and that fails.
                if frameContains(control.frame, text.frame) {
                    continue
                }
                guard text.frame.minY < control.frame.minY - 4 else { continue }
                let overlap = text.frame.intersection(control.frame)
                guard !overlap.isNull, !overlap.isInfinite, overlap.width > 4, overlap.height > 4 else { continue }
                reasons.append("\(text.describe) overlaps \(control.describe)")
            }
        }
        return reasons
    }

    private func sheetPort(_ app: XCUIApplication) -> CGRect? {
        for id in ["jobSheet.half", "jobSheet.full", "jobSheet.collapsed"] {
            let item = element(app, id)
            if item.exists, item.frame.width > 1, item.frame.height > 1 {
                return item.frame
            }
        }
        return nil
    }

    private func scrollViewPorts(_ app: XCUIApplication) -> [Viewport] {
        app.scrollViews.allElementsBoundByIndex.compactMap { item in
            guard item.exists else { return nil }
            let frame = item.frame
            guard frame.width > 1, frame.height > 1 else { return nil }
            return Viewport(id: item.identifier, frame: frame)
        }
    }

    private func clipPorts(_ app: XCUIApplication) -> [Viewport] {
        let bay = element(app, "onboarding.bay")
        guard bay.exists, bay.frame.width > 1, bay.frame.height > 1 else { return [] }
        return [Viewport(id: "onboarding.bay", frame: bay.frame)]
    }

    private func horizontalOverflow(_ frame: CGRect, window: CGRect) -> String? {
        let visible = frame.intersection(window)
        guard visible.width > 2, visible.height > 2 else { return nil }
        let pastLeft = window.minX - frame.minX
        let pastRight = frame.maxX - window.maxX
        guard pastLeft > 2 || pastRight > 2 else { return nil }
        return String(
            format: "extends past the window (minX %.0f, maxX %.0f, window %.0f…%.0f)",
            frame.minX, frame.maxX, window.minX, window.maxX
        )
    }

    /// Status-bar chrome (clock, signal) sits in the island on purpose. App headers do not.
    /// Body copy such as `jobSheet.answer` is not a header, so scrolling it does not fail this check.
    /// `chat.garage` above a sheet is the dimmed sliver from #121, not an island collision.
    private func islandOverlap(_ item: FittedControl, inset: CGFloat, window: CGRect) -> String? {
        if item.islandExempt || item.id == "jobSheet.dim" || item.frame.height >= window.height * 0.45 { return nil }
        if item.id.isEmpty && item.frame.maxY <= inset + 2 { return nil }
        guard item.frame.minY < inset - 2, item.frame.maxY > window.minY else { return nil }
        let ident = item.id.lowercased()
        let headerWord = ["title", "close", "open", "skip", "garage", "back", "header"]
            .contains { ident.contains($0) }
        let header = headerWord
            || (item.type == "button" && !item.inStatusBar)
            || (item.type == "staticText" && item.id.isEmpty && !item.inStatusBar)
        guard header else { return nil }
        return String(
            format: "minY %.0f is under the status bar / island (safe area %.0f)",
            item.frame.minY, inset
        )
    }

    private func truncationProxy(_ item: FittedControl) -> String? {
        if item.inStatusBar { return nil }
        let label = item.label
        if label.contains("…") || label.contains("...") {
            return "label looks truncated: \(label)"
        }
        let tokens = label.split { $0.isWhitespace || $0 == "·" }
        let longest = tokens.map(\.count).max() ?? 0
        let width = item.frame.width
        let height = item.frame.height
        if longest >= 6, width < 72, height > width * 1.35, width > 1 {
            return "label \(label) is squeezed into a \(Int(width))×\(Int(height))pt column (mid-word wrap proxy)"
        }
        return nil
    }

    private func headerOverlapReasons(_ items: [FittedControl], inset: CGFloat) -> [String] {
        let band = items.filter { item in
            !item.inStatusBar
                && !item.islandExempt
                && item.id != "jobSheet.dim"
                && item.frame.minY < inset + 96
                && item.frame.height < 160
                && item.frame.height > 1
        }
        var reasons: [String] = []
        for index in band.indices {
            for other in band.indices where other > index {
                let first = band[index]
                let second = band[other]
                if frameContains(first.frame, second.frame) || frameContains(second.frame, first.frame) {
                    continue
                }
                let overlap = first.frame.intersection(second.frame)
                if overlap.width > 4, overlap.height > 4 {
                    reasons.append("\(first.describe) overlaps \(second.describe)")
                }
            }
        }
        return reasons
    }

    private func frameContains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.minX <= inner.minX + 2
            && outer.minY <= inner.minY + 2
            && outer.maxX >= inner.maxX - 2
            && outer.maxY >= inner.maxY - 2
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
