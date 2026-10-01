/// Non-empty document ID from `docs/MANUALS.md`. JSON key: `doc_id`.
public struct DocumentID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// Manual page number. Must be 1 or greater so a citation cannot omit a page.
public struct PageNumber: Hashable, Sendable, RawRepresentable {
    public let rawValue: Int

    public init?(rawValue: Int) {
        guard rawValue >= 1 else { return nil }
        self.rawValue = rawValue
    }
}

/// Bay-map photo ID. JSON key: `bay_photo_id`.
public struct BayPhotoID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// Bay-map part ID. JSON key: `part_id`.
public struct PartID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// Bay-map camera angle ID. JSON key: `angle_id`.
public struct BayAngleID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// Who confirmed a region. JSON key: `confirmed_by`.
public struct ConfirmerID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// Stable conversation identity for chat storage and `/chat` requests.
public struct ConversationID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// Stable message identity for SwiftUI lists.
public struct MessageID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

extension DocumentID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "doc_id")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PageNumber: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard let page = PageNumber(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "page must be >= 1, got \(value)"
            )
        }
        self = page
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension BayPhotoID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "bay_photo_id")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PartID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "part_id")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension BayAngleID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "angle_id")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ConfirmerID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "confirmed_by")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ConversationID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "id")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension MessageID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decodeNonEmptyString(from: decoder, label: "id")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

func decodeNonEmptyString(from decoder: Decoder, label: String) throws -> String {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard !value.isEmpty else {
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "\(label) must be non-empty"
        )
    }
    return value
}
