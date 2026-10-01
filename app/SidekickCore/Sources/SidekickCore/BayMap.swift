/// Normalized bay coordinates. Origin is the top left, x increases to the right, y increases down.
public enum BayCoordinateSpace: Hashable, Sendable {
    case normalizedTopLeft
}

public enum BayMapSchemaVersion: Int, Hashable, Sendable {
    case v1 = 1
}

public enum BayPhotoSourceKind: String, Codable, Hashable, Sendable {
    case publicPrototype = "public_prototype"
    case ownerObservation = "owner_observation"
}

public struct BayPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init?(x: Double, y: Double) {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            return nil
        }
        self.x = x
        self.y = y
    }
}

public struct BayPolygon: Hashable, Sendable {
    public let points: [BayPoint]

    public init?(points: [BayPoint]) {
        guard points.count >= 3, let first = points.first, let last = points.last, first != last else {
            return nil
        }
        guard polygonArea(points) > 0 else { return nil }
        self.points = points
    }
}

public struct BayRegionGeometry: Hashable, Sendable {
    public let polygons: [BayPolygon]

    public init?(polygons: [BayPolygon]) {
        guard !polygons.isEmpty else { return nil }
        self.polygons = polygons
    }
}

public struct PixelSize: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init?(width: Int, height: Int) {
        guard width >= 1, height >= 1 else { return nil }
        self.width = width
        self.height = height
    }
}

public struct BayPhotoSource: Hashable, Sendable {
    public let kind: BayPhotoSourceKind
    public let reference: String

    public init?(kind: BayPhotoSourceKind, reference: String) {
        guard !reference.isEmpty else { return nil }
        self.kind = kind
        self.reference = reference
    }
}

public struct BayPhotoLicense: Hashable, Sendable {
    public let name: String
    public let reference: String

    public init?(name: String, reference: String) {
        guard !name.isEmpty, !reference.isEmpty else { return nil }
        self.name = name
        self.reference = reference
    }
}

public struct BayPart: Hashable, Sendable {
    public let id: PartID
    public let displayName: String
    public let aliases: [String]
}

public struct BayPhoto: Hashable, Sendable {
    public let id: BayPhotoID
    public let angleID: BayAngleID
    public let imageSize: PixelSize
    public let source: BayPhotoSource
    public let license: BayPhotoLicense
}

/// One part the resolver may name, already paired with the preferred confirmed photo.
public struct HighlightChoice: Hashable, Sendable {
    public let part: BayPart
    public let reference: HighlightRef

    fileprivate init(part: BayPart, reference: HighlightRef) {
        self.part = part
        self.reference = reference
    }
}

/// Polygons for one confirmed region. `BayMap.resolve` is the only constructor.
public struct ConfirmedHighlight: Hashable, Sendable {
    public let part: BayPart
    public let photo: BayPhoto
    public let geometry: BayRegionGeometry
    public let confirmedBy: ConfirmerID

    public var reference: HighlightRef {
        HighlightRef(bayPhotoID: photo.id, partID: part.id)
    }

    fileprivate init(
        part: BayPart,
        photo: BayPhoto,
        geometry: BayRegionGeometry,
        confirmedBy: ConfirmerID
    ) {
        self.part = part
        self.photo = photo
        self.geometry = geometry
        self.confirmedBy = confirmedBy
    }
}

/// Unconfirmed regions stay in the file and cannot be resolved.
public struct BayMap: Hashable, Sendable {
    public let schemaVersion: BayMapSchemaVersion
    public let coordinateSpace: BayCoordinateSpace

    private let partsByID: [PartID: BayPart]
    private let photosByID: [BayPhotoID: StoredPhoto]
    private let regionsByKey: [RegionKey: RegionRecord]

