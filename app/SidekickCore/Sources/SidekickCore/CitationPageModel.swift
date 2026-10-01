import Foundation
import Observation

/// Loads the rendered page for one citation and keeps the snippet beside it.
@MainActor
@Observable
public final class CitationPageModel {
    public let citation: Citation
    public private(set) var phase: Phase
    public private(set) var isLoading: Bool

    @ObservationIgnored private let source: any ManualPageSource

    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded(ManualPageImage)
        case failed(ManualPageError)
    }

    public var headerDocument: String { citation.docID.rawValue }
    public var headerPage: String { "Page \(citation.page.rawValue)" }
    public var snippet: String { citation.snippet }

    public init(citation: Citation, source: any ManualPageSource) {
        self.citation = citation
        self.source = source
        self.phase = .idle
        self.isLoading = false
    }

    /// Cache or backend. A second call while a load is in flight does nothing.
    /// Cancellation restores the phase from before this call.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        let previous = phase
        phase = .loading
        defer { isLoading = false }

        do {
            let image = try await source.pageImage(docID: citation.docID, page: citation.page)
            try Task.checkCancellation()
            phase = accepted(image)
        } catch is CancellationError {
            phase = previous
        } catch let error as ManualPageError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unavailable)
        }
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
