import SidekickCore
import SwiftUI
import UIKit

/// Full-bleed highlight card (HL-1…4). Outline is always a polygon, never a box.
struct HighlightViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var presentation: HighlightViewerPresentation
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var image: UIImage
    var geometry: HighlightGeometry?
    var attribution: String
    var shareAlike: Bool
    var onYes: (() -> Void)?
    var onNotThis: (() -> Void)?

    init(
        presentation: HighlightViewerPresentation,
        image: UIImage,
        geometry: HighlightGeometry?,
        attribution: String,
        shareAlike: Bool,
        onYes: (() -> Void)? = nil,
        onNotThis: (() -> Void)? = nil
    ) {
        _presentation = State(initialValue: presentation)
        self.image = image
        self.geometry = geometry
        self.attribution = attribution
        self.shareAlike = shareAlike
        self.onYes = onYes
        self.onNotThis = onNotThis
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let banner = presentation.banner {
                    Text(banner)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(presentation.kind == .unsure ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(presentation.kind == .unsure ? Color.black : Color.yellow.opacity(0.35))
                        .accessibilityIdentifier("highlightViewer.banner")
                }

                photoStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("highlightViewer.close")
                }
            }
            .accessibilityIdentifier("highlightViewer")
        }
    }

    private var photoStage: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGray6)
                zoomablePhoto
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .overlay(alignment: .bottomTrailing) {
                zoomButton
                    .padding(16)
            }
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("highlightViewer.photo")
    }

    private var zoomablePhoto: some View {
        DemoHighlightView(
            image: image,
            geometry: presentation.showsOutline
                ? (geometry ?? HighlightViewerScript.airBoxGeometry)
                : nil,
            style: .outline,
            confirm: presentation.outlineStroke == .dashed,
            dashed: presentation.outlineStroke == .dashed,
            attribution: attribution,
            shareAlike: shareAlike,
            notFound: !presentation.showsOutline,
            cornerRadius: 0
        )
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnifyGesture)
        .simultaneousGesture(panGesture)
        .onTapGesture(count: 2, perform: toggleZoom)
        .animation(.easeInOut(duration: 0.2), value: scale)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clamped(lastScale * value.magnification)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    resetZoom()
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var zoomButton: some View {
        Button(action: toggleZoom) {
            Image(systemName: scale > 1 ? "minus.magnifyingglass" : "plus.magnifyingglass")
                .font(.title3)
                .foregroundStyle(.primary)
                .padding(10)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("highlightViewer.zoom")
        .accessibilityLabel(scale > 1 ? "Zoom out" : "Pinch to zoom")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("highlightViewer.caption")

            Text(presentation.body)
                .font(.body)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("highlightViewer.body")

            if presentation.showsDiagramLink {
                NavigationLink {
                    CitationPageView(citation: presentation.diagramCitation)
                } label: {
                    Text(HighlightViewerCopy.diagramChip)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.background, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.secondary.opacity(0.35))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("highlightViewer.diagram")
                .accessibilityHint("Opens the cited diagram")
            }

            if presentation.showsRetakeHint, let hint = presentation.retakeHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("highlightViewer.retake")
            }

            if presentation.showsConfirmPrompt {
                DemoConfirmBar(
                    onYes: {
                        presentation = .make(.confident)
                        onYes?()
                    },
                    onNotThis: {
                        presentation = .make(.notFound)
                        onNotThis?()
                    }
                )
            }

            Text(presentation.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("highlightViewer.footer")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.bar)
    }

    private func toggleZoom() {
        if scale > 1 {
            resetZoom()
        } else {
            scale = 2
            lastScale = 2
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 4)
    }
}

enum HighlightPlaceholderImage {
    static func make() -> UIImage {
        let size = CGSize(width: 390, height: 520)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemGray4.setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 28, width: 342, height: 56), cornerRadius: 8).fill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 420, width: 110, height: 72), cornerRadius: 8).fill()
            UIBezierPath(roundedRect: CGRect(x: 256, y: 420, width: 110, height: 72), cornerRadius: 8).fill()
        }
    }
}

#Preview("Confident") {
    HighlightViewerView(
        presentation: .make(.confident),
        image: HighlightPlaceholderImage.make(),
        geometry: HighlightViewerScript.airBoxGeometry,
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
}

#Preview("Unsure") {
    HighlightViewerView(
        presentation: .make(.unsure),
        image: HighlightPlaceholderImage.make(),
        geometry: HighlightViewerScript.airBoxGeometry,
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
}

#Preview("Not found") {
    HighlightViewerView(
        presentation: .make(.notFound),
        image: HighlightPlaceholderImage.make(),
        geometry: nil,
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
}

#Preview("Reference") {
    HighlightViewerView(
        presentation: .make(.reference),
        image: HighlightPlaceholderImage.make(),
        geometry: HighlightViewerScript.airBoxGeometry,
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
}

#Preview("Dark") {
    HighlightViewerView(
        presentation: .make(.confident),
        image: HighlightPlaceholderImage.make(),
        geometry: HighlightViewerScript.airBoxGeometry,
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    HighlightViewerView(
        presentation: .make(.reference),
        image: HighlightPlaceholderImage.make(),
        geometry: HighlightViewerScript.airBoxGeometry,
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