    public var parts: [BayPart] {
        partsByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var photos: [BayPhoto] {
        photosByID.values.map(\.photo).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var highlightChoices: [HighlightChoice] {
        var best: [PartID: AreaChoice] = [:]
        for (key, record) in regionsByKey {
            guard case let .confirmed(geometry, _) = record else { continue }
            let photo = photosByID[key.photoID]?.photo
            let candidate = AreaChoice(
                photoID: key.photoID,
                angleID: photo?.angleID.rawValue ?? "",
                area: pixelArea(geometry, size: photo?.imageSize)
            )
            if let current = best[key.partID] {
                if candidate.beats(current) {
                    best[key.partID] = candidate
                }
            } else {
                best[key.partID] = candidate
            }
        }
        return best.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { partID in
            guard let part = partsByID[partID], let winner = best[partID] else { return nil }
            return HighlightChoice(
                part: part,
                reference: HighlightRef(bayPhotoID: winner.photoID, partID: partID)
            )
        }
    }

    /// Nil when the pair is missing or the region is unconfirmed.
    public func resolve(_ reference: HighlightRef) -> ConfirmedHighlight? {
        guard
            let part = partsByID[reference.partID],
            let stored = photosByID[reference.bayPhotoID],
            let record = regionsByKey[RegionKey(photoID: reference.bayPhotoID, partID: reference.partID)],
            case let .confirmed(geometry, confirmedBy) = record
        else {
            return nil
        }
        return ConfirmedHighlight(
            part: part,
            photo: stored.photo,
            geometry: geometry,
            confirmedBy: confirmedBy
        )
    }
}

extension BayMap: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case coordinateSpace = "coordinate_space"
        case parts
        case photos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard let schemaVersion = BayMapSchemaVersion(rawValue: version) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "schema_version must be 1"
            )
        }
        coordinateSpace = try container.decode(BayCoordinateSpace.self, forKey: .coordinateSpace)
        let wireParts = try container.decode([WirePart].self, forKey: .parts)
        let wirePhotos = try container.decode([WirePhoto].self, forKey: .photos)
        let built = try buildCatalog(parts: wireParts, photos: wirePhotos)
        self.schemaVersion = schemaVersion
        partsByID = built.partsByID
        photosByID = built.photosByID
        regionsByKey = built.regionsByKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion.rawValue, forKey: .schemaVersion)
        try container.encode(coordinateSpace, forKey: .coordinateSpace)
        try container.encode(parts.map(WirePart.init), forKey: .parts)
        let wirePhotos = photos.map { photo in
            let regions = regionsByKey
                .filter { $0.key.photoID == photo.id }
                .sorted { $0.key.partID.rawValue < $1.key.partID.rawValue }
                .map { WireRegion(partID: $0.key.partID, record: $0.value) }
            return WirePhoto(photo: photo, regions: regions)
        }
        try container.encode(wirePhotos, forKey: .photos)
    }
}

extension BayCoordinateSpace: Codable {
    private enum CodingKeys: String, CodingKey {
        case units
        case origin
        case xAxis = "x_axis"
        case yAxis = "y_axis"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let units = try container.decode(String.self, forKey: .units)
        let origin = try container.decode(String.self, forKey: .origin)
        let xAxis = try container.decode(String.self, forKey: .xAxis)
        let yAxis = try container.decode(String.self, forKey: .yAxis)
        guard units == "normalized", origin == "top_left", xAxis == "right", yAxis == "down" else {
            throw DecodingError.dataCorruptedError(
                forKey: .units,
                in: container,
                debugDescription: "coordinate_space must be normalized top_left, x right, y down"
            )
        }
        self = .normalizedTopLeft
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("normalized", forKey: .units)
        try container.encode("top_left", forKey: .origin)
        try container.encode("right", forKey: .xAxis)
        try container.encode("down", forKey: .yAxis)
    }
}

private struct RegionKey: Hashable, Sendable {
    let photoID: BayPhotoID
    let partID: PartID
}

private enum RegionRecord: Hashable, Sendable {
    case confirmed(BayRegionGeometry, ConfirmerID)
    case unconfirmed(BayRegionGeometry)
}

private struct StoredPhoto: Hashable, Sendable {
    let photo: BayPhoto
}

private struct Catalog {
    let partsByID: [PartID: BayPart]
    let photosByID: [BayPhotoID: StoredPhoto]
    let regionsByKey: [RegionKey: RegionRecord]
}

private struct WirePart: Codable {
    let id: PartID
    let displayName: String
    let aliases: [String]

    enum CodingKeys: String, CodingKey {
        case id = "part_id"
        case displayName = "display_name"
        case aliases
    }

    init(part: BayPart) {
        id = part.id
        displayName = part.displayName
        aliases = part.aliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PartID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        aliases = try container.decode([String].self, forKey: .aliases)
        guard !displayName.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .displayName,
                in: container,
                debugDescription: "display_name must be non-empty"
            )
        }
        if aliases.contains(where: \.isEmpty) {
            throw DecodingError.dataCorruptedError(
                forKey: .aliases,
                in: container,
                debugDescription: "aliases must be non-empty"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(aliases, forKey: .aliases)
    }
}

private struct WirePhoto: Codable {
    let photo: BayPhoto
    let regions: [WireRegion]

    enum CodingKeys: String, CodingKey {
        case id = "bay_photo_id"
        case angleID = "angle_id"
        case imageSize = "image_size"
        case source
        case license
        case regions
    }

