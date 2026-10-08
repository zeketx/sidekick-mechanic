import SidekickCore
import SwiftUI
import UIKit

/// SwiftUI stand-in for the #31 Core Image renderer. Demo-mode only.
/// Styles match `backend/highlight.py`: outline, saturate, circle, dim.
struct DemoHighlightView: View {
    let image: UIImage
    let geometry: HighlightGeometry?
    let style: DemoHighlightStyle
    let confirm: Bool
    var dashed: Bool = false
    let attribution: String
    let shareAlike: Bool
    let notFound: Bool
    var cornerRadius: CGFloat = 12
    /// When nil, stroke and fill scale from the rendered width (thumbnails stay outlines).
    var outlineInk: HighlightOutlineInk? = nil
    var fillsContainer: Bool = false

    var body: some View {
        Group {
            if fillsContainer {
                // Overlay keeps the image's ideal size from expanding the parent
                // (Jobs row accessibility frames were 24pt wider than the card).
                Color.clear
                    .overlay {
                        GeometryReader { proxy in
                            let mapped = Self.imageRect(
                                imageSize: image.size,
                                bounds: proxy.size,
                                fill: true,
                                focus: HighlightOutlineLayout.focus(of: geometry)
                            )
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.medium)
                                .frame(width: mapped.width, height: mapped.height)
                                .position(x: mapped.midX, y: mapped.midY)
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay { styleOverlay }
                    .clipped()
                    .contentShape(Rectangle())
            } else {
                Color.clear
                    .aspectRatio(image.size, contentMode: .fit)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .overlay { styleOverlay }
                    }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !attributionLine.isEmpty {
                Text(attributionLine)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityIdentifier("answerCard.demoHighlight")
        .accessibilityLabel(accessibilityText)
    }

    private var attributionLine: String {
        if shareAlike {
            return "CC BY-SA. \(attribution)"
        }
        return attribution
    }

    private var accessibilityText: String {
        if notFound {
            return "Demo bay photo. No highlight. See the manual diagram placeholder."
        }
        return confirm
            ? "Demo highlight. Unsure. Is this it?"
            : "Demo highlight. \(style.pickerLabel)."
    }

    @ViewBuilder
    private var styleOverlay: some View {
        if notFound { EmptyView() }
        else {
            let rings = geometry?.polygons ?? []
            switch style {
            case .outline:
                Canvas { context, size in
                    let ink = outlineInk ?? HighlightOutlineInk.scaled(
                        renderedWidth: size.width,
                        dashed: confirm || dashed
                    )
                    let mapped = Self.imageRect(
                        imageSize: image.size,
                        bounds: size,
                        fill: fillsContainer,
                        focus: fillsContainer ? HighlightOutlineLayout.focus(of: geometry) : nil
                    )
                    let fill = Self.fillFuchsia.opacity(ink.fillOpacity)
                    for path in Self.smoothPaths(rings, in: mapped) {
                        context.fill(path, with: .color(fill))
                        context.stroke(
                            path,
                            with: .color(Self.fuchsia),
                            style: StrokeStyle(
                                lineWidth: ink.strokeWidth,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: ink.dash.map { CGFloat($0) }
                            )
                        )
                    }
                }
                .allowsHitTesting(false)
            case .circle:
                Canvas { context, size in
                    if let box = Self.circleBox(rings, in: size, padding: confirm ? 16 : 8) {
                        var path = Path()
                        path.addEllipse(in: box)
                        context.stroke(path, with: .color(Self.fuchsia), lineWidth: confirm ? 2 : 4)
                    }
                }
                .allowsHitTesting(false)
            case .saturate:
                Image(uiImage: image)
                    .resizable()
                    .saturation(confirm ? 2.0 : 3.0)
                    .mask { polygonFill(rings) }
                    .allowsHitTesting(false)
            case .dim:
                Color.black.opacity(confirm ? 0.55 : 0.62)
                    .mask { inverseFill(rings) }
                    .allowsHitTesting(false)
            }
        }
    }

    private func polygonFill(_ rings: [HighlightPolygon]) -> some View {
        Canvas { context, size in
            let mapped = Self.imageRect(
                imageSize: image.size,
                bounds: size,
                fill: fillsContainer,
                focus: fillsContainer ? HighlightOutlineLayout.focus(of: geometry) : nil
            )
            for path in Self.smoothPaths(rings, in: mapped) {
                context.fill(path, with: .color(.white))
            }
        }
    }

    private func inverseFill(_ rings: [HighlightPolygon]) -> some View {
        Canvas { context, size in
            let mapped = Self.imageRect(
                imageSize: image.size,
                bounds: size,
                fill: fillsContainer,
                focus: fillsContainer ? HighlightOutlineLayout.focus(of: geometry) : nil
            )
            var path = Path(CGRect(origin: .zero, size: size))
            for ring in Self.smoothPaths(rings, in: mapped) {
                path.addPath(ring)
            }
            context.fill(path, with: .color(.white), style: FillStyle(eoFill: true))
        }
    }

    private static let fuchsia = Color(red: 1, green: 0, blue: 1)
    private static let fillFuchsia = Color(red: 1, green: 0.45, blue: 0.95)

    private static func imageRect(
        imageSize: CGSize,
        bounds: CGSize,
        fill: Bool,
        focus: HighlightPoint? = nil
    ) -> OutlineRect {
        if fill {
            return HighlightOutlineLayout.aspectFill(
                imageWidth: imageSize.width,
                imageHeight: imageSize.height,
                boundsWidth: bounds.width,
                boundsHeight: bounds.height,
                focus: focus
            )
        }
        return HighlightOutlineLayout.aspectFit(
            imageWidth: imageSize.width,
            imageHeight: imageSize.height,
            boundsWidth: bounds.width,
            boundsHeight: bounds.height
        )
    }

    private static func smoothPaths(_ rings: [HighlightPolygon], in rect: OutlineRect) -> [Path] {
        rings.compactMap { ring in
            let cubics = HighlightOutlineCurve.closedCubics(points: ring.points)
            guard let first = cubics.first else { return nil }
            var path = Path()
            let start = HighlightOutlineLayout.map(first.start, in: rect)
            path.move(to: CGPoint(x: start.x, y: start.y))
            for cubic in cubics {
                let c1 = HighlightOutlineLayout.map(cubic.control1, in: rect)
                let c2 = HighlightOutlineLayout.map(cubic.control2, in: rect)
                let end = HighlightOutlineLayout.map(cubic.end, in: rect)
                path.addCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control1: CGPoint(x: c1.x, y: c1.y),
                    control2: CGPoint(x: c2.x, y: c2.y)
                )
            }
            path.closeSubpath()
            return path
        }
    }

    private static func circleBox(
        _ rings: [HighlightPolygon],
        in size: CGSize,
        padding: CGFloat
    ) -> CGRect? {
        let fitted = imageRect(imageSize: size, bounds: size, fill: false)
        let points = rings.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        let mapped = points.map {
            let point = HighlightOutlineLayout.map($0, in: fitted)
            return CGPoint(x: point.x, y: point.y)
        }
        let minX = mapped.map(\.x).min() ?? 0
        let maxX = mapped.map(\.x).max() ?? 0
        let minY = mapped.map(\.y).min() ?? 0
        let maxY = mapped.map(\.y).max() ?? 0
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let radius = hypot((maxX - minX) / 2, (maxY - minY) / 2) + padding
        return CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
    }
}

struct DemoDataBadge: View {
    var body: some View {
        Text("Demo data")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.yellow.opacity(0.92), in: Capsule())
            .foregroundStyle(.black)
            .accessibilityIdentifier("demo.badge")
    }
}
