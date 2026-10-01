import SidekickCore
import SwiftUI
import UIKit

/// Page the owner sees after tapping a citation chip.
///
/// The answer card calls `CitationPageView(citation:)` with the chip's `Citation`.
/// This view does not draw the chip. Page bytes come from the backend or the local cache.
@MainActor
struct CitationPageView: View {
    @State private var model: CitationPageModel

    init(
        citation: Citation,
        source: any ManualPageSource = ManualPageSources.makeFromEnvironment()
    ) {
        _model = State(wrappedValue: CitationPageModel(citation: citation, source: source))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pageBody
                snippetNote
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("Manual page")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("citation.viewer")
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.headerDocument)
                .font(.title2)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("citation.document")
            Text(model.headerPage)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("citation.pageNumber")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.headerDocument), \(model.headerPage)")
    }

    @ViewBuilder
    private var pageBody: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading page")
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("citation.loading")
        case let .loaded(image):
            loadedPage(image)
        case let .failed(error):
            failure(error.message)
        }
    }

    @ViewBuilder
    private func loadedPage(_ image: ManualPageImage) -> some View {
        if let uiImage = UIImage(data: image.pngData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(
                    Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityIdentifier("citation.pageImage")
                .accessibilityLabel("Rendered page \(model.headerDocument), \(model.headerPage)")
        } else {
            failure(ManualPageError.badImage.message)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
            .accessibilityIdentifier("citation.pageError")
            Button("Try again") {
                Task { await model.load() }
            }
            .disabled(model.isLoading)
            .accessibilityIdentifier("citation.retry")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var snippetNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cited snippet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(model.snippet)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("citation.snippet")
        .accessibilityLabel("Cited snippet. \(model.snippet)")
    }
}

private func previewCitation() -> Citation {
    Citation(
        docID: DocumentID(rawValue: "FAKE-DOC")!,
        page: PageNumber(rawValue: 999)!,
        snippet: "FAKE-SNIPPET on a generated page image."
    )!
}

private struct PreviewPageSource: ManualPageSource {
    var pngData: Data

    func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        ManualPageImage(docID: docID, page: page, pngData: pngData)
    }
}

private struct HangingManualPageSource: ManualPageSource {
    func pageImage(docID: DocumentID, page: PageNumber) async throws -> ManualPageImage {
        try await Task.sleep(for: .seconds(600))
        throw CancellationError()
    }
}

#Preview("Light") {
    NavigationStack {
        CitationPageView(
            citation: previewCitation(),
            source: PreviewPageSource(pngData: ManualPagePlaceholder.pngData())
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        CitationPageView(
            citation: previewCitation(),
            source: PreviewPageSource(pngData: ManualPagePlaceholder.pngData())
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Accessibility XL") {
    NavigationStack {
        CitationPageView(
            citation: previewCitation(),
            source: PreviewPageSource(pngData: ManualPagePlaceholder.pngData())
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Loading") {
    NavigationStack {
        CitationPageView(citation: previewCitation(), source: HangingManualPageSource())
    }
}

#Preview("Missing page") {
    NavigationStack {
        CitationPageView(
            citation: previewCitation(),
            source: FailingManualPageSource(error: .missingPage)
        )
    }
}
