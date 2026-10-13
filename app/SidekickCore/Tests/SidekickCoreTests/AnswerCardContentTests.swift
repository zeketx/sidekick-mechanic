import XCTest
@testable import SidekickCore

final class AnswerCardContentTests: XCTestCase {
    func testPlainFixtureHasTextAndNoChipsOrHighlight() throws {
        let card = AnswerCardContent(answer: try load("plain.json"))

        XCTAssertEqual(card.presentation, .found)
        XCTAssertEqual(card.text, "This is a fixture-only reply with no manual citations.")
        XCTAssertNil(card.statusTitle)
        XCTAssertEqual(card.accessibilityIdentifier, "answerCard.found")
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertFalse(card.showsHighlightSlot)
        XCTAssertNil(card.highlight)
        XCTAssertNil(card.highlightAccessibilityLabel)
    }

    func testCitationsFixtureRendersDocAndPageChipsWithoutAHighlightSlot() throws {
        let card = AnswerCardContent(answer: try load("with_citations.json"))

        XCTAssertEqual(card.presentation, .found)
        XCTAssertEqual(
            card.text,
            "Start with the fake intake path described in the fixture snippet. This is not a procedure."
        )
        XCTAssertNil(card.statusTitle)
        XCTAssertEqual(card.chips.map(\.id), [0])
        XCTAssertEqual(card.chips.map(\.label), ["FAKE-DOC-2JZ · p. 999"])
        XCTAssertEqual(card.chips.map(\.docID.rawValue), ["FAKE-DOC-2JZ"])
        XCTAssertEqual(card.chips.map(\.page.rawValue), [999])
        XCTAssertEqual(
            card.chips.map(\.citation.snippet),
            ["FAKE-SNIPPET: no real spec. Value FAKE-SPEC."]
        )
        XCTAssertFalse(card.showsHighlightSlot)
        XCTAssertNil(card.highlight)
    }

    func testHighlightFixtureShowsTheImageSlot() throws {
        let card = AnswerCardContent(answer: try load("with_highlight.json"))

        XCTAssertEqual(card.presentation, .found)
        XCTAssertEqual(card.text, "Look at the fake intake area on the fixture bay photo.")
        XCTAssertEqual(card.chips.map(\.label), ["FAKE-DOC-2JZ · p. 999"])
        XCTAssertTrue(card.showsHighlightSlot)
        XCTAssertEqual(card.highlight?.bayPhotoID.rawValue, "fake-bay-photo-front")
        XCTAssertEqual(card.highlight?.partID.rawValue, "fake-part-intake")
        XCTAssertEqual(
            card.highlightAccessibilityLabel,
            "Highlight image slot. Photo fake-bay-photo-front. Part fake-part-intake."
        )
    }

    func testRefusalFixtureIsNotFoundAndHidesChipsAndHighlight() throws {
        let card = AnswerCardContent(answer: try load("refusal.json"))

        XCTAssertEqual(card.presentation, .notFoundInManual)
        XCTAssertEqual(card.statusTitle, "Not found in the manual")
        XCTAssertEqual(AnswerCardContent.notFoundStatusTitle, "Not found in the manual")
        XCTAssertEqual(
            card.text,
            "Not found in the manual. I do not have a cited page for this."
        )
        XCTAssertEqual(card.accessibilityIdentifier, "answerCard.refusal")
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertFalse(card.showsHighlightSlot)
        XCTAssertNil(card.highlight)
        XCTAssertNil(card.highlightAccessibilityLabel)
    }

    func testChipLabelsKeepCitationOrder() throws {
        let answer = Answer.found(
            try XCTUnwrap(
                FoundAnswer(
                    text: "Two fake citations.",
                    citations: [
                        try citation(docID: "FAKE-DOC-A", snippet: "FAKE-SNIPPET-A"),
                        try citation(docID: "FAKE-DOC-B", snippet: "FAKE-SNIPPET-B"),
                    ]
                )
            )
        )
        let card = AnswerCardContent(answer: answer)

        XCTAssertEqual(card.chips.map(\.id), [0, 1])
        XCTAssertEqual(card.chips.map(\.label), [
            "FAKE-DOC-A · p. 999",
            "FAKE-DOC-B · p. 999",
        ])
        XCTAssertEqual(card.chips.map(\.citation), [
            try citation(docID: "FAKE-DOC-A", snippet: "FAKE-SNIPPET-A"),
            try citation(docID: "FAKE-DOC-B", snippet: "FAKE-SNIPPET-B"),
        ])
        XCTAssertFalse(card.showsHighlightSlot)
    }

