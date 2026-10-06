import XCTest
@testable import SidekickCore

final class JobSheetTests: XCTestCase {
    func testCollapsedAndHalfMoveWithOpenAndClose() async {
        await MainActor.run {
            let model = JobSheetViewModel(job: JobSheetScript.makeJob(detent: .collapsed, photoID: nil))
            XCTAssertEqual(model.detent, .collapsed)
            XCTAssertFalse(model.blocksChat)

            model.open()
            XCTAssertEqual(model.detent, .half)
            XCTAssertTrue(model.blocksChat)

            model.close()
            XCTAssertEqual(model.detent, .collapsed)
            XCTAssertFalse(model.blocksChat)
        }
    }

    func testDragMovesCollapsedHalfAndFull() async {
        await MainActor.run {
            let model = JobSheetViewModel(job: JobSheetScript.makeJob(detent: .collapsed, photoID: nil))
            model.applyDrag(translationHeight: -80)
            XCTAssertEqual(model.detent, .half)
            model.applyDrag(translationHeight: -80)
            XCTAssertEqual(model.detent, .full)
            model.applyDrag(translationHeight: 80)
            XCTAssertEqual(model.detent, .half)
            model.applyDrag(translationHeight: 80)
            XCTAssertEqual(model.detent, .collapsed)
            model.applyDrag(translationHeight: 10)
            XCTAssertEqual(model.detent, .collapsed)
        }
    }

    func testOutcomeIsExclusiveAndNeedsNoPartName() async {
        await MainActor.run {
            let model = JobSheetViewModel(job: JobSheetScript.makeJob(detent: .half, photoID: nil))
            XCTAssertNil(model.job?.outcome)
            XCTAssertEqual(JobOutcome.allCases.map(\.label), ["Worked", "Partly", "Didn't"])

            model.selectOutcome(.partly)
            XCTAssertEqual(model.job?.outcome, .partly)
            model.selectOutcome(.didnt)
            XCTAssertEqual(model.job?.outcome, .didnt)
            model.selectOutcome(.worked)
            XCTAssertEqual(model.job?.outcome, .worked)
            XCTAssertEqual(JobSheetCopy.answer.contains("FAKE-DOC-2JZ"), true)
            XCTAssertFalse(JobSheetCopy.answer.contains("FAKE-SPEC"))
            XCTAssertFalse(JobSheetCopy.answer.contains("air box"))
            XCTAssertTrue(JobSheetCopy.answer.contains("fuse/relay box"))
        }
    }

    func testAttachBindsPhotoToThisJobNotABayMap() async {
        await MainActor.run {
            let model = JobSheetViewModel(job: JobSheetScript.makeJob(detent: .half, photoID: nil))
            XCTAssertFalse(model.job?.hasPhoto == true)

            model.attachPhoto(photoID: "commons-hilux-2jz")
            XCTAssertEqual(model.job?.photoID, "commons-hilux-2jz")
            XCTAssertTrue(model.job?.hasPhoto == true)
            XCTAssertEqual(model.job?.highlight?.bayPhotoID.rawValue, "commons-hilux-2jz")
            XCTAssertEqual(model.job?.highlight?.partID.rawValue, "fuse-relay-box")
            XCTAssertEqual(model.job?.highlight?.isDemo, true)
            XCTAssertEqual(
                model.job?.highlight?.geometry,
                HighlightViewerScript.geometry(
                    photoID: "commons-hilux-2jz",
                    partID: "fuse-relay-box",
                    showingOutline: true
                )
            )
            XCTAssertTrue(model.job?.answerText.contains("fuse/relay box") == true)
            XCTAssertFalse(model.job?.answerText.contains("air box") == true)
            XCTAssertGreaterThanOrEqual(model.job?.highlight?.geometry?.polygons[0].points.count ?? 0, 5)

            model.attachPhoto(photoID: "hrymx-2jz-ge-25308847029")
            XCTAssertEqual(model.job?.highlight?.partID.rawValue, "throttle-body")
            XCTAssertTrue(model.job?.answerText.contains("throttle body") == true)
            XCTAssertEqual(
                model.job?.highlight?.geometry,
                HighlightViewerScript.geometry(
                    photoID: "hrymx-2jz-ge-25308847029",
                    partID: "throttle-body",
                    showingOutline: true
                )
            )
        }
    }

