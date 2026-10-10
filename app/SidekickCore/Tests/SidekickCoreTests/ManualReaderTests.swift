import Foundation
import XCTest
@testable import SidekickCore

@MainActor
final class ManualReaderModelTests: XCTestCase {
    private let viewport = ViewSize(width: 390, height: 520)

    func testDragAtFitMovesTheStageByPageWidthPlusGap() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))

        model.handle(.drag(translation: ViewPoint(x: -140, y: 0)))

        XCTAssertEqual(model.stage.map(\.id.rawValue), [998, 999, 1000])
        XCTAssertEqual(model.stage.map(\.x), [-546, -140, 266])
        XCTAssertEqual(model.current.page.rawValue, 999)
        XCTAssertFalse(model.isZoomed)
    }

    func testReleasingTowardAReadyPageTurnsAndResetsInOneUpdate() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))
        model.handle(.drag(translation: ViewPoint(x: -140, y: 0)))

        model.handle(.dragEnded(translation: ViewPoint(x: -140, y: 0), predictedEnd: ViewPoint(x: -300, y: 0)))

        XCTAssertEqual(model.current, PageRef(docID: fakeDocument(), page: try page(1000)))
        XCTAssertEqual(model.headerPage, "Page 1000")
        XCTAssertEqual(model.stage.map(\.id.rawValue), [999, 1000])
        XCTAssertEqual(model.stage.map(\.x), [-406, 0])
        XCTAssertEqual(model.stage.last?.scale, 1)
        XCTAssertEqual(model.stage.last?.pan, .zero)
        XCTAssertFalse(model.isZoomed)
        XCTAssertNil(model.snippet)
    }

    func testArrowTurnWhileZoomedLandsOnTheNextPageAtFit() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))
        model.handle(.doubleTap(at: ViewPoint(x: 95, y: 260)))
        XCTAssertTrue(model.isZoomed)

        model.handle(.turn(.next))

        XCTAssertEqual(model.current.page.rawValue, 1000)
        XCTAssertEqual(model.stage.map(\.x), [-406, 0])
        XCTAssertEqual(model.stage.last?.scale, 1)
        XCTAssertEqual(model.stage.last?.pan, .zero)
        XCTAssertFalse(model.isZoomed)
    }

    func testDragTowardALoadingNeighborDoesNotTurn() async throws {
        let source = PagedManualPageSource(gated: [1000])
        let model = ManualReaderModel(anchor: try fakeCitation(), source: source)
        let window = Task { await model.loadWindow() }
        await source.waitUntilRequested(1000)
        model.handle(.layout(viewport: viewport))
        XCTAssertEqual(model.neighbor(.next), .loading)

        model.handle(.drag(translation: ViewPoint(x: -140, y: 0)))
        XCTAssertEqual(model.stage.map(\.x), [-42, 364])
        model.handle(.dragEnded(translation: ViewPoint(x: -140, y: 0), predictedEnd: ViewPoint(x: -300, y: 0)))
        model.handle(.turn(.next))

        XCTAssertEqual(model.current.page.rawValue, 999)
        XCTAssertEqual(model.stage.map(\.x), [0, 406])

        source.release(1000, with: .success(placeholderImage(page: 1000)))
        await window.value
        XCTAssertEqual(model.neighbor(.next), .ready)
    }

    func testDoubleTapZoomsAboutTheTapAndAgainReturnsToFit() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))

        model.handle(.doubleTap(at: ViewPoint(x: 95, y: 260)))
        let zoomed = try XCTUnwrap(model.stage.first(where: \.isCurrent))
        XCTAssertEqual(zoomed.scale, 2.5)
        XCTAssertEqual(zoomed.pan, ViewPoint(x: 150, y: 0))
        XCTAssertTrue(model.isZoomed)

        model.handle(.doubleTap(at: ViewPoint(x: 95, y: 260)))
        let fit = try XCTUnwrap(model.stage.first(where: \.isCurrent))
        XCTAssertEqual(fit.scale, 1)
        XCTAssertEqual(fit.pan, .zero)
        XCTAssertFalse(model.isZoomed)
    }

    func testPinchBelowFitSettlesAtFit() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))

        model.handle(.pinch(magnification: 0.6, anchor: ViewPoint(x: 120, y: 200)))
        let live = try XCTUnwrap(model.stage.first(where: \.isCurrent))
        XCTAssertEqual(live.scale, 0.88, accuracy: 0.000_001)

        model.handle(.pinchEnded)
        let settled = try XCTUnwrap(model.stage.first(where: \.isCurrent))
        XCTAssertEqual(settled.scale, 1)
        XCTAssertEqual(settled.pan, .zero)
        XCTAssertFalse(model.isZoomed)
    }

    func testZoomedDragPansAndClampsInsteadOfTurning() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))
        model.handle(.doubleTap(at: ViewPoint(x: 195, y: 260)))

        model.handle(.drag(translation: ViewPoint(x: -10, y: 0)))
        model.handle(.drag(translation: ViewPoint(x: -110, y: 0)))
        XCTAssertEqual(model.stage.map(\.x), [-406, 0, 406])
        XCTAssertEqual(model.stage.first(where: \.isCurrent)?.pan, ViewPoint(x: -100, y: 0))

        model.handle(.dragEnded(translation: ViewPoint(x: -110, y: 0), predictedEnd: ViewPoint(x: -1000, y: 0)))
        let current = try XCTUnwrap(model.stage.first(where: \.isCurrent))
        XCTAssertEqual(model.current.page.rawValue, 999)
        XCTAssertEqual(current.scale, 2.5)
        // Placeholder 64 by 88 fits 390 by 520 at 520/88, so the half overflow is (64 * 520/88 * 2.5 - 390) / 2.
        XCTAssertEqual(current.pan.x, -(64 * 520 / 88 * 2.5 - 390) / 2, accuracy: 0.000_001)
        XCTAssertEqual(current.pan.y, 0)
        XCTAssertTrue(model.isZoomed)
    }

    func testVerticalDragAtFitIsLeftForTheSheet() async throws {
        let model = ManualReaderModel(anchor: try fakeCitation(), source: PagedManualPageSource())
        await model.loadWindow()
        model.handle(.layout(viewport: viewport))

        model.handle(.drag(translation: ViewPoint(x: 30, y: 160)))
        model.handle(.drag(translation: ViewPoint(x: 200, y: 170)))
        model.handle(.dragEnded(translation: ViewPoint(x: 200, y: 170), predictedEnd: ViewPoint(x: 400, y: 400)))

        XCTAssertEqual(model.current.page.rawValue, 999)
        XCTAssertEqual(model.stage.map(\.x), [-406, 0, 406])
    }

    func testLoadKeepsTheCitationHeaderAndSnippetWithTheImage() async throws {
        let citation = try fakeCitation(snippet: "FAKE-SNIPPET quoted text")
        let source = PagedManualPageSource()
        let model = ManualReaderModel(anchor: citation, source: source)

        XCTAssertEqual(model.headerDocument, "FAKE-DOC")
        XCTAssertEqual(model.headerPage, "Page 999")
        XCTAssertEqual(model.snippet, "FAKE-SNIPPET quoted text")
        XCTAssertEqual(model.stage.map(\.slot), [.loading])
        XCTAssertNil(model.goDeeper)
        XCTAssertNil(model.askContext)

        await model.loadWindow()

        XCTAssertEqual(model.stage.map(\.id.rawValue), [998, 999, 1000])
        XCTAssertEqual(model.stage[1].slot, .ready(placeholderImage(page: 999)))
        XCTAssertEqual(model.goDeeper, CannedGoDeeper.fixturePage)
        XCTAssertEqual(model.askContext, PageRef(docID: fakeDocument(), page: try page(999)))
        XCTAssertEqual(source.requests, [999, 1000, 998])

        await model.loadWindow()
        XCTAssertEqual(source.requests, [999, 1000, 998])
    }

    func testLoadShowsCannedGoDeeperForTheFuseFixture() async throws {
        let citation = try XCTUnwrap(
            Citation(
                docID: DocumentID(rawValue: "FAKE-DOC-2JZ")!,
                page: PageNumber(rawValue: 999)!,
                snippet: "FAKE-SNIPPET: check the mapped fixture part."
            )
        )
        let model = ManualReaderModel(anchor: citation, source: PagedManualPageSource())

        await model.loadWindow()

        XCTAssertEqual(model.goDeeper, CannedGoDeeper.fuseBox)
        XCTAssertEqual(CannedGoDeeper.fuseBox.sections.map(\.title), [
            "How this works",
            "What to test",
            "How to test it",
            "Tools",
        ])
        for section in CannedGoDeeper.fuseBox.sections {
            XCTAssertTrue(CannedGoDeeper.fakePageText.contains(section.body))
        }
        XCTAssertFalse(CannedGoDeeper.fuseBox.howItWorks?.contains("FAKE-SPEC") == true)
    }

    func testMissingCurrentPageFailsAndMissingNeighborEndsTheDocument() async throws {
        let source = PagedManualPageSource(scripted: [
            999: [.failure(ManualPageError.missingPage)],
            1000: [.failure(ManualPageError.missingPage)],
        ])
        let model = ManualReaderModel(anchor: try fakeCitation(snippet: "FAKE-SNIPPET"), source: source)

        await model.loadWindow()

        XCTAssertEqual(model.currentFailure, .missingPage)
        XCTAssertEqual(model.snippet, "FAKE-SNIPPET")
        XCTAssertEqual(model.headerPage, "Page 999")
        XCTAssertNil(model.askContext)
        XCTAssertEqual(model.neighbor(.next), .end)
        XCTAssertEqual(model.neighbor(.previous), .ready)
    }

    func testUnreadableImageAndUnknownFailure() async throws {
        let wrongDocument = try XCTUnwrap(DocumentID(rawValue: "FAKE-OTHER"))
        let source = PagedManualPageSource(scripted: [
            999: [
                .success(ManualPageImage(docID: wrongDocument, page: try page(999), pngData: ManualPagePlaceholder.pngData())),
                .success(ManualPageImage(docID: fakeDocument(), page: try page(999), pngData: Data("FAKE-BYTES".utf8))),
                .failure(SamplePageFailure()),
            ],
        ])
        let model = ManualReaderModel(anchor: try fakeCitation(), source: source)

        await model.loadWindow()
        XCTAssertEqual(model.currentFailure, .badImage)
        await model.loadWindow()
        XCTAssertEqual(model.currentFailure, .badImage)
        await model.loadWindow()
        XCTAssertEqual(model.currentFailure, .unavailable)
        XCTAssertEqual(source.requests, [999, 1000, 998, 999, 999])
    }

    func testRetryAfterAnErrorCanLoadThePage() async throws {
        let source = PagedManualPageSource(scripted: [999: [.failure(ManualPageError.unavailable)]])
        let model = ManualReaderModel(anchor: try fakeCitation(), source: source)

        await model.loadWindow()
        XCTAssertEqual(model.currentFailure, .unavailable)
        await model.loadWindow()

        XCTAssertNil(model.currentFailure)
        XCTAssertEqual(model.stage[1].slot, .ready(placeholderImage(page: 999)))
        XCTAssertEqual(source.requests, [999, 1000, 998, 999])
    }

    func testOverlappingLoadUsesOneRequestPerPage() async throws {
        let source = PagedManualPageSource(gated: [999])
        let model = ManualReaderModel(anchor: try fakeCitation(), source: source)
        let first = Task { await model.loadWindow() }
        await source.waitUntilRequested(999)

        XCTAssertEqual(model.stage.first(where: \.isCurrent)?.slot, .loading)
        await model.loadWindow()
        XCTAssertEqual(source.requests, [999, 1000, 998])

        source.release(999, with: .success(placeholderImage(page: 999)))
        await first.value

        XCTAssertEqual(source.requests, [999, 1000, 998])
        XCTAssertEqual(model.askContext?.page.rawValue, 999)
    }

    func testCancelledLoadIsNotAFailureAndTheNextWindowRetries() async throws {
        let source = PagedManualPageSource(gated: [999])
        let model = ManualReaderModel(anchor: try fakeCitation(), source: source)
        let window = Task { await model.loadWindow() }
        await source.waitUntilRequested(999)

        window.cancel()
        source.release(999, with: .failure(CancellationError()))
        await window.value

        XCTAssertNil(model.currentFailure)
        XCTAssertEqual(model.stage.first(where: \.isCurrent)?.slot, .loading)

        await model.loadWindow()
        XCTAssertEqual(model.askContext?.page.rawValue, 999)
        XCTAssertEqual(source.requests.filter { $0 == 999 }.count, 2)
    }

    func testTurningLoadsTheNewNeighborAndDropsFarPages() async throws {
        let source = PagedManualPageSource()
        let model = ManualReaderModel(anchor: try fakeCitation(), source: source)
        await model.loadWindow()

        model.handle(.turn(.next))
        await model.loadWindow()
        model.handle(.turn(.next))
        await model.loadWindow()
        XCTAssertEqual(model.current.page.rawValue, 1001)

        model.handle(.turn(.previous))
        model.handle(.turn(.previous))
        await model.loadWindow()

        XCTAssertEqual(model.current.page.rawValue, 999)
        XCTAssertEqual(model.snippet, "FAKE-SNIPPET")
        XCTAssertEqual(source.requests, [999, 1000, 998, 1001, 1002, 998])
    }
}

