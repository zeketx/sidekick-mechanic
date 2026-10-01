import Foundation
import XCTest
@testable import SidekickCore

final class AnswerContractTests: XCTestCase {
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
            let payload = try decodeFixture(name)
            switch payload {
            case let .answer(text, _, _):
                XCTAssertFalse(text.isEmpty, name)
            case let .refusal(text, reason):
                XCTAssertFalse(text.isEmpty, name)
                XCTAssertEqual(reason, .notFoundInManual)
            }
        }
    }

    func testPlainAnswerFixture() throws {
        let payload = try decodeFixture("plain.json")
        XCTAssertEqual(
            payload,
            .answer(
                text: "This is a fixture-only reply with no manual citations.",
                citations: [],
                highlight: nil
            )
        )
    }

    func testCitationsFixture() throws {
        let payload = try decodeFixture("with_citations.json")
        XCTAssertEqual(
            payload,
            .answer(
                text: "Start with the fake intake path described in the fixture snippet. This is not a procedure.",
                citations: [
                    AnswerContract.Citation(
                        docId: "FAKE-DOC-2JZ",
                        page: 999,
                        snippet: "FAKE-SNIPPET: no real spec. Value FAKE-SPEC."
                    ),
                ],
                highlight: nil
            )
        )
    }

    func testHighlightFixture() throws {
        let payload = try decodeFixture("with_highlight.json")
        XCTAssertEqual(
            payload,
            .answer(
                text: "Look at the fake intake area on the fixture bay photo.",
                citations: [
                    AnswerContract.Citation(
                        docId: "FAKE-DOC-2JZ",
                        page: 999,
                        snippet: "FAKE-SNIPPET: check the mapped fixture part."
                    ),
                ],
                highlight: AnswerContract.HighlightRef(
                    bayPhotoId: "fake-bay-photo-front",
                    partId: "fake-part-intake"
                )
            )
        )
    }

    func testRefusalFixture() throws {
        let payload = try decodeFixture("refusal.json")
        XCTAssertEqual(
            payload,
            .refusal(
                text: "Not found in the manual. I do not have a cited page for this.",
                reason: .notFoundInManual
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
            let roundTripped = try decoder.decode(AnswerContract.Payload.self, from: data)
            XCTAssertEqual(roundTripped, original, name)
        }
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
        XCTAssertThrowsError(try JSONDecoder().decode(AnswerContract.Payload.self, from: json))
    }

    func testUnknownKindFailsToDecode() {
        let json = Data(
            #"""
            { "kind": "unknown", "text": "nope", "citations": [] }
            """#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(AnswerContract.Payload.self, from: json))
    }

    private func fixtureNames() throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: fixturesDirectory(),
            includingPropertiesForKeys: nil
        )
        return Set(urls.filter { $0.pathExtension == "json" }.map(\.lastPathComponent))
    }

    private func decodeFixture(_ name: String) throws -> AnswerContract.Payload {
        let url = fixturesDirectory().appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AnswerContract.Payload.self, from: data)
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
