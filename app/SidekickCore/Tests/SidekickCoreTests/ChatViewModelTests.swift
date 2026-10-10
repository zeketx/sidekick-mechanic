import Foundation
import XCTest
@testable import SidekickCore

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testSendEnabledOnlyWhenTrimmedTextIsPresentAndIdle() async {
        let idle = makeModel(composerText: "")
        XCTAssertFalse(idle.canSend)

        idle.composerText = "   \n\t"
        XCTAssertFalse(idle.canSend)

        idle.composerText = "  rough idle  "
        XCTAssertTrue(idle.canSend)

        let gate = GateChatClient()
        let loading = makeModel(client: gate, composerText: "rough idle")
        let task = Task { await loading.send() }
        await gate.waitForSend()
        XCTAssertTrue(loading.isLoading)
        XCTAssertFalse(loading.canSend)
        gate.resume(with: .success(plainAnswer()))
        await task.value

        let failedClient = ScriptedChatClient(results: [.failure(ChatClientError.timeout)])
        let failed = makeModel(client: failedClient, composerText: "rough idle")
        await failed.send()
        failed.composerText = "rough idle"
        XCTAssertEqual(failed.errorMessage, ChatClientError.timeout.userMessage)
        XCTAssertTrue(failed.canSend)
    }

    func testEmptySendDoesNotCallTheClient() async {
        let client = ScriptedChatClient(results: [.failure(ChatClientError.offline)])
        let model = makeModel(client: client, composerText: "   \n")
        await model.send()
        XCTAssertTrue(client.sent.isEmpty)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(model.composerText, "   \n")
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testSendWhileLoadingDoesNotStartASecondRequest() async throws {
        let client = GateChatClient()
        let model = makeModel(client: client, composerText: "  hello  ")
        let task = Task { await model.send() }
        await client.waitForSend()

        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.canSend)
        XCTAssertEqual(model.composerText, "")
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(try userText(model.messages[0]), "hello")
        XCTAssertNil(model.errorMessage)

        model.composerText = "second thought"
        await model.send()
        XCTAssertEqual(client.sent.count, 1)
        XCTAssertEqual(model.composerText, "second thought")
        XCTAssertEqual(model.messages.count, 1)

        client.resume(with: .success(plainAnswer()))
        await task.value

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(try assistantAnswer(model.messages[1]), plainAnswer())
        XCTAssertEqual(model.messages[0].id.rawValue, "msg-1")
        XCTAssertEqual(model.messages[1].id.rawValue, "msg-3")
        XCTAssertEqual(model.composerText, "second thought")
        XCTAssertTrue(model.canSend)
        XCTAssertEqual(try userText(client.sent[0].messages[0]), "hello")
        XCTAssertEqual(client.sent[0].id.rawValue, "msg-2")
    }

    func testProviderErrorIsShownAsAnErrorNotAnAnswer() async throws {
        let unavailable = ProviderUnavailable(
            text: "The mechanic is unavailable right now. Try again in a moment."
        )!
        let highlight = HighlightRef(
            bayPhotoID: try XCTUnwrap(BayPhotoID(rawValue: "hrymx-2jz-ge-25308847029")),
            partID: try XCTUnwrap(PartID(rawValue: "intake-plenum")),
            display: .outline,
            isDemo: true
        )
        let refusal = try XCTUnwrap(
            Refusal(text: "Not found in the cited manual text.", highlight: highlight)
        )
        let client = ScriptedChatClient(results: [
            .success(.providerUnavailable(unavailable)),
            .success(.refusal(refusal)),
        ])
        let model = makeModel(client: client, composerText: "where is the fake part")

        await model.send()
        let failedID = try XCTUnwrap(model.target.jobID)

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(try userText(model.messages[0]), "where is the fake part")
        XCTAssertEqual(model.errorMessage, unavailable.text)
        XCTAssertNil(model.job?.highlight)

        model.startNewJob()
        model.composerText = "and the outline"
        await model.send()

        XCTAssertNotEqual(model.target.jobID, failedID)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.job?.answerText, refusal.text)
        XCTAssertEqual(model.job?.highlight, highlight)

        model.open(failedID)
        XCTAssertEqual(model.errorMessage, unavailable.text)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertNil(model.job?.highlight)
    }

    func testMockClientAppendsUserThenFixtureAnswer() async throws {
        let directory = try ContractFixtures.repositoryDirectory()
        let fixtures = try ContractFixtures.load(from: directory)
        let client = try MockChatClient(fixturesDirectory: directory, delay: .zero)
        let model = makeModel(client: client, composerText: "  anything else  ")

        await model.send()

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.composerText, "")
        XCTAssertFalse(model.canSend)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(try userText(model.messages[0]), "anything else")
        XCTAssertEqual(
            try assistantAnswer(model.messages[1]),
            try XCTUnwrap(fixtures["plain.json"])
        )
        XCTAssertEqual(
            try assistantAnswer(model.messages[1]).text,
            "This is a fixture-only reply with no manual citations."
        )
    }

    func testMockClientAppendsRefusalFixture() async throws {
        let directory = try ContractFixtures.repositoryDirectory()
        let fixtures = try ContractFixtures.load(from: directory)
        let client = try MockChatClient(fixturesDirectory: directory, delay: .zero)
        let model = makeModel(client: client, composerText: "this is a refusal not found")

        await model.send()

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(
            try assistantAnswer(model.messages[1]),
            try XCTUnwrap(fixtures["refusal.json"])
        )
        XCTAssertEqual(
            try assistantAnswer(model.messages[1]).text,
            "Not found in the manual. I do not have a cited page for this."
        )
        XCTAssertNil(model.errorMessage)
    }

    func testChatClientErrorSurfacesUserMessage() async throws {
        let client = ScriptedChatClient(results: [.failure(ChatClientError.httpStatus(503))])
        let prior = try userMessage("msg-0", "Earlier note.")
        let model = makeModel(
            client: client,
            messages: [.user(prior)],
            composerText: "  hello  "
        )

        await model.send()

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(
            model.errorMessage,
            "The backend could not complete this request. Try again."
        )
        XCTAssertEqual(model.errorMessage, ChatClientError.httpStatus(503).userMessage)
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(try userText(model.messages[0]), "Earlier note.")
        XCTAssertEqual(try userText(model.messages[1]), "hello")
        XCTAssertEqual(model.composerText, "")
        XCTAssertFalse(model.canSend)
        XCTAssertEqual(client.sent.count, 1)
        XCTAssertEqual(client.sent[0].messages.count, 2)
        XCTAssertEqual(client.sent[0].id.rawValue, "convo-1")
    }

    func testUnknownErrorUsesFallbackCopy() async throws {
        let client = ScriptedChatClient(results: [.failure(SampleFailure())])
        let model = makeModel(client: client, composerText: "hello")

        await model.send()

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.errorMessage, "Something went wrong. Try again.")
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(try userText(model.messages[0]), "hello")
    }

    func testCancellationClearsLoadingWithoutAnError() async throws {
        let model = makeModel(client: SleepingChatClient(), composerText: "hello")
        let task = Task { await model.send() }
        for _ in 0..<10_000 where !model.isLoading {
            await Task.yield()
        }
        XCTAssertTrue(model.isLoading)
        task.cancel()
        await task.value

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(try userText(model.messages[0]), "hello")
    }

    func testFailedSendCanBeFollowedByASuccessfulReply() async throws {
        let directory = try ContractFixtures.repositoryDirectory()
        let fixtures = try ContractFixtures.load(from: directory)
        let client = ScriptedChatClient(results: [
            .failure(ChatClientError.timeout),
            .success(try XCTUnwrap(fixtures["plain.json"])),
        ])
        let ids = SequentialMessageIDs(values: ["msg-1", "msg-2", "msg-3", "msg-4"])
        let model = makeModel(client: client, makeMessageID: { ids.next() })
        model.composerText = "first try"
        await model.send()
        XCTAssertEqual(model.errorMessage, "The backend took too long to respond. Try again.")
        XCTAssertEqual(model.messages.count, 1)

        model.composerText = "second try"
        await model.send()

        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(try userText(model.messages[0]), "first try")
        XCTAssertEqual(try userText(model.messages[1]), "second try")
        XCTAssertEqual(
            try assistantAnswer(model.messages[2]),
            try XCTUnwrap(fixtures["plain.json"])
        )
        XCTAssertEqual(client.sent.count, 2)
        XCTAssertEqual(client.sent[1].messages.count, 2)
        XCTAssertEqual(try userText(client.sent[1].messages[0]), "first try")
        XCTAssertEqual(try userText(client.sent[1].messages[1]), "second try")
    }

    func testDemoModeRequiresAPhotoToSend() {
        let model = makeModel(composerText: "where's the throttle body?", isDemoMode: true)
        XCTAssertFalse(model.canSend)
        model.selectedDemoPhotoID = "hrymx-2jz-ge-25308847029"
        XCTAssertTrue(model.canSend)
        model.isDemoMode = false
        XCTAssertTrue(model.canSend)
        XCTAssertNil(model.activeDemoPhotoID)
    }

    func testSendPassesDemoPhotoIDWhenDemoModeIsOn() async throws {
        let client = ScriptedChatClient(results: [.success(plainAnswer())])
        let model = makeModel(
            client: client,
            composerText: "where's the throttle body?",
            isDemoMode: true,
            selectedDemoPhotoID: "hrymx-2jz-ge-25308847029"
        )
        await model.send()
        XCTAssertEqual(client.sentDemoPhotoIDs, ["hrymx-2jz-ge-25308847029"])
    }

    func testConfirmYesPromotesToOutline() throws {
        let model = makeModel()
        let highlight = HighlightRef(
            bayPhotoID: try XCTUnwrap(BayPhotoID(rawValue: "hrymx-2jz-ge-25308847029")),
            partID: try XCTUnwrap(PartID(rawValue: "intake-plenum")),
            display: .confirm,
            isDemo: true
        )
        let id = try XCTUnwrap(MessageID(rawValue: "msg-1"))
        XCTAssertEqual(model.effectiveDisplay(for: id, highlight: highlight), .confirm)
        model.applyDemoConfirm(messageID: id, decision: .yes)
        XCTAssertEqual(model.effectiveDisplay(for: id, highlight: highlight), .outline)
        model.applyDemoConfirm(messageID: id, decision: .notThis)
        XCTAssertNil(model.effectiveDisplay(for: id, highlight: highlight))
    }

    private func makeModel(
        client: any ChatClient = ScriptedChatClient(results: []),
        messages: [Message] = [],
        composerText: String = "",
        isDemoMode: Bool = false,
        selectedDemoPhotoID: String? = nil,
        makeMessageID: (@Sendable () -> MessageID)? = nil
    ) -> ChatViewModel {
        let ids = SequentialMessageIDs(values: ["msg-1", "msg-2", "msg-3", "msg-4", "msg-5"])
        let makeID = makeMessageID ?? { ids.next() }
        let seeded = messages.isEmpty ? [] : [seededJob(messages: messages)]
        let jobs = JobsModel(
            source: .memory(seeded),
            client: client,
            makeID: { makeID().rawValue }
        )
        let target: ChatTarget = seeded.isEmpty ? .newJob : .job(seeded[0].id)
        return ChatViewModel(
            jobs: jobs,
            target: target,
            composerText: composerText,
            isDemoMode: isDemoMode,
            selectedDemoPhotoID: selectedDemoPhotoID
        )
    }

    private func seededJob(messages: [Message]) -> JobSheetState {
        let id = JobID(rawValue: "convo-1")!
        return JobSheetState(
            id: id,
            title: "Earlier note",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            conversation: Conversation(id: ConversationID(rawValue: id.rawValue)!, messages: messages)
        )
    }

    private func plainAnswer() -> Answer {
        .found(FoundAnswer(text: "FAKE-SPEC reply")!)
    }

    private func userMessage(_ id: String, _ text: String) throws -> UserMessage {
        try XCTUnwrap(UserMessage(id: XCTUnwrap(MessageID(rawValue: id)), text: text))
    }

    private func userText(_ message: Message) throws -> String {
        guard case let .user(user) = message else {
            XCTFail("expected a user message")
            throw SampleFailure()
        }
        return user.text
    }

    private func assistantAnswer(_ message: Message) throws -> Answer {
        guard case let .assistant(assistant) = message else {
            XCTFail("expected an assistant message")
            throw SampleFailure()
        }
        return assistant.answer
    }
}