private struct SamplePageFailure: Error {}

private func fakeDocument() -> DocumentID {
    DocumentID(rawValue: "FAKE-DOC")!
}

private func page(_ number: Int) throws -> PageNumber {
    try XCTUnwrap(PageNumber(rawValue: number))
}

private func fakeCitation(snippet: String = "FAKE-SNIPPET") throws -> Citation {
    try XCTUnwrap(Citation(docID: fakeDocument(), page: try page(999), snippet: snippet))
}

private func placeholderImage(page number: Int) -> ManualPageImage {
    ManualPageImage(docID: fakeDocument(), page: PageNumber(rawValue: number)!, pngData: ManualPagePlaceholder.pngData())
}

/// Serves the placeholder for any page unless a page has scripted results or is gated.
private final class PagedManualPageSource: ManualPageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var scripted: [Int: [Result<ManualPageImage, Error>]]
    private var gated: Set<Int>
    private var waiters: [Int: CheckedContinuation<ManualPageImage, Error>] = [:]
    private var log: [Int] = []

    init(scripted: [Int: [Result<ManualPageImage, Error>]] = [:], gated: Set<Int> = []) {
        self.scripted = scripted
        self.gated = gated
    }

    var requests: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        let number = page.rawValue
        let immediate: Result<ManualPageImage, Error>? = {
            lock.lock()
            defer { lock.unlock() }
            if gated.contains(number) { return nil }
            log.append(number)
            if var queue = scripted[number], !queue.isEmpty {
                let next = queue.removeFirst()
                scripted[number] = queue
                return next
            }
            return .success(ManualPageImage(docID: docID, page: page, pngData: ManualPagePlaceholder.pngData()))
        }()
        if let immediate { return try immediate.get() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            waiters[number] = continuation
            log.append(number)
            lock.unlock()
        }
    }

    func waitUntilRequested(_ number: Int) async {
        for _ in 0..<10_000 {
            if requests.contains(number) { return }
            await Task.yield()
        }
        XCTFail("timed out waiting for page \(number)")
    }

    /// Answers the waiting request and serves later requests for that page without a gate.
    func release(_ number: Int, with result: Result<ManualPageImage, Error>) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: number)
        gated.remove(number)
        lock.unlock()
        waiter?.resume(with: result)
    }
}
