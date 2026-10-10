import Foundation

/// Sends a `Conversation` to the backend and returns the shared `Answer` model.
///
/// `demoPhotoID` is demo-mode only. Pass `nil` on the normal path.
public protocol ChatClient: Sendable {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer
}

extension ChatClient {
    public func send(_ conversation: Conversation) async throws -> Answer {
        try await send(conversation, demoPhotoID: nil)
    }
}

public enum ChatClientKind: String, Equatable, Sendable {
    case mock
    case live

    /// `SIDEKICK_CHAT_CLIENT`, then Info.plist `SidekickChatClient`. Defaults to mock.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> ChatClientKind {
        let raw = environment["SIDEKICK_CHAT_CLIENT"]
            ?? infoDictionary?["SidekickChatClient"] as? String
            ?? ChatClientKind.mock.rawValue
        return ChatClientKind(rawValue: raw.lowercased()) ?? .mock
    }
}

public struct ChatClientConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var requestTimeout: TimeInterval

    public static let serverRetryBudget: TimeInterval = 120

    public init(baseURL: URL, requestTimeout: TimeInterval = ChatClientConfiguration.serverRetryBudget) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    public var chatURL: URL {
        baseURL.appendingPathComponent("chat")
    }

    /// `SIDEKICK_BACKEND_URL`, then Info.plist `SidekickBackendURL`. No hardcoded URL.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) throws -> ChatClientConfiguration {
        let raw = environment["SIDEKICK_BACKEND_URL"]
            ?? infoDictionary?["SidekickBackendURL"] as? String
        guard let raw, let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil
        else {
            throw ChatClientError.missingBackendURL
        }
        let timeout = environment["SIDEKICK_BACKEND_TIMEOUT"].flatMap(TimeInterval.init)
            ?? serverRetryBudget
        return ChatClientConfiguration(baseURL: url, requestTimeout: timeout)
    }
}

public enum ChatClients {
    public static func make(
        kind: ChatClientKind,
        configuration: ChatClientConfiguration? = nil,
        mockDelay: Duration = .milliseconds(350),
        fixturesDirectory: URL? = nil
    ) throws -> any ChatClient {
        switch kind {
        case .mock:
            let directory = try fixturesDirectory ?? ContractFixtures.repositoryDirectory()
            return try MockChatClient(fixturesDirectory: directory, delay: mockDelay)
        case .live:
            return LiveChatClient(configuration: try configuration ?? ChatClientConfiguration.load())
        }
    }
}

public enum ChatClientError: Error, Equatable, Sendable, LocalizedError {
    case offline
    case timeout
    case badPayload
    case missingBackendURL
    case httpStatus(Int)
    case fixturesUnavailable

    public var userMessage: String {
        switch self {
        case .offline:
            "No network connection. Check that this device is online and try again."
        case .timeout:
            "The backend took too long to respond. Try again."
        case .badPayload:
            "The backend sent a reply this app could not read."
        case .missingBackendURL:
            "The backend URL is not configured for this build."
        case .httpStatus:
            "The backend could not complete this request. Try again."
        case .fixturesUnavailable:
            "Mock answers could not be loaded."
        }
    }

    public var errorDescription: String? { userMessage }
}

public enum ContractFixtures {
    public static let requiredNames = [
        "plain.json",
        "with_citations.json",
        "with_highlight.json",
        "refusal.json",
    ]

    public static func load(from directory: URL) throws -> [String: Answer] {
        var answers: [String: Answer] = [:]
        for name in requiredNames {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let answer = try? JSONDecoder().decode(Answer.self, from: data)
            else {
                throw ChatClientError.fixturesUnavailable
            }
            answers[name] = answer
        }
        return answers
    }

    public static func repositoryDirectory(startingAt filePath: String = #filePath) throws -> URL {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = url.appendingPathComponent("backend/contracts/fixtures")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            url.deleteLastPathComponent()
        }
        throw ChatClientError.fixturesUnavailable
    }
}
