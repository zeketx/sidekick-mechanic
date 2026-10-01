import XCTest
@testable import SidekickCore

final class BayMapTests: XCTestCase {
    func testFixtureResolvesOnlyConfirmedRegions() throws {
        let map = try loadFixture()
        XCTAssertEqual(map.schemaVersion, .v1)
        XCTAssertEqual(map.coordinateSpace, .normalizedTopLeft)
        XCTAssertEqual(
            map.parts.map(\.id.rawValue),
            ["fake-part-hidden", "fake-part-intake", "fake-part-tied"]
        )
        XCTAssertEqual(
            map.highlightChoices.map(\.part.id.rawValue),
            ["fake-part-intake", "fake-part-tied"]
        )
        XCTAssertEqual(
            map.highlightChoices.map(\.reference.bayPhotoID.rawValue),
            ["fake-bay-photo-wide", "fake-bay-photo-aaa"]
        )

        let frontID = try photoID("fake-bay-photo-front")
        let intakeID = try partID("fake-part-intake")
        let front = try XCTUnwrap(map.resolve(HighlightRef(bayPhotoID: frontID, partID: intakeID)))
        XCTAssertEqual(front.confirmedBy.rawValue, "FAKE-OWNER")
        XCTAssertEqual(front.photo.imageSize.width, 100)
        XCTAssertEqual(front.photo.imageSize.height, 50)
        XCTAssertEqual(front.photo.angleID.rawValue, "fake-angle-front")
        XCTAssertEqual(front.photo.license.name, "FAKE-LICENSE")
        XCTAssertEqual(front.reference.bayPhotoID, frontID)
        XCTAssertEqual(front.geometry.polygons.count, 2)
        XCTAssertEqual(front.geometry.polygons[0].points.map(\.x), [0, 0.5, 0.5])
        XCTAssertEqual(front.geometry.polygons[0].points.map(\.y), [0, 0, 0.5])

        let wide = try XCTUnwrap(
            map.resolve(HighlightRef(bayPhotoID: try photoID("fake-bay-photo-wide"), partID: intakeID))
        )
        XCTAssertEqual(wide.photo.imageSize.width, 400)
        XCTAssertEqual(wide.photo.imageSize.height, 400)
        XCTAssertEqual(map.highlightChoices[0].reference.bayPhotoID.rawValue, "fake-bay-photo-wide")

        XCTAssertNil(map.resolve(HighlightRef(bayPhotoID: try photoID("fake-bay-photo-side"), partID: intakeID)))
        XCTAssertNil(map.resolve(HighlightRef(bayPhotoID: frontID, partID: try partID("fake-part-hidden"))))
        XCTAssertNil(map.resolve(HighlightRef(bayPhotoID: try photoID("fake-bay-photo-missing"), partID: intakeID)))

        let angles = Dictionary(uniqueKeysWithValues: map.photos.map { ($0.id.rawValue, $0.angleID.rawValue) })
        XCTAssertEqual(angles["fake-bay-photo-aaa"], "fake-angle-shared")
        XCTAssertEqual(angles["fake-bay-photo-mmm"], "fake-angle-shared")
    }

    func testRoundTripKeepsTheUnconfirmedRegion() throws {
        let map = try loadFixture()
        let encoded = try JSONEncoder().encode(map)
        let again = try JSONDecoder().decode(BayMap.self, from: encoded)
        XCTAssertEqual(again.highlightChoices, map.highlightChoices)
        XCTAssertNil(
            again.resolve(
                HighlightRef(
                    bayPhotoID: try photoID("fake-bay-photo-side"),
                    partID: try partID("fake-part-intake")
                )
            )
        )
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(text.contains("\"unconfirmed\""))
        XCTAssertFalse(text.contains("fake-part-missing"))
    }

    func testDuplicateRegionFails() {
        assertRejects(minimal(regionPartID: "fake-part-intake", extraRegion: true))
    }

    func testUnconfirmedWithConfirmedByFails() {
        let json = minimal().replacingOccurrences(
            of: #"{"kind":"confirmed","confirmed_by":"FAKE-OWNER"}"#,
            with: #"{"kind":"unconfirmed","confirmed_by":"FAKE-OWNER"}"#
        )
        assertRejects(json)
    }

    func testZeroAreaFails() {
        let json = minimal().replacingOccurrences(
            of: #"[{"x":0,"y":0},{"x":0.5,"y":0},{"x":0.5,"y":0.5}]"#,
            with: #"[{"x":0,"y":0},{"x":0.5,"y":0},{"x":1,"y":0}]"#
        )
        assertRejects(json)
    }

    func testPartWithNoRegionFails() {
        let json = minimal().replacingOccurrences(
            of: #"[{"part_id":"fake-part-intake","display_name":"FAKE-NAME-INTAKE","aliases":[]}]"#,
            with: #"[{"part_id":"fake-part-intake","display_name":"FAKE-NAME-INTAKE","aliases":[]},{"part_id":"fake-part-hidden","display_name":"FAKE-NAME-HIDDEN","aliases":[]}]"#
        )
        assertRejects(json)
    }

    private func assertRejects(_ json: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try JSONDecoder().decode(BayMap.self, from: Data(json.utf8)), file: file, line: line)
    }

    private func loadFixture() throws -> BayMap {
        let data = try Data(contentsOf: fixtureURL())
        return try JSONDecoder().decode(BayMap.self, from: data)
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("backend/contracts/fixtures/bay-map/fake-bay-map.json")
    }

    private func photoID(_ raw: String) throws -> BayPhotoID {
        try XCTUnwrap(BayPhotoID(rawValue: raw))
    }

    private func partID(_ raw: String) throws -> PartID {
        try XCTUnwrap(PartID(rawValue: raw))
    }

    private func minimal(regionPartID: String = "fake-part-intake", extraRegion: Bool = false) -> String {
        let extra = extraRegion
            ? #",{"part_id":"fake-part-intake","polygons":[{"points":[{"x":0,"y":0},{"x":0.5,"y":0},{"x":0.5,"y":0.5}]}],"confirmation":{"kind":"confirmed","confirmed_by":"FAKE-OWNER"}}"#
            : ""
        return """
        {"schema_version":1,"coordinate_space":{"units":"normalized","origin":"top_left","x_axis":"right","y_axis":"down"},"parts":[{"part_id":"fake-part-intake","display_name":"FAKE-NAME-INTAKE","aliases":[]}],"photos":[{"bay_photo_id":"fake-bay-photo-front","angle_id":"fake-angle-front","image_size":{"width":8,"height":8},"source":{"kind":"public_prototype","reference":"FAKE-SOURCE"},"license":{"name":"FAKE-LICENSE","reference":"FAKE-LICENSE-REF"},"regions":[{"part_id":"\(regionPartID)","polygons":[{"points":[{"x":0,"y":0},{"x":0.5,"y":0},{"x":0.5,"y":0.5}]}],"confirmation":{"kind":"confirmed","confirmed_by":"FAKE-OWNER"}}\(extra)]}]}
        """
    }
}
