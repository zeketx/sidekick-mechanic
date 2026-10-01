/// Wire types for `backend/contracts/answer.schema.json`.
///
/// Provisional for issue #10. Issue #9 owns the domain model (`Answer`,
/// `Citation`, `HighlightRef`); keep this namespace so those names stay free.
public enum AnswerContract: Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case answer
        case refusal
    }

    public enum RefusalReason: String, Codable, Equatable, Sendable {
        case notFoundInManual = "not_found_in_manual"
    }

    public struct Citation: Codable, Equatable, Sendable {
        public var docId: String
        public var page: Int
        public var snippet: String

        public init(docId: String, page: Int, snippet: String) {
            self.docId = docId
            self.page = page
            self.snippet = snippet
        }

        enum CodingKeys: String, CodingKey {
            case docId = "doc_id"
            case page
            case snippet
        }
    }

    public struct HighlightRef: Codable, Equatable, Sendable {
        public var bayPhotoId: String
        public var partId: String

        public init(bayPhotoId: String, partId: String) {
            self.bayPhotoId = bayPhotoId
            self.partId = partId
        }

        enum CodingKeys: String, CodingKey {
            case bayPhotoId = "bay_photo_id"
            case partId = "part_id"
        }
    }

    public enum Payload: Equatable, Sendable {
        case answer(text: String, citations: [Citation], highlight: HighlightRef?)
        case refusal(text: String, reason: RefusalReason)
    }
}

extension AnswerContract.Payload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case citations
        case highlight
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AnswerContract.Kind.self, forKey: .kind)
        let text = try container.decode(String.self, forKey: .text)
        switch kind {
        case .answer:
            let citations = try container.decode([AnswerContract.Citation].self, forKey: .citations)
            let highlight = try container.decodeIfPresent(
                AnswerContract.HighlightRef.self,
                forKey: .highlight
            )
            self = .answer(text: text, citations: citations, highlight: highlight)
        case .refusal:
            let reason = try container.decode(AnswerContract.RefusalReason.self, forKey: .reason)
            self = .refusal(text: text, reason: reason)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .answer(text, citations, highlight):
            try container.encode(AnswerContract.Kind.answer, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(citations, forKey: .citations)
            try container.encodeIfPresent(highlight, forKey: .highlight)
        case let .refusal(text, reason):
            try container.encode(AnswerContract.Kind.refusal, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(reason, forKey: .reason)
        }
    }
}
