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
        XCTAssertEqual(shown.outlineStroke, .solid)
        XCTAssertFalse(shown.showsConfirmPrompt)
        XCTAssertFalse(shown.showsDiagramLink)
        XCTAssertEqual(shown.title, "Your photo")
        XCTAssertEqual(shown.footer, "Confident outline · pinch to zoom")
        XCTAssertEqual(shown.body, "Start with the air box on top of the engine.")
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
        XCTAssertEqual(shown.footer, "Is this it?")
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
        XCTAssertFalse(shown.showsConfirmPrompt)
        XCTAssertEqual(shown.banner, "Reference, not your truck.")
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
        XCTAssertEqual(shown.body, "This part is not in this photo.")
    }

    func testNotFoundHasNoOutlineAndPointsAtFixtureDiagram() {
        let shown = HighlightViewerPresentation.resolve(source: .notFound)
        XCTAssertEqual(shown.kind, .notFound)
        XCTAssertEqual(shown.target, .userPhoto)
        XCTAssertFalse(shown.showsOutline)
        XCTAssertTrue(shown.showsDiagramLink)
        XCTAssertEqual(shown.title, "Not found")
        XCTAssertEqual(shown.body, "This part is not in this photo.")
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
        XCTAssertEqual(
            shown.retakeHint,
            "Retake from a standard angle so this snap can match a traced view. Photo angles are TBD."
        )
        XCTAssertTrue(shown.retakeHint?.contains("TBD") == true)
    }

    func testScriptedGeometryIsAPolygonNotABox() {
        let ring = HighlightViewerScript.airBoxGeometry.polygons[0]
        XCTAssertGreaterThanOrEqual(ring.points.count, 5)
        XCTAssertNil(HighlightViewerScript.geometry(showingOutline: false))
        XCTAssertEqual(
            HighlightViewerScript.geometry(showingOutline: true)?.polygons[0].points.count,
            7
        )
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
        XCTAssertEqual(reference.cannedQuestion, "where's the air box?")
    }
}
