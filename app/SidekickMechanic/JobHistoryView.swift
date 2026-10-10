import SidekickCore
import SwiftUI
import UIKit

/// One look-back push. `generation` makes a second visit a new destination.
///
/// NavigationStack keeps the destination for an equal `LookBackScreen`. After
/// opening a job and coming back, Jobs reused that screen: the scroll offset
/// from the previous visit stayed, and the newest row was above the viewport
/// so its identifier was not in the accessibility tree.
struct LookBackVisit: Hashable {
    var screen: LookBackScreen
    var generation: Int
}

/// Jobs list from the approved Figma frame. Peeks use #112's public outline renderer.
struct JobHistoryView: View {
    var jobs: [JobSheetState]
    var now: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var store: DemoImageStore
    var configuration: ChatClientConfiguration
    var flags: FeatureFlags = .v1
    var visitGeneration: Int = 0
    var onOpenJob: (JobID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(JobHistoryCopy.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("jobHistory.subtitle")
                if jobs.isEmpty {
                    Text(JobsCopy.emptyList)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("jobHistory.empty")
                }
                ForEach(jobs) { job in
                    Button {
                        onOpenJob(job.id)
                    } label: {
                        rowCard(job)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier(job.rowIdentifier)
                    .accessibilityHint("Opens this job sheet")
                    .id(job.id)
                }
            }
            .padding(16)
        }
        .onAppear {
            guard let top = jobs.first?.id else { return }
            proxy.scrollTo(top, anchor: .top)
        }
        .background(JobSheetChrome.screen)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            LookBackPaperHeader(
                title: JobHistoryCopy.title,
                showScanLog: true,
                onBack: { dismiss() }
            )
        }
        .task {
            if store.catalog == nil {
                await store.load(from: configuration)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jobHistory.list")
        }
    }

    private func rowCard(_ job: JobSheetState) -> some View {
        let presentation = HighlightViewerPresentation.resolve(
            source: HighlightViewerState.fromDemo(
                display: job.highlight?.display,
                highlight: job.highlight
            ),
            flags: flags,
            photoID: job.photoID ?? DemoLaunchOptions.defaultPhotoID,
            partID: job.highlight?.partID.rawValue
        )
        let geometry = presentation.showsOutline
            ? (job.highlight?.geometry ?? HighlightViewerScript.geometry(
                photoID: presentation.outlinePhotoID,
                partID: presentation.partID,
                showingOutline: true
            ))
            : nil
        let thumbSize: CGFloat = dynamicTypeSize.isAccessibilitySize ? 72 : 44
        let dateLabel = job.dateLabel(now: now)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    LookBackThumb(
                        image: store.images[job.photoID ?? ""] ?? HighlightPlaceholderImage.make(),
                        geometry: geometry,
                        confirm: presentation.outlineStroke == .dashed,
                        notFound: !presentation.showsOutline,
                        cornerRadius: 8,
                        renderedWidth: thumbSize
                    )
                    wrappingText(job.title, font: .headline, color: .primary)
                    wrappingText(dateLabel, font: .subheadline, color: .secondary)
                    outcomeBadge(job.outcome)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    LookBackThumb(
                        image: store.images[job.photoID ?? ""] ?? HighlightPlaceholderImage.make(),
                        geometry: geometry,
                        confirm: presentation.outlineStroke == .dashed,
                        notFound: !presentation.showsOutline,
                        cornerRadius: 8,
                        renderedWidth: thumbSize
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(dateLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    outcomeBadge(job.outcome)
                }
            }
        }
        .padding(12)
        .background(JobSheetChrome.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
    }

    /// Full words at accessibility sizes. Hyphenation is what produced "Col / d i…".
    /// `AttributedString.hyphenationFactor` is not settable; UIKit's paragraph style is.
    private func wrappingText(_ string: String, font: Font, color: Color) -> some View {
        let style = NSMutableParagraphStyle()
        style.hyphenationFactor = 0
        style.lineBreakMode = .byWordWrapping
        var container = AttributeContainer()
        container.uiKit.paragraphStyle = style
        return Text(AttributedString(string, attributes: container))
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func outcomeBadge(_ outcome: JobOutcome?) -> some View {
        if let outcome {
            let filled = outcome == .worked
            Text(outcome.label)
                .font(.caption.weight(filled ? .semibold : .regular))
                .foregroundStyle(filled ? JobSheetChrome.paper : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(filled ? Color.primary : Color.clear, in: Capsule())
                .overlay {
                    if !filled {
                        Capsule().strokeBorder(Color.secondary.opacity(0.4))
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("jobHistory.badge.\(outcome.rawValue)")
        }
    }
}

/// Square thumb. Size-aware #112 ink. Aspect-fill + clip keeps a 1:1 tile.
struct LookBackThumb: View {
    var image: UIImage
    var geometry: HighlightGeometry?
    var confirm: Bool
    var notFound: Bool
    var cornerRadius: CGFloat
    var renderedWidth: CGFloat

    var body: some View {
        DemoHighlightView(
            image: image,
            geometry: geometry,
            style: .outline,
            confirm: confirm,
            dashed: confirm,
            attribution: "",
            shareAlike: false,
            notFound: notFound,
            cornerRadius: 0,
            outlineInk: .scaled(renderedWidth: Double(renderedWidth), dashed: confirm),
            fillsContainer: true
        )
        .frame(width: renderedWidth, height: renderedWidth)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Plain Back / Scan log on #F4F4F4 paper. Avoids iOS 26 toolbar glass capsules.
struct LookBackPaperHeader: View {
    var title: String
    var showScanLog: Bool
    var onBack: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            sheetTopMarker("lookBack.sheetTop")
            headerRow
        }
    }

    private var headerRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        backButton
                        Spacer(minLength: 0)
                        scanLogLink
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("lookBack.title")
                }
            } else {
                ZStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("lookBack.title")
                    HStack {
                        backButton
                        Spacer(minLength: 8)
                        scanLogLink
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .sheetHeaderClearance()
        .padding(.bottom, 10)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JobSheetChrome.screen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lookBack.header")
    }

    private var backButton: some View {
        Button(JobHistoryCopy.back, action: onBack)
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize()
            .accessibilityIdentifier("lookBack.back")
    }

    @ViewBuilder
    private var scanLogLink: some View {
        if showScanLog {
            NavigationLink(value: LookBackVisit(screen: .scanLog, generation: visitGeneration)) {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "square.grid.2x2")
                        .font(.body.weight(.medium))
                        .imageScale(.medium)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityHidden(true)
                } else {
                    Text(ScanLogCopy.title)
                }
            }
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize()
            .accessibilityLabel(ScanLogCopy.title)
            .accessibilityIdentifier("jobHistory.scanLog")
        }
    }
}

#Preview("Jobs") {
    NavigationStack {
        JobHistoryView(
            jobs: JobHistoryScript.jobs(now: Date()),
            now: Date(),
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenJob: { _ in }
        )
    }
}

#Preview("Jobs Dark") {
    NavigationStack {
        JobHistoryView(
            jobs: JobHistoryScript.jobs(now: Date()),
            now: Date(),
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenJob: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Jobs Large Dynamic Type") {
    NavigationStack {
        JobHistoryView(
            jobs: JobHistoryScript.jobs(now: Date()),
            now: Date(),
            store: DemoImageStore(),
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://localhost:8000")!),
            onOpenJob: { _ in }
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
