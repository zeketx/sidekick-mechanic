import Foundation

/// Returns contract fixtures after a configurable delay so UI work can run
/// without the backend.
public struct MockChatClient: ChatClient, Sendable {
    public var delay: Duration
    public var selectFixture: @Sendable (ChatRequest) -> String
    private let fixtures: [String: AnswerContract.Payload]

    public init(
        fixtures: [String: AnswerContract.Payload],
        delay: Duration = .milliseconds(350),
        selectFixture: @escaping @Sendable (ChatRequest) -> String = MockChatClient.defaultSelectFixture
    ) {
        self.fixtures = fixtures
        self.delay = delay
        self.selectFixture = selectFixture
    }

    public init(
        fixturesDirectory: URL,
        delay: Duration = .milliseconds(350),
        selectFixture: @escaping @Sendable (ChatRequest) -> String = MockChatClient.defaultSelectFixture
    ) throws {
        try self.init(
            fixtures: ContractFixtures.load(from: fixturesDirectory),
            delay: delay,
            selectFixture: selectFixture
        )
    }

    public func send(_ request: ChatRequest) async throws -> AnswerContract.Payload {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        guard let payload = fixtures[selectFixture(request)] else {
            throw ChatClientError.fixturesUnavailable
        }
        return payload
    }

    public static func defaultSelectFixture(_ request: ChatRequest) -> String {
        let text = request.messages.last(where: { $0.role == .user })?.text.lowercased() ?? ""
        if text.contains("not found") || text.contains("refusal") { return "refusal.json" }
        if text.contains("highlight") { return "with_highlight.json" }
        if text.contains("citation") { return "with_citations.json" }
        return "plain.json"
    }
}
