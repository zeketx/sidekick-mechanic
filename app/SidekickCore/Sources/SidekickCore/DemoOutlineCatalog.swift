import Foundation

/// One scripted part from `demo_bay_photos.json` (#92 / #93, spike #85 masks).
public struct DemoOutlinePart: Equatable, Sendable {
    public var partID: String
    public var displayName: String
    public var demoState: String
    public var geometry: HighlightGeometry?

    public var hasOutline: Bool {
        guard let geometry else { return false }
        return geometry.polygons.contains { $0.points.count >= 3 }
    }
}

/// One demo bay photo and the parts that have (or lack) a traced ring.
public struct DemoOutlinePhoto: Equatable, Sendable {
    public var photoID: String
    public var width: Int
    public var height: Int
    public var parts: [DemoOutlinePart]

    public func part(id partID: String) -> DemoOutlinePart? {
        parts.first { $0.partID == partID }
    }
}

/// Picked photo + part for a highlight card. Copy and rings stay in lockstep.
public struct DemoOutlineSelection: Equatable, Sendable {
    public var photoID: String
    public var partID: String
    public var displayName: String
    public var geometry: HighlightGeometry?
    public var tags: [String]
    public var referencePhotoID: String?
    public var imageWidth: Int
    public var imageHeight: Int
}

/// Per-photo, per-part polygons from the #92/#93 demo catalog.
public enum DemoOutlineCatalog {
    public static func photo(id photoID: String) -> DemoOutlinePhoto? {
        let resolved = DemoLaunchOptions.resolvePhotoID(photoID)
        return load().first { $0.photoID == resolved }
    }

    public static func part(photoID: String, partID: String) -> DemoOutlinePart? {
        photo(id: photoID)?.part(id: partID)
    }

    public static func geometry(photoID: String, partID: String) -> HighlightGeometry? {
        part(photoID: photoID, partID: partID)?.geometry.flatMap(HighlightOutlineCleanup.cleaned)
    }

    /// Featured part for a card. Honors an explicit `partID` when that part exists.
    public static func selection(
        photoID: String,
        partID: String? = nil,
        state: HighlightViewerState
    ) -> DemoOutlineSelection {
        let resolvedPhoto = DemoLaunchOptions.resolvePhotoID(photoID)
        let photo = self.photo(id: resolvedPhoto)
        let picked = pickPart(on: photo, requested: partID, state: state)
        let geometry = picked?.geometry.flatMap(HighlightOutlineCleanup.cleaned)
        let displayName = nameMatching(partID: picked?.partID ?? partID, catalogName: picked?.displayName, geometry: geometry)
        let resolvedPartID = picked?.partID ?? partID ?? fallbackPartID(for: resolvedPhoto, state: state)
        return DemoOutlineSelection(
            photoID: resolvedPhoto,
            partID: resolvedPartID,
            displayName: displayName,
            geometry: geometry,
            tags: tags(partID: resolvedPartID, hasOutline: geometry != nil),
            referencePhotoID: standInPhotoID(for: resolvedPhoto, partID: resolvedPartID),
            imageWidth: photo?.width ?? 1,
            imageHeight: photo?.height ?? 1
        )
    }

    public static func everydayCopy(displayName: String, state: HighlightViewerState) -> String {
        switch state {
        case .confident:
            return "Start with the \(displayName)."
        case .unsure:
            return "The \(displayName) on this demo photo."
        case .notFound:
            return "The \(displayName) — not visible in this photo."
        case .reference:
            return "The \(displayName) on a traced stand-in."
        }
    }

    public static func shortTag(partID: String) -> String {
        switch partID {
        case "fuse-relay-box": "fuse/relay"
        case "intake-plenum": "intake"
        case "throttle-body": "throttle"
        case "radiator-cap-upper-hose": "radiator"
        case "coil-packs": "coils"
        case "battery-terminals": "battery"
        default: partID.replacingOccurrences(of: "-", with: " ")
        }
    }

    public static func tags(partID: String, hasOutline: Bool) -> [String] {
        if hasOutline {
            return [shortTag(partID: partID), "inspected"]
        }
        return [shortTag(partID: partID)]
    }

