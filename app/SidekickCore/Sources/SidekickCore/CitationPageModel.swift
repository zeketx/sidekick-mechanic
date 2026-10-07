import Foundation
import Observation

/// Loads the rendered page for one citation and keeps the snippet beside it.
@MainActor
@Observable
public final class CitationPageModel {
    public let citation: Citation
    public private(set) var phase: Phase
    public private(set) var goDeeper: GoDeeper?
    public private(set) var isLoading: Bool

    @ObservationIgnored private let source: any ManualPageSource
    @ObservationIgnored private let goDeeperSource: any GoDeeperSource

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded(ManualPageImage)
        case failed(ManualPageError)
    }

    public var headerDocument: String { citation.docID.rawValue }
    public var headerPage: String { "Page \(citation.page.rawValue)" }
    public var snippet: String { citation.snippet }

    public init(
        citation: Citation,
        source: any ManualPageSource,
        goDeeperSource: any GoDeeperSource = CannedGoDeeperSource()
    ) {
        self.citation = citation
        self.source = source
        self.goDeeperSource = goDeeperSource
        self.phase = .idle
        self.goDeeper = nil
        self.isLoading = false
    }

    /// Cache or backend. A second call while a load is in flight does nothing.
    /// Cancellation restores the phase from before this call.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        let previous = phase
        let previousGoDeeper = goDeeper
        phase = .loading
        defer { isLoading = false }

        do {
            let image = try await source.pageImage(docID: citation.docID, page: citation.page)
            try Task.checkCancellation()
            phase = accepted(image)
            goDeeper = await loadGoDeeper()
        } catch is CancellationError {
            phase = previous
            goDeeper = previousGoDeeper
        } catch let error as ManualPageError {
            phase = .failed(error)
            goDeeper = await loadGoDeeper()
        } catch {
            phase = .failed(.unavailable)
            goDeeper = await loadGoDeeper()
        }
    }

    private func loadGoDeeper() async -> GoDeeper? {
        if Task.isCancelled { return goDeeper }
        return try? await goDeeperSource.goDeeper(docID: citation.docID, page: citation.page)
    }

    private func accepted(_ image: ManualPageImage) -> Phase {
        guard image.docID == citation.docID,
              image.page == citation.page,
              ManualPageImage.isPNG(image.pngData)
        else {
            return .failed(.badImage)
        }
        return .loaded(image)
    }
}
