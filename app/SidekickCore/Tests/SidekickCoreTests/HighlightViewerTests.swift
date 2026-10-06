import XCTest
@testable import SidekickCore

final class HighlightViewerTests: XCTestCase {
    func testUnsureFlagDefaultsOff() {
        let flags = FeatureFlags.parse(arguments: ["SidekickMechanic"], environment: [:])
        XCTAssertFalse(flags.unsureHighlight)
        XCTAssertFalse(FeatureFlags.v1.unsureHighlight)
    }

    func testUnsureFlagParsesLaunchArgumentAndEnv() {
        let fromArg = FeatureFlags.parse(
            arguments: ["SidekickMechanic", "-flagUnsureHighlight", "1"],
            environment: [:]
        )
        XCTAssertTrue(fromArg.unsureHighlight)

        let fromEnv = FeatureFlags.parse(
            arguments: ["SidekickMechanic"],
            environment: ["SIDEKICK_FLAG_UNSURE_HIGHLIGHT": "true"]
        )
        XCTAssertTrue(fromEnv.unsureHighlight)

        let ignored = FeatureFlags.parse(
            arguments: ["SidekickMechanic", "-flagUnsureHighlight", "0"],
            environment: [:]
        )
        XCTAssertFalse(ignored.unsureHighlight)
    }

    func testConfidentUsesUserPhotoAndSolidOutline() {
        let shown = HighlightViewerPresentation.resolve(source: .confident)
        XCTAssertEqual(shown.kind, .confident)
        XCTAssertEqual(shown.target, .userPhoto)
        XCTAssertTrue(shown.showsOutline)
        XCTAssertTrue(shown.showsOutlineOnUserPhoto)
        XCTAssertFalse(shown.showsOutlineOnReferencePhoto)
        XCTAssertEqual(shown.outlineStroke, .solid)
        XCTAssertFalse(shown.showsConfirmPrompt)
        XCTAssertFalse(shown.showsDiagramLink)
        XCTAssertEqual(shown.title, "Your photo")
        XCTAssertEqual(shown.footer, "Confident outline · pinch to zoom")
        XCTAssertEqual(shown.photoID, "commons-hilux-2jz")
        XCTAssertEqual(shown.partID, "fuse-relay-box")
        XCTAssertEqual(shown.body, "Start with the fuse/relay box.")
        XCTAssertEqual(shown.tags, ["fuse/relay", "inspected"])
        XCTAssertNil(shown.banner)
    }

    func testUnsureWithFlagOnShowsDashedConfirm() {
        let shown = HighlightViewerPresentation.resolve(
            source: .unsure,
            flags: FeatureFlags(unsureHighlight: true)
        )
        XCTAssertEqual(shown.kind, .unsure)
        XCTAssertEqual(shown.target, .userPhoto)
        XCTAssertTrue(shown.showsOutline)
        XCTAssertEqual(shown.outlineStroke, .dashed)
        XCTAssertTrue(shown.showsConfirmPrompt)
        XCTAssertEqual(shown.banner, "Internal only · flag off in v1")
        XCTAssertEqual(shown.footer, "")
        XCTAssertEqual(shown.partID, "radiator-cap-upper-hose")
        XCTAssertEqual(shown.body, "The radiator cap on this demo photo.")
        XCTAssertFalse(shown.body.contains("upper hose"))
        XCTAssertEqual(HighlightViewerCopy.unsurePrompt, "Is this it?")
    }

    func testUnsureWithFlagOffFallsBackToReference() {
        let shown = HighlightViewerPresentation.resolve(
            source: .unsure,
            flags: .v1,
            hasReferencePhoto: true
        )
        XCTAssertEqual(shown.kind, .reference)
        XCTAssertEqual(shown.target, .referencePhoto)
        XCTAssertTrue(shown.showsOutline)
        XCTAssertTrue(shown.showsOutlineOnReferencePhoto)
        XCTAssertFalse(shown.showsOutlineOnUserPhoto)
        XCTAssertFalse(shown.showsConfirmPrompt)
        XCTAssertEqual(shown.banner, "Reference, not your truck.")
        XCTAssertEqual(shown.userPhotoBanner, "No outline on your photo (not traced yet)")
    }