    init(photo: BayPhoto, regions: [WireRegion]) {
        self.photo = photo
        self.regions = regions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(BayPhotoID.self, forKey: .id)
        let angleID = try container.decode(BayAngleID.self, forKey: .angleID)
        let imageSize = try container.decode(PixelSize.self, forKey: .imageSize)
        let source = try container.decode(BayPhotoSource.self, forKey: .source)
        let license = try container.decode(BayPhotoLicense.self, forKey: .license)
        regions = try container.decode([WireRegion].self, forKey: .regions)
        photo = BayPhoto(id: id, angleID: angleID, imageSize: imageSize, source: source, license: license)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(photo.id, forKey: .id)
        try container.encode(photo.angleID, forKey: .angleID)
        try container.encode(photo.imageSize, forKey: .imageSize)
        try container.encode(photo.source, forKey: .source)
        try container.encode(photo.license, forKey: .license)
        try container.encode(regions, forKey: .regions)
    }
}

private struct WireRegion: Codable {
    let partID: PartID
    let record: RegionRecord

    enum CodingKeys: String, CodingKey {
        case partID = "part_id"
        case polygons
        case confirmation
    }

    init(partID: PartID, record: RegionRecord) {
        self.partID = partID
        self.record = record
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        partID = try container.decode(PartID.self, forKey: .partID)
        let polygons = try container.decode([BayPolygon].self, forKey: .polygons)
        guard let geometry = BayRegionGeometry(polygons: polygons) else {
            throw DecodingError.dataCorruptedError(
                forKey: .polygons,
                in: container,
                debugDescription: "region needs at least one polygon"
            )
        }
        let confirmation = try container.decode(ConfirmationWire.self, forKey: .confirmation)
        record = attach(geometry, to: confirmation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partID, forKey: .partID)
        switch record {
        case let .confirmed(geometry, confirmedBy):
            try container.encode(geometry.polygons, forKey: .polygons)
            try container.encode(ConfirmationWire.confirmed(confirmedBy), forKey: .confirmation)
        case let .unconfirmed(geometry):
            try container.encode(geometry.polygons, forKey: .polygons)
            try container.encode(ConfirmationWire.unconfirmed, forKey: .confirmation)
        }
    }
}

private enum ConfirmationWire: Codable {
    case confirmed(ConfirmerID)
    case unconfirmed

    private enum CodingKeys: String, CodingKey {
        case kind
        case confirmedBy = "confirmed_by"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "confirmed":
            self = .confirmed(try container.decode(ConfirmerID.self, forKey: .confirmedBy))
        case "unconfirmed":
            if container.contains(.confirmedBy) {
                throw DecodingError.dataCorruptedError(
                    forKey: .confirmedBy,
                    in: container,
                    debugDescription: "unconfirmed region cannot include confirmed_by"
                )
            }
            self = .unconfirmed
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "confirmation kind must be confirmed or unconfirmed"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .confirmed(confirmedBy):
            try container.encode("confirmed", forKey: .kind)
            try container.encode(confirmedBy, forKey: .confirmedBy)
        case .unconfirmed:
            try container.encode("unconfirmed", forKey: .kind)
        }
    }
}

extension PixelSize: Codable {
    private enum CodingKeys: String, CodingKey {
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int.self, forKey: .width)
        let height = try container.decode(Int.self, forKey: .height)
        guard let size = PixelSize(width: width, height: height) else {
            throw DecodingError.dataCorruptedError(
                forKey: .width,
                in: container,
                debugDescription: "image width and height must be >= 1"
            )
        }
        self = size
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}

extension BayPhotoSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case reference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(BayPhotoSourceKind.self, forKey: .kind)
        let reference = try container.decode(String.self, forKey: .reference)
        guard let source = BayPhotoSource(kind: kind, reference: reference) else {
            throw DecodingError.dataCorruptedError(
                forKey: .reference,
                in: container,
                debugDescription: "source reference must be non-empty"
            )
        }
        self = source
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(reference, forKey: .reference)
    }
}

extension BayPhotoLicense: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case reference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let reference = try container.decode(String.self, forKey: .reference)
        guard let license = BayPhotoLicense(name: name, reference: reference) else {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "license name and reference must be non-empty"
            )
        }
        self = license
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(reference, forKey: .reference)
    }
}

extension BayPoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case x
        case y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        guard let point = BayPoint(x: x, y: y) else {
            throw DecodingError.dataCorruptedError(
                forKey: .x,
                in: container,
                debugDescription: "point must be finite and inside 0...1"
            )
        }
        self = point
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}

