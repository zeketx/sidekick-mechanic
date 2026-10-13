import XCTest
@testable import SidekickCore

final class JobSheetTests: XCTestCase {
    func testCollapsedAndHalfMoveWithOpenAndClose() async {
        await MainActor.run {
            let model = JobSheetViewModel(detent: .collapsed)
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
            let model = JobSheetViewModel(detent: .collapsed)
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

    func testOutcomeLabelsNeedNoPartName() {
        XCTAssertEqual(JobOutcome.allCases.map(\.label), ["Worked", "Partly", "Didn't"])
        XCTAssertEqual(JobSheetCopy.howDidItGo, "How did it go?")
        XCTAssertEqual(JobSheetCopy.whatFixedPlaceholder, "What fixed it? (optional)")
        XCTAssertEqual(JobSheetCopy.answer.contains("FAKE-DOC-2JZ"), true)
        XCTAssertFalse(JobSheetCopy.answer.contains("FAKE-SPEC"))
        XCTAssertFalse(JobSheetCopy.answer.contains("air box"))
        XCTAssertTrue(JobSheetCopy.answer.contains("fuse/relay box"))
    }

    func testNotesAndTagCopyStayFixtureOnly() {
        XCTAssertEqual(JobSheetCopy.notesHeading, "Notes")
        XCTAssertEqual(JobSheetCopy.tagsHeading, "Tags")
        XCTAssertEqual(JobSheetCopy.addTag, "+ add")
        XCTAssertEqual(JobSheetCopy.notesPlaceholder, "Hoses look dry. No numbers guessed.")
        XCTAssertFalse(JobSheetCopy.notesPlaceholder.contains("FAKE-SPEC"))
        XCTAssertFalse(JobSheetCopy.whatFixedPlaceholder.contains("FAKE-SPEC"))
    }

    func testLaunchScreensOpenEachDetentAndCloseout() {
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
        XCTAssertEqual(full.jobSheetScreen?.outcome, .worked)

        let closeout = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: ["SIDEKICK_SCREEN": "job-sheet-closeout"]
        )
        XCTAssertEqual(closeout.jobSheetScreen, .closeout)
        XCTAssertEqual(closeout.jobSheetScreen?.detent, .half)
        XCTAssertEqual(closeout.jobSheetScreen?.outcome, .worked)
        XCTAssertFalse(closeout.opensCitationPage)

        let citation = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "citation-page"],
            environment: [:]
        )
        XCTAssertEqual(citation.citationPageScreen, .page)
        XCTAssertTrue(citation.opensCitationPage)
        XCTAssertTrue(citation.opensJobSheet)
        XCTAssertNil(citation.jobSheetScreen)
        XCTAssertTrue(citation.enablesDemoMode)

        let job = JobSheetScript.job(
            photoID: DemoLaunchOptions.defaultPhotoID,
            outcome: .worked,
            now: Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(job.outcome, .worked)
        XCTAssertTrue(JobSheetLayout.fillsSelectedOutcome(detent: .half, outcome: .worked))
        XCTAssertTrue(JobSheetLayout.fillsSelectedOutcome(detent: .full, outcome: .worked))
        XCTAssertEqual(job.photoID, DemoLaunchOptions.defaultPhotoID)
        XCTAssertEqual(job.headerTitle, "Job · Cold idle")
        XCTAssertEqual(job.tags, ["fuse/relay", "inspected"])
        XCTAssertEqual(job.highlight?.partID.rawValue, "fuse-relay-box")
        XCTAssertEqual(job.answerText.contains("fuse/relay box"), true)
        XCTAssertEqual(job.answerText.contains("air box"), false)
        XCTAssertEqual(job.citations.first?.docID.rawValue, "FAKE-DOC-2JZ")
        XCTAssertEqual(job.citations.first?.page.rawValue, 999)
        XCTAssertEqual(job.relatedCitations, [])
        XCTAssertEqual(job.conversation.messages.count, 2)
    }

