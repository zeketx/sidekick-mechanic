import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SidekickCore

final class ChatClientTests: XCTestCase {
    func testMockReturnsEachContractFixture() async throws {
        let directory = try ContractFixtures.repositoryDirectory()
        let expected = try ContractFixtures.load(from: directory)
        let client = try MockChatClient(fixturesDirectory: directory, delay: .zero)
        let cases: [(String, String)] = [
            ("anything else", "plain.json"),
            ("show the citation please", "with_citations.json"),
            ("highlight the intake", "with_highlight.json"),
            ("this is a refusal not found", "refusal.json"),
        ]
        for (text, name) in cases {
            let answer = try await client.send(try conversation(text))
            XCTAssertEqual(answer, expected[name], name)
        }
    }

    func testMockDelayIsConfigurable() throws {
        let client = try MockChatClient(
            fixturesDirectory: try ContractFixtures.repositoryDirectory(),
            delay: .milliseconds(250)
        )
        XCTAssertEqual(client.delay, .milliseconds(250))
    }

    func testBackendURLComesFromBuildConfiguration() throws {
        XCTAssertThrowsError(
            try ChatClientConfiguration.load(environment: [:], infoDictionary: nil)
        ) { error in
            XCTAssertEqual(error as? ChatClientError, .missingBackendURL)
            XCTAssertEqual(
                (error as? ChatClientError)?.userMessage,
                "The backend URL is not configured for this build."
            )
        }

        let fromEnv = try ChatClientConfiguration.load(
            environment: ["SIDEKICK_BACKEND_URL": "http://127.0.0.1:8000"],
            infoDictionary: nil
        )
        XCTAssertEqual(fromEnv.chatURL, URL(string: "http://127.0.0.1:8000/chat"))
        XCTAssertEqual(fromEnv.requestTimeout, ChatClientConfiguration.serverRetryBudget)
        XCTAssertEqual(ChatClientConfiguration.serverRetryBudget, 120)

        let fromPlist = try ChatClientConfiguration.load(
            environment: [:],
            infoDictionary: ["SidekickBackendURL": "http://example.test:9"]
        )
        XCTAssertEqual(fromPlist.baseURL, URL(string: "http://example.test:9"))

        XCTAssertEqual(ChatClientKind.load(environment: [:], infoDictionary: nil), .mock)
        XCTAssertEqual(
            ChatClientKind.load(environment: ["SIDEKICK_CHAT_CLIENT": "live"], infoDictionary: nil),
            .live
        )
    }

    func testFactoryMockServesPlainFixture() async throws {
        let client = try ChatClients.make(kind: .mock, mockDelay: .zero)
        let expected = try ContractFixtures.load(from: ContractFixtures.repositoryDirectory())
        let answer = try await client.send(try conversation("hello"))
        XCTAssertEqual(answer, expected["plain.json"])
    }

    func testLivePostsSlimChatBodyAndDecodesAnswer() async throws {
        let http = FakeHTTP(result: .success((
            Data(#"""
            {"kind":"answer","text":"Fixture-only live reply.","citations":[]}
            """#.utf8),
            httpResponse(200)
        )))
        let client = LiveChatClient(
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://example.test:9")!),
            http: http
        )
        let answer = try await client.send(try conversation("hello"))
        XCTAssertEqual(
            answer,
            .found(try XCTUnwrap(FoundAnswer(text: "Fixture-only live reply.")))
        )
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests[0].url, URL(string: "http://example.test:9/chat"))
        XCTAssertEqual(http.requests[0].httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(http.requests[0].httpBody))
        let object = try XCTUnwrap(body as? [String: Any])
        XCTAssertNil(object["id"])
        XCTAssertEqual(
            object["messages"] as? [[String: String]],
            [["role": "user", "text": "hello"]]
        )
        XCTAssertNil(object["demo"])
    }

    func testLivePostsDemoPhotoIDWhenProvided() async throws {
        let http = FakeHTTP(result: .success((
            Data(#"""
            {"kind":"answer","text":"Demo reply.","citations":[]}
            """#.utf8),
            httpResponse(200)
        )))
        let client = LiveChatClient(
            configuration: ChatClientConfiguration(baseURL: URL(string: "http://example.test:9")!),
            http: http
        )
        _ = try await client.send(
            try conversation("where's the throttle body?"),
            demoPhotoID: "hrymx-2jz-ge-25308847029"
        )
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(http.requests[0].httpBody))
        let object = try XCTUnwrap(body as? [String: Any])
        let demo = try XCTUnwrap(object["demo"] as? [String: String])
        XCTAssertEqual(demo["photo_id"], "hrymx-2jz-ge-25308847029")
    }

    func testLiveErrorsMapToUserMessages() async throws {
        let cases: [(Error, ChatClientError, String)] = [
            (URLError(.timedOut), .timeout, "The backend took too long to respond. Try again."),
            (
                URLError(.notConnectedToInternet),
                .offline,
                "No network connection. Check that this device is online and try again."
            ),
            (
                URLError(.cannotConnectToHost),
                .offline,
                "No network connection. Check that this device is online and try again."
            ),
        ]
        for (transport, expected, message) in cases {
            await assertMappedError(transport, expected: expected, message: message)
        }

        let config = ChatClientConfiguration(baseURL: URL(string: "http://example.test:9")!)
        await assertSendError(
            LiveChatClient(
                configuration: config,
                http: FakeHTTP(result: .success((Data(#"{"kind":"unknown"}"#.utf8), httpResponse(200))))
            ),
            expected: .badPayload,
            message: "The backend sent a reply this app could not read."
        )
        await assertSendError(
            LiveChatClient(
                configuration: config,
                http: FakeHTTP(result: .success((Data(), httpResponse(503))))
            ),
            expected: .httpStatus(503),
            message: "The backend could not complete this request. Try again."
        )
    }

    private func conversation(_ userText: String) throws -> Conversation {
        Conversation(
            id: try XCTUnwrap(ConversationID(rawValue: "convo-test")),
            messages: [
                .user(
                    try XCTUnwrap(
                        UserMessage(
                            id: try XCTUnwrap(MessageID(rawValue: "msg-1")),
                            text: userText
                        )
                    )
                ),
            ]
        )
    }

    private func assertMappedError(
        _ transportError: Error,
        expected: ChatClientError,
        message: String
    ) async {
        let http = FakeHTTP(result: .failure(transportError))
        await assertSendError(
            LiveChatClient(
                configuration: ChatClientConfiguration(baseURL: URL(string: "http://example.test:9")!),
                http: http
            ),
            expected: expected,
            message: message
        )
    }

    private func assertSendError(
        _ client: LiveChatClient,
        expected: ChatClientError,
        message: String
    ) async {
        do {
            _ = try await client.send(try conversation("hello"))
            XCTFail("expected \(expected)")
        } catch let error as ChatClientError {
            XCTAssertEqual(error, expected)
            XCTAssertEqual(error.userMessage, message)
            XCTAssertEqual(error.errorDescription, message)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://example.test:9/chat")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

final class FakeHTTP: HTTPPerforming, @unchecked Sendable {
    var result: Result<(Data, URLResponse), Error>
    private(set) var requests: [URLRequest] = []

    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try result.get()
    }
}
