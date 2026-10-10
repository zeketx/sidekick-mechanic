import Foundation
import Observation

/// One manual page. Identity only. The server owns the page's text.
public struct PageRef: Hashable, Sendable, Codable {
    public let docID: DocumentID
    public let page: PageNumber

    public init(docID: DocumentID, page: PageNumber) {
        self.docID = docID
        self.page = page
    }

    /// Same wording as a citation chip.
    public var chipLabel: String {
        "\(docID.rawValue) · p. \(page.rawValue)"
    }

    enum CodingKeys: String, CodingKey {
        case docID = "doc_id"
        case page
    }
}

extension Citation {
    public var pageRef: PageRef {
        PageRef(docID: docID, page: page)
    }
}

public enum PageDirection: Hashable, Sendable {
    case previous
    case next
}

/// Viewport points, top-left origin, the same space as SwiftUI gesture locations.
public struct ViewPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = ViewPoint(x: 0, y: 0)
}

public struct ViewSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = ViewSize(width: 0, height: 0)
}

/// Everything the page viewport can receive. The view forwards these untouched.
public enum ReaderInput: Hashable, Sendable {
    case layout(viewport: ViewSize)
    case pinch(magnification: Double, anchor: ViewPoint)
    case pinchEnded
    case drag(translation: ViewPoint)
    case dragEnded(translation: ViewPoint, predictedEnd: ViewPoint)
    case doubleTap(at: ViewPoint)
    case turn(PageDirection)

    /// Ended gestures, double taps, and turns animate to rest. Live tracking follows the finger.
    public var settles: Bool {
        switch self {
        case .pinchEnded, .dragEnded, .doubleTap, .turn:
            true
        case .layout, .pinch, .drag:
            false
        }
    }
}

public enum PageSlot: Equatable, Sendable {
    case loading
    case ready(ManualPageImage)
    case failed(ManualPageError)
    /// A neighbor that 404s. The document ends here.
    case missing
}

/// "zoomed 2.5x". One decimal and POSIX digits so a UI test can read the scale.
public enum ZoomAccessibility {
    public static func value(scale: Double) -> String {
        let tenths = Int((scale * 10).rounded())
        return "zoomed \(tenths / 10).\(abs(tenths % 10))x"
    }
}

public enum NeighborStatus: Equatable, Sendable {
    case ready
    case loading
    case failed
    case end
}

/// What the view draws for one page. Positions are final.
public struct StagedPage: Identifiable, Equatable, Sendable {
    public let id: PageNumber
    public let slot: PageSlot
    /// Offset of this page's center from the viewport center.
    public let x: Double
    /// 1 for neighbors.
    public let scale: Double
    /// Zero for neighbors.
    public let pan: ViewPoint
    public let isCurrent: Bool
}

/// The open manual page, its neighbors, zoom, and paging. One per presented sheet.
///
/// A turn only targets a `.ready` neighbor, so the page that slides in is already drawn.
/// A turn resets zoom, moves the current page, and zeroes the swipe in one write.
@MainActor
@Observable
public final class ManualReaderModel {
    public let anchor: Citation
    private var state: ReaderState
    private var slots: [PageNumber: PageSlot]
    private var goDeeperByPage: [PageNumber: GoDeeper]

    @ObservationIgnored private var inFlight: Set<PageNumber> = []
    @ObservationIgnored private let source: any ManualPageSource
    @ObservationIgnored private let goDeeperSource: any GoDeeperSource

    public init(
        anchor: Citation,
        source: any ManualPageSource,
        goDeeperSource: any GoDeeperSource = CannedGoDeeperSource()
    ) {
        self.anchor = anchor
        self.source = source
        self.goDeeperSource = goDeeperSource
        self.state = ReaderState(current: anchor.page)
        self.slots = [:]
        self.goDeeperByPage = [:]
    }

    public var current: PageRef {
        PageRef(docID: anchor.docID, page: state.current)
    }

    public var headerDocument: String { anchor.docID.rawValue }
    public var headerPage: String { "Page \(state.current.rawValue)" }

    /// The chip's snippet belongs to the anchor page only.
    public var snippet: String? {
        state.current == anchor.page ? anchor.snippet : nil
    }

    public var goDeeper: GoDeeper? { goDeeperByPage[state.current] }

    public var isZoomed: Bool { state.zoom != .fit }

