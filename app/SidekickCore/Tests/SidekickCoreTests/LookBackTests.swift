import XCTest
@testable import SidekickCore

@MainActor
final class LookBackTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
    func testLaunchScreensMapJobHistoryAndScanLog() {
        let jobs = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "job-history"],
            environment: [:]
        )
        XCTAssertEqual(jobs.lookBackScreen, .jobHistory)
        XCTAssertNil(jobs.jobSheetScreen)
        XCTAssertNil(jobs.screen)
        XCTAssertTrue(jobs.opensLookBack)
        XCTAssertFalse(jobs.opensJobSheet)
        XCTAssertFalse(jobs.opensHighlightViewer)
        XCTAssertTrue(jobs.enablesDemoMode)
        XCTAssertEqual(jobs.cannedQuestion, "")

        let log = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: ["SIDEKICK_SCREEN": "scan-log"]
        )
        XCTAssertEqual(log.lookBackScreen, .scanLog)
        XCTAssertTrue(log.opensLookBack)
        XCTAssertEqual(LookBackScreen.allCases.map(\.rawValue), ["job-history", "scan-log"])
    }

    func testJobHistoryRowsMatchFigmaAndReuseJobSheet() throws {
        let now = try XCTUnwrap(utcCalendar.date(from: DateComponents(
            year: 2026, month: 10, day: 10, hour: 15
        )))
        let rows = JobHistoryScript.jobs(now: now, calendar: utcCalendar)
        XCTAssertEqual(rows.map(\.title), ["Cold idle", "Hard start", "Battery light", "Hose check"])
        XCTAssertEqual(rows.map { $0.dateLabel(now: now, calendar: utcCalendar) }, [
            "Today", "Yesterday", "Sep 28", "Sep 20",
        ])
        XCTAssertEqual(rows.map(\.outcome), [.worked, .partly, .didnt, .worked])
        XCTAssertEqual(rows.map(\.rowIdentifier), [
            "jobHistory.row.cold-idle",
            "jobHistory.row.hard-start",
            "jobHistory.row.battery-light",
            "jobHistory.row.hose-check",
        ])
        XCTAssertEqual(JobHistoryCopy.title, "Jobs")
        XCTAssertEqual(JobHistoryCopy.subtitle, "Each one keeps its own chat.")
        XCTAssertEqual(JobHistoryCopy.back, "Back")
        XCTAssertEqual(JobOutcome.allCases.map(\.label), ["Worked", "Partly", "Didn't"])

        let expectedParts = [
            "fuse-relay-box",
            "fuse-relay-box",
            "throttle-body",
            "throttle-body",
        ]
        let expectedAsks = [
            "Rough idle after a cold start",
            "Hard start",
            "Battery light",
            "Hose check",
        ]
        for index in rows.indices {
            let row = rows[index]
            let partID = expectedParts[index]
            let ask = expectedAsks[index]
            let photoID = try XCTUnwrap(row.photoID)
            XCTAssertEqual(row.answerText, JobSheetCopy.answer(photoID: photoID))
            XCTAssertEqual(row.citations.first?.docID.rawValue, "FAKE-DOC-2JZ")
            XCTAssertEqual(row.citations.first?.page.rawValue, 999)
            XCTAssertEqual(row.highlight?.isDemo, true)
            XCTAssertEqual(row.highlight?.partID.rawValue, partID)
            XCTAssertEqual(
                row.highlight?.geometry,
                HighlightViewerScript.geometry(
                    photoID: photoID,
                    partID: partID,
                    showingOutline: true
                )
            )
            XCTAssertGreaterThanOrEqual(row.highlight?.geometry?.polygons[0].points.count ?? 0, 5)
            XCTAssertFalse(row.answerText.contains("air box"))
            XCTAssertEqual(try userText(row.conversation.messages[0]), ask)
        }

        let older = JobSheetState(
            id: JobID(rawValue: "older-year")!,
            title: "Older",
            createdAt: try XCTUnwrap(utcCalendar.date(from: DateComponents(
                year: 2025, month: 9, day: 28, hour: 12
            ))),
            conversation: Conversation(id: ConversationID(rawValue: "older-year")!)
        )
        XCTAssertEqual(older.dateLabel(now: now, calendar: utcCalendar), "Sep 28, 2025")
    }

    func testOpeningAHistoryRowShowsThatJobsChatAtTheCallersDetent() async throws {
        let now = try XCTUnwrap(utcCalendar.date(from: DateComponents(
            year: 2026, month: 10, day: 10, hour: 15
        )))
        let rows = JobHistoryScript.jobs(now: now, calendar: utcCalendar)
        let hardStart = rows[1]
        let jobs = JobsModel(source: .memory(rows), client: LookBackIdleClient())
        let chat = ChatViewModel(jobs: jobs)
        chat.open(hardStart.id)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(try userText(chat.messages[0]), "Hard start")
        XCTAssertEqual(chat.job?.title, "Hard start")
        XCTAssertEqual(chat.job?.outcome, .partly)
        XCTAssertEqual(chat.job?.photoID, "commons-supra-n5abh")
        XCTAssertEqual(chat.job?.highlight?.bayPhotoID.rawValue, "commons-supra-n5abh")
        XCTAssertEqual(chat.job?.highlight?.partID.rawValue, "fuse-relay-box")
        XCTAssertEqual(chat.job?.answerText, JobSheetCopy.answer(photoID: "commons-supra-n5abh"))
        XCTAssertFalse(chat.job?.answerText.contains("air box") == true)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertNotEqual(try userText(chat.messages[0]), "Rough idle after a cold start")
        let sheet = JobSheetViewModel()
        sheet.setDetent(.half)
        XCTAssertEqual(sheet.detent, .half)
        XCTAssertEqual(rows[1].title, "Hard start")
    }

    func testScanLogGridNamesTheSamePartAsTheOutline() {
        let entries = ScanLogScript.entries
        XCTAssertEqual(entries.count, 9)
        XCTAssertEqual(ScanLogCopy.title, "Scan log")
        XCTAssertEqual(ScanLogCopy.subtitle, "Photos and outlines, filterable")
        XCTAssertEqual(ScanLogCopy.chips, [
            "all", "intake", "cooling", "ignition", "electrical", "fuel", "inspected", "watch",
        ])
        XCTAssertEqual(ScanLogCopy.selectedChip, "all")
        XCTAssertEqual(ScanLogCopy.thumbBanner, "Not your truck")
        XCTAssertLessThan(ScanLogCopy.thumbBanner.count, HighlightViewerCopy.referenceBanner.count)
        XCTAssertFalse(ScanLogCopy.thumbBanner.contains("Demo"))

        XCTAssertEqual(entries.map(\.filterTag), ScanLogScript.filterTags)
        let outlined = entries.filter { $0.presentation().showsOutline }
        XCTAssertEqual(outlined.count, 6)
        for entry in outlined {
            let shown = entry.presentation()
            let geometry = entry.geometry()
            XCTAssertEqual(shown.partID, DemoOutlineCatalog.selection(
                photoID: entry.photoID,
                state: entry.source
            ).partID)
            XCTAssertEqual(entry.tagLabel, DemoOutlineCatalog.shortTag(partID: shown.partID))
            XCTAssertEqual(
                geometry,
                HighlightViewerScript.geometry(
                    photoID: shown.outlinePhotoID,
                    partID: shown.partID,
                    showingOutline: true
                )
            )
            XCTAssertGreaterThanOrEqual(geometry?.polygons[0].points.count ?? 0, 5)
            let xs = geometry?.polygons[0].points.map(\.x) ?? []
            let ys = geometry?.polygons[0].points.map(\.y) ?? []
            XCTAssertFalse(Set(xs).count == 2 && Set(ys).count == 2)
            XCTAssertFalse(shown.partDisplayName.contains("air box"))
            XCTAssertNotEqual(shown.partID, "air-box")
        }

        let empty = entries.filter { !$0.presentation().showsOutline }
        XCTAssertEqual(empty.count, 3)
        for entry in empty {
            XCTAssertNil(entry.geometry())
            XCTAssertEqual(entry.presentation().kind, .notFound)
            XCTAssertEqual(entry.tagLabel, "—")
            XCTAssertTrue(ScanLogCopy.chips.contains(entry.filterTag))
        }
    }

    func testEachScanLogChipShowsADifferentSubset() {
        let entries = ScanLogScript.entries
        XCTAssertEqual(
            ScanLogFilter.shown(entries, chip: "all").map(\.id),
            [
                "scan-log-0", "scan-log-1", "scan-log-2", "scan-log-3", "scan-log-4",
                "scan-log-5", "scan-log-6", "scan-log-7", "scan-log-8",
            ]
        )
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "intake").map(\.id), ["scan-log-0", "scan-log-7"])
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "cooling").map(\.id), ["scan-log-1"])
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "ignition").map(\.id), ["scan-log-2"])
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "electrical").map(\.id), ["scan-log-3", "scan-log-8"])
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "fuel").map(\.id), ["scan-log-4"])
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "inspected").map(\.id), ["scan-log-5"])
        XCTAssertEqual(ScanLogFilter.shown(entries, chip: "watch").map(\.id), ["scan-log-6"])
        XCTAssertTrue(ScanLogFilter.shown(entries, chip: "not-a-chip").isEmpty)
        XCTAssertEqual(ScanLogCopy.empty, "Nothing matches.")
        let subsets = ScanLogCopy.chips.map { chip in
            Set(ScanLogFilter.shown(entries, chip: chip).map(\.id))
        }
        XCTAssertEqual(Set(subsets).count, ScanLogCopy.chips.count)
        for chip in ScanLogCopy.chips where chip != "all" {
            let shown = ScanLogFilter.shown(entries, chip: chip)
            XCTAssertFalse(shown.isEmpty, chip)
            XCTAssertTrue(shown.allSatisfy { $0.filterTag == chip }, chip)
        }
    }

    func testReferenceCellKeepsNotYourTruckBanner() {
        let reference = ScanLogScript.entries[6]
        let shown = reference.presentation(flags: .v1)
        XCTAssertEqual(reference.source, .reference)
        XCTAssertEqual(shown.kind, .reference)
        XCTAssertEqual(shown.target, .referencePhoto)
        XCTAssertTrue(shown.showsOutline)
        XCTAssertEqual(shown.banner, HighlightViewerCopy.referenceBanner)
        XCTAssertEqual(shown.banner, "Reference, not your truck.")
        XCTAssertEqual(reference.cellBanner(), "Not your truck")
        XCTAssertEqual(shown.partID, "throttle-body")
        XCTAssertEqual(reference.tagLabel, "throttle")
        XCTAssertEqual(reference.filterTag, "watch")
        XCTAssertNil(ScanLogScript.entries[0].cellBanner())
        XCTAssertEqual(
            reference.geometry(),
            HighlightViewerScript.geometry(
                photoID: shown.outlinePhotoID,
                partID: shown.partID,
                showingOutline: true
            )
        )
    }

    func testScanLogTileCropCentersOnTheOutline() throws {
        let hilux = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "commons-hilux-2jz", partID: "fuse-relay-box")
        )
        let box = try XCTUnwrap(HighlightOutlineLayout.normalizedBounds(of: hilux))
        XCTAssertLessThan(box.midX, 0.25, "Hilux fuse sits on the left of the photo")
        let centered = HighlightOutlineLayout.aspectFill(
            imageWidth: 200,
            imageHeight: 100,
            boundsWidth: 100,
            boundsHeight: 100
        )
        XCTAssertEqual(centered.x, -50)
        let focused = HighlightOutlineLayout.aspectFill(
            imageWidth: 200,
            imageHeight: 100,
            boundsWidth: 100,
            boundsHeight: 100,
            focus: HighlightPoint(x: box.midX, y: box.midY)
        )
        XCTAssertEqual(focused.x, 0)
        XCTAssertEqual(focused.y, 0)
        XCTAssertEqual(focused.width, 200)
        XCTAssertEqual(focused.height, 100)
        let mapped = HighlightOutlineLayout.map(
            HighlightPoint(x: box.midX, y: box.midY),
            in: focused
        )
        XCTAssertGreaterThanOrEqual(mapped.x, 0)
        XCTAssertLessThanOrEqual(mapped.x, 100)
        let left = HighlightOutlineLayout.map(HighlightPoint(x: box.minX, y: box.midY), in: focused)
        XCTAssertGreaterThanOrEqual(left.x, -1)

        let supra = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "commons-supra-n5abh", partID: "fuse-relay-box")
        )
        let rightBox = try XCTUnwrap(HighlightOutlineLayout.normalizedBounds(of: supra))
        XCTAssertGreaterThan(rightBox.midX, 0.7)
        let rightFill = HighlightOutlineLayout.aspectFill(
            imageWidth: 200,
            imageHeight: 100,
            boundsWidth: 100,
            boundsHeight: 100,
            focus: HighlightPoint(x: rightBox.midX, y: rightBox.midY)
        )
        XCTAssertLessThan(rightFill.x, centered.x)
        XCTAssertGreaterThanOrEqual(rightFill.x, -100)
        let rightMapped = HighlightOutlineLayout.map(
            HighlightPoint(x: rightBox.midX, y: rightBox.midY),
            in: rightFill
        )
        XCTAssertGreaterThanOrEqual(rightMapped.x, 0)
        XCTAssertLessThanOrEqual(rightMapped.x, 100)
    }

    func testScanLogTileInkIsAThinOutline() {
        let solid = HighlightOutlineInk.lookBackTile()
        XCTAssertEqual(solid.strokeWidth, 2.0, accuracy: 0.01)
        XCTAssertEqual(solid.fillOpacity, 0.08, accuracy: 0.001)
        XCTAssertEqual(solid.dash, [])
        let dashed = HighlightOutlineInk.lookBackTile(dashed: true)
        XCTAssertEqual(dashed.strokeWidth, 1.5, accuracy: 0.01)
        XCTAssertLessThan(dashed.fillOpacity, 0.1)
        XCTAssertFalse(dashed.dash.isEmpty)
        let midCell = HighlightOutlineInk.scaled(renderedWidth: 110)
        XCTAssertGreaterThan(midCell.strokeWidth, 4)
        XCTAssertLessThan(solid.strokeWidth, midCell.strokeWidth)
    }

    func testV1LookBackOmitsLaterBacklog() {
        XCTAssertEqual(JobHistoryCopy.subtitle, "Each one keeps its own chat.")
        XCTAssertFalse(ScanLogCopy.chips.contains("user"))
        XCTAssertEqual(JobHistoryScript.jobs(now: Date(timeIntervalSince1970: 1_760_000_000)).count, 4)
        XCTAssertFalse(JobSheetCopy.answer.contains("FAKE-SPEC"))
        XCTAssertFalse(JobSheetCopy.answer.contains("air box"))
        XCTAssertTrue(JobSheetCopy.answer.contains("FAKE-DOC-2JZ"))
    }

    private func userText(_ message: Message) throws -> String {
        guard case let .user(user) = message else {
            XCTFail("expected a user message")
            throw LookBackIdleFailure()
        }
        return user.text
    }
}

private struct LookBackIdleFailure: Error {}

private struct LookBackIdleClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        throw ChatClientError.offline
    }
}
