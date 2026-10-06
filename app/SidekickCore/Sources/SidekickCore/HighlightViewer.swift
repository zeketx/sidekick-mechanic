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
    public static let notFoundTitle = "Not found"
    public static let referenceTitle = "Reference"

    public static let unsureBanner = "Internal only · flag off in v1"
    public static let referenceBanner = "Reference, not your truck."

    public static let caption = "Engine bay photo"
    public static let confidentFooter = "Confident outline · pinch to zoom"
    public static let unsurePrompt = "Is this it?"
    public static let notFoundFooter = "Not in this photo · open the diagram"
    public static let referenceFooter = "Reference outline · pinch to zoom"

    public static let everydayConfident = "Start with the air box on top of the engine."
    public static let notInPhoto = "This part is not in this photo."
    public static let retakeHint =
        "Retake from a standard angle so this snap can match a traced view. Photo angles are TBD."
    public static let diagramChip = "FAKE-DOC-2JZ · p. 999"
}

/// Scripted demo highlight. Polygon follows a part shape, not a box.
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

    /// Irregular air-box ring in normalized photo space. Not a rectangle.
    public static let airBoxGeometry = HighlightGeometry(
        polygons: [
            HighlightPolygon(
                points: [
                    HighlightPoint(x: 0.30, y: 0.40),
                    HighlightPoint(x: 0.48, y: 0.36),
                    HighlightPoint(x: 0.70, y: 0.38),
                    HighlightPoint(x: 0.74, y: 0.50),
                    HighlightPoint(x: 0.66, y: 0.58),
                    HighlightPoint(x: 0.38, y: 0.56),
                    HighlightPoint(x: 0.28, y: 0.48),
                ]
            ),
        ]
    )

    public static func geometry(showingOutline: Bool) -> HighlightGeometry? {
        showingOutline ? airBoxGeometry : nil
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
    public var caption: String
    public var footer: String
    public var body: String
    public var showsDiagramLink: Bool
    public var showsRetakeHint: Bool
    public var showsConfirmPrompt: Bool
    public var retakeHint: String?
    public var diagramCitation: Citation

    /// Unsure + flag off falls back to a labeled reference, or not-found if none.
    public static func resolve(
        source: HighlightViewerState,
        flags: FeatureFlags = .v1,
        hasReferencePhoto: Bool = true
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
        return make(kind)
    }

    public static func make(_ kind: HighlightViewerState) -> HighlightViewerPresentation {
        switch kind {
        case .confident:
            return HighlightViewerPresentation(
                kind: .confident,
                target: .userPhoto,
                showsOutline: true,
                outlineStroke: .solid,
                title: HighlightViewerCopy.confidentTitle,
                banner: nil,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.confidentFooter,
                body: HighlightViewerCopy.everydayConfident,
                showsDiagramLink: false,
                showsRetakeHint: false,
                showsConfirmPrompt: false,
                retakeHint: nil,
                diagramCitation: HighlightViewerScript.fixtureCitation
            )
        case .unsure:
            return HighlightViewerPresentation(
                kind: .unsure,
                target: .userPhoto,
                showsOutline: true,
                outlineStroke: .dashed,
                title: HighlightViewerCopy.unsureTitle,
                banner: HighlightViewerCopy.unsureBanner,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.unsurePrompt,
                body: HighlightViewerCopy.everydayConfident,
                showsDiagramLink: false,
                showsRetakeHint: false,
                showsConfirmPrompt: true,
                retakeHint: nil,
                diagramCitation: HighlightViewerScript.fixtureCitation
            )
        case .notFound:
            return HighlightViewerPresentation(
                kind: .notFound,
                target: .userPhoto,
                showsOutline: false,
                outlineStroke: .solid,
                title: HighlightViewerCopy.notFoundTitle,
                banner: nil,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.notFoundFooter,
                body: HighlightViewerCopy.notInPhoto,
                showsDiagramLink: true,
                showsRetakeHint: false,
                showsConfirmPrompt: false,
                retakeHint: nil,
                diagramCitation: HighlightViewerScript.fixtureCitation
            )
        case .reference:
            return HighlightViewerPresentation(
                kind: .reference,
                target: .referencePhoto,
                showsOutline: true,
                outlineStroke: .solid,
                title: HighlightViewerCopy.referenceTitle,
                banner: HighlightViewerCopy.referenceBanner,
                caption: HighlightViewerCopy.caption,
                footer: HighlightViewerCopy.referenceFooter,
                body: HighlightViewerCopy.everydayConfident,
                showsDiagramLink: true,
                showsRetakeHint: true,
                showsConfirmPrompt: false,
                retakeHint: HighlightViewerCopy.retakeHint,
                diagramCitation: HighlightViewerScript.fixtureCitation
            )
        }
    }
}