    /// Scale the page image reports to UI tests. The accessibility frame does not change when the image scales.
    public var zoomAccessibilityValue: String {
        ZoomAccessibility.value(scale: state.zoom.scale)
    }

    public var currentFailure: ManualPageError? {
        if case let .failed(error) = slots[state.current] { return error }
        return nil
    }

    /// The current page once its image is drawn.
    public var askContext: PageRef? {
        if case .ready = slots[state.current] { return current }
        return nil
    }

    public var stage: [StagedPage] {
        [step(.previous), state.current, step(.next)].compactMap { page -> StagedPage? in
            guard let page else { return nil }
            let isCurrent = page == state.current
            guard let slot = slots[page] ?? (isCurrent ? .loading : nil) else { return nil }
            return StagedPage(
                id: page,
                slot: slot,
                x: state.x(of: page),
                scale: isCurrent ? state.zoom.scale : 1,
                pan: isCurrent ? state.zoom.pan : .zero,
                isCurrent: isCurrent
            )
        }
    }

    public func neighbor(_ direction: PageDirection) -> NeighborStatus {
        guard let page = step(direction) else { return .end }
        switch slots[page] {
        case .ready: return .ready
        case .loading, nil: return .loading
        case .failed: return .failed
        case .missing: return .end
        }
    }

    /// The only synchronous entry point. No I/O.
    public func handle(_ input: ReaderInput) {
        var next = state
        next.apply(input, pixels: currentPixels, turnable: turnable)
        state = next
    }

    /// Converges the window to current-1...current+1, current first, then next, then previous.
    /// Drops slots beyond current±2. Then loads Go deeper for the current page.
    /// A ready page is never fetched again. Safe to call twice, and safe to cancel.
    public func loadWindow() async {
        let center = state.current
        for page in [center, step(.next), step(.previous)].compactMap({ $0 }) {
            if Task.isCancelled { return }
            await load(page)
        }
        evict(around: state.current)
        await loadGoDeeper(for: state.current)
    }

    private var turnable: Set<PageDirection> {
        Set([PageDirection.previous, .next].filter { neighbor($0) == .ready })
    }

    private var currentPixels: ViewSize? {
        guard case let .ready(image) = slots[state.current] else { return nil }
        return PNGHeader.pixelSize(image.pngData)
    }

    private func step(_ direction: PageDirection) -> PageNumber? {
        let offset = direction == .next ? 1 : -1
        return PageNumber(rawValue: state.current.rawValue + offset)
    }

    private func load(_ page: PageNumber) async {
        if inFlight.contains(page) { return }
        switch slots[page] {
        case .ready, .missing: return
        case .loading, .failed, nil: break
        }
        inFlight.insert(page)
        defer { inFlight.remove(page) }
        slots[page] = .loading

        let result: PageSlot?
        do {
            let image = try await source.pageImage(docID: anchor.docID, page: page)
            try Task.checkCancellation()
            result = accepted(image, page: page)
        } catch is CancellationError {
            result = nil
        } catch let error as ManualPageError {
            result = error == .missingPage && page != state.current ? .missing : .failed(error)
        } catch {
            result = .failed(.unavailable)
        }
        // Evicted while loading: the page left the window, so drop the result.
        guard slots[page] == .loading else { return }
        slots[page] = result
    }

    private func accepted(_ image: ManualPageImage, page: PageNumber) -> PageSlot {
        guard image.docID == anchor.docID, image.page == page, ManualPageImage.isPNG(image.pngData) else {
            return .failed(.badImage)
        }
        return .ready(image)
    }

    private func evict(around center: PageNumber) {
        let far = { (page: PageNumber) in abs(page.rawValue - center.rawValue) > 2 }
        for page in slots.keys where far(page) {
            slots[page] = nil
        }
        for page in goDeeperByPage.keys where far(page) {
            goDeeperByPage[page] = nil
        }
    }

    private func loadGoDeeper(for page: PageNumber) async {
        guard goDeeperByPage[page] == nil, !Task.isCancelled else { return }
        let snippet = page == anchor.page ? anchor.snippet : ""
        guard let block = try? await goDeeperSource.goDeeper(
            docID: anchor.docID,
            page: page,
            snippet: snippet
        ) else { return }
        if Task.isCancelled { return }
        goDeeperByPage[page] = block
    }
}

