import Foundation

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

    /// Scan-log cell (~110pt square). About 2pt stroke, light fill — never a blob.
    public static func lookBackTile(dashed: Bool = false) -> HighlightOutlineInk {
        HighlightOutlineInk(
            strokeWidth: dashed ? 1.5 : 2.0,
            fillOpacity: 0.08,
            dash: dashed ? [4, 3] : []
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
    static let significantRingFraction = 0.2
    static let minConvexAngleDegrees = 75.0
    static let thinWidthFraction = 0.05

    public static func cleaned(_ geometry: HighlightGeometry) -> HighlightGeometry? {
        let rings = geometry.polygons.compactMap { ring -> HighlightPolygon? in
            let points = cleaned(points: ring.points)
            guard points.count >= 3, area(points) >= minRingArea else { return nil }
            return HighlightPolygon(points: points)
        }
        let kept = largestContours(rings)
        return kept.isEmpty ? nil : HighlightGeometry(polygons: kept)
    }

    public static func cleaned(points: [HighlightPoint]) -> [HighlightPoint] {
        var pts = points
        if pts.count >= 2, pts.first == pts.last {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return pts }
        pts = removeSpikes(pts)
        pts = removeThinProtrusions(pts)
        pts = simplify(pts, epsilon: 0.008)
        pts = smooth(pts)
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

    /// Smaller angle at each vertex, in degrees (0...180).
    static func vertexAngleDegrees(_ points: [HighlightPoint]) -> [Double] {
        let count = points.count
        guard count >= 3 else { return [] }
        return (0..<count).map { index in
            angleDegrees(
                prev: points[(index - 1 + count) % count],
                point: points[index],
                next: points[(index + 1) % count]
            )
        }
    }

    static func minimumVertexAngleDegrees(_ points: [HighlightPoint]) -> Double {
        vertexAngleDegrees(points).min() ?? 180
    }

    static func solidity(_ points: [HighlightPoint]) -> Double {
        let hull = convexHullArea(points)
        guard hull > 1e-12 else { return 0 }
        return area(points) / hull
    }

    static func hasSelfIntersection(_ points: [HighlightPoint]) -> Bool {
        let count = points.count
        guard count >= 4 else { return false }
        for i in 0..<count {
            let a = points[i]
            let b = points[(i + 1) % count]
            var j = i + 2
            while j < count {
                if i == 0, j == count - 1 {
                    j += 1
                    continue
                }
                let c = points[j]
                let d = points[(j + 1) % count]
                if segmentsIntersect(a, b, c, d) {
                    return true
                }
                j += 1
            }
        }
        return false
    }

    private static func largestContours(_ rings: [HighlightPolygon]) -> [HighlightPolygon] {
        guard let largest = rings.map({ area($0.points) }).max(), largest > 0 else {
            return []
        }
        let floor = max(minRingArea, significantRingFraction * largest)
        return rings.filter { area($0.points) >= floor }
            .sorted { area($0.points) > area($1.points) }
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

    /// Drop thin convex protrusions (SAM tails / squiggles). Leaves the part body.
    private static func removeThinProtrusions(_ points: [HighlightPoint]) -> [HighlightPoint] {
        var pts = points
        var guardCount = 0
        while pts.count > 8, guardCount < 32 {
            guardCount += 1
            let box = boundingBox(pts)
            let maxSide = max(box.width, box.height)
            let widthFloor = thinWidthFraction * maxSide
            let count = pts.count
            var worstIndex: Int?
            var worstScore = Double.greatestFiniteMagnitude
            for index in 0..<count {
                let prev = pts[(index - 1 + count) % count]
                let point = pts[index]
                let next = pts[(index + 1) % count]
                guard isConvexVertex(prev: prev, point: point, next: next, winding: signedArea(pts)) else {
                    continue
                }
                let angle = angleDegrees(prev: prev, point: point, next: next)
                let width = localWidth(at: index, points: pts)
                let sharp = angle < minConvexAngleDegrees
                let thin = width < widthFloor && angle < 110
                guard sharp || thin else { continue }
                let score = sharp ? angle : width
                if score < worstScore {
                    worstScore = score
                    worstIndex = index
                }
            }
            guard let worstIndex else { break }
            pts.remove(at: worstIndex)
        }
        return pts
    }

    /// Mild Laplacian so Catmull-Rom does not loop on leftover corners.
    private static func smooth(_ points: [HighlightPoint], passes: Int = 2, weight: Double = 0.25) -> [HighlightPoint] {
        var pts = points
        guard pts.count >= 5 else { return pts }
        let kept = 1 - weight
        for _ in 0..<passes {
            let count = pts.count
            pts = (0..<count).map { index in
                let prev = pts[(index - 1 + count) % count]
                let point = pts[index]
                let next = pts[(index + 1) % count]
                return HighlightPoint(
                    x: kept * point.x + weight * 0.5 * (prev.x + next.x),
                    y: kept * point.y + weight * 0.5 * (prev.y + next.y)
                )
            }
        }
        return pts
    }

    private static func angleDegrees(prev: HighlightPoint, point: HighlightPoint, next: HighlightPoint) -> Double {
        let v1x = prev.x - point.x
        let v1y = prev.y - point.y
        let v2x = next.x - point.x
        let v2y = next.y - point.y
        let n1 = (v1x * v1x + v1y * v1y).squareRoot()
        let n2 = (v2x * v2x + v2y * v2y).squareRoot()
        guard n1 > 1e-12, n2 > 1e-12 else { return 0 }
        let cosine = max(-1, min(1, (v1x * v2x + v1y * v2y) / (n1 * n2)))
        return acos(cosine) * 180 / Double.pi
    }

    private static func signedArea(_ points: [HighlightPoint]) -> Double {
        var acc = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            acc += a.x * b.y - b.x * a.y
        }
        return acc / 2
    }

    private static func isConvexVertex(
        prev: HighlightPoint,
        point: HighlightPoint,
        next: HighlightPoint,
        winding: Double
    ) -> Bool {
        let cross = (point.x - prev.x) * (next.y - prev.y) - (point.y - prev.y) * (next.x - prev.x)
        return cross * winding > 0
    }

    private static func boundingBox(_ points: [HighlightPoint]) -> OutlineRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return OutlineRect(
            x: minX,
            y: minY,
            width: (xs.max() ?? 0) - minX,
            height: (ys.max() ?? 0) - minY
        )
    }

    private static func localWidth(at index: Int, points: [HighlightPoint]) -> Double {
        let count = points.count
        let point = points[index]
        var best = Double.greatestFiniteMagnitude
        for edge in 0..<count {
            let next = (edge + 1) % count
            if edge == index || next == index { continue }
            if edge == (index - 1 + count) % count { continue }
            let distance = pointToSegmentDistance(point, a: points[edge], b: points[next])
            if distance < best { best = distance }
        }
        return best
    }

    private static func pointToSegmentDistance(
        _ point: HighlightPoint,
        a: HighlightPoint,
        b: HighlightPoint
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 1e-18 else { return distance(point, a) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSq))
        return distance(point, HighlightPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private static func convexHullArea(_ points: [HighlightPoint]) -> Double {
        let unique = Array(Set(points)).sorted { lhs, rhs in
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
        guard unique.count >= 3 else { return 0 }
        var lower: [HighlightPoint] = []
        for point in unique {
            while lower.count >= 2,
                  cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0
            {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [HighlightPoint] = []
        for point in unique.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0
            {
                upper.removeLast()
            }
            upper.append(point)
        }
        lower.removeLast()
        upper.removeLast()
        return area(lower + upper)
    }

    private static func cross(_ origin: HighlightPoint, _ a: HighlightPoint, _ b: HighlightPoint) -> Double {
        (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
    }

    private static func segmentsIntersect(
        _ a: HighlightPoint,
        _ b: HighlightPoint,
        _ c: HighlightPoint,
        _ d: HighlightPoint
    ) -> Bool {
        if a == c || a == d || b == c || b == d { return false }
        func ccw(_ p: HighlightPoint, _ q: HighlightPoint, _ r: HighlightPoint) -> Bool {
            (r.y - p.y) * (q.x - p.x) > (q.y - p.y) * (r.x - p.x)
        }
        return ccw(a, c, d) != ccw(b, c, d) && ccw(a, b, c) != ccw(a, b, d)
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
