import SidekickCore
import XCTest

/// Taps launch arguments cannot reach: Garage sheet, Jobs row, Scan log, sheet detents, scrim.
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
        XCTAssertTrue(
            element(app, "jobSheet.dim").waitForExistence(timeout: 3),
            "Half sheet from a Jobs row should dim chat"
        )
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

    func testEditGarageAddsFactAndTodo() throws {
        let app = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
            "-garageTemporaryStore", "1",
        ])
        let garage = element(app, "chat.garage")
        XCTAssertTrue(garage.waitForExistence(timeout: 8), "chat.garage is missing")
        garage.tap()
        XCTAssertTrue(element(app, "onboarding.garage").waitForExistence(timeout: 5))
        let edit = element(app, "garage.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "garage.edit is missing")
        edit.tap()

        let addFact = element(app, "garage.addFact")
        XCTAssertTrue(addFact.waitForExistence(timeout: 3), "garage.addFact is missing")
        addFact.tap()

        let stamp = String(Int(Date().timeIntervalSince1970) % 100000)
        let factLabel = "Spare \(stamp)"
        let factValue = "FAKE-NOTE \(stamp)"
        let todoTitle = "Check spare \(stamp)"

        let label = element(app, "garage.fact.label")
        XCTAssertTrue(label.waitForExistence(timeout: 5), "garage.fact.label is missing")
        label.tap()
        label.typeText(factLabel)

        let value = element(app, "garage.fact.value")
        XCTAssertTrue(value.waitForExistence(timeout: 3), "garage.fact.value is missing")
        value.tap()
        value.typeText(factValue)

        let save = element(app, "garage.fact.save")
        XCTAssertTrue(save.waitForExistence(timeout: 3), "garage.fact.save is missing")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: save)], timeout: 3),
            .completed,
            "Save stays off until both fields have text"
        )
        if save.isHittable {
            save.tap()
        } else {
            value.typeText("\n")
        }

        let form = element(app, "garage.form.title")
        let dismissed = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: form)], timeout: 3),
            .completed,
            "Saving a fact should close the sheet"
        )
        XCTAssertTrue(app.staticTexts[factLabel].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[factValue].exists)

        var todoField = element(app, "garage.todo.field")
        var swipes = 0
        while !todoField.isHittable && swipes < 5 {
            app.swipeUp()
            swipes += 1
            todoField = element(app, "garage.todo.field")
        }
        XCTAssertTrue(todoField.waitForExistence(timeout: 3), "garage.todo.field is missing")
        todoField.tap()
        todoField.typeText(todoTitle + "\n")
        let addedTodo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "garage.todo.toggle."))
            .firstMatch
        XCTAssertTrue(addedTodo.waitForExistence(timeout: 5), "The new to-do should show a checkbox")
        XCTAssertTrue(app.staticTexts[todoTitle].exists)

        if FileManager.default.fileExists(atPath: "/tmp/sidekick-verify-sidekick/evidence-path") {
            try writeShot("taps-garage-edit.png")
        }
    }

    private var sheetHeaderClearance: CGFloat { CGFloat(JobSheetLayout.headerTopClearance) }

    func testSheetHeadersClearTheGrabber() throws {
        let garage = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
            "-garageTemporaryStore", "1",
        ])
        let openGarage = element(garage, "chat.garage")
        XCTAssertTrue(openGarage.waitForExistence(timeout: 8))
        openGarage.tap()
        assertHeaderClearsGrabber(garage, sheetID: "garage.sheetTop", headerID: "garage.done", screen: "garage")
        element(garage, "garage.edit").tap()
        let addFact = element(garage, "garage.addFact")
        XCTAssertTrue(addFact.waitForExistence(timeout: 3))
        addFact.tap()
        assertHeaderClearsGrabber(
            garage,
            sheetID: "garage.formTop",
            headerID: "garage.form.cancel",
            screen: "garage-form"
        )
        garage.terminate()

        let collapsed = launchApp(arguments: ["-screen", "job-sheet-collapsed", "-demoPhoto", "hilux"])
        assertHeaderClearsGrabber(
            collapsed,
            sheetID: "jobSheet.collapsed",
            headerID: "jobSheet.open",
            screen: "job-sheet-collapsed"
        )
        collapsed.terminate()

        let half = launchApp(arguments: ["-screen", "job-sheet-half", "-demoPhoto", "hilux"])
        assertHeaderClearsGrabber(half, sheetID: "jobSheet.half", headerID: "jobSheet.close", screen: "job-sheet-half")
        half.terminate()

        let full = launchApp(arguments: ["-screen", "job-sheet-full", "-demoPhoto", "hilux"])
        assertHeaderClearsGrabber(full, sheetID: "jobSheet.full", headerID: "jobSheet.close", screen: "job-sheet-full")
        full.terminate()

        let jobs = launchApp(arguments: ["-screen", "job-history"])
        assertHeaderClearsGrabber(jobs, sheetID: "lookBack.sheetTop", headerID: "lookBack.back", screen: "jobs")
        let past = element(jobs, "jobHistory.row.cold-idle")
        XCTAssertTrue(past.waitForExistence(timeout: 5))
        past.tap()
        assertHeaderClearsGrabber(jobs, sheetID: "jobSheet.half", headerID: "jobSheet.close", screen: "past-job")
        jobs.terminate()

        let scan = launchApp(arguments: ["-screen", "scan-log"])
        assertHeaderClearsGrabber(scan, sheetID: "lookBack.sheetTop", headerID: "lookBack.back", screen: "scan-log")
        scan.terminate()

        let citation = launchApp(arguments: ["-screen", "citation-page", "-demoPhoto", "hilux"])
        assertHeaderClearsGrabber(
            citation,
            sheetID: "citation.sheetTop",
            headerID: "citation.close",
            screen: "citation"
        )
        citation.terminate()

        let onboarding = launchApp(arguments: ["-resetOnboarding", "-screen", "onboarding-1"])
        assertHeaderClearsGrabber(
            onboarding,
            sheetID: "onboarding.sheetTop",
            headerID: "onboarding.skip",
            screen: "onboarding"
        )
    }

    func testGarageEditsSurviveCloseAndRelaunch() throws {
        let stamp = String(Int(Date().timeIntervalSince1970) % 100000)
        let factLabel = "Spare \(stamp)"
        let factValue = "FAKE-NOTE \(stamp)"
        let photoCaption = "FAKE-PHOTO \(stamp)"
        let partName = "FAKE-PART \(stamp)"
        let todoTitle = "Check spare \(stamp)"
        let folder = "sidekick-garage-\(UUID().uuidString)"
        let arguments = [
            "-sidekick.onboarding.completed", "YES",
            "-garageTemporaryStore", "1",
        ]
        let environment = [GarageStoreLocation.directoryEnvironmentKey: folder]

        let app = launchApp(arguments: arguments, environment: environment)
        addGarageRecords(
            app,
            factLabel: factLabel,
            factValue: factValue,
            photoCaption: photoCaption,
            partName: partName,
            todoTitle: todoTitle
        )
        element(app, "garage.done").tap()
        let reopen = element(app, "chat.garage")
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reopen.tap()
        assertGarageRecords(
            app,
            factLabel: factLabel,
            factValue: factValue,
            photoCaption: photoCaption,
            partName: partName,
            todoTitle: todoTitle
        )
        app.terminate()

        let relaunched = launchApp(arguments: arguments, environment: environment)
        let garage = element(relaunched, "chat.garage")
        XCTAssertTrue(garage.waitForExistence(timeout: 8))
        garage.tap()
        assertGarageRecords(
            relaunched,
            factLabel: factLabel,
            factValue: factValue,
            photoCaption: photoCaption,
            partName: partName,
            todoTitle: todoTitle
        )
    }

    func testScanLogFilterAll() throws {
        try assertScanLogFilter("all", shown: (0..<9).map { "scan-log-\($0)" })
    }

    func testScanLogFilterIntake() throws {
        try assertScanLogFilter("intake", shown: ["scan-log-0", "scan-log-7"])
    }

    func testScanLogFilterCooling() throws {
        try assertScanLogFilter("cooling", shown: ["scan-log-1"])
    }

    func testScanLogFilterIgnition() throws {
        try assertScanLogFilter("ignition", shown: ["scan-log-2"])
    }

    func testScanLogFilterElectrical() throws {
        try assertScanLogFilter("electrical", shown: ["scan-log-3", "scan-log-8"])
    }

    func testScanLogFilterFuel() throws {
        try assertScanLogFilter("fuel", shown: ["scan-log-4"])
    }

    func testScanLogFilterInspected() throws {
        try assertScanLogFilter("inspected", shown: ["scan-log-5"])
    }

    func testScanLogFilterWatch() throws {
        try assertScanLogFilter("watch", shown: ["scan-log-6"])
    }

    private func assertScanLogFilter(_ chip: String, shown: [String]) throws {
        let app = launchApp(arguments: ["-screen", "scan-log"])
        XCTAssertTrue(element(app, "scanLog.grid").waitForExistence(timeout: 8))
        let control = element(app, "scanLog.chip.\(chip)")
        XCTAssertTrue(control.waitForExistence(timeout: 3), "scanLog.chip.\(chip) is missing")
        control.tap()
        let visible = Set(shown)
        for index in 0..<9 {
            let id = "scan-log-\(index)"
            let cell = element(app, "scanLog.cell.\(id)")
            if visible.contains(id) {
                XCTAssertTrue(cell.waitForExistence(timeout: 2), "\(chip) should show \(id)")
            } else {
                XCTAssertFalse(cell.exists, "\(chip) should hide \(id)")
            }
        }
        if shown.isEmpty {
            XCTAssertTrue(element(app, "scanLog.empty").waitForExistence(timeout: 2))
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
        let list = element(app, "jobHistory.list")
        XCTAssertTrue(list.waitForExistence(timeout: 8), "jobHistory.list is missing")
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
                ["chat.composer", "chat.garage", "chat.jobs", "chat.scanLog", "chat.send"],
                false
            ),
            (
                "job-history",
                ["-screen", "job-history"],
                ["jobHistory.list", "lookBack.back", "jobHistory.scanLog"],
                false
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
                ["chat.garage", "chat.jobs", "chat.scanLog", "chat.composer", "chat.send", "chat.messageList"],
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
                ["jobHistory.list", "lookBack.back", "lookBack.title", "jobHistory.scanLog", "jobHistory.row.cold-idle"],
                false
            ),
            (
                "scan-log",
                ["-screen", "scan-log"],
                ["scanLog.grid", "lookBack.back", "lookBack.title", "scanLog.cell.scan-log-0"],
                false
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

    func testAccessibilityXXXLHeaderAndHalfSheet() throws {
        let chat = launchApp(arguments: [
            "-sidekick.onboarding.completed", "YES",
            "-dynamicTypeSize", "accessibility5",
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
        try writeShot("taps-chat-axxxl.png")
        chat.terminate()

        let app = launchApp(arguments: [
            "-screen", "job-sheet-half",
            "-demoPhoto", "hilux",
            "-dynamicTypeSize", "accessibility5",
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
        try writeShot("taps-job-sheet-half-axxxl.png")
        app.terminate()

        let closeout = launchApp(arguments: [
            "-screen", "job-sheet-closeout",
            "-demoPhoto", "hilux",
            "-dynamicTypeSize", "accessibility5",
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
        try writeShot("taps-job-sheet-closeout-axxxl.png")
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

        let citation = launchApp(arguments: [
            "-screen", "citation-page",
            "-demoPhoto", "hilux",
            "-dynamicTypeSize", "accessibility5",
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
        try writeShot("taps-citation-page-axxxl.png")
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

    private func assertHeaderClearsGrabber(
        _ app: XCUIApplication,
        sheetID: String,
        headerID: String,
        screen: String
    ) {
        let sheet = element(app, sheetID)
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "\(screen): \(sheetID) is missing")
        let header = element(app, headerID)
        XCTAssertTrue(header.waitForExistence(timeout: 5), "\(screen): \(headerID) is missing")
        let gap = header.frame.minY - sheet.frame.minY
        XCTAssertGreaterThanOrEqual(
            gap,
            sheetHeaderClearance,
            "\(screen): \(headerID) is \(gap) pt below \(sheetID); need at least \(sheetHeaderClearance)"
        )
    }

    private func addGarageRecords(
        _ app: XCUIApplication,
        factLabel: String,
        factValue: String,
        photoCaption: String,
        partName: String,
        todoTitle: String
    ) {
        let garage = element(app, "chat.garage")
        XCTAssertTrue(garage.waitForExistence(timeout: 8))
        garage.tap()
        let edit = element(app, "garage.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        element(app, "garage.addFact").tap()
        let label = element(app, "garage.fact.label")
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText(factLabel)
        let value = element(app, "garage.fact.value")
        value.tap()
        value.typeText(factValue)
        tapSave(app, identifier: "garage.fact.save", fallback: value)

        reveal(app, "garage.addPhoto").tap()
        let sample = element(app, "garage.photo.sample")
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "garage.photo.sample is missing")
        sample.tap()
        let caption = element(app, "garage.photo.caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
        caption.tap()
        caption.typeText(photoCaption)
        tapSave(app, identifier: "garage.photo.save", fallback: caption)

        reveal(app, "garage.addPart").tap()
        let name = element(app, "garage.item.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(partName)
        tapSave(app, identifier: "garage.item.save", fallback: name)

        let todoField = reveal(app, "garage.todo.field")
        todoField.tap()
        todoField.typeText(todoTitle + "\n")
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "garage.todo.toggle.",
                todoTitle
            ))
            .firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The new to-do should show a checkbox")
        toggle.tap()
        XCTAssertTrue(toggle.label.hasPrefix("Done,"), "Toggling should mark the to-do done")
    }

    private func assertGarageRecords(
        _ app: XCUIApplication,
        factLabel: String,
        factValue: String,
        photoCaption: String,
        partName: String,
        todoTitle: String
    ) {
        XCTAssertTrue(app.staticTexts[factLabel].waitForExistence(timeout: 5), "Missing fact \(factLabel)")
        XCTAssertTrue(revealText(app, factValue).exists, "Missing fact value \(factValue)")
        XCTAssertTrue(revealText(app, photoCaption).exists, "Missing photo \(photoCaption)")
        XCTAssertTrue(revealText(app, partName).exists, "Missing part \(partName)")
        XCTAssertTrue(revealText(app, todoTitle).exists, "Missing to-do \(todoTitle)")
        let done = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "garage.todo.toggle.",
                "Done, \(todoTitle)"
            ))
            .firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "To-do should still be done")
    }

    private func tapSave(_ app: XCUIApplication, identifier: String, fallback: XCUIElement) {
        let save = element(app, identifier)
        XCTAssertTrue(save.waitForExistence(timeout: 3), "\(identifier) is missing")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: save)], timeout: 3),
            .completed,
            "\(identifier) stays off"
        )
        if save.isHittable {
            save.tap()
        } else {
            fallback.typeText("\n")
        }
        let form = element(app, "garage.form.title")
        let dismissed = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: form)], timeout: 3),
            .completed,
            "Saving should close the form"
        )
    }

    private func reveal(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        var match = element(app, identifier)
        var swipes = 0
        while !match.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
            match = element(app, identifier)
        }
        XCTAssertTrue(match.waitForExistence(timeout: 3), "\(identifier) is missing")
        return match
    }

    private func revealText(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        var match = app.staticTexts[label]
        var swipes = 0
        while !match.exists && swipes < 6 {
            app.swipeUp()
            swipes += 1
            match = app.staticTexts[label]
        }
        return match
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

    private func launchApp(
        arguments: [String],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // Skip first-run onboarding unless a test opts in with -resetOnboarding.
        let onboarding = arguments.contains("-resetOnboarding") || arguments.contains("-sidekick.onboarding.completed")
        app.launchArguments = onboarding ? arguments : arguments + ["-sidekick.onboarding.completed", "YES"]
        app.launchEnvironment = environment
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