struct ZoomTransform: Hashable, Sendable {
    var scale: Double
    var pan: ViewPoint

    static let fit = ZoomTransform(scale: 1, pan: .zero)
}

/// Gesture lock. The first drag event decides what the rest of that drag means.
enum Interaction: Hashable, Sendable {
    case idle
    case pinching(from: ZoomTransform, anchor: ViewPoint)
    /// Pan is `origin + translation`. Entering mid-drag stores the offset so the page does not jump.
    case panning(origin: ViewPoint)
    case swiping
    /// A vertical drag at fit belongs to the sheet.
    case passingThrough
}

struct ReaderState: Hashable, Sendable {
    static let maxScale = 4.0
    static let doubleTapScale = 2.5
    static let pageGap = 16.0
    static let turnFraction = 0.33
    static let rubberBand = 0.3
    static let snapToFit = 1.02

    var current: PageNumber
    var viewport: ViewSize = .zero
    var zoom: ZoomTransform = .fit
    var swipe: Double = 0
    var interaction: Interaction = .idle

    func x(of page: PageNumber) -> Double {
        Double(page.rawValue - current.rawValue) * (viewport.width + Self.pageGap) + swipe
    }

    /// `pixels` is the current page image size, nil until it is ready.
    mutating func apply(_ input: ReaderInput, pixels: ViewSize?, turnable: Set<PageDirection>) {
        switch input {
        case let .layout(size):
            viewport = size
            swipe = 0
            if zoom != .fit {
                zoom = settled(zoom, pixels: pixels)
            }
        case let .pinch(magnification, anchor):
            pinch(magnification: magnification, anchor: anchor)
        case .pinchEnded:
            guard case .pinching = interaction else { return }
            interaction = .idle
            zoom = settled(zoom, pixels: pixels)
        case let .drag(translation):
            drag(translation, pixels: pixels, turnable: turnable)
        case let .dragEnded(translation, predictedEnd):
            dragEnded(translation, predictedEnd: predictedEnd, pixels: pixels, turnable: turnable)
        case let .doubleTap(point):
            interaction = .idle
            swipe = 0
            if zoom != .fit {
                zoom = .fit
            } else {
                let offset = offsetFromCenter(point)
                let scale = Self.doubleTapScale
                let tapped = ZoomTransform(
                    scale: scale,
                    pan: ViewPoint(x: offset.x * (1 - scale), y: offset.y * (1 - scale))
                )
                zoom = settled(tapped, pixels: pixels)
            }
        case let .turn(direction):
            turn(direction, turnable: turnable)
        }
    }

    private mutating func pinch(magnification: Double, anchor: ViewPoint) {
        switch interaction {
        case .swiping, .passingThrough:
            return
        case .idle, .panning:
            interaction = .pinching(from: zoom, anchor: anchor)
        case .pinching:
            break
        }
        guard case let .pinching(from, start) = interaction else { return }
        let scale = Self.softScale(from.scale * magnification)
        let ratio = scale / from.scale
        let offset = offsetFromCenter(start)
        // Keeps the content point that was under the fingers at the start under them now.
        zoom = ZoomTransform(
            scale: scale,
            pan: ViewPoint(
                x: offset.x - (offset.x - from.pan.x) * ratio,
                y: offset.y - (offset.y - from.pan.y) * ratio
            )
        )
    }

    private mutating func drag(_ translation: ViewPoint, pixels: ViewSize?, turnable: Set<PageDirection>) {
        switch interaction {
        case .pinching, .passingThrough:
            return
        case .idle:
            if zoom != .fit {
                interaction = .panning(
                    origin: ViewPoint(x: zoom.pan.x - translation.x, y: zoom.pan.y - translation.y)
                )
            } else if abs(translation.x) >= abs(translation.y) {
                interaction = .swiping
            } else {
                interaction = .passingThrough
                return
            }
        case .panning, .swiping:
            break
        }
        switch interaction {
        case let .panning(origin):
            let limit = panLimit(scale: zoom.scale, pixels: pixels)
            zoom.pan = ViewPoint(
                x: Self.softClamp(origin.x + translation.x, limit: limit.x),
                y: Self.softClamp(origin.y + translation.y, limit: limit.y)
            )
        case .swiping:
            let toward: PageDirection = translation.x < 0 ? .next : .previous
            swipe = turnable.contains(toward) ? translation.x : translation.x * Self.rubberBand
        case .idle, .pinching, .passingThrough:
            break
        }
    }