    func testUnsureWithFlagOffAndNoReferenceFallsBackToNotFound() {
        let shown = HighlightViewerPresentation.resolve(
            source: .unsure,
            flags: .v1,
            hasReferencePhoto: false
        )
        XCTAssertEqual(shown.kind, .notFound)
        XCTAssertFalse(shown.showsOutline)
        XCTAssertFalse(shown.showsConfirmPrompt)
        XCTAssertEqual(shown.title, "Your photo")
        XCTAssertTrue(shown.body.contains("not visible in this photo"))
    }

    func testNotFoundHasNoOutlineAndPointsAtFixtureDiagram() {
        let shown = HighlightViewerPresentation.resolve(source: .notFound)
        XCTAssertEqual(shown.kind, .notFound)
        XCTAssertEqual(shown.target, .userPhoto)
        XCTAssertFalse(shown.showsOutline)
        XCTAssertTrue(shown.showsDiagramLink)
        XCTAssertEqual(shown.title, "Your photo")
        XCTAssertEqual(shown.partID, "coil-packs")
        XCTAssertEqual(shown.body, "The coil packs — not visible in this photo.")
        XCTAssertEqual(shown.diagramCitation.docID.rawValue, "FAKE-DOC-2JZ")
        XCTAssertEqual(shown.diagramCitation.page.rawValue, 999)
        XCTAssertEqual(shown.footer, "Not in this photo · open the diagram")
        XCTAssertEqual(HighlightViewerCopy.diagramChip, "FAKE-DOC-2JZ · p. 999")
    }

    func testReferenceLabelsStandInPhotoAndKeepsAnglesTBD() {
        let shown = HighlightViewerPresentation.resolve(source: .reference)
        XCTAssertEqual(shown.kind, .reference)
        XCTAssertEqual(shown.target, .referencePhoto)
        XCTAssertTrue(shown.showsOutline)
        XCTAssertEqual(shown.outlineStroke, .solid)
        XCTAssertTrue(shown.showsDiagramLink)
        XCTAssertTrue(shown.showsRetakeHint)
        XCTAssertEqual(shown.banner, "Reference, not your truck.")
        XCTAssertEqual(shown.userPhotoBanner, "No outline on your photo (not traced yet)")
        XCTAssertFalse(shown.showsOutlineOnUserPhoto)
        XCTAssertTrue(shown.showsOutlineOnReferencePhoto)
        XCTAssertEqual(
            shown.retakeHint,
            "Retake from a standard angle so this snap can match a traced view. Photo angles are TBD."
        )
        XCTAssertTrue(shown.retakeHint?.contains("TBD") == true)
    }

