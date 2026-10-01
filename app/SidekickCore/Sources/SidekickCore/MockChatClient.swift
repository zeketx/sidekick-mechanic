import Foundation

/// Returns contract fixtures after a configurable delay so UI work can run
/// without the backend.
public struct MockChatClient: ChatClient, Sendable {
    public var delay: Duration
    public var selectFixture: @Sendable (Conversation) -> String
    private let fixtures: [String: Answer]

    public init(
        fixtures: [String: Answer],
        delay: Duration = .milliseconds(350),
        selectFixture: @escaping @Sendable (Conversation) -> String = MockChatClient.defaultSelectFixture
    ) {
        self.fixtures = fixtures
        self.delay = delay
        self.selectFixture = selectFixture
    }

    public init(
        fixturesDirectory: URL,
        delay: Duration = .milliseconds(350),
        selectFixture: @escaping @Sendable (Conversation) -> String = MockChatClient.defaultSelectFixture
    ) throws {
        try self.init(
            fixtures: ContractFixtures.load(from: fixturesDirectory),
            delay: delay,
            selectFixture: selectFixture
        )
    }

    public func send(_ conversation: Conversation) async throws -> Answer {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        guard let answer = fixtures[selectFixture(conversation)] else {
            throw ChatClientError.fixturesUnavailable
        }
        return answer
    }

    public static func defaultSelectFixture(_ conversation: Conversation) -> String {
        let text = conversation.lastUserText?.lowercased() ?? ""
        if text.contains("not found") || text.contains("refusal") { return "refusal.json" }
        if text.contains("highlight") { return "with_highlight.json" }
        if text.contains("citation") { return "with_citations.json" }
        return "plain.json"
    }
}

extension Conversation {
    var lastUserText: String? {
        for message in messages.reversed() {
            if case let .user(user) = message {
                return user.text
            }
        }
        return nil
    }
}
