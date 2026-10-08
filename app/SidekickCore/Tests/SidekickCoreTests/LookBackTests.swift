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
        XCTAssertEqual(ScanLogCopy.selectedChip, "intake")
        XCTAssertEqual(ScanLogCopy.thumbBanner, "Not your truck")
        XCTAssertLessThan(ScanLogCopy.thumbBanner.count, HighlightViewerCopy.referenceBanner.count)
        XCTAssertFalse(ScanLogCopy.thumbBanner.contains("Demo"))

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
