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

/// Chassis and engine copied from the garage, or none.
/// `TBD` is a legal value. Notes and to-dos are not on this value.
public enum AdviceBasis: Hashable, Sendable {
    case none
    case garage(truck: String?, engine: String?)

    public var basisLine: String? {
        guard case let .garage(truck, engine) = self else { return nil }
        var parts: [String] = []
        if let truck {
            parts.append("Truck: \(truck).")
        }
        if let engine {
            parts.append("Engine: \(engine).")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
}

extension AdviceBasis: Codable {
    private enum CodingKeys: String, CodingKey {
        case source
        case truck
        case engine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(String.self, forKey: .source)
        switch source {
        case "none":
            if container.contains(.truck) || container.contains(.engine) {
                throw DecodingError.dataCorruptedError(
                    forKey: .source,
                    in: container,
                    debugDescription: "a none garage has no truck or engine"
                )
            }
            self = .none
        case "garage":
            let truck = try container.decodeIfPresent(String.self, forKey: .truck)
            let engine = try container.decodeIfPresent(String.self, forKey: .engine)
            if let truck, truck.isEmpty {
                throw DecodingError.dataCorruptedError(
                    forKey: .truck,
                    in: container,
                    debugDescription: "truck must be non-empty"
                )
            }
            if let engine, engine.isEmpty {
                throw DecodingError.dataCorruptedError(
                    forKey: .engine,
                    in: container,
                    debugDescription: "engine must be non-empty"
                )
            }
            let hasTruck = truck != nil
            let hasEngine = engine != nil
            guard hasTruck || hasEngine else {
                throw DecodingError.dataCorruptedError(
                    forKey: .source,
                    in: container,
                    debugDescription: "a garage basis needs a truck or an engine"
                )
            }
            self = .garage(truck: truck, engine: engine)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .source,
                in: container,
                debugDescription: "garage source must be none or garage"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .source)
        case let .garage(truck, engine):
            try container.encode("garage", forKey: .source)
            try container.encodeIfPresent(truck, forKey: .truck)
            try container.encodeIfPresent(engine, forKey: .engine)
        }
    }
}

/// Checks when the manual has no page for the question.
/// Honesty and safety are fixed lines, not free text on the payload.
public struct GeneralAdvice: Hashable, Sendable {
    public static let honesty = "Not in your manual. Here's what usually causes this."
    public static let safety = "Safety: Let the engine cool before you touch it. Disconnect the battery when the step calls for it. Support the vehicle on stands before you work underneath."

    public let steps: [String]
    public let garage: AdviceBasis
    public let related: [Citation]
    public let highlight: HighlightRef?

    public var basisLine: String? { garage.basisLine }

    public init?(
        steps: [String],
        garage: AdviceBasis,
        related: [Citation] = [],
        highlight: HighlightRef? = nil
    ) {
        guard (1...5).contains(steps.count) else { return nil }
        guard steps.allSatisfy({ !$0.isEmpty && $0.count <= 500 }) else { return nil }
        if case let .garage(truck, engine) = garage {
            let hasTruck = truck.map { !$0.isEmpty } ?? false
            let hasEngine = engine.map { !$0.isEmpty } ?? false
            guard hasTruck || hasEngine else { return nil }
        }
        self.steps = steps
        self.garage = garage
        self.related = related
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
    case generalAdvice(GeneralAdvice)
    case providerUnavailable(ProviderUnavailable)

    public var text: String {
        switch self {
        case let .found(found):
            return found.text
        case let .refusal(refusal):
            return refusal.text
        case let .generalAdvice(advice):
            var lines = [GeneralAdvice.honesty]
            if let basis = advice.basisLine {
                lines.append(basis)
            }
            lines.append(GeneralAdvice.safety)
            lines.append(contentsOf: advice.steps)
            return lines.joined(separator: "\n")
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
        case let .generalAdvice(advice):
            return advice.highlight
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
        case honesty
        case safety
        case steps
        case garage
        case related
    }

    private enum Kind: String, Codable {
        case answer
        case refusal
        case generalAdvice = "general_advice"
        case error
    }

    private enum ProviderReason: String, Codable {
        case providerUnavailable = "provider_unavailable"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .answer:
            let text = try container.decode(String.self, forKey: .text)
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
            let text = try container.decode(String.self, forKey: .text)
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
        case .generalAdvice:
            if container.contains(.citations) {
                throw DecodingError.dataCorruptedError(
                    forKey: .citations,
                    in: container,
                    debugDescription: "general advice cannot include citations"
                )
            }
            if container.contains(.reason) {
                throw DecodingError.dataCorruptedError(
                    forKey: .reason,
                    in: container,
                    debugDescription: "general advice cannot include reason"
                )
            }
            if container.contains(.text) {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "general advice cannot include text"
                )
            }
            let honesty = try container.decode(String.self, forKey: .honesty)
            guard honesty == GeneralAdvice.honesty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .honesty,
                    in: container,
                    debugDescription: "general advice honesty is a fixed line"
                )
            }
            let safety = try container.decode(String.self, forKey: .safety)
            guard safety == GeneralAdvice.safety else {
                throw DecodingError.dataCorruptedError(
                    forKey: .safety,
                    in: container,
                    debugDescription: "general advice safety is the safety note"
                )
            }
            let steps = try container.decode([String].self, forKey: .steps)
            let garage = try container.decode(AdviceBasis.self, forKey: .garage)
            let related = try container.decode([Citation].self, forKey: .related)
            let highlight = try container.decodeIfPresent(HighlightRef.self, forKey: .highlight)
            guard let advice = GeneralAdvice(
                steps: steps,
                garage: garage,
                related: related,
                highlight: highlight
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .steps,
                    in: container,
                    debugDescription: "general advice needs one to five non-empty steps"
                )
            }
            self = .generalAdvice(advice)
        case .error:
            let text = try container.decode(String.self, forKey: .text)
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
        case let .generalAdvice(advice):
            try container.encode(Kind.generalAdvice, forKey: .kind)
            try container.encode(GeneralAdvice.honesty, forKey: .honesty)
            try container.encode(GeneralAdvice.safety, forKey: .safety)
            try container.encode(advice.steps, forKey: .steps)
            try container.encode(advice.garage, forKey: .garage)
            try container.encode(advice.related, forKey: .related)
            try container.encodeIfPresent(advice.highlight, forKey: .highlight)
        case let .providerUnavailable(unavailable):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(unavailable.text, forKey: .text)
            try container.encode(ProviderReason.providerUnavailable, forKey: .reason)
        }
    }
}
