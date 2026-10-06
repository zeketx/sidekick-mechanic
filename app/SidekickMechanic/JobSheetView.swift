import SidekickCore
import SwiftUI
import UIKit

/// Bottom sheet for one job (JS-1/2/3). Outline is the #112 polygon, never a box.
struct JobSheetView: View {
    @Bindable var model: JobSheetViewModel
    var image: UIImage?
    var attribution: String
    var shareAlike: Bool
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
        .background(.background, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .strokeBorder(Color.secondary.opacity(0.2))
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
        if model.job?.hasPhoto == true, let image {
            Button(action: onOpenHighlight) {
                DemoHighlightView(
                    image: image,
                    geometry: model.job?.highlight?.geometry ?? HighlightViewerScript.airBoxGeometry,
                    style: .outline,
                    confirm: false,
                    attribution: attribution,
                    shareAlike: shareAlike,
                    notFound: false,
                    cornerRadius: 10,
                    showsAttribution: height > 80
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jobSheet.photo")
            .accessibilityHint("Opens the highlight card")
        } else if model.job?.hasPhoto == true {
            Button(action: onOpenHighlight) {
                Image(uiImage: HighlightPlaceholderImage.make())
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        DemoHighlightView(
                            image: HighlightPlaceholderImage.make(),
                            geometry: HighlightViewerScript.airBoxGeometry,
                            style: .outline,
                            confirm: false,
                            attribution: attribution,
                            shareAlike: shareAlike,
                            notFound: false,
                            cornerRadius: 10
                        )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jobSheet.photo")
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
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
        Button(action: onAttachPhoto) {
            Label(JobSheetCopy.attach, systemImage: "photo.badge.plus")
                .font(.subheadline.weight(.semibold))
        }
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.background, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color.secondary.opacity(0.35))
                            }
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(JobOutcome.allCases, id: \.self) { outcome in
                    Button {
                        model.selectOutcome(outcome)
                    } label: {
                        Text(outcome.label)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.job?.outcome == outcome ? Color(.systemBackground) : .primary)
                    .background(
                        model.job?.outcome == outcome ? Color.primary : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        if model.job?.outcome != outcome {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.35))
                        }
                    }
                    .accessibilityIdentifier("jobSheet.outcome.\(outcome.rawValue)")
                    .accessibilityAddTraits(model.job?.outcome == outcome ? .isSelected : [])
                }
            }
        }
        .accessibilityIdentifier("jobSheet.outcome")
    }
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
            Color(.systemGroupedBackground)
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
