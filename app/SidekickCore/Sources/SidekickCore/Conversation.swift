/// Owner turn. Cannot carry citations or a highlight.
public struct UserMessage: Hashable, Sendable, Identifiable {
    public let id: MessageID
    public let text: String

    public init?(id: MessageID, text: String) {
        guard !text.isEmpty else { return nil }
        self.id = id
        self.text = text
    }
}

/// Sidekick turn. The payload is always an `Answer`.
public struct AssistantMessage: Hashable, Sendable, Identifiable {
    public let id: MessageID
    public let answer: Answer

    public init(id: MessageID, answer: Answer) {
        self.id = id
        self.answer = answer
    }
}

/// One turn in a conversation. A user turn cannot hold an answer.
public enum Message: Hashable, Sendable {
    case user(UserMessage)
    case assistant(AssistantMessage)

    public var id: MessageID {
        switch self {
        case let .user(message):
            return message.id
        case let .assistant(message):
            return message.id
        }
    }
}

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case role
        case id
        case text
        case answer
    }

    private enum Role: String, Codable {
        case user
        case assistant
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(Role.self, forKey: .role)
        let id = try container.decode(MessageID.self, forKey: .id)
        switch role {
        case .user:
            if container.contains(.answer) {
                throw DecodingError.dataCorruptedError(
                    forKey: .answer,
                    in: container,
                    debugDescription: "user message cannot include answer"
                )
            }
            let text = try container.decode(String.self, forKey: .text)
            guard let message = UserMessage(id: id, text: text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "user text must be non-empty"
                )
            }
            self = .user(message)
        case .assistant:
            if container.contains(.text) {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: "assistant text lives on answer, not on the message"
                )
            }
            let answer = try container.decode(Answer.self, forKey: .answer)
            self = .assistant(AssistantMessage(id: id, answer: answer))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch self {
        case let .user(message):
            try container.encode(Role.user, forKey: .role)
            try container.encode(message.text, forKey: .text)
        case let .assistant(message):
            try container.encode(Role.assistant, forKey: .role)
            try container.encode(message.answer, forKey: .answer)
        }
    }
}

/// Ordered chat history sent to `POST /chat` and rendered by the message list.
public struct Conversation: Hashable, Sendable, Identifiable, Codable {
    public let id: ConversationID
    public let messages: [Message]

    public init(id: ConversationID, messages: [Message] = []) {
        self.id = id
        self.messages = messages
    }

    public func appending(_ message: Message) -> Conversation {
        Conversation(id: id, messages: messages + [message])
    }
}
