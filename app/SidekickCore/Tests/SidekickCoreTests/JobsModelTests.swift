import Foundation
import XCTest
@testable import SidekickCore

private let jobModelNow = Date(timeIntervalSince1970: 1_760_000_000)

@MainActor
final class JobsModelTests: XCTestCase {

    func testReplyLandsInTheJobThatWasWaitingAfterASwitch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = GateJobClient()
        let ids = IDSource(prefix: "id")
        let jobs = JobsModel(
            source: .file(.directory(directory)),
            client: gate,
            makeID: { ids.next() },
            now: { jobModelNow }
        )
        let chat = ChatViewModel(jobs: jobs)

        chat.composerText = "Alpha squeak"
        let sendA = Task { await chat.send() }
        await gate.waitForSend()
        let a = try XCTUnwrap(chat.target.jobID)
        XCTAssertEqual(jobs.job(a)?.conversation.messages.count, 1)
        XCTAssertEqual(try userText(jobs.job(a)?.conversation.messages[0]), "Alpha squeak")
        XCTAssertEqual(jobs.job(a)?.rowIdentifier, "jobHistory.row.alpha-squeak")

        chat.startNewJob()
        XCTAssertTrue(chat.messages.isEmpty)
        gate.resume(with: .success(citedAnswer("Fixture reply. FAKE-DOC-2JZ p. 999.")))
        await sendA.value

        XCTAssertEqual(jobs.job(a)?.conversation.messages.count, 2)
        XCTAssertEqual(try assistantText(jobs.job(a)?.conversation.messages[1]), "Fixture reply. FAKE-DOC-2JZ p. 999.")
        XCTAssertEqual(try citation(jobs.job(a)?.conversation.messages[1]).docID.rawValue, "FAKE-DOC-2JZ")
        XCTAssertEqual(try citation(jobs.job(a)?.conversation.messages[1]).page.rawValue, 999)
        XCTAssertTrue(chat.messages.isEmpty)

        chat.composerText = "Bravo rattle"
        let sendB = Task { await chat.send() }
        await gate.waitForSend(count: 2)
        gate.resume(with: .failure(ChatClientError.offline))
        await sendB.value

        let b = try XCTUnwrap(chat.target.jobID)
        XCTAssertEqual(jobs.job(b)?.conversation.messages.count, 1)
        XCTAssertEqual(try userText(jobs.job(b)?.conversation.messages[0]), "Bravo rattle")
        XCTAssertEqual(chat.errorMessage, ChatClientError.offline.userMessage)
        XCTAssertEqual(jobs.job(a)?.conversation.messages.count, 2)

