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
    var screenHeight: CGFloat = 0
    var topSafeArea: CGFloat = 0
    var bottomChromeInset: CGFloat = 0
    var onOpenHighlight: () -> Void
    var onAttachPhoto: () -> Void
    @State private var showsCredit = false

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
        .clipShape(sheetShape)
        .background {
            sheetShape
                .fill(JobSheetChrome.paper)
                .shadow(color: Color.black.opacity(0.12), radius: 12, y: -2)
        }
        .overlay {
            sheetShape.strokeBorder(Color.secondary.opacity(0.18))
        }
        .padding(.horizontal, CGFloat(JobSheetLayout.horizontalInset))
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.22), value: model.detent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(detentIdentifier)
        .confirmationDialog(JobSheetCopy.creditInfo, isPresented: $showsCredit, titleVisibility: .visible) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(creditText)
        }
    }

    private var detentIdentifier: String {
        switch model.detent {
        case .collapsed: "jobSheet.collapsed"
        case .half: "jobSheet.half"
        case .full: "jobSheet.full"
        }
    }

    private var sheetHeight: CGFloat {
        let screen = screenHeight > 0 ? screenHeight : UIScreen.main.bounds.height
        return CGFloat(
            JobSheetLayout.height(
                detent: model.detent,
                screenHeight: Double(screen),
                topSafeArea: Double(topSafeArea)
            )
        )
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: CGFloat(JobSheetLayout.topCornerRadius),
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: CGFloat(JobSheetLayout.topCornerRadius),
            style: .continuous
        )
    }

    private var catalogPhotoID: String {
        model.job?.photoID ?? DemoLaunchOptions.defaultPhotoID
    }

    private var catalogPartID: String? {
        model.job?.highlight?.partID.rawValue
    }

    /// Public #112 view model. Thumbnails follow resolve(), not a copied outline.
    private var presentation: HighlightViewerPresentation {
        HighlightViewerPresentation.resolve(
            source: HighlightViewerState.fromDemo(
                display: model.job?.highlight?.display,
                highlight: model.job?.highlight
            ),
            flags: flags,
            photoID: catalogPhotoID,
            partID: catalogPartID
        )
    }

    private var outlineGeometry: HighlightGeometry? {
        guard presentation.showsOutline else { return nil }
        return model.job?.highlight?.geometry
            ?? HighlightViewerScript.geometry(
                photoID: presentation.outlinePhotoID,
                partID: presentation.partID,
                showingOutline: true
            )
    }

    private var creditText: String {
        JobSheetCopy.creditLine(attribution: attribution, shareAlike: shareAlike)
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
            photoThumb(height: 48, fillsWidth: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.job?.hasPhoto == true ? JobSheetCopy.photoCaption : JobSheetCopy.peekHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if model.job?.hasPhoto == true {
                        creditInfoButton
                    }
                }
                if model.job?.hasPhoto == true {
                    partChip
                } else {
                    attachButton
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("jobSheet.peek")
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    photoStage
                    Text(model.job?.answerText ?? JobSheetCopy.answer(photoID: catalogPhotoID))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("jobSheet.answer")
                    chipRow
                    stepsList
                    if model.job?.hasPhoto != true {
                        attachButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .accessibilityIdentifier("jobSheet.body")
            outcomeRow
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8 + bottomChromeInset)
                .safeAreaPadding(.bottom)
        }
    }

        private var photoStage: some View {
        VStack(alignment: .leading, spacing: 4) {
            photoThumb(
                height: model.detent == .full
                    ? CGFloat(JobSheetLayout.fullPhotoHeight)
                    : CGFloat(JobSheetLayout.halfPhotoHeight),
                fillsWidth: true
            )
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(JobSheetCopy.photoCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("jobSheet.photoCaption")
                Spacer(minLength: 8)
                if model.job?.hasPhoto == true {
                    creditInfoButton
                }
            }
            if model.job?.hasPhoto == true {
                Text(creditText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("jobSheet.credit")
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func photoThumb(height: CGFloat, fillsWidth: Bool) -> some View {
        if model.job?.hasPhoto == true {
            Button(action: onOpenHighlight) {
                DemoHighlightView(
                    image: image ?? HighlightPlaceholderImage.make(),
                    geometry: outlineGeometry,
                    style: .outline,
                    confirm: presentation.outlineStroke == .dashed,
                    dashed: presentation.outlineStroke == .dashed,
                    attribution: "",
                    shareAlike: false,
                    notFound: !presentation.showsOutline,
                    outlineInk: height < 120
                        ? .scaled(
                            renderedWidth: Double(fillsWidth ? height : 72),
                            dashed: presentation.outlineStroke == .dashed
                        )
                        : nil
                )
                .frame(width: fillsWidth ? nil : 72, height: height)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jobSheet.photo")
            .accessibilityHint("Opens the highlight card")
            .accessibilityValue(creditText)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JobSheetChrome.emptyPhoto)
                .frame(width: fillsWidth ? nil : 72, height: height)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .overlay {
                    Text(JobSheetCopy.peekHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(fillsWidth ? 1 : 0)
                }
                .accessibilityIdentifier("jobSheet.photoEmpty")
        }
    }

    private var creditInfoButton: some View {
        Button {
            showsCredit.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jobSheet.creditInfo")
        .accessibilityLabel(JobSheetCopy.creditInfo)
        .accessibilityValue(creditText)
        .accessibilityHint("Shows the photo license")
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
                        JobSheetChipLabel(text: index == 0 ? JobSheetCopy.chip : citation.chipLabel)
                    }
                    .buttonStyle(.plain)
                    .tint(JobSheetChrome.chipInk)
                    .foregroundStyle(JobSheetChrome.chipInk)
                    .accessibilityIdentifier("jobSheet.chip.\(index)")
                    .accessibilityHint("Opens the cited page")
                }
                partChip
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("jobSheet.chips")
    }

    private var partChip: some View {
        JobSheetChipLabel(text: JobSheetCopy.partChip(photoID: catalogPhotoID, partID: catalogPartID))
            .accessibilityIdentifier("jobSheet.partChip")
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(JobSheetCopy.stepsHeading)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityIdentifier("jobSheet.stepsHeading")
            ForEach(JobSheetCopy.steps(photoID: catalogPhotoID, partID: catalogPartID)) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: step.isComplete ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    Text(step.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(step.title)
                .accessibilityValue(step.isComplete ? "Completed" : "Not completed")
                .accessibilityIdentifier("jobSheet.step.\(step.id)")
            }
        }
        .accessibilityIdentifier("jobSheet.steps")
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
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .underline(selected)
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

private struct JobSheetChipLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(JobSheetChrome.chipInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(JobSheetChrome.paper, in: Capsule())
            .overlay {
                Capsule().strokeBorder(JobSheetChrome.chipInk.opacity(0.4), lineWidth: 1)
            }
    }
}

/// Figma paper: #FFFFFF sheet on #F4F4F4 chat. Not system blue-gray.
enum JobSheetChrome {
    static let paper = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .systemBackground }
        return .white
    })

    static let screen = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .systemBackground }
        return UIColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
    })

    static let emptyPhoto = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .secondarySystemBackground }
        return UIColor(red: 0.910, green: 0.910, blue: 0.910, alpha: 1)
    })

    static var screenUIColor: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark { return .systemBackground }
            return UIColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
        }
    }

    /// Label ink. Hierarchical `.primary` on a NavigationLink reads as disabled gray.
    static let chipInk = Color(uiColor: .label)
}