    func testRelatedPagesStayOffTheCitedChipList() throws {
        let related = try XCTUnwrap(
            Citation(
                docID: try XCTUnwrap(DocumentID(rawValue: "FAKE-DOC")),
                page: try XCTUnwrap(PageNumber(rawValue: 999)),
                snippet: "FAKE-SNIPPET"
            )
        )
        let advice = try XCTUnwrap(
            GeneralAdvice(
                steps: ["FAKE-STEP: check the fixture connection before the fixture motor."],
                garage: .none,
                related: [related]
            )
        )
        let job = JobSheetState(
            id: try XCTUnwrap(JobID(rawValue: "job-fake")),
            title: "FAKE",
            createdAt: Date(timeIntervalSince1970: 0),
            conversation: Conversation(
                id: try XCTUnwrap(ConversationID(rawValue: "job-fake")),
                messages: [
                    .assistant(
                        AssistantMessage(
                            id: try XCTUnwrap(MessageID(rawValue: "m-fake")),
                            answer: .generalAdvice(advice)
                        )
                    )
                ]
            )
        )

        XCTAssertEqual(job.citations, [])
        XCTAssertEqual(job.relatedCitations, [related])
        XCTAssertEqual(related.chipLabel, "FAKE-DOC · p. 999")
        XCTAssertEqual(
            AnswerCardContent.relatedHint,
            "Opens a related manual page. This page did not answer the question."
        )
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
        XCTAssertEqual(JobSheetCopy.stepsHeading, "Steps 1 of 3")
        XCTAssertEqual(
            JobSheetCopy.steps(photoID: "commons-hilux-2jz").map(\.title),
            ["Look at the fuse/relay box", "Next step (from the cited page)"]
        )
        XCTAssertEqual(
            JobSheetCopy.steps(photoID: "commons-hilux-2jz").map(\.isComplete),
            [true, false]
        )
        XCTAssertEqual(
            JobSheetCopy.steps(photoID: "hrymx-2jz-ge-25308847029").first?.title,
            "Look at the throttle body"
        )
        XCTAssertEqual(JobSheetCopy.partChip(photoID: "commons-hilux-2jz"), "fuse/relay")
        XCTAssertEqual(JobSheetCopy.partChip(photoID: "commons-supra-n5abh"), "fuse/relay")
        XCTAssertEqual(JobSheetCopy.partChip(photoID: "hrymx-2jz-ge-25308847029"), "throttle")
        XCTAssertFalse(JobSheetCopy.firstStep(displayName: "fuse/relay box").contains("FAKE-SPEC"))
        XCTAssertFalse(JobSheetCopy.nextStep.contains("air box"))
        XCTAssertEqual(
            JobSheetCopy.creditLine(attribution: "Demo data. Not Zeke's truck.", shareAlike: true),
            "CC BY-SA. Demo data. Not Zeke's truck."
        )
        XCTAssertEqual(
            JobSheetLayout.height(detent: .full, screenHeight: 874, topSafeArea: 62),
            874
        )
        XCTAssertEqual(
            JobSheetLayout.contentTopInset(detent: .full, topSafeArea: 62),
            62
        )
        XCTAssertEqual(
            JobSheetLayout.contentTopInset(detent: .half, topSafeArea: 62),
            0
        )
        XCTAssertEqual(JobSheetLayout.halfOutcomeTopSpacing, 16)
        XCTAssertEqual(JobSheetLayout.composerHomeInset(hasJob: true, bottomSafeArea: 34), 0)
        XCTAssertEqual(JobSheetLayout.composerHomeInset(hasJob: false, bottomSafeArea: 34), 34)
        XCTAssertEqual(JobSheetLayout.composerHomeInset(hasJob: false, bottomSafeArea: 336), 0)
        XCTAssertEqual(JobSheetLayout.height(detent: .collapsed, screenHeight: 874, topSafeArea: 62), 128)
        XCTAssertLessThan(
            JobSheetLayout.height(detent: .half, screenHeight: 874, topSafeArea: 62),
            874 - 62
        )
        XCTAssertEqual(JobSheetLayout.halfPhotoHeight, 72)
        XCTAssertEqual(JobSheetLayout.halfScrollBottomPadding, 24)
        XCTAssertGreaterThanOrEqual(
            JobSheetLayout.height(detent: .half, screenHeight: 844, topSafeArea: 59),
            380
        )
        XCTAssertEqual(
            JobSheetLayout.height(detent: .half, screenHeight: 874, topSafeArea: 62),
            min(874 * JobSheetLayout.halfHeightFraction, JobSheetLayout.halfMaxHeight)
        )
        XCTAssertTrue(JobSheetLayout.fillsSelectedOutcome(detent: .full, outcome: nil))
        XCTAssertTrue(JobSheetLayout.fillsSelectedOutcome(detent: .full, outcome: .worked))
        XCTAssertFalse(JobSheetLayout.fillsSelectedOutcome(detent: .half, outcome: nil))
        XCTAssertTrue(JobSheetLayout.fillsSelectedOutcome(detent: .half, outcome: .worked))
        XCTAssertFalse(JobSheetLayout.fillsSelectedOutcome(detent: .collapsed, outcome: .worked))
        XCTAssertEqual(JobSheetLayout.halfPhotoHeight(isAccessibilitySize: false), 72)
        XCTAssertEqual(JobSheetLayout.halfPhotoHeight(isAccessibilitySize: true), 0)
        XCTAssertFalse(JobSheetLayout.stacksOutcome(isAccessibilitySize: false))
        XCTAssertTrue(JobSheetLayout.stacksOutcome(isAccessibilitySize: true))
        let halfDefault = JobSheetLayout.height(
            detent: .half,
            screenHeight: 874,
            topSafeArea: 62,
            isAccessibilitySize: false
        )
        let halfAccess = JobSheetLayout.height(
            detent: .half,
            screenHeight: 874,
            topSafeArea: 62,
            isAccessibilitySize: true
        )
        XCTAssertEqual(halfDefault, min(874 * JobSheetLayout.halfHeightFraction, JobSheetLayout.halfMaxHeight))
        XCTAssertEqual(
            JobSheetLayout.height(
                detent: .half,
                screenHeight: 874,
                topSafeArea: 0,
                isAccessibilitySize: false
            ),
            halfDefault
        )
        XCTAssertGreaterThan(halfAccess, halfDefault)
        let accessTop = JobSheetLayout.accessibilityHalfTopGap(topSafeArea: 62)
        XCTAssertEqual(accessTop, 62 + JobSheetLayout.halfAccessibilityChatSliver)
        XCTAssertEqual(
            JobSheetLayout.accessibilityHalfTopGap(topSafeArea: 0),
            JobSheetLayout.fallbackTopSafeArea + JobSheetLayout.halfAccessibilityChatSliver
        )
        XCTAssertEqual(halfAccess, 874 - accessTop)
        XCTAssertGreaterThanOrEqual(accessTop, 62 + 24)
        XCTAssertLessThan(halfAccess, 874 - 62)
        XCTAssertEqual(
            JobSheetLayout.originY(
                detent: .half,
                screenHeight: 874,
                topSafeArea: 62,
                isAccessibilitySize: true
            ),
            accessTop
        )
        XCTAssertEqual(
            JobSheetLayout.originY(
                detent: .half,
                screenHeight: 874,
                topSafeArea: 62,
                isAccessibilitySize: true
            ) + halfAccess,
            874
        )
        XCTAssertEqual(JobSheetLayout.horizontalInset, 0)
        XCTAssertEqual(JobSheetLayout.width(screenWidth: 402), 402)
        XCTAssertEqual(JobSheetLayout.topCornerRadius, 24)
        XCTAssertGreaterThanOrEqual(JobSheetLayout.headerTopClearance, 32)
        XCTAssertEqual(
            JobSheetLayout.grabberTopPadding
                + JobSheetLayout.grabberHeight
                + JobSheetLayout.grabberBottomPadding
                + JobSheetLayout.headerPaddingUnderGrabber,
            JobSheetLayout.headerTopClearance
        )
    }

