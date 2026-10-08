/// A pointer at one confirmed bay-map region. JSON object keys are `bay_photo_id`, `part_id`.
/// Optional `display`, `geometry`, and `demo` are demo-scoped (#89 direction, not contract v2).
public struct HighlightRef: Hashable, Sendable, Codable {
    public let bayPhotoID: BayPhotoID
    public let partID: PartID
    public let display: HighlightDisplay?
    public let geometry: HighlightGeometry?
    public let isDemo: Bool

    public init(
        bayPhotoID: BayPhotoID,
        partID: PartID,
        display: HighlightDisplay? = nil,
        geometry: HighlightGeometry? = nil,
        isDemo: Bool = false
    ) {
        self.bayPhotoID = bayPhotoID
        self.partID = partID
        self.display = display
        self.geometry = geometry
        self.isDemo = isDemo
    }

    enum CodingKeys: String, CodingKey {
        case bayPhotoID = "bay_photo_id"
        case partID = "part_id"
        case display
        case geometry
        case isDemo = "demo"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bayPhotoID = try container.decode(BayPhotoID.self, forKey: .bayPhotoID)
        partID = try container.decode(PartID.self, forKey: .partID)
        display = try container.decodeIfPresent(HighlightDisplay.self, forKey: .display)
        geometry = try container.decodeIfPresent(HighlightGeometry.self, forKey: .geometry)
        isDemo = try container.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bayPhotoID, forKey: .bayPhotoID)
        try container.encode(partID, forKey: .partID)
        try container.encodeIfPresent(display, forKey: .display)
        try container.encodeIfPresent(geometry, forKey: .geometry)
        if isDemo {
            try container.encode(true, forKey: .isDemo)
        }
    }
}

/// Wire `display`: `outline` or `confirm`. Omitted means outline.
public enum HighlightDisplay: String, Hashable, Sendable, Codable {
    case outline
    case confirm
}

public struct HighlightPoint: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct HighlightPolygon: Hashable, Sendable, Codable {
    public let points: [HighlightPoint]

    public init(points: [HighlightPoint]) {
        self.points = points
    }
}

public struct HighlightGeometry: Hashable, Sendable, Codable {
    public let polygons: [HighlightPolygon]

    public init(polygons: [HighlightPolygon]) {
        self.polygons = polygons
    }

    public var focus: HighlightPoint? {
        HighlightOutlineLayout.focus(of: self)
    }
}
