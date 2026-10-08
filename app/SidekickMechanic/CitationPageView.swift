import SidekickCore
import SwiftUI
import UIKit

/// Page the owner sees after tapping a citation chip.
///
/// Chat and the job sheet present this as a white sheet. Page bytes come from
/// the backend for real manuals, or a canned FAKE-DOC stand-in.
@MainActor
struct CitationPageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: CitationPageModel

    init(
        citation: Citation,
        source: any ManualPageSource = ManualPageSources.makeFromEnvironment(),
        goDeeperSource: any GoDeeperSource = GoDeeperSources.makeFromEnvironment()
    ) {
        _model = State(
            wrappedValue: CitationPageModel(
                citation: citation,
                source: source,
                goDeeperSource: goDeeperSource
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pageBody
                snippetNote
                goDeeperBlock
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            headerBar
        }
        .background(JobSheetChrome.paper)
        .modifier(
            AccessibilityLaunchModifier(
                enabled: DemoLaunchOptions.parse().prefersAccessibilitySize
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("citation.viewer")
        .task { await model.load() }
    }

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    private var headerBar: some View {
        Group {
            if isAccessibilitySize {
                accessibilityHeader
            } else {
                defaultHeader
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JobSheetChrome.paper)
        .accessibilityElement(children: .contain)
    }

    /// Centered title with a matching hidden Close so the label stays in the middle.
    private var defaultHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            closeTextButton
                .accessibilityIdentifier("citation.close")
            Text("Manual page")
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("citation.title")
            closeTextButton
                .hidden()
                .accessibilityHidden(true)
        }
    }

    /// Close plus the doc/page labels already in the body; no centered title.
    private var accessibilityHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("citation.close")
            Spacer(minLength: 0)
        }
    }

    private var closeTextButton: some View {
        Button("Close") { dismiss() }
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.headerDocument)
                .font(.title2)
                .foregroundStyle(.primary)
                .wrapsWords(maxLines: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("citation.document")
            Text(model.headerPage)
                .font(.headline)
                .foregroundStyle(.secondary)
                .wrapsWords(maxLines: 2)
                .accessibilityIdentifier("citation.pageNumber")
        }
        .accessibilityElement(children: .contain)
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

    @ViewBuilder
    private var goDeeperBlock: some View {
        if let goDeeper = model.goDeeper, goDeeper.hasContent {
            VStack(alignment: .leading, spacing: 12) {
                Text("Go deeper")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(goDeeper.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("citation.goDeeper")
        }
    }
}

private func previewCitation() -> Citation {
    Citation(
        docID: DocumentID(rawValue: "FAKE-DOC-2JZ")!,
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
            source: PreviewPageSource(pngData: ManualPagePlaceholder.pngData()),
            goDeeperSource: CannedGoDeeperSource()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        CitationPageView(
            citation: previewCitation(),
            source: PreviewPageSource(pngData: ManualPagePlaceholder.pngData()),
            goDeeperSource: CannedGoDeeperSource()
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Accessibility XL") {
    NavigationStack {
        CitationPageView(
            citation: previewCitation(),
            source: PreviewPageSource(pngData: ManualPagePlaceholder.pngData()),
            goDeeperSource: CannedGoDeeperSource()
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
            source: FailingManualPageSource(error: .missingPage),
            goDeeperSource: CannedGoDeeperSource()
        )
    }
}