private struct SampleFailure: Error {}

private struct SleepingChatClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = demoPhotoID
        try await Task.sleep(for: .seconds(30))
        throw ChatClientError.timeout
    }
}

private final class SequentialMessageIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(values: [String]) {
        self.values = values
    }

    func next() -> MessageID {
        lock.lock()
        defer { lock.unlock() }
        return MessageID(rawValue: values.removeFirst())!
    }
}

private final class ScriptedChatClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Answer, Error>]
    private(set) var sent: [Conversation] = []
    private(set) var sentDemoPhotoIDs: [String?] = []

    init(results: [Result<Answer, Error>]) {
        self.results = results
    }

    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        let result: Result<Answer, Error> = {
            lock.lock()
            defer { lock.unlock() }
            sent.append(conversation)
            sentDemoPhotoIDs.append(demoPhotoID)
            return results.removeFirst()
        }()
        return try result.get()
    }
}

private final class GateChatClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Answer, Error>?
    private(set) var sent: [Conversation] = []

    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = demoPhotoID
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            sent.append(conversation)
            waiter = continuation
            lock.unlock()
        }
    }

    func waitForSend() async {
        for _ in 0..<10_000 {
            let count: Int = {
                lock.lock()
                defer { lock.unlock() }
                return sent.count
            }()
            if count > 0 { return }
            await Task.yield()
        }
        XCTFail("timed out waiting for send")
    }

    func resume(with result: Result<Answer, Error>) {
        lock.lock()
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(with: result)
    }
}
