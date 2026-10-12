import Foundation
import XCTest
@testable import SidekickCore

final class AnswerTests: XCTestCase {
    private static let requiredFixtures = [
        "plain.json",
        "with_citations.json",
        "with_highlight.json",
        "refusal.json",
    ]

    func testRequiredFixturesExist() throws {
        let names = try fixtureNames()
        XCTAssertEqual(names, Set(Self.requiredFixtures))
    }

    func testEveryFixtureDecodes() throws {
        for name in try fixtureNames().sorted() {
            let answer = try decodeFixture(name)
            XCTAssertFalse(answer.text.isEmpty, name)
        }
    }

    func testPlainAnswerFixture() throws {
        let answer = try decodeFixture("plain.json")
        XCTAssertEqual(
            answer,
            .found(
                try XCTUnwrap(
                    FoundAnswer(text: "This is a fixture-only reply with no manual citations.")
                )
            )
        )
    }

    func testCitationsFixture() throws {
        let answer = try decodeFixture("with_citations.json")
        XCTAssertEqual(
            answer,
            .found(
                try XCTUnwrap(
                    FoundAnswer(
                        text: "Start with the fake intake path described in the fixture snippet. This is not a procedure.",
                        citations: [
                            try XCTUnwrap(
                                Citation(
                                    docID: try XCTUnwrap(DocumentID(rawValue: "FAKE-DOC-2JZ")),
                                    page: try XCTUnwrap(PageNumber(rawValue: 999)),
                                    snippet: "FAKE-SNIPPET: no real spec. Value FAKE-SPEC."
                                )
                            ),
                        ]
                    )
                )
            )
        )
    }

    func testHighlightFixture() throws {
        let answer = try decodeFixture("with_highlight.json")
        XCTAssertEqual(
            answer,
            .found(
                try XCTUnwrap(
                    FoundAnswer(
                        text: "Look at the fake intake area on the fixture bay photo.",
                        citations: [
                            try XCTUnwrap(
                                Citation(
                                    docID: try XCTUnwrap(DocumentID(rawValue: "FAKE-DOC-2JZ")),
                                    page: try XCTUnwrap(PageNumber(rawValue: 999)),
                                    snippet: "FAKE-SNIPPET: check the mapped fixture part."
                                )
                            ),
                        ],
                        highlight: HighlightRef(
                            bayPhotoID: try XCTUnwrap(BayPhotoID(rawValue: "fake-bay-photo-front")),
                            partID: try XCTUnwrap(PartID(rawValue: "fake-part-intake"))
                        )
                    )
                )
            )
        )
    }

    func testRefusalFixture() throws {
        let answer = try decodeFixture("refusal.json")
        XCTAssertEqual(
            answer,
            .refusal(
                try XCTUnwrap(
                    Refusal(text: "Not found in the manual. I do not have a cited page for this.")
                )
            )
        )
    }

