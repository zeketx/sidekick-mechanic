import SidekickCore
import SwiftUI
import UIKit

/// Bottom sheet for one job (JS-1/2/3). Outline comes from #112's public renderer.
struct JobSheetView: View {
    @Bindable var model: JobSheetViewModel
    var image: UIImage?
    var attribution: String
    var shareAlike: Bool
    var flags: FeatureFlags = .v1
    var onOpenHighlight: () -> Void
    var onAttachPhoto: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            if model.detent == .collapsed {
                collapsedPeek
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: sheetHeight)
        .background(JobSheetChrome.paper, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .strokeBorder(Color.secondary.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(detentIdentifier)
    }

    private var detentIdentifier: String {
        switch model.detent {
        case .collapsed: "jobSheet.collapsed"
        case .half: "jobSheet.half"
        case .full: "jobSheet.full"
        }
    }

    private var sheetHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        switch model.detent {
        case .collapsed: 128
        case .half: min(screen * 0.52, 460)
        case .full: screen * 0.88
        }
    }

    /// Public #112 view model. Thumbnails follow resolve(), not a copied outline.
    private var presentation: HighlightViewerPresentation {
        HighlightViewerPresentation.resolve(
            source: HighlightViewerState.fromDemo(
                display: model.job?.highlight?.display,
                highlight: model.job?.highlight
            ),
            flags: flags
        )
    }

    private var outlineGeometry: HighlightGeometry? {
        guard presentation.showsOutline else { return nil }
        return model.job?.highlight?.geometry
            ?? HighlightViewerScript.geometry(showingOutline: true)
    }

    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        model.applyDrag(translationHeight: value.translation.height)
                    }
            )
            .accessibilityIdentifier("jobSheet.handle")
            .accessibilityLabel("Job sheet handle")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.job?.headerTitle ?? JobSheetCopy.titlePrefix + JobSheetCopy.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("jobSheet.title")
            Spacer(minLength: 8)
            Button(model.detent == .collapsed ? JobSheetCopy.open : JobSheetCopy.close) {
                if model.detent == .collapsed {
                    model.open()
                } else {
                    model.close()
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(model.detent == .collapsed ? "jobSheet.open" : "jobSheet.close")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var collapsedPeek: some View {
        HStack(alignment: .center, spacing: 12) {
            photoThumb(height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.job?.hasPhoto == true ? JobSheetCopy.photoCaption : JobSheetCopy.peekHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if model.job?.hasPhoto != true {
                    attachButton
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("jobSheet.peek")
    }

    private var expandedBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                photoStage
                Text(model.job?.answerText ?? JobSheetCopy.answer)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("jobSheet.answer")
                chipRow
                if model.job?.hasPhoto != true {
                    attachButton
                }
                outcomeRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .accessibilityIdentifier("jobSheet.body")
    }

    private var photoStage: some View {
        VStack(alignment: .leading, spacing: 6) {
            photoThumb(height: model.detent == .full ? 200 : 140)
            Text(JobSheetCopy.photoCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("jobSheet.photoCaption")
        }
    }

    @ViewBuilder
    private func photoThumb(height: CGFloat) -> some View {
        if model.job?.hasPhoto == true {
            Button(action: onOpenHighlight) {
                DemoHighlightView(
                    image: image ?? HighlightPlaceholderImage.make(),
                    geometry: outlineGeometry,
                    style: .outline,
                    confirm: presentation.outlineStroke == .dashed,
                    dashed: presentation.outlineStroke == .dashed,
                    attribution: attribution,
                    shareAlike: shareAlike,
                    notFound: !presentation.showsOutline
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jobSheet.photo")
            .accessibilityHint("Opens the highlight card")
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JobSheetChrome.emptyPhoto)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    Text(JobSheetCopy.peekHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("jobSheet.photoEmpty")
        }
    }

    private var attachButton: some View {
        Button(JobSheetCopy.attach, action: onAttachPhoto)
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("jobSheet.attach")
            .accessibilityHint(JobSheetCopy.attachHint)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array((model.job?.citations ?? []).enumerated()), id: \.offset) { index, citation in
                    NavigationLink {
                        CitationPageView(citation: citation)
                    } label: {
                        Text(index == 0 ? JobSheetCopy.chip : citation.chipLabel)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("jobSheet.chip.\(index)")
                    .accessibilityHint("Opens the cited page")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("jobSheet.chips")
    }

    private var outcomeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(JobSheetCopy.outcomeHeading)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(JobOutcome.allCases, id: \.self) { outcome in
                    let selected = model.job?.outcome == outcome
                    Button(outcome.label) {
                        model.selectOutcome(outcome)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("jobSheet.outcome.\(outcome.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("jobSheet.outcome")
    }
}

/// Figma paper: white / #f4f4f4 / #e8e8e8. Not system blue-gray.
enum JobSheetChrome {
    static let paper = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .systemBackground }
        return UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    })

    static let screen = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .systemBackground }
        return UIColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
    })

    static let emptyPhoto = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .secondarySystemBackground }
        return UIColor(red: 0.910, green: 0.910, blue: 0.910, alpha: 1)
    })
}

#Preview("Collapsed") {
    JobSheetPreview(detent: .collapsed)
}

#Preview("Half") {
    JobSheetPreview(detent: .half)
}

#Preview("Full") {
    JobSheetPreview(detent: .full)
}

#Preview("Closeout") {
    JobSheetPreview(detent: .half, outcome: .worked)
}

#Preview("Dark") {
    JobSheetPreview(detent: .half)
        .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    JobSheetPreview(detent: .half)
        .environment(\.dynamicTypeSize, .accessibility3)
}

private struct JobSheetPreview: View {
    @State private var model: JobSheetViewModel

    init(detent: JobSheetDetent, outcome: JobOutcome? = nil) {
        _model = State(
            initialValue: JobSheetViewModel(
                job: JobSheetScript.makeJob(
                    detent: detent,
                    photoID: DemoLaunchOptions.defaultPhotoID,
                    outcome: outcome
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            JobSheetChrome.screen
                .ignoresSafeArea()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    JobSheetView(
                        model: model,
                        image: HighlightPlaceholderImage.make(),
                        attribution: "Demo data. Not Zeke's truck.",
                        shareAlike: false,
                        onOpenHighlight: {},
                        onAttachPhoto: {}
                    )
                }
        }
    }
}