    private mutating func dragEnded(
        _ translation: ViewPoint,
        predictedEnd: ViewPoint,
        pixels: ViewSize?,
        turnable: Set<PageDirection>
    ) {
        switch interaction {
        case .swiping:
            let dx = translation.x
            let toward: PageDirection = dx < 0 ? .next : .previous
            // A flick back past the start cancels, however far the finger went.
            let reach = predictedEnd.x * dx > 0 ? max(abs(dx), abs(predictedEnd.x)) : 0
            if reach >= viewport.width * Self.turnFraction, turnable.contains(toward) {
                turn(toward, turnable: turnable)
            } else {
                swipe = 0
                interaction = .idle
            }
        case let .panning(origin):
            let limit = panLimit(scale: zoom.scale, pixels: pixels)
            zoom.pan = ViewPoint(
                x: Self.clamp(origin.x + predictedEnd.x, limit: limit.x),
                y: Self.clamp(origin.y + predictedEnd.y, limit: limit.y)
            )
            interaction = .idle
        case .pinching:
            return
        case .idle, .passingThrough:
            interaction = .idle
        }
    }

    private mutating func turn(_ direction: PageDirection, turnable: Set<PageDirection>) {
        guard turnable.contains(direction) else { return }
        let offset = direction == .next ? 1 : -1
        guard let target = PageNumber(rawValue: current.rawValue + offset) else { return }
        current = target
        zoom = .fit
        swipe = 0
        interaction = .idle
    }

    private func settled(_ transform: ZoomTransform, pixels: ViewSize?) -> ZoomTransform {
        let scale = min(max(transform.scale, 1), Self.maxScale)
        if scale < Self.snapToFit { return .fit }
        let limit = panLimit(scale: scale, pixels: pixels)
        return ZoomTransform(
            scale: scale,
            pan: ViewPoint(
                x: Self.clamp(transform.pan.x, limit: limit.x),
                y: Self.clamp(transform.pan.y, limit: limit.y)
            )
        )
    }

    /// How far the scaled page can move before its edge leaves the viewport edge.
    private func panLimit(scale: Double, pixels: ViewSize?) -> ViewPoint {
        let content = fitted(pixels)
        return ViewPoint(
            x: max(0, (content.width * scale - viewport.width) / 2),
            y: max(0, (content.height * scale - viewport.height) / 2)
        )
    }

    /// The page image at scale 1, aspect-fit into the viewport.
    private func fitted(_ pixels: ViewSize?) -> ViewSize {
        guard let pixels, pixels.width > 0, pixels.height > 0, viewport.width > 0, viewport.height > 0 else {
            return viewport
        }
        let scale = min(viewport.width / pixels.width, viewport.height / pixels.height)
        return ViewSize(width: pixels.width * scale, height: pixels.height * scale)
    }

    private func offsetFromCenter(_ point: ViewPoint) -> ViewPoint {
        ViewPoint(x: point.x - viewport.width / 2, y: point.y - viewport.height / 2)
    }

    private static func softScale(_ raw: Double) -> Double {
        if raw < 1 { return 1 - (1 - raw) * rubberBand }
        if raw > maxScale { return maxScale + (raw - maxScale) * rubberBand }
        return raw
    }

    private static func softClamp(_ value: Double, limit: Double) -> Double {
        guard abs(value) > limit else { return value }
        let overflow = abs(value) - limit
        return (value < 0 ? -1 : 1) * (limit + overflow * rubberBand)
    }

    private static func clamp(_ value: Double, limit: Double) -> Double {
        min(max(value, -limit), limit)
    }
}

enum PNGHeader {
    /// Width and height from the IHDR chunk. Nil when the bytes are not a PNG header.
    static func pixelSize(_ data: Data) -> ViewSize? {
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24,
              ManualPageImage.isPNG(data),
              bytes[12..<16].elementsEqual(Array("IHDR".utf8))
        else { return nil }
        let width = bytes[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = bytes[20..<24].reduce(0) { $0 << 8 | Int($1) }
        guard width > 0, height > 0 else { return nil }
        return ViewSize(width: Double(width), height: Double(height))
    }
}
