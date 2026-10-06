/// Fitted image rect in the same space the outline is drawn.
public struct OutlineRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// One cubic Bézier of a closed Catmull-Rom ring, still in normalized 0-1 space.
public struct OutlineCubic: Equatable, Sendable {
    public var start: HighlightPoint
    public var control1: HighlightPoint
    public var control2: HighlightPoint
    public var end: HighlightPoint

    public init(
        start: HighlightPoint,
        control1: HighlightPoint,
        control2: HighlightPoint,
        end: HighlightPoint
    ) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }
}

/// Aspect-fit mapping for normalized outline points.
public enum HighlightOutlineLayout {
    /// Letterboxed rect of `image` inside `bounds`. Used so the stroke tracks the photo.
    public static func aspectFit(
        imageWidth: Double,
        imageHeight: Double,
        boundsWidth: Double,
        boundsHeight: Double
    ) -> OutlineRect {
        guard imageWidth > 0, imageHeight > 0, boundsWidth > 0, boundsHeight > 0 else {
            return OutlineRect(x: 0, y: 0, width: 0, height: 0)
        }
        let scale = min(boundsWidth / imageWidth, boundsHeight / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return OutlineRect(
            x: (boundsWidth - width) / 2,
            y: (boundsHeight - height) / 2,
            width: width,
            height: height
        )
    }

    public static func map(_ point: HighlightPoint, in rect: OutlineRect) -> HighlightPoint {
        HighlightPoint(
            x: rect.x + point.x * rect.width,
            y: rect.y + point.y * rect.height
        )
    }
}

/// Closed Catmull-Rom → cubic Béziers. Never a bounding box.
public enum HighlightOutlineCurve {
    public static func closedCubics(points: [HighlightPoint]) -> [OutlineCubic] {
        let count = points.count
        guard count >= 3 else { return [] }
        return (0..<count).map { index in
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            return OutlineCubic(
                start: p1,
                control1: HighlightPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                ),
                control2: HighlightPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                ),
                end: p2
            )
        }
    }

    /// Four corners / two unique X and two unique Y. A highlight must not be this.
    public static func isAxisAlignedRectangle(_ points: [HighlightPoint]) -> Bool {
        guard points.count == 4 else { return false }
        let xs = Set(points.map { rounded($0.x) })
        let ys = Set(points.map { rounded($0.y) })
        return xs.count == 2 && ys.count == 2
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
