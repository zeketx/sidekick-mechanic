/// A pointer at one confirmed bay-map region. JSON object keys are `bay_photo_id`, `part_id`.
public struct HighlightRef: Hashable, Sendable, Codable {
    public let bayPhotoID: BayPhotoID
    public let partID: PartID

    public init(bayPhotoID: BayPhotoID, partID: PartID) {
        self.bayPhotoID = bayPhotoID
        self.partID = partID
    }

    enum CodingKeys: String, CodingKey {
        case bayPhotoID = "bay_photo_id"
        case partID = "part_id"
    }
}
