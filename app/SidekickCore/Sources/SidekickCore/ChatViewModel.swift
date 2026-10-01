import Foundation
import Observation

/// Screen state for the chat message list and composer.
///
/// Send stays disabled until the trimmed composer text is non-empty and no reply is loading.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var conversation: Conversation
    public var composerText: String
    public private(set) var isLoading: Bool
    public private(set) var errorMessage: String?

    @ObservationIgnored private let client: any ChatClient
    @ObservationIgnored private let makeMessageID: @Sendable () -> MessageID

    public var messages: [Message] { conversation.messages }

    public var canSend: Bool {
        !isLoading && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        conversationID: ConversationID,
        messages: [Message] = [],
        composerText: String = "",
        isLoading: Bool = false,
        errorMessage: String? = nil,
        client: any ChatClient,
        makeMessageID: @escaping @Sendable () -> MessageID = ChatViewModel.makeUUIDMessageID
    ) {
        self.conversation = Conversation(id: conversationID, messages: messages)
        self.composerText = composerText
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.client = client
        self.makeMessageID = makeMessageID
    }

    public static func makeUUIDMessageID() -> MessageID {
        let raw = UUID().uuidString
        guard let id = MessageID(rawValue: raw) else {
            preconditionFailure("UUID string is non-empty")
        }
        return id
    }

    /// Appends the trimmed composer text, then the assistant answer from `ChatClient`.
    ///
    /// A `ChatClientError` is shown as `userMessage`. The user turn stays in the list.
    /// Cancellation leaves that turn in place and does not present a backend failure.
    public func send() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !trimmed.isEmpty else { return }
        guard let user = UserMessage(id: makeMessageID(), text: trimmed) else { return }

        conversation = conversation.appending(.user(user))
        composerText = ""
        errorMessage = nil
        isLoading = true
        let outgoing = conversation

        do {
            let answer = try await client.send(outgoing)
            let assistant = AssistantMessage(id: makeMessageID(), answer: answer)
            conversation = conversation.appending(.assistant(assistant))
            isLoading = false
        } catch is CancellationError {
            isLoading = false
        } catch let error as ChatClientError {
            errorMessage = error.userMessage
            isLoading = false
        } catch {
            errorMessage = Self.unknownFailureMessage
            isLoading = false
        }
    }

    static let unknownFailureMessage = "Something went wrong. Try again."
}