    func testPerPhotoPolygonLookupMatchesDemoCatalog() throws {
        let hiluxFuse = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "hilux", partID: "fuse-relay-box")
        )
        let supraFuse = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "supra", partID: "fuse-relay-box")
        )
        let hrymxThrottle = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "hrymx", partID: "throttle-body")
        )
        let flickrThrottle = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "flickr", partID: "throttle-body")
        )

        XCTAssertEqual(hiluxFuse.polygons.count, 1)
        XCTAssertGreaterThanOrEqual(hiluxFuse.polygons[0].points.count, 5)
        XCTAssertLessThan(hiluxFuse.polygons[0].points.map(\.x).min() ?? 1, 0.2)

        XCTAssertEqual(supraFuse.polygons.count, 1)
        XCTAssertGreaterThanOrEqual(supraFuse.polygons[0].points.count, 5)
        XCTAssertGreaterThan(supraFuse.polygons[0].points.map(\.x).min() ?? 0, 0.7)
        XCTAssertNotEqual(hiluxFuse, supraFuse)

        XCTAssertGreaterThanOrEqual(hrymxThrottle.polygons[0].points.count, 5)
        XCTAssertLessThan(hrymxThrottle.polygons[0].points.map(\.x).max() ?? 1, 0.99)
        XCTAssertGreaterThanOrEqual(flickrThrottle.polygons[0].points.count, 5)
        XCTAssertNotEqual(hrymxThrottle, flickrThrottle)

        XCTAssertNil(DemoOutlineCatalog.geometry(photoID: "hilux", partID: "coil-packs"))
        XCTAssertEqual(
            DemoOutlineCatalog.geometry(photoID: "supra", partID: "radiator-cap-upper-hose")?
                .polygons.count,
            2
        )
    }

    func testFeaturedPartFollowsPhotoAndNamedCopy() {
        let hilux = DemoOutlineCatalog.selection(photoID: "hilux", state: .confident)
        XCTAssertEqual(hilux.partID, "fuse-relay-box")
        XCTAssertEqual(hilux.displayName, "fuse/relay box")

        let supra = DemoOutlineCatalog.selection(photoID: "supra", state: .confident)
        XCTAssertEqual(supra.partID, "fuse-relay-box")

        let hrymx = DemoOutlineCatalog.selection(photoID: "hrymx", state: .confident)
        XCTAssertEqual(hrymx.partID, "throttle-body")

        let flickr = DemoOutlineCatalog.selection(photoID: "flickr", state: .confident)
        XCTAssertEqual(flickr.partID, "throttle-body")

        let named = DemoOutlineCatalog.selection(
            photoID: "hilux",
            partID: "intake-plenum",
            state: .confident
        )
        XCTAssertEqual(named.partID, "intake-plenum")
        XCTAssertEqual(named.displayName, "intake plenum")
        XCTAssertGreaterThanOrEqual(named.geometry?.polygons[0].points.count ?? 0, 5)

        let shown = HighlightViewerPresentation.resolve(
            source: .confident,
            photoID: "hilux",
            partID: "intake-plenum"
        )
        XCTAssertEqual(shown.body, "Start with the intake plenum.")
        XCTAssertEqual(shown.tags, ["intake", "inspected"])
    }

    func testCatalogRingsArePolygonsNotBoxes() throws {
        for photoID in ["hilux", "supra", "hrymx", "flickr"] {
            let pick = DemoOutlineCatalog.selection(photoID: photoID, state: .confident)
            let ring = try XCTUnwrap(pick.geometry?.polygons.first)
            XCTAssertGreaterThanOrEqual(ring.points.count, 5)
            XCTAssertFalse(HighlightOutlineCurve.isAxisAlignedRectangle(ring.points))
            XCTAssertFalse(HighlightViewerScript.geometry(
                photoID: photoID,
                partID: pick.partID,
                showingOutline: false
            ) != nil)
        }
    }

    func testAspectFitMapsNormalizedPointThroughImageRect() {
        let fitted = HighlightOutlineLayout.aspectFit(
            imageWidth: 100,
            imageHeight: 100,
            boundsWidth: 200,
            boundsHeight: 100
        )
        XCTAssertEqual(fitted.x, 50)
        XCTAssertEqual(fitted.y, 0)
        XCTAssertEqual(fitted.width, 100)
        XCTAssertEqual(fitted.height, 100)

        let center = HighlightOutlineLayout.map(HighlightPoint(x: 0.5, y: 0.5), in: fitted)
        XCTAssertEqual(center.x, 100)
        XCTAssertEqual(center.y, 50)

        let filled = HighlightOutlineLayout.aspectFill(
            imageWidth: 200,
            imageHeight: 100,
            boundsWidth: 100,
            boundsHeight: 100
        )
        XCTAssertEqual(filled.x, -50)
        XCTAssertEqual(filled.y, 0)
        XCTAssertEqual(filled.width, 200)
        XCTAssertEqual(filled.height, 100)

        let cubics = HighlightOutlineCurve.closedCubics(points: [
            HighlightPoint(x: 0.2, y: 0.2),
            HighlightPoint(x: 0.8, y: 0.25),
            HighlightPoint(x: 0.7, y: 0.8),
            HighlightPoint(x: 0.25, y: 0.7),
        ])
        XCTAssertEqual(cubics.count, 4)
        XCTAssertEqual(cubics[0].start.x, 0.2)
        XCTAssertGreaterThan(cubics[0].control1.x, cubics[0].start.x)
    }

    func testDemoDisplayMapsToSourceState() throws {
        let outline = HighlightRef(
            bayPhotoID: try XCTUnwrap(BayPhotoID(rawValue: "fake-bay-photo-front")),
            partID: try XCTUnwrap(PartID(rawValue: "fake-part-intake")),
            display: .outline
        )
        let confirm = HighlightRef(
            bayPhotoID: outline.bayPhotoID,
            partID: outline.partID,
            display: .confirm
        )
        XCTAssertEqual(
            HighlightViewerState.fromDemo(display: .outline, highlight: outline),
            .confident
        )
        XCTAssertEqual(
            HighlightViewerState.fromDemo(display: .confirm, highlight: confirm),
            .unsure
        )
        XCTAssertEqual(
            HighlightViewerState.fromDemo(display: nil, highlight: confirm),
            .notFound
        )
        XCTAssertEqual(
            HighlightViewerState.fromDemo(display: nil, highlight: nil),
            .notFound
        )
        XCTAssertEqual(HighlightViewerState.fromDemoState("reference"), .reference)
        XCTAssertEqual(HighlightViewerState.fromDemoState("not_found"), .notFound)
    }

    func testScreenLaunchOpensEachState() {
        let confident = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "highlight-confident"],
            environment: [:]
        )
        XCTAssertEqual(confident.screen, .confident)
        XCTAssertTrue(confident.opensHighlightViewer)
        XCTAssertTrue(confident.enablesDemoMode)
        XCTAssertFalse(confident.unsureHighlight)
        XCTAssertEqual(confident.cannedQuestion, "where's the fuse box?")

        let unsure = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "highlight-unsure"],
            environment: [:]
        )
        XCTAssertEqual(unsure.screen, .unsure)
        XCTAssertTrue(unsure.unsureHighlight)
        XCTAssertEqual(unsure.cannedQuestion, "where's the intake plenum?")
        XCTAssertEqual(
            HighlightViewerPresentation.resolve(
                source: unsure.screen!.source,
                flags: unsure.featureFlags
            ).kind,
            .unsure
        )

        let notFound = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "highlight-not-found"],
            environment: [:]
        )
        XCTAssertEqual(notFound.screen, .notFound)
        XCTAssertEqual(notFound.cannedQuestion, "where are the coil packs?")

        let reference = DemoLaunchOptions.parse(
            arguments: ["SidekickMechanic", "-screen", "highlight-reference"],
            environment: [:]
        )
        XCTAssertEqual(reference.screen, .reference)
        XCTAssertEqual(reference.cannedQuestion, "where's the fuse box?")
    }

    func testUnsureCopyMatchesOutlinedRings() {
        let hilux = HighlightViewerPresentation.resolve(
            source: .unsure,
            flags: FeatureFlags(unsureHighlight: true),
            photoID: "hilux"
        )
        XCTAssertEqual(hilux.partDisplayName, "radiator cap")
        XCTAssertEqual(hilux.body, "The radiator cap on this demo photo.")
        XCTAssertEqual(hilux.partID, "radiator-cap-upper-hose")
        XCTAssertEqual(
            DemoOutlineCatalog.geometry(photoID: "hilux", partID: "radiator-cap-upper-hose")?.polygons.count,
            1
        )

        let supra = HighlightViewerPresentation.resolve(
            source: .unsure,
            flags: FeatureFlags(unsureHighlight: true),
            photoID: "supra"
        )
        XCTAssertEqual(supra.partDisplayName, "radiator cap + upper hose")
        XCTAssertEqual(supra.body, "The radiator cap + upper hose on this demo photo.")
        XCTAssertEqual(
            DemoOutlineCatalog.geometry(photoID: "supra", partID: "radiator-cap-upper-hose")?.polygons.count,
            2
        )
    }

    func testCleanupDropsTinyRingsAndBorderSpurs() throws {
        let tiny = HighlightPolygon(points: [
            HighlightPoint(x: 0.50, y: 0.50),
            HighlightPoint(x: 0.501, y: 0.50),
            HighlightPoint(x: 0.50, y: 0.501),
        ])
        let body = HighlightPolygon(points: [
            HighlightPoint(x: 0.20, y: 0.20),
            HighlightPoint(x: 0.80, y: 0.22),
            HighlightPoint(x: 0.78, y: 0.80),
            HighlightPoint(x: 0.22, y: 0.78),
            HighlightPoint(x: 0.18, y: 0.50),
        ])
        let cleaned = try XCTUnwrap(
            HighlightOutlineCleanup.cleaned(
                HighlightGeometry(polygons: [body, tiny])
            )
        )
        XCTAssertEqual(cleaned.polygons.count, 1)
        XCTAssertGreaterThanOrEqual(cleaned.polygons[0].points.count, 5)

        let spurred = [
            HighlightPoint(x: 0.30, y: 0.30),
            HighlightPoint(x: 0.70, y: 0.30),
            HighlightPoint(x: 0.70, y: 0.70),
            HighlightPoint(x: 0.999, y: 0.55),
            HighlightPoint(x: 0.68, y: 0.72),
            HighlightPoint(x: 0.30, y: 0.70),
        ]
        let trimmed = HighlightOutlineCleanup.cleaned(points: spurred)
        XCTAssertLessThan(trimmed.map(\.x).max() ?? 1, 0.99)
        XCTAssertGreaterThanOrEqual(trimmed.count, 5)
        XCTAssertFalse(HighlightOutlineCurve.isAxisAlignedRectangle(trimmed))

        let hrymx = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "hrymx", partID: "throttle-body")
        )
        XCTAssertLessThan(hrymx.polygons[0].points.map(\.x).max() ?? 1, 0.99)
        XCTAssertGreaterThan(HighlightOutlineCleanup.area(hrymx.polygons[0].points), 0.01)
    }

    func testHrymxThrottleHasNoSpikeOrSelfIntersection() throws {
        let hrymx = try XCTUnwrap(
            DemoOutlineCatalog.geometry(photoID: "hrymx", partID: "throttle-body")
        )
        XCTAssertEqual(hrymx.polygons.count, 1)
        let points = hrymx.polygons[0].points
        XCTAssertGreaterThanOrEqual(points.count, 8)
        XCTAssertFalse(HighlightOutlineCleanup.hasSelfIntersection(points))
        XCTAssertGreaterThanOrEqual(
            HighlightOutlineCleanup.minimumVertexAngleDegrees(points),
            25,
            "cleaned throttle still has a spike"
        )
        XCTAssertGreaterThan(
            HighlightOutlineCleanup.solidity(points),
            0.85,
            "cleaned throttle is too concave to follow the part"
        )
        XCTAssertFalse(HighlightOutlineCurve.isAxisAlignedRectangle(points))
        XCTAssertLessThan(points.map(\.x).max() ?? 1, 0.99)
        XCTAssertLessThan(points.map(\.y).max() ?? 1, 0.62)
        XCTAssertGreaterThan(HighlightOutlineCleanup.area(points), 0.02)
    }

    func testOutlineInkThinsForThumbnails() {
        let card = HighlightOutlineInk.scaled(renderedWidth: 200)
        let thumb = HighlightOutlineInk.scaled(renderedWidth: 80)
        XCTAssertEqual(card.strokeWidth, 6, accuracy: 0.01)
        XCTAssertEqual(card.fillOpacity, 0.22, accuracy: 0.001)
        XCTAssertLessThan(thumb.strokeWidth, 4)
        XCTAssertLessThan(thumb.fillOpacity, 0.16)
        XCTAssertGreaterThan(thumb.strokeWidth, 1)
        XCTAssertEqual(HighlightOutlineInk.scaled(renderedWidth: 40).strokeWidth, 1.25, accuracy: 0.05)
        XCTAssertEqual(HighlightOutlineInk.scaled(renderedWidth: 40).fillOpacity, 0.06, accuracy: 0.005)
    }

    func testViewerLayoutKeepsEveryCatalogPolygonOnScreen() {
        let visible = OutlineRect(x: 0, y: 0, width: 393, height: 620)
        var checked = 0
        for photo in DemoOutlineCatalog.load() {
            for part in photo.parts {
                guard let geometry = DemoOutlineCatalog.geometry(
                    photoID: photo.photoID,
                    partID: part.partID
                ) else { continue }
                let displayed = HighlightOutlineLayout.viewerDisplayedImage(
                    imageWidth: Double(photo.width),
                    imageHeight: Double(photo.height),
                    boundsWidth: visible.width,
                    boundsHeight: visible.height
                )
                XCTAssertGreaterThan(displayed.width, 0)
                XCTAssertGreaterThan(displayed.height, 0)
                for ring in geometry.polygons {
                    for point in ring.points {
                        let mapped = HighlightOutlineLayout.map(point, in: displayed)
                        XCTAssertTrue(
                            visible.contains(mapped),
                            "\(photo.photoID) \(part.partID) (\(point.x), \(point.y)) mapped to (\(mapped.x), \(mapped.y)) outside the visible card"
                        )
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 20)
    }

    func testViewerCardMatchingPhotoAspectFillsTheRect() {
        for photo in DemoOutlineCatalog.load() {
            let width = 361.0
            let height = width * Double(photo.height) / Double(photo.width)
            let card = HighlightOutlineLayout.viewerDisplayedImage(
                imageWidth: Double(photo.width),
                imageHeight: Double(photo.height),
                boundsWidth: width,
                boundsHeight: height
            )
            XCTAssertEqual(card.x, 0, accuracy: 0.01)
            XCTAssertEqual(card.y, 0, accuracy: 0.01)
            XCTAssertEqual(card.width, width, accuracy: 0.01)
            XCTAssertEqual(card.height, height, accuracy: 0.01)
        }
    }
}