    func testSheetIsEdgeToEdgeAndFullReachesScreenBottom() {
        let screenHeight = 874.0
        let screenWidth = 402.0
        let top = 62.0
        XCTAssertEqual(JobSheetLayout.width(screenWidth: screenWidth), screenWidth)
        XCTAssertEqual(JobSheetLayout.horizontalInset, 0)

        for detent in JobSheetDetent.allCases {
            let height = JobSheetLayout.height(
                detent: detent,
                screenHeight: screenHeight,
                topSafeArea: top
            )
            let origin = JobSheetLayout.originY(
                detent: detent,
                screenHeight: screenHeight,
                topSafeArea: top
            )
            XCTAssertEqual(origin + height, screenHeight)
            XCTAssertEqual(JobSheetLayout.bottomY(screenHeight: screenHeight), screenHeight)
        }

        let full = JobSheetLayout.height(detent: .full, screenHeight: screenHeight, topSafeArea: top)
        XCTAssertEqual(full, screenHeight)
        XCTAssertEqual(
            JobSheetLayout.originY(detent: .full, screenHeight: screenHeight, topSafeArea: top),
            0
        )
        XCTAssertEqual(
            JobSheetLayout.originY(detent: .full, screenHeight: screenHeight, topSafeArea: top) + full,
            screenHeight
        )
        XCTAssertEqual(JobSheetLayout.contentTopInset(detent: .full, topSafeArea: top), top)
    }

