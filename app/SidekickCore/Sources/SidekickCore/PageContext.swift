import Foundation

/// The owner's photo of a plug. Downscaled and re-encoded on the phone. Bytes are never printed.
public struct PlugPhoto: Hashable, Sendable, CustomStringConvertible {
    public static let maxBytes = 1_500_000

    public let jpegData: Data

    /// Nil unless the bytes start with the JPEG start marker, end with the end marker, and fit `maxBytes`.
    public init?(jpegData: Data) {
        guard jpegData.count <= Self.maxBytes,
              jpegData.starts(with: [0xFF, 0xD8, 0xFF]),
              jpegData.suffix(2).elementsEqual([0xFF, 0xD9])
        else { return nil }
        self.jpegData = jpegData
    }

    public var description: String { "PlugPhoto(\(jpegData.count) bytes)" }
}

/// What a user turn is about. A plug photo always belongs to a page.
public enum TurnAttachment: Hashable, Sendable {
    case page(PageRef)
    case plugPhoto(PlugPhoto, page: PageRef)

    public var page: PageRef {
        switch self {
        case let .page(page), let .plugPhoto(_, page):
            page
        }
    }

    public var plugPhoto: PlugPhoto? {
        if case let .plugPhoto(photo, _) = self { return photo }
        return nil
    }
}

/// The three questions offered under a pinned page. The raw value is the text that is sent.
public enum StarterQuestion: String, CaseIterable, Identifiable, Sendable {
    case explainSimply = "Explain this page simply"
    case tools = "What tools do I need?"
    case whichConnector = "Which connector is this?"

    public var id: String { rawValue }
    public var text: String { rawValue }

    /// The connector question compares a photo of the owner's plug with the page.
    public var wantsPlugPhoto: Bool { self == .whichConnector }
}
