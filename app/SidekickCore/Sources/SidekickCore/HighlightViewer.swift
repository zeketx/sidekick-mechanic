/// Launch keys for the full-bleed highlight card. Matches the Figma frame names.
public enum HighlightViewerScreen: String, Hashable, Sendable, CaseIterable {
    case confident = "highlight-confident"
    case unsure = "highlight-unsure"
    case notFound = "highlight-not-found"
    case reference = "highlight-reference"

    public var source: HighlightViewerState {
        switch self {
        case .confident: .confident
        case .unsure: .unsure
        case .notFound: .notFound
        case .reference: .reference
        }
    }
}

/// Shown card. Source data uses the same cases; resolve() may change unsure.
public enum HighlightViewerState: String, Hashable, Sendable, CaseIterable {
    case confident
    case unsure
    case notFound = "not_found"
    case reference

    /// Maps demo `display` / `demo_state` onto a source state. Not contract v2.
    public static func fromDemo(
        display: HighlightDisplay?,
        highlight: HighlightRef?,
        demoState: String? = nil
    ) -> HighlightViewerState {
        if let demoState, let parsed = fromDemoState(demoState) {
            return parsed
        }
        guard highlight != nil else { return .notFound }
        if display == nil { return .notFound }
        if display == .confirm { return .unsure }
        return .confident
    }

    public static func fromDemoState(_ raw: String) -> HighlightViewerState? {
        switch raw {
        case "outline", "confident":
            return .confident
        case "confirm", "unsure":
            return .unsure
        case "not_found":
            return .notFound
        case "reference":
            return .reference
        default:
            return nil
        }
    }
}

/// Contract v2 photo target (`user_photo` | `reference_photo`). View-model only.
public enum HighlightPhotoTarget: String, Hashable, Sendable {
    case userPhoto = "user_photo"
    case referencePhoto = "reference_photo"
}

/// Outline stroke. Never a bounding box.
public enum HighlightOutlineStroke: String, Hashable, Sendable {
    case solid
    case dashed
}

/// Copy and chrome for the v1 highlight card. Locked by tests.
public enum HighlightViewerCopy {
    public static let confidentTitle = "Your photo"
    public static let unsureTitle = "Unsure"
    public static let notFoundTitle = "Your photo"
    public static let referenceTitle = "Reference"

    public static let unsureBanner = "Internal only · flag off in v1"
    public static let referenceBanner = "Reference, not your truck."
    public static let userPhotoUntracedBanner = "No outline on your photo (not traced yet)"

    public static let caption = "Engine bay photo"
    public static let confidentFooter = "Confident outline · pinch to zoom"
    public static let unsurePrompt = "Is this it?"
    public static let notFoundFooter = "Not in this photo · open the diagram"
    public static let referenceFooter = "Reference outline · pinch to zoom"
    public static let pinchLabel = "pinch"

    public static let notInPhoto = "This part is not in this photo."
    public static let retakeHint =
        "Retake from a standard angle so this snap can match a traced view. Photo angles are TBD."
    public static let diagramChip = "FAKE-DOC-2JZ · p. 999"
}

/// Fixture citation and catalog-backed rings for the scripted card.
public enum HighlightViewerScript {
    public static let fixtureCitation: Citation = {
        let citation = Citation(
            docID: DocumentID(rawValue: "FAKE-DOC-2JZ")!,
            page: PageNumber(rawValue: 999)!,
            snippet: "FAKE-SNIPPET: no real spec. Value FAKE-SPEC."
        )
        guard let citation else {
            preconditionFailure("fixture citation is valid")
        }
        return citation
    }()

    public static func geometry(
        photoID: String,
        partID: String,
        showingOutline: Bool
    ) -> HighlightGeometry? {
        showingOutline ? DemoOutlineCatalog.geometry(photoID: photoID, partID: partID) : nil
    }
}

/// Resolved chrome for one highlight card. Drive this from scripted demo data.
public struct HighlightViewerPresentation: Equatable, Sendable {
    public var kind: HighlightViewerState
    public var target: HighlightPhotoTarget
    public var showsOutline: Bool
    public var outlineStroke: HighlightOutlineStroke
    public var title: String
    public var banner: String?
    public var userPhotoBanner: String?
    public var caption: String
    public var footer: String
    public var body: String
    public var showsDiagramLink: Bool
    public var showsRetakeHint: Bool
    public var showsConfirmPrompt: Bool
    public var retakeHint: String?
    public var diagramCitation: Citation
    public var photoID: String
    public var partID: String
    public var partDisplayName: String
    public var tags: [String]
    public var referencePhotoID: String?
    public var outlinePhotoID: String

    /// Outline belongs on the user snap, not the stand-in.
    public var showsOutlineOnUserPhoto: Bool {
        showsOutline && kind != .reference
    }

    /// Outline belongs on the traced stand-in only.
    public var showsOutlineOnReferencePhoto: Bool {
        showsOutline && kind == .reference
    }

