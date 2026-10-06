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

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(_ point: HighlightPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
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

    /// Layout the highlight viewer uses: the whole photo is visible (aspect-fit).
    public static func viewerDisplayedImage(
        imageWidth: Double,
        imageHeight: Double,
        boundsWidth: Double,
        boundsHeight: Double
    ) -> OutlineRect {
        aspectFit(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            boundsWidth: boundsWidth,
            boundsHeight: boundsHeight
        )
    }

    /// Cropped rect of `image` covering `bounds`. Used when the photo fills a taller card.
    public static func aspectFill(
        imageWidth: Double,
        imageHeight: Double,
        boundsWidth: Double,
        boundsHeight: Double
    ) -> OutlineRect {
        guard imageWidth > 0, imageHeight > 0, boundsWidth > 0, boundsHeight > 0 else {
            return OutlineRect(x: 0, y: 0, width: 0, height: 0)
        }
        let scale = max(boundsWidth / imageWidth, boundsHeight / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return OutlineRect(
            x: (boundsWidth - width) / 2,
            y: (boundsHeight - height) / 2,
            width: width,
            height: height
        )
    }
}

/// Stroke width and fill opacity for an outline. Scales down on small thumbnails.
public struct HighlightOutlineInk: Equatable, Sendable {
    public var strokeWidth: Double
    public var fillOpacity: Double
    public var dash: [Double]

    public init(strokeWidth: Double, fillOpacity: Double, dash: [Double] = []) {
        self.strokeWidth = strokeWidth
        self.fillOpacity = fillOpacity
        self.dash = dash
    }

    /// Full-size card: 6pt solid (3pt dashed), fill 0.22.
    public static func card(dashed: Bool = false) -> HighlightOutlineInk {
        HighlightOutlineInk(
            strokeWidth: dashed ? 3 : 6,
            fillOpacity: 0.22,
            dash: dashed ? [8, 6] : []
        )
    }

    /// Size-aware default. Below ~120pt the stroke thins and the fill lightens so a
    /// thumbnail does not fill into a solid blob. Callers can pass a custom value.
    public static func scaled(renderedWidth: Double, dashed: Bool = false) -> HighlightOutlineInk {
        let full = card(dashed: dashed)
        let t = min(1, max(0, (renderedWidth - 48) / 72))
        let minStroke = dashed ? 1.0 : 1.25
        let minFill = 0.06
        return HighlightOutlineInk(
            strokeWidth: minStroke + (full.strokeWidth - minStroke) * t,
            fillOpacity: minFill + (full.fillOpacity - minFill) * t,
            dash: dashed ? [4 + 4 * t, 3 + 3 * t] : []
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

/// Drop tiny rings and thin spurs from SAM masks. Keeps the overall part shape.
public enum HighlightOutlineCleanup {
    public static let minRingArea = 0.0004

    public static func cleaned(_ geometry: HighlightGeometry) -> HighlightGeometry? {
        let rings = geometry.polygons.compactMap { ring -> HighlightPolygon? in
            let points = cleaned(points: ring.points)
            guard points.count >= 3, area(points) >= minRingArea else { return nil }
            return HighlightPolygon(points: points)
        }
        return rings.isEmpty ? nil : HighlightGeometry(polygons: rings)
    }

    public static func cleaned(points: [HighlightPoint]) -> [HighlightPoint] {
        var pts = points
        if pts.count >= 2, pts.first == pts.last {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return pts }
        pts = removeSpikes(pts)
        pts = simplify(pts, epsilon: 0.008)
        return pts.count >= 5 ? pts : points
    }

    public static func area(_ points: [HighlightPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var acc = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            acc += a.x * b.y - b.x * a.y
        }
        return abs(acc) / 2
    }

    private static func removeSpikes(_ points: [HighlightPoint]) -> [HighlightPoint] {
        var pts = points
        var changed = true
        var guardCount = 0
        while changed, pts.count > 5, guardCount < 24 {
            changed = false
            guardCount += 1
            var kept: [HighlightPoint] = []
            kept.reserveCapacity(pts.count)
            let count = pts.count
            for index in 0..<count {
                let prev = pts[(index - 1 + count) % count]
                let point = pts[index]
                let next = pts[(index + 1) % count]
                if isSpur(prev: prev, point: point, next: next) {
                    changed = true
                    continue
                }
                kept.append(point)
            }
            if kept.count >= 5 {
                pts = kept
            } else {
                break
            }
        }
        return pts
    }

    private static func isSpur(prev: HighlightPoint, point: HighlightPoint, next: HighlightPoint) -> Bool {
        let chord = distance(prev, next)
        let detour = distance(prev, point) + distance(point, next)
        let tri = abs(
            (prev.x * (point.y - next.y))
                + (point.x * (next.y - prev.y))
                + (next.x * (prev.y - point.y))
        ) / 2
        let onEdge = point.x < 0.02 || point.x > 0.98 || point.y < 0.02 || point.y > 0.98
        let neighborInside = !onBorder(prev) || !onBorder(next)
        if onEdge, neighborInside, detour / max(chord, 1e-9) > 1.25 {
            return true
        }
        guard chord > 1e-9 else { return false }
        return detour / chord > 1.7 && tri < 0.0008
    }

    private static func onBorder(_ point: HighlightPoint) -> Bool {
        point.x < 0.02 || point.x > 0.98 || point.y < 0.02 || point.y > 0.98
    }

    private static func simplify(_ points: [HighlightPoint], epsilon: Double) -> [HighlightPoint] {
        guard points.count > 5 else { return points }
        var ring = points
        ring.append(points[0])
        let reduced = ramerDouglasPeucker(ring, epsilon: epsilon)
        if reduced.count >= 2, reduced.first == reduced.last {
            return Array(reduced.dropLast())
        }
        return reduced.count >= 5 ? reduced : points
    }

    private static func ramerDouglasPeucker(_ points: [HighlightPoint], epsilon: Double) -> [HighlightPoint] {
        guard points.count > 2 else { return points }
        let start = points[0]
        let end = points[points.count - 1]
        var maxDistance = 0.0
        var maxIndex = 0
        for index in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[index], start: start, end: end)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = index
            }
        }
        if maxDistance > epsilon {
            let left = ramerDouglasPeucker(Array(points[0...maxIndex]), epsilon: epsilon)
            let right = ramerDouglasPeucker(Array(points[maxIndex...]), epsilon: epsilon)
            return left.dropLast() + right
        }
        return [start, end]
    }

    private static func perpendicularDistance(
        _ point: HighlightPoint,
        start: HighlightPoint,
        end: HighlightPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-12 else { return distance(point, start) }
        return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / length
    }

    private static func distance(_ a: HighlightPoint, _ b: HighlightPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