    func testRoundTripEveryFixture() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        for name in Self.requiredFixtures {
            let original = try decodeFixture(name)
            let data = try encoder.encode(original)
            let roundTripped = try decoder.decode(Answer.self, from: data)
            XCTAssertEqual(roundTripped, original, name)
        }
    }

    func testCitationJSONUsesSnakeCaseKeys() throws {
        let citation = try XCTUnwrap(
            Citation(
                docID: try XCTUnwrap(DocumentID(rawValue: "FAKE-DOC-2JZ")),
                page: try XCTUnwrap(PageNumber(rawValue: 999)),
                snippet: "FAKE-SNIPPET"
            )
        )
        let object = try encodeObject(citation)
        XCTAssertEqual(object["doc_id"] as? String, "FAKE-DOC-2JZ")
        XCTAssertEqual(object["page"] as? Int, 999)
        XCTAssertEqual(object["snippet"] as? String, "FAKE-SNIPPET")
        XCTAssertNil(object["docId"])
        XCTAssertNil(object["docID"])
    }

    func testHighlightJSONUsesSnakeCaseKeys() throws {
        let highlight = HighlightRef(
            bayPhotoID: try XCTUnwrap(BayPhotoID(rawValue: "fake-bay-photo-front")),
            partID: try XCTUnwrap(PartID(rawValue: "fake-part-intake"))
        )
        let object = try encodeObject(highlight)
        XCTAssertEqual(object["bay_photo_id"] as? String, "fake-bay-photo-front")
        XCTAssertEqual(object["part_id"] as? String, "fake-part-intake")
        XCTAssertNil(object["bayPhotoId"])
        XCTAssertNil(object["partId"])
        XCTAssertNil(object["demo"])
        XCTAssertNil(object["display"])
        XCTAssertNil(object["geometry"])
    }

    func testDemoHighlightDecodesOptionalFields() throws {
        let json = Data(
            #"""
            {
              "kind": "answer",
              "text": "Demo throttle body on the stand-in photo.",
              "citations": [],
              "highlight": {
                "bay_photo_id": "hrymx-2jz-ge-25308847029",
                "part_id": "throttle-body",
                "display": "confirm",
                "demo": true,
                "geometry": {
                  "polygons": [
                    {
                      "points": [
                        {"x": 0.1, "y": 0.2},
                        {"x": 0.3, "y": 0.2},
                        {"x": 0.3, "y": 0.4}
                      ]
                    }
                  ]
                }
              }
            }
            """#.utf8
        )
        let answer = try JSONDecoder().decode(Answer.self, from: json)
        guard case let .found(found) = answer, let highlight = found.highlight else {
            return XCTFail("expected a demo highlight")
        }
        XCTAssertEqual(highlight.bayPhotoID.rawValue, "hrymx-2jz-ge-25308847029")
        XCTAssertEqual(highlight.partID.rawValue, "throttle-body")
        XCTAssertEqual(highlight.display, .confirm)
        XCTAssertTrue(highlight.isDemo)
        XCTAssertEqual(highlight.geometry?.polygons.count, 1)
        XCTAssertEqual(highlight.geometry?.polygons[0].points[0].x, 0.1)
        let encoded = try encodeObject(highlight)
        XCTAssertEqual(encoded["demo"] as? Bool, true)
        XCTAssertEqual(encoded["display"] as? String, "confirm")
    }

    func testCitationWithoutPageFailsToDecode() {
        let json = Data(
            #"""
            {
              "kind": "answer",
              "text": "Missing page.",
              "citations": [
                { "doc_id": "FAKE-DOC-2JZ", "snippet": "FAKE-SNIPPET" }
              ]
            }
            """#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(Answer.self, from: json))
    }

    func testCitationPageZeroFailsToDecode() {
        let json = Data(
            #"""
            {
              "kind": "answer",
              "text": "Page zero is not a real page.",
              "citations": [
                { "doc_id": "FAKE-DOC-2JZ", "page": 0, "snippet": "FAKE-SNIPPET" }
              ]
            }
            """#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(Answer.self, from: json))
    }

    func testEmptySnippetFailsToDecode() {
        let json = Data(
            #"""
            {
              "kind": "answer",
              "text": "Empty snippet.",
              "citations": [
                { "doc_id": "FAKE-DOC-2JZ", "page": 999, "snippet": "" }
              ]
            }
            """#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(Answer.self, from: json))
    }

    func testPageZeroCannotBeConstructed() {
        XCTAssertNil(PageNumber(rawValue: 0))
        XCTAssertNil(PageNumber(rawValue: -1))
        XCTAssertEqual(PageNumber(rawValue: 1)?.rawValue, 1)
        XCTAssertEqual(PageNumber(rawValue: 999)?.rawValue, 999)
    }

    func testEmptyIDsCannotBeConstructed() {
        XCTAssertNil(DocumentID(rawValue: ""))
        XCTAssertNil(BayPhotoID(rawValue: ""))
        XCTAssertNil(PartID(rawValue: ""))
        XCTAssertNil(Citation(
            docID: DocumentID(rawValue: "FAKE-DOC-2JZ")!,
            page: PageNumber(rawValue: 999)!,
            snippet: ""
        ))
        XCTAssertNil(FoundAnswer(text: ""))
        XCTAssertNil(Refusal(text: ""))
    }

    func testRefusalCanCarryADemoHighlight() throws {
        let json = Data(
            #"""
            {
              "kind": "refusal",
              "text": "Not found in the manual.",
              "reason": "not_found_in_manual",
              "highlight": {
                "bay_photo_id": "fake-bay-photo-front",
                "part_id": "fake-part-intake"
              }
            }
            """#.utf8
        )
        let answer = try JSONDecoder().decode(Answer.self, from: json)
        guard case let .refusal(refusal) = answer else {
            XCTFail("expected a refusal")
            return
        }
        XCTAssertEqual(refusal.text, "Not found in the manual.")
        XCTAssertEqual(refusal.highlight?.bayPhotoID.rawValue, "fake-bay-photo-front")
        XCTAssertEqual(refusal.highlight?.partID.rawValue, "fake-part-intake")
        XCTAssertNil(refusal.highlight?.display)
    }

    func testProviderErrorDecodesAndIsNotAFoundAnswer() throws {
        let json = Data(
            #"""
            {
              "kind": "error",
              "text": "The mechanic is unavailable right now. Try again in a moment.",
              "reason": "provider_unavailable"
            }
            """#.utf8
        )
        let answer = try JSONDecoder().decode(Answer.self, from: json)
        guard case let .providerUnavailable(unavailable) = answer else {
            XCTFail("expected a provider error")
            return
        }
        XCTAssertEqual(
            unavailable.text,
            "The mechanic is unavailable right now. Try again in a moment."
        )
        let card = AnswerCardContent(answer: answer)
        XCTAssertEqual(card.presentation, .providerUnavailable)
        XCTAssertEqual(card.statusTitle, AnswerCardContent.unavailableStatusTitle)
        XCTAssertEqual(card.accessibilityIdentifier, "answerCard.unavailable")
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertFalse(card.showsHighlightSlot)
    }

    func testUnknownKindFailsToDecode() {
        let json = Data(
            #"""
            { "kind": "unknown", "text": "nope", "citations": [] }
            """#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(Answer.self, from: json))
    }

    private func fixtureNames() throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: fixturesDirectory(),
            includingPropertiesForKeys: nil
        )
        return Set(urls.filter { $0.pathExtension == "json" }.map(\.lastPathComponent))
    }

    private func decodeFixture(_ name: String) throws -> Answer {
        let url = fixturesDirectory().appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Answer.self, from: data)
    }

    private func encodeObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("backend/contracts/fixtures")
    }
}