    /// Unsure + flag off falls back to a labeled reference, or not-found if none.
    public static func resolve(
        source: HighlightViewerState,
        flags: FeatureFlags = .v1,
        hasReferencePhoto: Bool = true,
        photoID: String = DemoLaunchOptions.defaultPhotoID,
        partID: String? = nil
    ) -> HighlightViewerPresentation {
        let kind: HighlightViewerState
        switch source {
        case .confident:
            kind = .confident
        case .unsure:
            if flags.unsureHighlight {
                kind = .unsure
            } else if hasReferencePhoto {
                kind = .reference
            } else {
                kind = .notFound
            }
        case .notFound:
            kind = .notFound
        case .reference:
            kind = .reference
        }
        return make(kind, pick: DemoOutlineCatalog.selection(
            photoID: photoID,
            partID: partID,
            state: kind
        ))
    }

    public static func make(_ kind: HighlightViewerState) -> HighlightViewerPresentation {
        make(
            kind,
            pick: DemoOutlineCatalog.selection(
                photoID: DemoLaunchOptions.defaultPhotoID,
                state: kind
            )
        )
    }

    public static func make(
        _ kind: HighlightViewerState,
        pick: DemoOutlineSelection
    ) -> HighlightViewerPresentation {
        let outlinePhotoID = kind == .reference
            ? (pick.referencePhotoID ?? pick.photoID)
            : pick.photoID
        let outlinePick = kind == .reference && pick.referencePhotoID != nil
            ? DemoOutlineCatalog.selection(
                photoID: outlinePhotoID,
                partID: pick.partID,
                state: .reference
            )
            : pick
        switch kind {
        case .confident:
            return HighlightViewerPresentation(
                kind: .confident,
                target: .userPhoto,
                showsOutline: outlinePick.geometry != nil,
                outlineStroke: .solid,
                title: HighlightViewerCopy.confidentTitle,
                banner: nil,
                userPhotoBanner: nil,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.confidentFooter,
                body: DemoOutlineCatalog.everydayCopy(
                    displayName: outlinePick.displayName,
                    state: .confident
                ),
                showsDiagramLink: false,
                showsRetakeHint: false,
                showsConfirmPrompt: false,
                retakeHint: nil,
                diagramCitation: HighlightViewerScript.fixtureCitation,
                photoID: pick.photoID,
                partID: outlinePick.partID,
                partDisplayName: outlinePick.displayName,
                tags: outlinePick.tags,
                referencePhotoID: pick.referencePhotoID,
                outlinePhotoID: outlinePhotoID
            )
        case .unsure:
            return HighlightViewerPresentation(
                kind: .unsure,
                target: .userPhoto,
                showsOutline: outlinePick.geometry != nil,
                outlineStroke: .dashed,
                title: HighlightViewerCopy.unsureTitle,
                banner: HighlightViewerCopy.unsureBanner,
                userPhotoBanner: nil,
                caption: HighlightViewerCopy.caption,
                footer: "",
                body: DemoOutlineCatalog.everydayCopy(
                    displayName: outlinePick.displayName,
                    state: .unsure
                ),
                showsDiagramLink: false,
                showsRetakeHint: false,
                showsConfirmPrompt: true,
                retakeHint: nil,
                diagramCitation: HighlightViewerScript.fixtureCitation,
                photoID: pick.photoID,
                partID: outlinePick.partID,
                partDisplayName: outlinePick.displayName,
                tags: outlinePick.tags,
                referencePhotoID: pick.referencePhotoID,
                outlinePhotoID: outlinePhotoID
            )
        case .notFound:
            return HighlightViewerPresentation(
                kind: .notFound,
                target: .userPhoto,
                showsOutline: false,
                outlineStroke: .solid,
                title: HighlightViewerCopy.notFoundTitle,
                banner: nil,
                userPhotoBanner: nil,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.notFoundFooter,
                body: DemoOutlineCatalog.everydayCopy(
                    displayName: pick.displayName,
                    state: .notFound
                ),
                showsDiagramLink: true,
                showsRetakeHint: false,
                showsConfirmPrompt: false,
                retakeHint: nil,
                diagramCitation: HighlightViewerScript.fixtureCitation,
                photoID: pick.photoID,
                partID: pick.partID,
                partDisplayName: pick.displayName,
                tags: pick.tags,
                referencePhotoID: pick.referencePhotoID,
                outlinePhotoID: pick.photoID
            )
        case .reference:
            return HighlightViewerPresentation(
                kind: .reference,
                target: .referencePhoto,
                showsOutline: outlinePick.geometry != nil,
                outlineStroke: .solid,
                title: HighlightViewerCopy.referenceTitle,
                banner: HighlightViewerCopy.referenceBanner,
                userPhotoBanner: HighlightViewerCopy.userPhotoUntracedBanner,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.referenceFooter,
                body: DemoOutlineCatalog.everydayCopy(
                    displayName: outlinePick.displayName,
                    state: .reference
                ),
                showsDiagramLink: true,
                showsRetakeHint: true,
                showsConfirmPrompt: false,
                retakeHint: HighlightViewerCopy.retakeHint,
                diagramCitation: HighlightViewerScript.fixtureCitation,
                photoID: pick.photoID,
                partID: outlinePick.partID,
                partDisplayName: outlinePick.displayName,
                tags: outlinePick.tags,
                referencePhotoID: pick.referencePhotoID,
                outlinePhotoID: outlinePhotoID
            )
        }
    }
}