    func testSyncTakesLatestAssistantAndKeepsExistingJob() async {
        await MainActor.run {
            let model = JobSheetViewModel()
            model.sync(from: JobSheetScript.messages, photoID: DemoLaunchOptions.defaultPhotoID)
            XCTAssertEqual(model.job?.sourceMessageID, JobSheetScript.assistantMessageID)
            XCTAssertEqual(model.job?.title, JobSheetCopy.title)
            XCTAssertEqual(model.job?.detent, .collapsed)
            XCTAssertEqual(model.job?.citations.first?.docID.rawValue, "FAKE-DOC-2JZ")
            XCTAssertEqual(model.job?.citations.first?.page.rawValue, 999)

            model.open()
            model.selectOutcome(.worked)
            model.sync(from: JobSheetScript.messages, photoID: "other-photo")
            XCTAssertEqual(model.detent, .half)
            XCTAssertEqual(model.job?.outcome, .worked)
            XCTAssertEqual(model.job?.photoID, DemoLaunchOptions.defaultPhotoID)
        }
    }

    func testLaunchScreensOpenEachDetentAndCloseout() async {
        let collapsed = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "job-sheet-collapsed"],
            environment: [:]
        )
        XCTAssertEqual(collapsed.jobSheetScreen, .collapsed)
        XCTAssertNil(collapsed.screen)
        XCTAssertTrue(collapsed.opensJobSheet)
        XCTAssertFalse(collapsed.opensHighlightViewer)
        XCTAssertTrue(collapsed.enablesDemoMode)
        XCTAssertEqual(collapsed.cannedQuestion, JobSheetCopy.question)

        let half = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "job-sheet-half"],
            environment: [:]
        )
        XCTAssertEqual(half.jobSheetScreen?.detent, .half)
        XCTAssertNil(half.jobSheetScreen?.outcome)

        let full = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "job-sheet-full"],
            environment: [:]
        )
        XCTAssertEqual(full.jobSheetScreen?.detent, .full)

        let closeout = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: ["SIDEKICK_SCREEN": "job-sheet-closeout"]
        )
        XCTAssertEqual(closeout.jobSheetScreen, .closeout)
        XCTAssertEqual(closeout.jobSheetScreen?.detent, .half)
        XCTAssertEqual(closeout.jobSheetScreen?.outcome, .worked)

        await MainActor.run {
            let model = JobSheetViewModel()
            model.applyLaunch(.closeout, photoID: DemoLaunchOptions.defaultPhotoID)
            XCTAssertEqual(model.detent, .half)
            XCTAssertEqual(model.job?.outcome, .worked)
            XCTAssertEqual(model.job?.photoID, DemoLaunchOptions.defaultPhotoID)
            XCTAssertEqual(model.job?.headerTitle, "Job · Cold idle")
            XCTAssertEqual(model.job?.highlight?.partID.rawValue, "fuse-relay-box")
            XCTAssertTrue(model.job?.answerText.contains("fuse/relay box") == true)
            XCTAssertFalse(model.job?.answerText.contains("air box") == true)
        }
    }

    func testV1SheetHasNoLaterBacklogFields() {
        XCTAssertEqual(JobSheetCopy.chip, HighlightViewerCopy.diagramChip)
        XCTAssertFalse(JobSheetCopy.answer.contains("Step"))
        XCTAssertFalse(JobSheetCopy.answer.contains("Notes"))
        XCTAssertFalse(JobSheetCopy.answer.contains("Tags"))
        XCTAssertFalse(JobSheetCopy.answer.contains("air box"))
        XCTAssertEqual(
            JobSheetCopy.answer(photoID: "commons-supra-n5abh"),
            "Start with the fuse/relay box. FAKE-DOC-2JZ p. 999. No guessed numbers."
        )
        XCTAssertEqual(
            JobSheetCopy.answer(photoID: "flickr-robmarson-6763892857"),
            "Start with the throttle body. FAKE-DOC-2JZ p. 999. No guessed numbers."
        )
        XCTAssertEqual(JobSheetScreen.allCases.map(\.rawValue), [
            "job-sheet-collapsed",
            "job-sheet-half",
            "job-sheet-full",
            "job-sheet-closeout",
        ])
    }
}
