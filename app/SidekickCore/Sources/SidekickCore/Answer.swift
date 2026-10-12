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

/// A "not found in the manual" reply. Cannot carry citations.
/// A demo outline may ride along. The refusal text stays the refusal text.
public struct Refusal: Hashable, Sendable {
    public let text: String
    public let reason: RefusalReason
    public let highlight: HighlightRef?

    public init?(
        text: String,
        reason: RefusalReason = .notFoundInManual,
        highlight: HighlightRef? = nil
    ) {
        guard !text.isEmpty else { return nil }
        self.text = text
        self.reason = reason
        self.highlight = highlight
    }
}

/// The provider failed. This is not a manual answer.
public struct ProviderUnavailable: Hashable, Sendable {
    public let text: String

    public init?(text: String) {
        guard !text.isEmpty else { return nil }
        self.text = text
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
    case providerUnavailable(ProviderUnavailable)

    public var text: String {
        switch self {
        case let .found(found):
            return found.text
        case let .refusal(refusal):
            return refusal.text
        case let .providerUnavailable(unavailable):
            return unavailable.text
        }
    }

    public var highlight: HighlightRef? {
        switch self {
        case let .found(found):
            return found.highlight
        case let .refusal(refusal):
            return refusal.highlight
        case .providerUnavailable:
            return nil
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
        case error
    }

    private enum ProviderReason: String, Codable {
        case providerUnavailable = "provider_unavailable"
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
            let reason = try container.decode(RefusalReason.self, forKey: .reason)
            let highlight = try container.decodeIfPresent(HighlightRef.self, forKey: .highlight)
            guard let refusal = Refusal(text: text, reason: reason, highlight: highlight) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "refusal text must be non-empty"
                )
            }
            self = .refusal(refusal)
        case .error:
            if container.contains(.citations) {
                throw DecodingError.dataCorruptedError(
                    forKey: .citations,
                    in: container,
                    debugDescription: "provider error cannot include citations"
                )
            }
            if container.contains(.highlight) {
                throw DecodingError.dataCorruptedError(
                    forKey: .highlight,
                    in: container,
                    debugDescription: "provider error cannot include highlight"
                )
            }
            _ = try container.decode(ProviderReason.self, forKey: .reason)
            guard let unavailable = ProviderUnavailable(text: text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "provider error text must be non-empty"
                )
            }
            self = .providerUnavailable(unavailable)
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
            try container.encodeIfPresent(refusal.highlight, forKey: .highlight)
        case let .providerUnavailable(unavailable):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(unavailable.text, forKey: .text)
            try container.encode(ProviderReason.providerUnavailable, forKey: .reason)
        }
    }
}
