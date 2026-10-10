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
    @State private var model: ManualReaderModel
    @State private var viewport: CGSize = .zero
    private let onAsk: ((PageRef) -> Void)?

    init(
        citation: Citation,
        source: any ManualPageSource = ManualPageSources.makeFromEnvironment(),
        goDeeperSource: any GoDeeperSource = GoDeeperSources.makeFromEnvironment(),
        onAsk: ((PageRef) -> Void)? = nil
    ) {
        self.onAsk = onAsk
        _model = State(
            wrappedValue: ManualReaderModel(
                anchor: citation,
                source: source,
                goDeeperSource: goDeeperSource
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            documentHeader
            stage
                .padding(.horizontal, 16)
            notes
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            headerBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            askBar
        }
        .background(JobSheetChrome.paper)
        .overlay(alignment: .top) {
            sheetTopMarker("citation.sheetTop")
        }
        .modifier(
            AccessibilityLaunchModifier(
                enabled: DemoLaunchOptions.parse().prefersAccessibilitySize
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("citation.viewer")
        .interactiveDismissDisabled(model.isZoomed)
        .task(id: model.current) {
            await model.loadWindow()
        }
    }

    private func send(_ input: ReaderInput) {
        if input.settles {
            withAnimation(.snappy(duration: 0.32)) {
                model.handle(input)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.handle(input)
            }
        }
    }

    private func updateViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - viewport.width) > 0.5 || abs(size.height - viewport.height) > 0.5 else { return }
        viewport = size
        send(.layout(viewport: ViewSize(width: Double(size.width), height: Double(size.height))))
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
        .sheetHeaderClearance()
        .padding(.bottom, 10)
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

    private var documentHeader: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var stage: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(model.stage) { staged in
                    stagedPage(staged, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(
                Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .simultaneousGesture(pinchGesture)
            // Simultaneous so a vertical drag at fit still reaches the sheet. The model pans only while zoomed.
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) { location in
                send(.doubleTap(at: ViewPoint(x: Double(location.x), y: Double(location.y))))
            }
            .overlay(alignment: .leading) {
                if model.neighbor(.previous) == .ready {
                    turnButton(.previous, systemImage: "chevron.left", identifier: "citation.previous")
                        .padding(.leading, 8)
                }
            }
            .overlay(alignment: .trailing) {
                if model.neighbor(.next) == .ready {
                    turnButton(.next, systemImage: "chevron.right", identifier: "citation.next")
                        .padding(.trailing, 8)
                }
            }
            .onAppear { updateViewport(size) }
            .onChange(of: geo.size) { _, newSize in
                updateViewport(newSize)
            }
        }
        .frame(height: 360)
    }

    private func stagedPage(_ staged: StagedPage, in size: CGSize) -> some View {
        pageContent(staged)
            .frame(width: size.width, height: size.height)
            .scaleEffect(staged.scale, anchor: .center)
            .offset(x: staged.x + staged.pan.x, y: staged.pan.y)
            .accessibilityHidden(!staged.isCurrent)
    }

    @ViewBuilder
    private func pageContent(_ staged: StagedPage) -> some View {
        switch staged.slot {
        case .loading:
            if staged.isCurrent {
                ProgressView("Loading page")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("citation.loading")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .ready(image):
            if let uiImage = UIImage(data: image.pngData) {
                if staged.isCurrent {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("citation.pageImage")
                        .accessibilityLabel("Rendered page \(model.headerDocument), \(model.headerPage)")
                        .accessibilityValue(model.zoomAccessibilityValue)
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
            } else if staged.isCurrent {
                failure(ManualPageError.badImage.message)
            }
        case let .failed(error):
            if staged.isCurrent {
                failure(error.message)
            }
        case .missing:
            Color.clear
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
                Task { await model.loadWindow() }
            }
            .accessibilityIdentifier("citation.retry")
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func turnButton(
        _ direction: PageDirection,
        systemImage: String,
        identifier: String
    ) -> some View {
        Button {
            send(.turn(direction))
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(JobSheetChrome.paper, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .previous ? "Previous page" : "Next page")
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var askBar: some View {
        if let page = model.askContext, onAsk != nil {
            Button {
                onAsk?(page)
            } label: {
                Text("Ask about this page")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("citation.ask")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(JobSheetChrome.paper)
        }
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                snippetNote
                goDeeperBlock
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var snippetNote: some View {
        if let snippet = model.snippet {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cited snippet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(snippet)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("citation.snippet")
            .accessibilityLabel("Cited snippet. \(snippet)")
        }
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                send(.drag(translation: point(value.translation)))
            }
            .onEnded { value in
                send(.dragEnded(
                    translation: point(value.translation),
                    predictedEnd: point(value.predictedEndTranslation)
                ))
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                send(.pinch(
                    magnification: Double(value.magnification),
                    anchor: ViewPoint(x: Double(value.startLocation.x), y: Double(value.startLocation.y))
                ))
            }
            .onEnded { _ in
                send(.pinchEnded)
            }
    }

    private func point(_ size: CGSize) -> ViewPoint {
        ViewPoint(x: Double(size.width), y: Double(size.height))
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
