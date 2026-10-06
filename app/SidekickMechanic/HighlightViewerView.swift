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
    var referenceImage: UIImage?
    var geometry: HighlightGeometry?
    var attribution: String
    var shareAlike: Bool
    var onYes: (() -> Void)?
    var onNotThis: (() -> Void)?

    init(
        presentation: HighlightViewerPresentation,
        image: UIImage,
        referenceImage: UIImage? = nil,
        geometry: HighlightGeometry?,
        attribution: String,
        shareAlike: Bool,
        onYes: (() -> Void)? = nil,
        onNotThis: (() -> Void)? = nil
    ) {
        _presentation = State(initialValue: presentation)
        self.image = image
        self.referenceImage = referenceImage
        self.geometry = geometry
        self.attribution = attribution
        self.shareAlike = shareAlike
        self.onYes = onYes
        self.onNotThis = onNotThis
    }

    private var cardFill: Color {
        Color(red: 244 / 255, green: 244 / 255, blue: 244 / 255)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let banner = presentation.banner {
                    bannerPill(banner)
                }
                photos
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(cardFill)
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(cardFill, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("highlightViewer.close")
                }
            }
            .accessibilityIdentifier("highlightViewer")
        }
    }

    private func bannerPill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(presentation.kind == .unsure ? .white : .primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                presentation.kind == .unsure ? Color.black : Color.yellow.opacity(0.35),
                in: Capsule()
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityIdentifier("highlightViewer.banner")
    }

    private var photos: some View {
        VStack(spacing: 8) {
            if presentation.kind == .reference {
                photoCard(
                    image: image,
                    geometry: nil,
                    inFrameBanner: presentation.userPhotoBanner,
                    zoomable: false
                )
                .frame(maxHeight: .infinity)
                photoCard(
                    image: referenceImage ?? image,
                    geometry: presentation.showsOutlineOnReferencePhoto ? outlineGeometry : nil,
                    inFrameBanner: nil,
                    zoomable: true
                )
                .frame(maxHeight: .infinity)
            } else {
                photoCard(
                    image: image,
                    geometry: presentation.showsOutlineOnUserPhoto ? outlineGeometry : nil,
                    inFrameBanner: nil,
                    zoomable: true
                )
                .frame(maxHeight: .infinity)
            }
            HStack(alignment: .center, spacing: 8) {
                chipRow
                pinchControl
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var outlineGeometry: HighlightGeometry? {
        geometry
            ?? DemoOutlineCatalog.geometry(
                photoID: presentation.outlinePhotoID,
                partID: presentation.partID
            )
    }

    private func photoCard(
        image: UIImage,
        geometry: HighlightGeometry?,
        inFrameBanner: String?,
        zoomable: Bool
    ) -> some View {
        let photo = DemoHighlightView(
            image: image,
            geometry: geometry,
            style: .outline,
            confirm: presentation.outlineStroke == .dashed,
            dashed: presentation.outlineStroke == .dashed,
            attribution: attribution,
            shareAlike: shareAlike,
            notFound: geometry == nil,
            cornerRadius: 0,
            fillsContainer: true
        )
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Group {
                    if zoomable {
                        photo
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(magnifyGesture)
                            .simultaneousGesture(panGesture)
                            .onTapGesture(count: 2, perform: toggleZoom)
                            .animation(.easeInOut(duration: 0.2), value: scale)
                    } else {
                        photo
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .top) {
                if let inFrameBanner {
                    Text(inFrameBanner)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.black.opacity(0.72))
                        .accessibilityIdentifier("highlightViewer.userPhotoBanner")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("highlightViewer.photo")
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(presentation.tags, id: \.self) { tag in
                Text(tag)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("highlightViewer.tags")
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

    private var pinchControl: some View {
        Button(action: toggleZoom) {
            VStack(spacing: 2) {
                Image(systemName: scale > 1 ? "minus.magnifyingglass" : "plus.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
                Text(HighlightViewerCopy.pinchLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
                Text(HighlightViewerCopy.unsurePrompt)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("highlightViewer.unsurePrompt")

                HStack(spacing: 12) {
                    Button("Yes") {
                        presentation = .make(.confident, pick: DemoOutlineCatalog.selection(
                            photoID: presentation.photoID,
                            partID: presentation.partID,
                            state: .confident
                        ))
                        onYes?()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("demo.confirm.yes")

                    Button("Not this") {
                        presentation = .make(.notFound, pick: DemoOutlineCatalog.selection(
                            photoID: presentation.photoID,
                            partID: presentation.partID,
                            state: .notFound
                        ))
                        onNotThis?()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 1.5)
                    )
                    .accessibilityIdentifier("demo.confirm.notThis")
                }
                .accessibilityIdentifier("demo.confirmBar")
            }

            if !presentation.footer.isEmpty {
                Text(presentation.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("highlightViewer.footer")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
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
        geometry: DemoOutlineCatalog.geometry(photoID: "hilux", partID: "fuse-relay-box"),
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
}

#Preview("Unsure") {
    HighlightViewerView(
        presentation: .make(.unsure),
        image: HighlightPlaceholderImage.make(),
        geometry: DemoOutlineCatalog.geometry(photoID: "hilux", partID: "radiator-cap-upper-hose"),
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
        referenceImage: HighlightPlaceholderImage.make(),
        geometry: DemoOutlineCatalog.geometry(photoID: "supra", partID: "fuse-relay-box"),
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
}

#Preview("Dark") {
    HighlightViewerView(
        presentation: .make(.confident),
        image: HighlightPlaceholderImage.make(),
        geometry: DemoOutlineCatalog.geometry(photoID: "hilux", partID: "fuse-relay-box"),
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    HighlightViewerView(
        presentation: .make(.reference),
        image: HighlightPlaceholderImage.make(),
        geometry: DemoOutlineCatalog.geometry(photoID: "supra", partID: "fuse-relay-box"),
        attribution: "Demo data. Not Zeke's truck.",
        shareAlike: false
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
