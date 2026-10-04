import Foundation

/// Client-side highlight style picker for demo mode. Matches `HighlightStyle` in `backend/highlight.py`.
public enum DemoHighlightStyle: String, CaseIterable, Hashable, Sendable {
    case outline
    case saturate
    case circle
    case dim

    public var pickerLabel: String {
        switch self {
        case .outline: "Outline"
        case .saturate: "Saturate"
        case .circle: "Circle"
        case .dim: "Dim the rest"
        }
    }
}

/// Local Yes / Not this on a `display: confirm` highlight.
public enum DemoConfirmDecision: String, Hashable, Sendable, Codable {
    case yes
    case notThis = "not_this"
}

/// `GET /demo/photos` payload. Scripted demo data, not Zeke's truck.
public struct DemoCatalog: Hashable, Sendable, Codable {
    public let demo: Bool
    public let label: String
    public let attributionURL: String
    public let photos: [DemoPhotoInfo]

    enum CodingKeys: String, CodingKey {
        case demo
        case label
        case attributionURL = "attribution_url"
        case photos
    }
}

public struct DemoPhotoInfo: Hashable, Sendable, Codable, Identifiable {
    public var id: String { photoID }
    public let photoID: String
    public let imageURL: String
    public let attribution: String
    public let author: String
    public let license: String
    public let licenseURL: String
    public let sourcePageURL: String
    public let engineAsStated: String
    public let shareAlike: Bool
    public let width: Int
    public let height: Int
    public let parts: [DemoPartInfo]

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case imageURL = "image_url"
        case attribution
        case author
        case license
        case licenseURL = "license_url"
        case sourcePageURL = "source_page_url"
        case engineAsStated = "engine_as_stated"
        case shareAlike = "share_alike"
        case width
        case height
        case parts
    }
}

public struct DemoPartInfo: Hashable, Sendable, Codable {
    public let partID: String
    public let displayName: String
    public let demoState: String

    enum CodingKeys: String, CodingKey {
        case partID = "part_id"
        case displayName = "display_name"
        case demoState = "demo_state"
    }
}

public struct DemoFeedbackBody: Hashable, Sendable, Encodable {
    public let photoID: String
    public let partID: String
    public let action: DemoConfirmDecision

    public init(photoID: String, partID: String, action: DemoConfirmDecision) {
        self.photoID = photoID
        self.partID = partID
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case photoID = "photo_id"
        case partID = "part_id"
        case action
    }
}

extension ChatClientConfiguration {
    public var demoPhotosURL: URL {
        baseURL.appendingPathComponent("demo/photos")
    }

    public var demoAttributionURL: URL {
        baseURL.appendingPathComponent("demo/attribution")
    }

    public var demoFeedbackURL: URL {
        baseURL.appendingPathComponent("demo/feedback")
    }

    public func demoImageURL(photoID: String) -> URL {
        baseURL
            .appendingPathComponent("demo")
            .appendingPathComponent("photos")
            .appendingPathComponent(photoID)
            .appendingPathComponent("image")
    }
}