/// Full-window height from a reader that ignores the safe area, plus insets from one
/// that does **not**. Ignoring zeros `safeAreaInsets.top`; fallback is 59 when it is 0.
struct WindowSafeAreaProbe: View {
    var onMeasure: (_ height: CGFloat, _ top: CGFloat, _ bottom: CGFloat) -> Void
    @State private var windowHeight: CGFloat = 0
    @State private var topInset: CGFloat = 0
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ZStack {
            GeometryReader { window in
                Color.clear
                    .onAppear {
                        windowHeight = window.size.height
                        report()
                    }
                    .onChange(of: window.size.height) { _, height in
                        windowHeight = height
                    }
            }
            .ignoresSafeArea()

            GeometryReader { safe in
                Color.clear
                    .onAppear {
                        topInset = safe.safeAreaInsets.top
                        bottomInset = safe.safeAreaInsets.bottom
                        report()
                    }
                    .onChange(of: safe.safeAreaInsets.top) { _, top in
                        topInset = top
                    }
                    .onChange(of: safe.safeAreaInsets.bottom) { _, bottom in
                        bottomInset = bottom
                    }
            }
        }
        .onChange(of: windowHeight) { _, _ in report() }
        .onChange(of: topInset) { _, _ in report() }
        .onChange(of: bottomInset) { _, _ in report() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func report() {
        onMeasure(
            windowHeight,
            topInset > 0 ? topInset : CGFloat(JobSheetLayout.fallbackTopSafeArea),
            bottomInset
        )
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
            JobSheetChrome.screen
                .ignoresSafeArea()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    JobSheetView(
                        model: model,
                        image: HighlightPlaceholderImage.make(),
                        attribution: "Demo data. Not Zeke's truck.",
                        shareAlike: true,
                        onOpenHighlight: {},
                        onAttachPhoto: {}
                    )
                }
        }
    }
}
