/// How an `Answer` is shown on the answer card.
///
/// Chip labels, the refusal status, and highlight-slot visibility live here so
/// the SwiftUI view does not re-learn found vs refusal rules.
public struct AnswerCardContent: Hashable, Sendable {
    public enum Presentation: Hashable, Sendable {
        case found
        case notFoundInManual
        case generalAdvice
        case providerUnavailable
    }

    /// One citation chip. The label is the document id and page.
    /// `citation` is the page a tap opens, including the snippet.
    public struct Chip: Hashable, Sendable, Identifiable {
        public let id: Int
        public let label: String
        public let citation: Citation

        public var docID: DocumentID { citation.docID }
        public var page: PageNumber { citation.page }
    }

    /// Stable heading for the refusal card. The body text stays the model's reply.
    public static let notFoundStatusTitle = "Not found in the manual"
    public static let unavailableStatusTitle = "Mechanic unavailable"
    public static let relatedHeading = "Related pages"
    public static let relatedHint = "Opens a related manual page. This page did not answer the question."

    public let text: String
    public let presentation: Presentation
    public let chips: [Chip]
    public let relatedChips: [Chip]
    public let steps: [String]
    public let basisLine: String?
    public let safetyText: String?
    public let showsHighlightSlot: Bool
    public let highlight: HighlightRef?

    public var statusTitle: String? {
        switch presentation {
        case .found:
            return nil
        case .notFoundInManual:
            return Self.notFoundStatusTitle
        case .generalAdvice:
            return GeneralAdvice.honesty
        case .providerUnavailable:
            return Self.unavailableStatusTitle
        }
    }

    public var statusSymbol: String {
        switch presentation {
        case .generalAdvice:
            return "wrench.and.screwdriver"
        case .found, .notFoundInManual, .providerUnavailable:
            return "book.closed"
        }
    }

    public var accessibilityIdentifier: String {
        switch presentation {
        case .found:
            return "answerCard.found"
        case .notFoundInManual:
            return "answerCard.refusal"
        case .generalAdvice:
            return "answerCard.generalAdvice"
        case .providerUnavailable:
            return "answerCard.unavailable"
        }
    }

    /// Spoken name for the image slot. Nil when the slot is hidden.
    public var highlightAccessibilityLabel: String? {
        guard showsHighlightSlot, let highlight else { return nil }
        return "Highlight image slot. Photo \(highlight.bayPhotoID.rawValue). Part \(highlight.partID.rawValue)."
    }

    public init(answer: Answer) {
        text = answer.text
        switch answer {
        case let .found(found):
            presentation = .found
            chips = Self.chips(found.citations)
            relatedChips = []
            steps = []
            basisLine = nil
            safetyText = nil
            highlight = found.highlight
            showsHighlightSlot = found.highlight != nil
        case let .refusal(refusal):
            presentation = .notFoundInManual
            chips = []
            relatedChips = []
            steps = []
            basisLine = nil
            safetyText = nil
            highlight = refusal.highlight
            showsHighlightSlot = refusal.highlight != nil
        case let .generalAdvice(advice):
            presentation = .generalAdvice
            chips = []
            relatedChips = Self.chips(advice.related)
            steps = advice.steps
            basisLine = advice.basisLine
            safetyText = GeneralAdvice.safety
            highlight = advice.highlight
            showsHighlightSlot = advice.highlight != nil
        case .providerUnavailable:
            presentation = .providerUnavailable
            chips = []
            relatedChips = []
            steps = []
            basisLine = nil
            safetyText = nil
            highlight = nil
            showsHighlightSlot = false
        }
    }

    private static func chips(_ citations: [Citation]) -> [Chip] {
        citations.enumerated().map { index, citation in
            Chip(id: index, label: citation.chipLabel, citation: citation)
        }
    }
}

extension Citation {
    /// Document id and page on the chip. The snippet stays on `citation` for the page viewer.
    public var chipLabel: String {
        "\(docID.rawValue) · p. \(page.rawValue)"
    }
}

/// Mirrors `backend/contracts/fixtures`. `FAKE-*` ids and page 999 only.
/// Not vehicle facts. Tests lock these values to the JSON files.
public enum AnswerCardFixture {
    public static let plain: Answer = .found(makeFound(
        text: "This is a fixture-only reply with no manual citations."
    ))

    public static let withCitations: Answer = .found(makeFound(
        text: "Start with the fake intake path described in the fixture snippet. This is not a procedure.",
        citations: [
            makeCitation(
                docID: "FAKE-DOC-2JZ",
                page: 999,
                snippet: "FAKE-SNIPPET: no real spec. Value FAKE-SPEC."
            ),
        ]
    ))

    public static let withHighlight: Answer = .found(makeFound(
        text: "Look at the fake intake area on the fixture bay photo.",
        citations: [
            makeCitation(
                docID: "FAKE-DOC-2JZ",
                page: 999,
                snippet: "FAKE-SNIPPET: check the mapped fixture part."
            ),
        ],
        highlight: HighlightRef(
            bayPhotoID: makeID(BayPhotoID.init, "fake-bay-photo-front"),
            partID: makeID(PartID.init, "fake-part-intake")
        )
    ))

    public static let refusal: Answer = .refusal(makeRefusal(
        text: "Not found in the manual. I do not have a cited page for this."
    ))

    public static let generalAdvice: Answer = .generalAdvice(makeGeneralAdvice())

    private static func makeFound(
        text: String,
        citations: [Citation] = [],
        highlight: HighlightRef? = nil
    ) -> FoundAnswer {
        guard let found = FoundAnswer(text: text, citations: citations, highlight: highlight) else {
            preconditionFailure("answer card fixture text is non-empty")
        }
        return found
    }

    private static func makeGeneralAdvice() -> GeneralAdvice {
        guard let advice = GeneralAdvice(
            steps: ["FAKE-STEP: check the fixture connection before the fixture motor."],
            garage: .garage(truck: "FAKE-TRUCK", engine: "TBD"),
            related: [
                makeCitation(docID: "FAKE-DOC", page: 999, snippet: "FAKE-SNIPPET"),
            ]
        ) else {
            preconditionFailure("general advice fixture is valid")
        }
        return advice
    }

    private static func makeRefusal(text: String) -> Refusal {
        guard let refusal = Refusal(text: text) else {
            preconditionFailure("answer card fixture text is non-empty")
        }
        return refusal
    }

    private static func makeCitation(docID: String, page: Int = 999, snippet: String) -> Citation {
        guard let citation = Citation(
            docID: makeID(DocumentID.init, docID),
            page: makeID(PageNumber.init, page),
            snippet: snippet
        ) else {
            preconditionFailure("answer card fixture citation is valid")
        }
        return citation
    }

    private static func makeID<Raw, ID>(_ make: (Raw) -> ID?, _ raw: Raw) -> ID {
        guard let id = make(raw) else {
            preconditionFailure("answer card fixture id is valid")
        }
        return id
    }
}