    func testComposerCornerRadiusStaysPillWhenMultiline() {
        let single: Double = 37
        let multiline: Double = 103
        XCTAssertEqual(ComposerLayout.cornerRadius(height: single), single / 2)
        XCTAssertEqual(ComposerLayout.cornerRadius(height: multiline), multiline / 2)
        XCTAssertGreaterThan(
            ComposerLayout.cornerRadius(height: multiline),
            ComposerLayout.maxCornerRadius
        )
        for height in [single, multiline] {
            let ratio = ComposerLayout.cornerRadius(height: height) / (height / 2)
            XCTAssertGreaterThanOrEqual(ratio, ComposerLayout.pillRatioMinimum)
        }
    }

    func testFullHeightCoversNavHeaderBelowStatusBar() {
        let screen = 874.0
        let top = 62.0
        let full = JobSheetLayout.height(detent: .full, screenHeight: screen, topSafeArea: top)
        let uncovered = screen - full
        XCTAssertEqual(uncovered, 0)
        XCTAssertEqual(full, screen)
        XCTAssertEqual(JobSheetLayout.contentTopInset(detent: .full, topSafeArea: top), top)
        XCTAssertLessThanOrEqual(uncovered, top + JobSheetLayout.fullTopGap)
        XCTAssertGreaterThanOrEqual(full, screen - top)
        XCTAssertGreaterThan(
            full,
            screen - top - JobSheetLayout.navigationBarHeight
        )

        let zeroTop = JobSheetLayout.height(detent: .full, screenHeight: screen, topSafeArea: 0)
        XCTAssertEqual(JobSheetLayout.resolvedTopSafeArea(0), 59)
        XCTAssertEqual(zeroTop, screen)
        XCTAssertEqual(JobSheetLayout.contentTopInset(detent: .full, topSafeArea: 0), 59)
        XCTAssertEqual(screen - zeroTop, 0)
    }

    func testScrimOpacityIsMonotonicAndBounded() {
        let collapsed = JobSheetLayout.scrimOpacity(detent: .collapsed)
        let half = JobSheetLayout.scrimOpacity(detent: .half)
        let full = JobSheetLayout.scrimOpacity(detent: .full)
        XCTAssertEqual(collapsed, 0)
        XCTAssertEqual(half, 0.30)
        XCTAssertEqual(full, 0.40)
        XCTAssertLessThan(collapsed, half)
        XCTAssertLessThan(half, full)
        for opacity in [collapsed, half, full] {
            XCTAssertGreaterThanOrEqual(opacity, 0)
            XCTAssertLessThanOrEqual(opacity, 0.45)
        }
        XCTAssertGreaterThanOrEqual(half, 0.25)
        XCTAssertLessThanOrEqual(half, 0.40)
        XCTAssertGreaterThanOrEqual(full, 0.25)
        XCTAssertLessThanOrEqual(full, 0.40)
    }

    func testDemoChromeStaysOffUnlessLaunchArg() {
        let hidden = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "job-sheet-half"],
            environment: [:]
        )
        XCTAssertFalse(hidden.showDemoChrome)
        XCTAssertTrue(hidden.opensJobSheet)

        let shown = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-showDemoChrome", "1"],
            environment: [:]
        )
        XCTAssertTrue(shown.showDemoChrome)
        XCTAssertFalse(shown.enablesDemoMode)

        let env = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic"],
            environment: ["SIDEKICK_SHOW_DEMO_CHROME": "true"]
        )
        XCTAssertTrue(env.showDemoChrome)
    }

    func testAccessibilityLaunchArgIsOffByDefault() {
        let off = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "job-sheet-half"],
            environment: [:]
        )
        XCTAssertFalse(off.prefersAccessibilitySize)

        let on = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-dynamicTypeSize", "accessibility5"],
            environment: [:]
        )
        XCTAssertTrue(on.prefersAccessibilitySize)

        let uiKit = DemoLaunchOptions.parse(
            arguments: [
                "SidekickMechanic",
                "-UIPreferredContentSizeCategoryName",
                "UIContentSizeCategoryAccessibilityXXXL",
            ],
            environment: [:]
        )
        XCTAssertTrue(uiKit.prefersAccessibilitySize)
    }
}