    func testSamePageChipsKeepTheirOwnSnippets() throws {
        let answer = Answer.found(
            try XCTUnwrap(
                FoundAnswer(
                    text: "Two fake citations on one page.",
                    citations: [
                        try citation(docID: "FAKE-DOC", snippet: "FAKE-SNIPPET-A"),
                        try citation(docID: "FAKE-DOC", snippet: "FAKE-SNIPPET-B"),
                    ]
                )
            )
        )
        let card = AnswerCardContent(answer: answer)

        XCTAssertEqual(card.chips.map(\.docID.rawValue), ["FAKE-DOC", "FAKE-DOC"])
        XCTAssertEqual(card.chips.map(\.page.rawValue), [999, 999])
        XCTAssertEqual(card.chips.map(\.citation.snippet), ["FAKE-SNIPPET-A", "FAKE-SNIPPET-B"])
        XCTAssertEqual(card.chips[0].citation, try citation(docID: "FAKE-DOC", snippet: "FAKE-SNIPPET-A"))
        XCTAssertEqual(card.chips[1].citation, try citation(docID: "FAKE-DOC", snippet: "FAKE-SNIPPET-B"))
    }

    func testCitationChipLabelIsDocumentAndPage() throws {
        let citation = try citation(docID: "FAKE-DOC-2JZ", snippet: "FAKE-SNIPPET")
        XCTAssertEqual(citation.chipLabel, "FAKE-DOC-2JZ · p. 999")
    }

    func testPreviewFixturesMatchContractFiles() throws {
        let loaded = try ContractFixtures.load(from: ContractFixtures.repositoryDirectory())
        XCTAssertEqual(loaded["plain.json"], AnswerCardFixture.plain)
        XCTAssertEqual(loaded["with_citations.json"], AnswerCardFixture.withCitations)
        XCTAssertEqual(loaded["with_highlight.json"], AnswerCardFixture.withHighlight)
        XCTAssertEqual(loaded["refusal.json"], AnswerCardFixture.refusal)
        XCTAssertEqual(loaded["general_advice.json"], AnswerCardFixture.generalAdvice)
    }

    func testGeneralAdviceKeepsRelatedPagesOffTheAnswerChips() throws {
        let card = AnswerCardContent(answer: try load("general_advice.json"))

        XCTAssertEqual(card.presentation, .generalAdvice)
        XCTAssertEqual(card.accessibilityIdentifier, "answerCard.generalAdvice")
        XCTAssertEqual(card.statusTitle, GeneralAdvice.honesty)
        XCTAssertEqual(card.statusSymbol, "wrench.and.screwdriver")
        XCTAssertEqual(card.basisLine, "Truck: FAKE-TRUCK. Engine: TBD.")
        XCTAssertEqual(card.safetyText, GeneralAdvice.safety)
        XCTAssertEqual(
            card.steps,
            ["FAKE-STEP: check the fixture connection before the fixture motor."]
        )
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertEqual(card.relatedChips.map(\.label), ["FAKE-DOC · p. 999"])
        XCTAssertEqual(card.relatedChips.map(\.citation.snippet), ["FAKE-SNIPPET"])
        XCTAssertEqual(AnswerCardContent.relatedHeading, "Related pages")
        XCTAssertEqual(
            AnswerCardContent.relatedHint,
            "Opens a related manual page. This page did not answer the question."
        )
    }

    func testGeneralAdviceBasisKeepsTBDWhenOnlyTheEngineIsSet() throws {
        let advice = try XCTUnwrap(
            GeneralAdvice(
                steps: ["FAKE-STEP: listen for the fixture."],
                garage: .garage(truck: nil, engine: "TBD")
            )
        )
        let card = AnswerCardContent(answer: .generalAdvice(advice))

        XCTAssertEqual(card.basisLine, "Engine: TBD.")
        XCTAssertTrue(card.chips.isEmpty)
        XCTAssertTrue(card.relatedChips.isEmpty)
    }

    func testGeneralAdviceOmitsBasisWhenTheGarageHasNoTruckOrEngine() throws {
        let advice = try XCTUnwrap(
            GeneralAdvice(
                steps: ["FAKE-STEP: listen for the fixture."],
                garage: .none
            )
        )
        let card = AnswerCardContent(answer: .generalAdvice(advice))

        XCTAssertNil(card.basisLine)
    }

    func testRefusalKeepsTheClosedBookSymbol() throws {
        let card = AnswerCardContent(answer: try load("refusal.json"))
        XCTAssertEqual(card.statusSymbol, "book.closed")
        XCTAssertEqual(card.accessibilityIdentifier, "answerCard.refusal")
    }

    private func load(_ name: String) throws -> Answer {
        let loaded = try ContractFixtures.load(from: ContractFixtures.repositoryDirectory())
        return try XCTUnwrap(loaded[name])
    }

    private func citation(docID: String, snippet: String) throws -> Citation {
        try XCTUnwrap(
            Citation(
                docID: try XCTUnwrap(DocumentID(rawValue: docID)),
                page: try XCTUnwrap(PageNumber(rawValue: 999)),
                snippet: snippet
            )
        )
    }
}