    static func nameMatching(partID: String?, catalogName: String?, geometry: HighlightGeometry?) -> String {
        if partID == "radiator-cap-upper-hose" {
            let rings = geometry?.polygons.count ?? 0
            return rings >= 2 ? "radiator cap + upper hose" : "radiator cap"
        }
        if let catalogName, !catalogName.isEmpty {
            return catalogName
        }
        return fallbackName(partID)
    }

    /// Another catalog photo that already has rings for this part.
    public static func standInPhotoID(for photoID: String, partID: String) -> String? {
        let resolved = DemoLaunchOptions.resolvePhotoID(photoID)
        return load().first { photo in
            photo.photoID != resolved && photo.part(id: partID)?.hasOutline == true
        }?.photoID
    }

    private static func pickPart(
        on photo: DemoOutlinePhoto?,
        requested: String?,
        state: HighlightViewerState
    ) -> DemoOutlinePart? {
        guard let photo else { return nil }
        if let requested, let match = photo.part(id: requested) {
            switch state {
            case .notFound:
                return match
            case .confident, .unsure, .reference:
                if match.hasOutline { return match }
            }
        }
        switch state {
        case .confident, .reference:
            return photo.parts.first { $0.demoState == "outline" && $0.hasOutline }
                ?? photo.parts.first { $0.hasOutline }
        case .unsure:
            return photo.parts.first { $0.demoState == "confirm" && $0.hasOutline }
                ?? photo.parts.first { $0.hasOutline }
        case .notFound:
            return photo.parts.first { $0.demoState == "not_found" }
                ?? photo.parts.first { !$0.hasOutline }
        }
    }

    private static func fallbackPartID(for photoID: String, state: HighlightViewerState) -> String {
        switch state {
        case .notFound:
            return photoID == "flickr-robmarson-6763892857" ? "battery-terminals" : "coil-packs"
        case .unsure:
            return photoID == "commons-hilux-2jz" || photoID == "commons-supra-n5abh"
                ? "radiator-cap-upper-hose"
                : "intake-plenum"
        case .confident, .reference:
            return photoID == "commons-hilux-2jz" || photoID == "commons-supra-n5abh"
                ? "fuse-relay-box"
                : "throttle-body"
        }
    }

    private static func fallbackName(_ partID: String?) -> String {
        switch partID {
        case "fuse-relay-box":
            return "fuse/relay box"
        case "intake-plenum":
            return "intake plenum"
        case "throttle-body":
            return "throttle body"
        case "radiator-cap-upper-hose":
            return "radiator cap + upper hose"
        case "coil-packs":
            return "coil packs"
        case "battery-terminals":
            return "battery terminals"
        case .some(let value):
            return value.replacingOccurrences(of: "-", with: " ")
        case nil:
            return "that part"
        }
    }

    private static let photos: [DemoOutlinePhoto] = decodeBundled()

    static func load() -> [DemoOutlinePhoto] {
        photos
    }

    private static func decodeBundled() -> [DemoOutlinePhoto] {
        guard let url = Bundle.module.url(forResource: "demo_bay_photos", withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.photos.map { photo in
            DemoOutlinePhoto(
                photoID: photo.photoID,
                width: photo.width,
                height: photo.height,
                parts: photo.parts.map { part in
                    let rings = (part.polygons ?? []).compactMap { ring -> HighlightPolygon? in
                        guard ring.points.count >= 3 else { return nil }
                        return HighlightPolygon(points: ring.points)
                    }
                    return DemoOutlinePart(
                        partID: part.partID,
                        displayName: part.displayName,
                        demoState: part.demoState,
                        geometry: rings.isEmpty ? nil : HighlightGeometry(polygons: rings)
                    )
                }
            )
        }
    }

    private struct File: Decodable {
        var photos: [Photo]

        struct Photo: Decodable {
            var photoID: String
            var width: Int
            var height: Int
            var parts: [Part]

            enum CodingKeys: String, CodingKey {
                case photoID = "photo_id"
                case width
                case height
                case parts
            }
        }

        struct Part: Decodable {
            var partID: String
            var displayName: String
            var demoState: String
            var polygons: [HighlightPolygon]?

            enum CodingKeys: String, CodingKey {
                case partID = "part_id"
                case displayName = "display_name"
                case demoState = "demo_state"
                case polygons
            }
        }
    }
}
