/// A page-anchored quote from a manual. JSON object keys are `doc_id`, `page`, `snippet`.
public struct Citation: Hashable, Sendable {
    public let docID: DocumentID
    public let page: PageNumber
    public let snippet: String

    public init?(docID: DocumentID, page: PageNumber, snippet: String) {
        guard !snippet.isEmpty else { return nil }
        self.docID = docID
        self.page = page
        self.snippet = snippet
    }
}

extension Citation: Codable {
    enum CodingKeys: String, CodingKey {
        case docID = "doc_id"
        case page
        case snippet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let docID = try container.decode(DocumentID.self, forKey: .docID)
        let page = try container.decode(PageNumber.self, forKey: .page)
        let snippet = try container.decode(String.self, forKey: .snippet)
        guard let citation = Citation(docID: docID, page: page, snippet: snippet) else {
            throw DecodingError.dataCorruptedError(
                forKey: .snippet,
                in: container,
                debugDescription: "snippet must be non-empty"
            )
        }
        self = citation
    }
}
