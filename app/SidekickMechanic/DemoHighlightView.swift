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
    let attribution: String
    let shareAlike: Bool
    let notFound: Bool

    var body: some View {
        Color.clear
            .aspectRatio(image.size, contentMode: .fit)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .overlay { styleOverlay }
            }
            .overlay(alignment: .topLeading) {
                DemoDataBadge()
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                Text(attributionLine)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("answerCard.demoHighlight")
            .accessibilityLabel(accessibilityText)
    }

    private var attributionLine: String {
        if shareAlike {
            return "Demo data · CC BY-SA. \(attribution)"
        }
        return "Demo data. \(attribution)"
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
            let width = confirm ? 3.0 : 6.0
            switch style {
            case .outline:
                Canvas { context, size in
                    for path in Self.paths(rings, in: size) {
                        context.stroke(path, with: .color(Self.fuchsia), lineWidth: width)
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
                Color.black.opacity(confirm ? 0.30 : 0.55)
                    .mask { inverseFill(rings) }
                    .allowsHitTesting(false)
            }
        }
    }

    private func polygonFill(_ rings: [HighlightPolygon]) -> some View {
        Canvas { context, size in
            for path in Self.paths(rings, in: size) {
                context.fill(path, with: .color(.white))
            }
        }
    }

    private func inverseFill(_ rings: [HighlightPolygon]) -> some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            for ring in Self.paths(rings, in: size) {
                path.addPath(ring)
            }
            context.fill(path, with: .color(.white), style: FillStyle(eoFill: true))
        }
    }

    private static let fuchsia = Color(red: 1, green: 0, blue: 1)

    private static func paths(_ rings: [HighlightPolygon], in size: CGSize) -> [Path] {
        rings.compactMap { ring in
            guard ring.points.count >= 3 else { return nil }
            var path = Path()
            let first = CGPoint(x: ring.points[0].x * size.width, y: ring.points[0].y * size.height)
            path.move(to: first)
            for point in ring.points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
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
        let points = rings.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        let mapped = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let cx = mapped.map(\.x).reduce(0, +) / CGFloat(mapped.count)
        let cy = mapped.map(\.y).reduce(0, +) / CGFloat(mapped.count)
        let reach = mapped.map { hypot($0.x - cx, $0.y - cy) }.max() ?? 0
        let radius = reach + padding
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
