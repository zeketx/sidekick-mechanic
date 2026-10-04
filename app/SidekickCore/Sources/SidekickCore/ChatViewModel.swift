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
    public var isDemoMode: Bool
    public var selectedDemoPhotoID: String?
    public var highlightStyle: DemoHighlightStyle
    public private(set) var confirmDecisions: [String: DemoConfirmDecision]

    @ObservationIgnored private let client: any ChatClient
    @ObservationIgnored private let makeMessageID: @Sendable () -> MessageID

    public var messages: [Message] { conversation.messages }

    public var canSend: Bool {
        let hasText = !isLoading && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isDemoMode {
            return hasText && selectedDemoPhotoID != nil
        }
        return hasText
    }

    public var activeDemoPhotoID: String? {
        isDemoMode ? selectedDemoPhotoID : nil
    }

    public init(
        conversationID: ConversationID,
        messages: [Message] = [],
        composerText: String = "",
        isLoading: Bool = false,
        errorMessage: String? = nil,
        isDemoMode: Bool = false,
        selectedDemoPhotoID: String? = nil,
        highlightStyle: DemoHighlightStyle = .outline,
        client: any ChatClient,
        makeMessageID: @escaping @Sendable () -> MessageID = ChatViewModel.makeUUIDMessageID
    ) {
        self.conversation = Conversation(id: conversationID, messages: messages)
        self.composerText = composerText
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.isDemoMode = isDemoMode
        self.selectedDemoPhotoID = selectedDemoPhotoID
        self.highlightStyle = highlightStyle
        self.confirmDecisions = [:]
        self.client = client
        self.makeMessageID = makeMessageID
    }

    public nonisolated static func makeUUIDMessageID() -> MessageID {
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
            let answer = try await client.send(outgoing, demoPhotoID: activeDemoPhotoID)
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

    public func applyDemoConfirm(messageID: MessageID, decision: DemoConfirmDecision) {
        confirmDecisions[messageID.rawValue] = decision
    }

    public func effectiveDisplay(for messageID: MessageID, highlight: HighlightRef?) -> HighlightDisplay? {
        if let decision = confirmDecisions[messageID.rawValue] {
            switch decision {
            case .yes:
                return .outline
            case .notThis:
                return nil
            }
        }
        return highlight?.display ?? (highlight == nil ? nil : .outline)
    }

    static let unknownFailureMessage = "Something went wrong. Try again."
}
