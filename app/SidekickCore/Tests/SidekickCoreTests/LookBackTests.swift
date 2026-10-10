import XCTest
@testable import SidekickCore

final class LookBackTests: XCTestCase {
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
        let rows = JobHistoryScript.rows
        XCTAssertEqual(rows.map(\.job.title), ["Cold idle", "Hard start", "Battery light", "Hose check"])
        XCTAssertEqual(rows.map(\.dateLabel), ["Today", "Yesterday", "Sep 28", "Sep 20"])
        XCTAssertEqual(rows.map(\.job.outcome), [.worked, .partly, .didnt, .worked])
        XCTAssertEqual(JobHistoryCopy.title, "Jobs")
        XCTAssertEqual(JobHistoryCopy.subtitle, "One row per ask")
        XCTAssertEqual(JobHistoryCopy.back, "Back")
        XCTAssertEqual(JobOutcome.allCases.map(\.label), ["Worked", "Partly", "Didn't"])

        let expectedParts = [
            "fuse-relay-box",
            "fuse-relay-box",
            "throttle-body",
            "throttle-body",
        ]
        for (row, partID) in zip(rows, expectedParts) {
            let photoID = try XCTUnwrap(row.job.photoID)
            XCTAssertEqual(row.job.answerText, JobSheetCopy.answer(photoID: photoID))
            XCTAssertEqual(row.job.citations.first?.docID.rawValue, "FAKE-DOC-2JZ")
            XCTAssertEqual(row.job.citations.first?.page.rawValue, 999)
            XCTAssertEqual(row.job.highlight?.isDemo, true)
            XCTAssertEqual(row.job.highlight?.partID.rawValue, partID)
            XCTAssertEqual(
                row.job.highlight?.geometry,
                HighlightViewerScript.geometry(
                    photoID: photoID,
                    partID: partID,
                    showingOutline: true
                )
            )
            XCTAssertGreaterThanOrEqual(row.job.highlight?.geometry?.polygons[0].points.count ?? 0, 5)
            XCTAssertFalse(row.job.answerText.contains("air box"))
            XCTAssertEqual(row.job.detent, .collapsed)
        }
    }

    func testOpeningAHistoryRowReturnsThatJobSheetAtHalf() {
        let row = JobHistoryScript.rows[1]
        let opened = row.openedSheet()
        XCTAssertEqual(opened.title, "Hard start")
        XCTAssertEqual(opened.outcome, .partly)
        XCTAssertEqual(opened.detent, .half)
        XCTAssertEqual(opened.photoID, "commons-supra-n5abh")
        XCTAssertEqual(opened.highlight?.bayPhotoID.rawValue, "commons-supra-n5abh")
        XCTAssertEqual(opened.highlight?.partID.rawValue, "fuse-relay-box")
        XCTAssertEqual(opened.answerText, JobSheetCopy.answer(photoID: "commons-supra-n5abh"))
        XCTAssertFalse(opened.answerText.contains("air box"))
        XCTAssertEqual(row.job.detent, .collapsed)
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

        XCTAssertEqual(entries.map(\.tagLabel), ScanLogScript.filterTags)
        let outlined = entries.filter { $0.presentation().showsOutline }
        XCTAssertEqual(outlined.count, 6)
        for entry in outlined {
            let shown = entry.presentation()
            let geometry = entry.geometry()
            XCTAssertEqual(shown.partID, DemoOutlineCatalog.selection(
                photoID: entry.photoID,
                state: entry.source
            ).partID)
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
            XCTAssertNotEqual(entry.tagLabel, "—")
            XCTAssertTrue(ScanLogCopy.chips.contains(entry.tagLabel))
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
            XCTAssertTrue(shown.allSatisfy { $0.tagLabel == chip }, chip)
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
        XCTAssertEqual(reference.tagLabel, "watch")
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
        XCTAssertFalse(JobHistoryCopy.subtitle.contains("chat"))
        XCTAssertFalse(ScanLogCopy.chips.contains("user"))
        XCTAssertEqual(JobHistoryScript.rows.count, 4)
        XCTAssertFalse(JobSheetCopy.answer.contains("FAKE-SPEC"))
        XCTAssertFalse(JobSheetCopy.answer.contains("air box"))
        XCTAssertTrue(JobSheetCopy.answer.contains("FAKE-DOC-2JZ"))
    }
}
