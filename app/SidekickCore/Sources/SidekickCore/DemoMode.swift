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
    public let defaultPhotoID: String?
    public let photos: [DemoPhotoInfo]

    enum CodingKeys: String, CodingKey {
        case demo
        case label
        case attributionURL = "attribution_url"
        case defaultPhotoID = "default_photo_id"
        case photos
    }
}

public struct DemoPhotoInfo: Hashable, Sendable, Codable, Identifiable {
    public var id: String { photoID }
    public let photoID: String
    public let shortName: String?
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
        case shortName = "short_name"
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

    public var thumbnailLabel: String {
        if let shortName, !shortName.isEmpty { return shortName }
        return DemoLaunchOptions.shortName(for: photoID)
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

/// Launch arguments and env hooks for screenshot runs. No typing required.
///
/// `-demoPhoto <id> -demoPart <part_id> -demoState outline|confirm|not_found|reference -demoStyle outline|saturate|circle|dim`
/// `-screen highlight-confident|highlight-unsure|highlight-not-found|highlight-reference`
/// `-screen job-sheet-collapsed|job-sheet-half|job-sheet-full|job-sheet-closeout`
/// `-screen job-history|scan-log`
/// `-showDemoChrome 1` shows the Demo mode toggle, demo banner, and Chat/Readings tabs.
/// `-flagUnsureHighlight 1` turns on the internal unsure card. Off by default.
/// Env: `SIDEKICK_DEMO_PHOTO`, `SIDEKICK_DEMO_PART`, `SIDEKICK_DEMO_STATE`, `SIDEKICK_DEMO_STYLE`,
/// `SIDEKICK_SCREEN`, `SIDEKICK_SHOW_DEMO_CHROME`, `SIDEKICK_FLAG_UNSURE_HIGHLIGHT`.
public struct DemoLaunchOptions: Equatable, Sendable {
    public static let defaultPhotoID = "commons-hilux-2jz"

    public var photoID: String?
    public var partID: String?
    public var state: String?
    public var style: DemoHighlightStyle?
    public var screen: HighlightViewerScreen?
    public var jobSheetScreen: JobSheetScreen?
    public var lookBackScreen: LookBackScreen?
    public var showDemoChrome: Bool
    public var unsureHighlight: Bool

    public var enablesDemoMode: Bool {
        photoID != nil
            || partID != nil
            || state != nil
            || style != nil
            || screen != nil
            || jobSheetScreen != nil
            || lookBackScreen != nil
    }

    public var featureFlags: FeatureFlags {
        FeatureFlags(unsureHighlight: unsureHighlight)
    }

    public var opensHighlightViewer: Bool {
        screen != nil
    }

    public var opensJobSheet: Bool {
        jobSheetScreen != nil
    }

    public var opensLookBack: Bool {
        lookBackScreen != nil
    }

    public var resolvedPhotoID: String {
        photoID ?? Self.defaultPhotoID
    }

    public var cannedQuestion: String {
        if lookBackScreen != nil {
            return ""
        }
        if jobSheetScreen != nil {
            return JobSheetCopy.question
        }
        if let screen {
            switch screen {
            case .confident:
                return Self.question(partID: partID, state: "outline", photoID: resolvedPhotoID)
            case .unsure:
                return Self.question(partID: partID, state: "confirm", photoID: resolvedPhotoID)
            case .notFound:
                return Self.question(partID: partID, state: "not_found", photoID: resolvedPhotoID)
            case .reference:
                return Self.question(partID: partID, state: "reference", photoID: resolvedPhotoID)
            }
        }
        return Self.question(partID: partID, state: state, photoID: resolvedPhotoID)
    }

    public init(
        photoID: String? = nil,
        partID: String? = nil,
        state: String? = nil,
        style: DemoHighlightStyle? = nil,
        screen: HighlightViewerScreen? = nil,
        jobSheetScreen: JobSheetScreen? = nil,
        lookBackScreen: LookBackScreen? = nil,
        showDemoChrome: Bool = false,
        unsureHighlight: Bool = false
    ) {
        self.photoID = photoID.map(Self.resolvePhotoID)
        self.partID = partID
        self.state = state
        self.style = style
        self.screen = screen
        self.jobSheetScreen = jobSheetScreen
        self.lookBackScreen = lookBackScreen
        self.showDemoChrome = showDemoChrome
        self.unsureHighlight = unsureHighlight || screen == .unsure
    }

    public static func parse(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DemoLaunchOptions {
        let rawScreen = LaunchArgument.flag(arguments, "-screen")
            ?? environment["SIDEKICK_SCREEN"]
            ?? ""
        return DemoLaunchOptions(
            photoID: LaunchArgument.flag(arguments, "-demoPhoto") ?? environment["SIDEKICK_DEMO_PHOTO"],
            partID: LaunchArgument.flag(arguments, "-demoPart") ?? environment["SIDEKICK_DEMO_PART"],
            state: LaunchArgument.flag(arguments, "-demoState") ?? environment["SIDEKICK_DEMO_STATE"],
            style: DemoHighlightStyle(
                rawValue: LaunchArgument.flag(arguments, "-demoStyle")
                    ?? environment["SIDEKICK_DEMO_STYLE"]
                    ?? ""
            ),
            screen: HighlightViewerScreen(rawValue: rawScreen),
            jobSheetScreen: JobSheetScreen(rawValue: rawScreen),
            lookBackScreen: LookBackScreen(rawValue: rawScreen),
            showDemoChrome: FeatureFlags.isEnabled(
                LaunchArgument.flag(arguments, "-showDemoChrome")
                    ?? environment["SIDEKICK_SHOW_DEMO_CHROME"]
            ),
            unsureHighlight: FeatureFlags.parse(arguments: arguments, environment: environment)
                .unsureHighlight
        )
    }

    public static func shortName(for photoID: String) -> String {
        switch resolvePhotoID(photoID) {
        case "hrymx-2jz-ge-25308847029": "2JZ-GE prototype"
        case "commons-hilux-2jz": "Hilux"
        case "commons-supra-n5abh": "Supra (2JZ-GTE)"
        case "flickr-robmarson-6763892857": "2JZ bay"
        default: photoID
        }
    }

    public static func question(partID: String?, state: String?, photoID: String) -> String {
        if let partID {
            return question(forPart: partID)
        }
        switch state {
        case "confirm", "unsure":
            return "where's the intake plenum?"
        case "not_found":
            return "where are the coil packs?"
        case "reference":
            return "where's the fuse box?"
        default:
            return photoID == defaultPhotoID || photoID == "commons-hilux-2jz"
                ? "where's the fuse box?"
                : "where's the throttle body?"
        }
    }

    public static func question(forPart partID: String) -> String {
        switch partID {
        case "throttle-body": "where's the throttle body?"
        case "intake-plenum": "where's the intake plenum?"
        case "coil-packs": "where are the coil packs?"
        case "fuse-relay-box": "where's the fuse box?"
        case "radiator-cap-upper-hose": "where's the radiator cap?"
        case "battery-terminals": "where are the battery terminals?"
        default: "where's the \(partID.replacingOccurrences(of: "-", with: " "))?"
        }
    }

    public static func resolvePhotoID(_ raw: String) -> String {
        switch raw {
        case "hilux": "commons-hilux-2jz"
        case "supra": "commons-supra-n5abh"
        case "prototype", "hrymx": "hrymx-2jz-ge-25308847029"
        case "flickr": "flickr-robmarson-6763892857"
        default: raw
        }
    }
}