extension BayPolygon: Codable {
    private enum CodingKeys: String, CodingKey {
        case points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let points = try container.decode([BayPoint].self, forKey: .points)
        if let first = points.first, let last = points.last, first == last {
            throw DecodingError.dataCorruptedError(
                forKey: .points,
                in: container,
                debugDescription: "polygon repeats its first point"
            )
        }
        guard let polygon = BayPolygon(points: points) else {
            throw DecodingError.dataCorruptedError(
                forKey: .points,
                in: container,
                debugDescription: "polygon area must be positive"
            )
        }
        self = polygon
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
    }
}

private func polygonArea(_ points: [BayPoint]) -> Double {
    var sum = 0.0
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        sum += current.x * next.y - next.x * current.y
    }
    return abs(sum) / 2
}

private func regionArea(_ geometry: BayRegionGeometry) -> Double {
    geometry.polygons.reduce(0) { partial, polygon in
        partial + polygonArea(polygon.points)
    }
}

private struct AreaChoice {
    let photoID: BayPhotoID
    let angleID: String
    let area: Int

    func beats(_ other: AreaChoice) -> Bool {
        if area != other.area {
            return area > other.area
        }
        if photoID.rawValue != other.photoID.rawValue {
            return photoID.rawValue < other.photoID.rawValue
        }
        return angleID < other.angleID
    }
}

private func pixelArea(_ geometry: BayRegionGeometry, size: PixelSize?) -> Int {
    guard let size else { return 0 }
    let scaled = regionArea(geometry) * Double(size.width * size.height)
    return Int((scaled + 0.5).rounded(.down))
}

private func attach(_ geometry: BayRegionGeometry, to confirmation: ConfirmationWire) -> RegionRecord {
    switch confirmation {
    case let .confirmed(confirmedBy):
        return .confirmed(geometry, confirmedBy)
    case .unconfirmed:
        return .unconfirmed(geometry)
    }
}

private func buildCatalog(parts wireParts: [WirePart], photos wirePhotos: [WirePhoto]) throws -> Catalog {
    var partsByID: [PartID: BayPart] = [:]
    var displayNames: Set<String> = []
    var aliases: Set<String> = []
    for wire in wireParts {
        if partsByID[wire.id] != nil {
            throw BayMapParseError.duplicatePartID
        }
        if displayNames.contains(wire.displayName) {
            throw BayMapParseError.duplicateDisplayName
        }
        displayNames.insert(wire.displayName)
        partsByID[wire.id] = BayPart(id: wire.id, displayName: wire.displayName, aliases: wire.aliases)
    }
    let taken = Set(partsByID.keys.map(\.rawValue)).union(displayNames)
    for part in partsByID.values {
        for alias in part.aliases {
            if taken.contains(alias) || aliases.contains(alias) {
                throw BayMapParseError.aliasCollision
            }
            aliases.insert(alias)
        }
    }

    var photosByID: [BayPhotoID: StoredPhoto] = [:]
    var regionsByKey: [RegionKey: RegionRecord] = [:]
    var referenced: Set<PartID> = []
    for wire in wirePhotos {
        if photosByID[wire.photo.id] != nil {
            throw BayMapParseError.duplicatePhotoID
        }
        photosByID[wire.photo.id] = StoredPhoto(photo: wire.photo)
        var seenParts: Set<PartID> = []
        for region in wire.regions {
            if !seenParts.insert(region.partID).inserted {
                throw BayMapParseError.duplicateRegion
            }
            guard partsByID[region.partID] != nil else {
                throw BayMapParseError.unknownPart
            }
            let key = RegionKey(photoID: wire.photo.id, partID: region.partID)
            regionsByKey[key] = region.record
            referenced.insert(region.partID)
        }
    }
    if referenced != Set(partsByID.keys) {
        throw BayMapParseError.orphanPart
    }
    return Catalog(partsByID: partsByID, photosByID: photosByID, regionsByKey: regionsByKey)
}

private enum BayMapParseError: Error, CustomStringConvertible {
    case duplicatePartID
    case duplicateDisplayName
    case aliasCollision
    case duplicatePhotoID
    case duplicateRegion
    case unknownPart
    case orphanPart

    var description: String {
        switch self {
        case .duplicatePartID:
            return "duplicate part_id"
        case .duplicateDisplayName:
            return "duplicate display_name"
        case .aliasCollision:
            return "alias collides with a part id or display name"
        case .duplicatePhotoID:
            return "duplicate bay_photo_id"
        case .duplicateRegion:
            return "duplicate region for bay_photo_id and part_id"
        case .unknownPart:
            return "region part_id is not in parts"
        case .orphanPart:
            return "part has no region"
        }
    }
}
