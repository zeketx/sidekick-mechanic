/// Why the model refused to answer. Wire value: `not_found_in_manual`.
public enum RefusalReason: String, Codable, Hashable, Sendable {
    case notFoundInManual = "not_found_in_manual"
}

/// A grounded reply. Citations may be empty in M1 (chat before retrieval).
public struct FoundAnswer: Hashable, Sendable {
    public let text: String
    public let citations: [Citation]
    public let highlight: HighlightRef?

    public init?(text: String, citations: [Citation] = [], highlight: HighlightRef? = nil) {
        guard !text.isEmpty else { return nil }
        self.text = text
        self.citations = citations
        self.highlight = highlight
    }
}

/// A "not found in the manual" reply. Cannot carry citations or a highlight.
public struct Refusal: Hashable, Sendable {
    public let text: String
    public let reason: RefusalReason

    public init?(text: String, reason: RefusalReason = .notFoundInManual) {
        guard !text.isEmpty else { return nil }
        self.text = text
        self.reason = reason
    }
}

/// Chat answer shared by the app, backend, and eval.
///
/// Wire JSON uses snake_case and a `kind` discriminator that matches
/// `backend/contracts/answer.schema.json`.
/// `found` encodes as `"kind": "answer"` so existing fixtures decode as-is.
public enum Answer: Hashable, Sendable {
    case found(FoundAnswer)
    case refusal(Refusal)

    public var text: String {
        switch self {
        case let .found(found):
            return found.text
        case let .refusal(refusal):
            return refusal.text
        }
    }
}

extension Answer: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case citations
        case highlight
        case reason
    }

    private enum Kind: String, Codable {
        case answer
        case refusal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let text = try container.decode(String.self, forKey: .text)
        switch kind {
        case .answer:
            if container.contains(.reason) {
                throw DecodingError.dataCorruptedError(
                    forKey: .reason,
                    in: container,
                    debugDescription: "found answer cannot include reason"
                )
            }
            let citations = try container.decode([Citation].self, forKey: .citations)
            let highlight = try container.decodeIfPresent(HighlightRef.self, forKey: .highlight)
            guard let found = FoundAnswer(text: text, citations: citations, highlight: highlight) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "answer text must be non-empty"
                )
            }
            self = .found(found)
        case .refusal:
            if container.contains(.citations) {
                throw DecodingError.dataCorruptedError(
                    forKey: .citations,
                    in: container,
                    debugDescription: "refusal cannot include citations"
                )
            }
            if container.contains(.highlight) {
                throw DecodingError.dataCorruptedError(
                    forKey: .highlight,
                    in: container,
                    debugDescription: "refusal cannot include highlight"
                )
            }
            let reason = try container.decode(RefusalReason.self, forKey: .reason)
            guard let refusal = Refusal(text: text, reason: reason) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "refusal text must be non-empty"
                )
            }
            self = .refusal(refusal)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .found(found):
            try container.encode(Kind.answer, forKey: .kind)
            try container.encode(found.text, forKey: .text)
            try container.encode(found.citations, forKey: .citations)
            try container.encodeIfPresent(found.highlight, forKey: .highlight)
        case let .refusal(refusal):
            try container.encode(Kind.refusal, forKey: .kind)
            try container.encode(refusal.text, forKey: .text)
            try container.encode(refusal.reason, forKey: .reason)
        }
    }
}
