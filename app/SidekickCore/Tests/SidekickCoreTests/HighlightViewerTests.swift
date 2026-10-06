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
        XCTAssertEqual(shown.body, "The radiator cap + upper hose on this demo photo.")
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
        XCTAssertEqual(hiluxFuse.polygons[0].points.count, 26)
        XCTAssertEqual(hiluxFuse.polygons[0].points[0].x, 0.12207)
        XCTAssertEqual(hiluxFuse.polygons[0].points[0].y, 0.44706)

        XCTAssertEqual(supraFuse.polygons[0].points.count, 15)
        XCTAssertEqual(supraFuse.polygons[0].points[0].x, 0.89746)
        XCTAssertEqual(supraFuse.polygons[0].points[0].y, 0.56662)
        XCTAssertNotEqual(hiluxFuse, supraFuse)

        XCTAssertEqual(hrymxThrottle.polygons[0].points.count, 34)
        XCTAssertEqual(hrymxThrottle.polygons[0].points[0].x, 0.75586)
        XCTAssertEqual(flickrThrottle.polygons[0].points.count, 36)
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
        XCTAssertEqual(named.geometry?.polygons[0].points.count, 21)

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
}