        let relaunched = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobModelNow })
        XCTAssertEqual(relaunched.jobs.map(\.title), ["Bravo rattle", "Alpha squeak"])
        XCTAssertEqual(relaunched.job(a)?.conversation.messages.count, 2)
        XCTAssertEqual(relaunched.job(b)?.conversation.messages.count, 1)
        XCTAssertEqual(try userText(relaunched.job(a)?.conversation.messages[0]), "Alpha squeak")
        XCTAssertEqual(try userText(relaunched.job(b)?.conversation.messages[0]), "Bravo rattle")
        XCTAssertEqual(relaunched.job(b)?.conversation.messages.count, 1)
    }

    func testPageAskLandsOnlyInTheCapturedJobAndARepeatDoesNotAddATurn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = GateJobClient()
        let ids = IDSource(prefix: "page")
        let jobs = JobsModel(
            source: .file(.directory(directory)),
            client: gate,
            makeID: { ids.next() },
            now: { jobModelNow }
        )
        let chat = ChatViewModel(jobs: jobs, composerText: "Alpha squeak")
        let sendA = Task { await chat.send() }
        await gate.waitForSend()
        let a = try XCTUnwrap(chat.target.jobID)
        gate.resume(with: .success(citedAnswer("Fixture reply. FAKE-DOC-2JZ p. 999.")))
        await sendA.value

        chat.startNewJob()
        let pageID = MessageID(rawValue: "page-ask-1")!
        let ask = PageAsk(
            messageID: pageID,
            citation: HighlightViewerScript.fixtureCitation,
            question: "What does this page say?"
        )
        let first = try jobs.append(.page(ask), to: .job(a), options: .none)
        XCTAssertEqual(first, a)
        XCTAssertEqual(jobs.job(a)?.conversation.messages.count, 3)
        XCTAssertEqual(
            try userText(jobs.job(a)?.conversation.messages[2]),
            "What does this page say?\nFAKE-DOC-2JZ · p. 999"
        )
        XCTAssertTrue(chat.messages.isEmpty)
        await gate.waitForSend(count: 2)
        let saved = try Data(contentsOf: directory.appendingPathComponent("jobs.json"))

        let second = try jobs.append(.page(ask), to: .job(a), options: .none)
        XCTAssertEqual(second, a)
        XCTAssertEqual(jobs.job(a)?.conversation.messages.count, 3)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("jobs.json")), saved)
        XCTAssertEqual(gate.sent.count, 2)

        chat.composerText = "Bravo rattle"
        let sendB = Task { await chat.send() }
        await gate.waitForSend(count: 3)
        let b = try XCTUnwrap(chat.target.jobID)
        let beforeThrow = try Data(contentsOf: directory.appendingPathComponent("jobs.json"))
        XCTAssertThrowsError(try jobs.append(.page(ask), to: .job(b), options: .none)) { error in
            XCTAssertEqual(
                error as? JobAppendError,
                .messageUsedByAnotherJob(messageID: pageID, jobID: a)
            )
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("jobs.json")), beforeThrow)
        XCTAssertEqual(jobs.job(b)?.conversation.messages.count, 1)
        XCTAssertEqual(try userText(jobs.job(b)?.conversation.messages[0]), "Bravo rattle")
        XCTAssertFalse(jobs.job(b)?.conversation.messages.contains { $0.id == pageID } == true)

        gate.resume(with: .failure(ChatClientError.offline))
        gate.resume(with: .failure(ChatClientError.offline))
        await sendB.value
        await jobs.waitForReply(in: a)
    }

    func testASecondSendWhileWaitingDoesNotStartAnotherReply() async throws {
        let gate = GateJobClient()
        let ids = IDSource(prefix: "flight")
        let jobs = JobsModel(source: .memory([]), client: gate, makeID: { ids.next() }, now: { jobModelNow })
        let chat = ChatViewModel(jobs: jobs, composerText: "Alpha squeak")
        let first = Task { await chat.send() }
        await gate.waitForSend()
        let id = try XCTUnwrap(chat.target.jobID)
        XCTAssertFalse(jobs.canAppend(to: .job(id)))
        XCTAssertNil(try jobs.append(.typed("Second thought"), to: .job(id), options: .none))
        XCTAssertEqual(jobs.job(id)?.conversation.messages.count, 1)
        XCTAssertEqual(gate.sent.count, 1)
        gate.resume(with: .success(citedAnswer("Fixture reply. FAKE-DOC-2JZ p. 999.")))
        await first.value
        XCTAssertEqual(jobs.job(id)?.conversation.messages.count, 2)
    }

    func testAFailedWritePublishesNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobModelNow })
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)

        XCTAssertNil(try jobs.append(.typed("Alpha squeak"), to: .newJob, options: .none))
        XCTAssertEqual(jobs.jobs, [])
        XCTAssertEqual(jobs.saveFailure, "Could not save this job on this phone.")
        XCTAssertEqual(jobs.notice, "Could not save this job on this phone.")
    }

    func testSecondAnswerKeepsOutcomeNotesTagsAndCompletedSteps() async throws {
        let gate = GateJobClient()
        let ids = IDSource(prefix: "keep")
        let jobs = JobsModel(source: .memory([]), client: gate, makeID: { ids.next() }, now: { jobModelNow })
        let chat = ChatViewModel(jobs: jobs, composerText: "Rough idle after a cold start")
        let first = Task { await chat.send() }
        await gate.waitForSend()
        gate.resume(with: .success(hiluxAnswer("First fixture reply. FAKE-DOC-2JZ p. 999.")))
        await first.value
        let id = try XCTUnwrap(chat.target.jobID)

        XCTAssertEqual(jobs.job(id)?.photoID, "commons-hilux-2jz")
        XCTAssertEqual(jobs.job(id)?.tags, ["fuse/relay", "inspected"])
        XCTAssertEqual(jobs.job(id)?.steps.map(\.title), [
            "Look at the fuse/relay box",
            "Next step (from the cited page)",
        ])
        XCTAssertEqual(jobs.job(id)?.steps.map(\.isComplete), [true, false])
        XCTAssertTrue(jobs.edit(id, .outcome(.worked)))
        XCTAssertTrue(jobs.edit(id, .notes("Hoses look dry. No numbers guessed.")))
        XCTAssertTrue(jobs.edit(id, .whatFixed("Cleaned the connector.")))
        XCTAssertTrue(jobs.edit(id, .addTag("cooling")))
        XCTAssertFalse(jobs.edit(id, .addTag("cooling")))
        XCTAssertFalse(jobs.edit(id, .addTag("  ")))
        XCTAssertTrue(jobs.edit(id, .removeTag("inspected")))
        XCTAssertTrue(jobs.edit(id, .step(id: 2, isComplete: true)))
        XCTAssertFalse(jobs.edit(id, .step(id: 99, isComplete: true)))
        XCTAssertEqual(jobs.job(id)?.tags, ["fuse/relay", "cooling"])

        chat.composerText = "Still doing it"
        let second = Task { await chat.send() }
        await gate.waitForSend(count: 2)
        gate.resume(with: .success(prototypeAnswer("Second fixture reply. FAKE-DOC-2JZ p. 999.")))
        await second.value

        XCTAssertEqual(jobs.job(id)?.outcome, .worked)
        XCTAssertEqual(jobs.job(id)?.notes, "Hoses look dry. No numbers guessed.")
        XCTAssertEqual(jobs.job(id)?.whatFixed, "Cleaned the connector.")
        XCTAssertEqual(jobs.job(id)?.tags, ["fuse/relay", "cooling"])
        XCTAssertEqual(jobs.job(id)?.steps.map(\.isComplete), [true, true])
        XCTAssertEqual(jobs.job(id)?.steps.map(\.title), [
            "Look at the fuse/relay box",
            "Next step (from the cited page)",
        ])
        XCTAssertEqual(jobs.job(id)?.photoID, "commons-hilux-2jz")
        XCTAssertEqual(jobs.job(id)?.answerText, "Second fixture reply. FAKE-DOC-2JZ p. 999.")
        XCTAssertEqual(jobs.job(id)?.citations.first?.docID.rawValue, "FAKE-DOC-2JZ")
        XCTAssertEqual(jobs.job(id)?.citations.first?.page.rawValue, 999)
        XCTAssertEqual(jobs.job(id)?.highlight?.partID.rawValue, "throttle-body")
    }

    func testAttachDemoPhotoSetsPhotoIDOnly() async throws {
        let gate = GateJobClient()
        let ids = IDSource(prefix: "photo")
        let jobs = JobsModel(source: .memory([]), client: gate, makeID: { ids.next() }, now: { jobModelNow })
        let chat = ChatViewModel(jobs: jobs, composerText: "Rough idle after a cold start")
        let send = Task { await chat.send() }
        await gate.waitForSend()
        gate.resume(with: .success(hiluxAnswer("Fixture reply. FAKE-DOC-2JZ p. 999.")))
        await send.value
        let id = try XCTUnwrap(chat.target.jobID)
        let beforeHighlight = jobs.job(id)?.highlight
        let beforeAnswer = jobs.job(id)?.answerText
        let beforeTags = jobs.job(id)?.tags
        let beforeSteps = jobs.job(id)?.steps

        XCTAssertTrue(jobs.edit(id, .attachDemoPhoto(photoID: "hrymx-2jz-ge-25308847029")))
        XCTAssertEqual(jobs.job(id)?.photoID, "hrymx-2jz-ge-25308847029")
        XCTAssertEqual(jobs.job(id)?.hasPhoto, true)
        XCTAssertEqual(jobs.job(id)?.highlight, beforeHighlight)
        XCTAssertEqual(jobs.job(id)?.highlight?.bayPhotoID.rawValue, "commons-hilux-2jz")
        XCTAssertEqual(jobs.job(id)?.highlight?.partID.rawValue, "fuse-relay-box")
        XCTAssertEqual(jobs.job(id)?.answerText, beforeAnswer)
        XCTAssertEqual(jobs.job(id)?.tags, beforeTags)
        XCTAssertEqual(jobs.job(id)?.steps, beforeSteps)
        XCTAssertFalse(jobs.edit(id, .attachDemoPhoto(photoID: "hrymx-2jz-ge-25308847029")))
    }

    func testOutcomeIsExclusive() async throws {
        let gate = GateJobClient()
        let ids = IDSource(prefix: "out")
        let jobs = JobsModel(source: .memory([]), client: gate, makeID: { ids.next() }, now: { jobModelNow })
        let chat = ChatViewModel(jobs: jobs, composerText: "Alpha squeak")
        let send = Task { await chat.send() }
        await gate.waitForSend()
        gate.resume(with: .success(citedAnswer("Fixture reply. FAKE-DOC-2JZ p. 999.")))
        await send.value
        let id = try XCTUnwrap(chat.target.jobID)
        XCTAssertNil(jobs.job(id)?.outcome)
        XCTAssertTrue(jobs.edit(id, .outcome(.partly)))
        XCTAssertEqual(jobs.job(id)?.outcome, .partly)
        XCTAssertTrue(jobs.edit(id, .outcome(.didnt)))
        XCTAssertEqual(jobs.job(id)?.outcome, .didnt)
        XCTAssertTrue(jobs.edit(id, .outcome(.worked)))
        XCTAssertEqual(jobs.job(id)?.outcome, .worked)
        XCTAssertFalse(jobs.edit(id, .outcome(.worked)))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidekick-jobs-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func citedAnswer(_ text: String) -> Answer {
        .found(FoundAnswer(text: text, citations: [HighlightViewerScript.fixtureCitation])!)
    }

    private func hiluxAnswer(_ text: String) -> Answer {
        .found(
            FoundAnswer(
                text: text,
                citations: [HighlightViewerScript.fixtureCitation],
                highlight: JobSheetScript.highlight(photoID: "commons-hilux-2jz")
            )!
        )
    }

    private func prototypeAnswer(_ text: String) -> Answer {
        .found(
            FoundAnswer(
                text: text,
                citations: [HighlightViewerScript.fixtureCitation],
                highlight: JobSheetScript.highlight(photoID: "hrymx-2jz-ge-25308847029")
            )!
        )
    }

    private func userText(_ message: Message?) throws -> String {
        guard case let .user(user) = message else {
            XCTFail("expected a user message")
            throw JobsModelTestFailure()
        }
        return user.text
    }

    private func assistantText(_ message: Message?) throws -> String {
        guard case let .assistant(assistant) = message else {
            XCTFail("expected an assistant message")
            throw JobsModelTestFailure()
        }
        return assistant.answer.text
    }

    private func citation(_ message: Message?) throws -> Citation {
        guard case let .assistant(assistant) = message, case let .found(found) = assistant.answer else {
            XCTFail("expected a found answer")
            throw JobsModelTestFailure()
        }
        return try XCTUnwrap(found.citations.first)
    }
}

private struct JobsModelTestFailure: Error {}

private struct IdleJobClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        throw ChatClientError.offline
    }
}

private final class IDSource: @unchecked Sendable {
    private let lock = NSLock()
    private let prefix: String
    private var nextNumber = 0

    init(prefix: String) {
        self.prefix = prefix
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        nextNumber += 1
        return "\(prefix)-\(nextNumber)"
    }
}

private final class GateJobClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Answer, Error>] = []
    private(set) var sent: [Conversation] = []

    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = demoPhotoID
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            sent.append(conversation)
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func waitForSend(count: Int = 1) async {
        for _ in 0..<10_000 {
            let current: Int = {
                lock.lock()
                defer { lock.unlock() }
                return sent.count
            }()
            if current >= count { return }
            await Task.yield()
        }
        XCTFail("timed out waiting for send")
    }

    func resume(with result: Result<Answer, Error>) {
        lock.lock()
        let waiter = waiters.isEmpty ? nil : waiters.removeFirst()
        lock.unlock()
        waiter?.resume(with: result)
    }
}
