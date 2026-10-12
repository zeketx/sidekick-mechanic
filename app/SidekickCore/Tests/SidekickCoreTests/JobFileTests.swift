import Foundation
import XCTest
@testable import SidekickCore

private let jobFileNow = Date(timeIntervalSince1970: 1_760_000_000)

@MainActor
final class JobFileTests: XCTestCase {

    func testMissingFileLoadsEmptyAndDoesNotCreateTheFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")

        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobFileNow })

        XCTAssertEqual(jobs.jobs, [])
        XCTAssertEqual(jobs.storage, .saving)
        XCTAssertNil(jobs.notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRoundTripKeepsTheUserTurnAndTheCitedAnswer() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ids = IDSource(prefix: "round")
        let jobs = JobsModel(
            source: .file(.directory(directory)),
            client: ScriptedJobClient(answer: citedAnswer()),
            makeID: { ids.next() },
            now: { jobFileNow }
        )
        let chat = ChatViewModel(jobs: jobs, composerText: "Rough idle after a cold start")
        await chat.send()

        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(try userText(chat.messages[0]), "Rough idle after a cold start")
        XCTAssertEqual(try assistantText(chat.messages[1]), "Fixture reply. FAKE-DOC-2JZ p. 999.")
        XCTAssertEqual(try citation(chat.messages[1]).docID.rawValue, "FAKE-DOC-2JZ")
        XCTAssertEqual(try citation(chat.messages[1]).page.rawValue, 999)

        let relaunched = JobsModel(
            source: .file(.directory(directory)),
            client: IdleJobClient(),
            now: { jobFileNow }
        )
        XCTAssertEqual(relaunched.jobs.count, 1)
        XCTAssertEqual(relaunched.jobs[0].conversation.messages, chat.messages)
        XCTAssertEqual(relaunched.jobs[0].title, "Cold idle")
        let saved = try Data(contentsOf: directory.appendingPathComponent("jobs.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
    }

    func testGoldenVersionOneFileDecodesTheCitedTurns() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")
        try Data(goldenVersionOne.utf8).write(to: url)

        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobFileNow })

        XCTAssertEqual(jobs.jobs.count, 1)
        XCTAssertEqual(jobs.jobs[0].id.rawValue, "job-1")
        XCTAssertEqual(jobs.jobs[0].title, "Rough idle after")
        XCTAssertEqual(jobs.jobs[0].conversation.messages.count, 2)
        XCTAssertEqual(try userText(jobs.jobs[0].conversation.messages[0]), "Rough idle after a cold start")
        XCTAssertEqual(try assistantText(jobs.jobs[0].conversation.messages[1]), "Fixture reply. FAKE-DOC-2JZ p. 999.")
        XCTAssertEqual(try citation(jobs.jobs[0].conversation.messages[1]).docID.rawValue, "FAKE-DOC-2JZ")
        XCTAssertEqual(try citation(jobs.jobs[0].conversation.messages[1]).page.rawValue, 999)
        XCTAssertEqual(jobs.storage, .saving)
    }

    func testCorruptVersionOneBytesAreRenamedAsideAndALaterSaveLeavesThem() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")
        let original = Data("{\"version\":1,\"jobs\":[".utf8)
        try original.write(to: url)

        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobFileNow })
        guard case let .savingAfterSetAside(fileName) = jobs.storage else {
            XCTFail("expected the corrupt file to be set aside, got \(jobs.storage)")
            return
        }
        XCTAssertEqual(jobs.jobs, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let asideURL = directory.appendingPathComponent(fileName)
        XCTAssertEqual(try Data(contentsOf: asideURL), original)
        XCTAssertEqual(
            jobs.notice,
            "Saved jobs could not be opened. A copy was kept on this phone. New jobs save normally."
        )

        let id = try XCTUnwrap(try jobs.append(.typed("Alpha squeak"), to: .newJob, options: .none))
        await jobs.waitForReply(in: id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: asideURL), original)
        XCTAssertEqual(jobs.jobs.map(\.title), ["Alpha squeak"])
        XCTAssertNil(jobs.saveFailure)
    }

    func testVersionTwoBytesStayAtJobsJSONWhenASaveIsAttempted() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")
        let original = Data(#"{"version":2,"jobs":[]}"#.utf8)
        try original.write(to: url)

        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobFileNow })
        XCTAssertEqual(jobs.storage, .notSaving(.newerVersion(found: 2)))
        XCTAssertEqual(jobs.jobs, [])
        XCTAssertEqual(
            jobs.notice,
            "These jobs were saved by a newer version of the app. Update the app to see them. New jobs are not saved until then."
        )

        let id = try jobs.append(.typed("Hello there"), to: .newJob, options: .none)
        XCTAssertEqual(id?.rawValue.isEmpty, false)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(jobs.jobs.map(\.title), ["Hello there"])
    }

    func testUnreadableBytesThatCannotBeMovedAreNotReplaced() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("jobs.json")
        let original = Data("not json".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobFileNow })
        guard jobs.storage == .notSaving(.couldNotSetAside) else {
            throw XCTSkip("This process can rename a read-only directory, so the blocked write cannot be forced.")
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
        let id = try jobs.append(.typed("Hello there"), to: .newJob, options: .none)
        XCTAssertEqual(jobs.jobs.map(\.title), ["Hello there"])
        XCTAssertNotNil(id)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(
            jobs.notice,
            "Saved jobs could not be opened right now. Nothing was changed. New jobs are not saved until the app restarts."
        )
    }

    func testADirectoryAtJobsJSONIsNotReplaced() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let jobs = JobsModel(source: .file(.directory(directory)), client: IdleJobClient(), now: { jobFileNow })
        XCTAssertEqual(jobs.storage, .notSaving(.couldNotRead))
        _ = try jobs.append(.typed("Hello there"), to: .newJob, options: .none)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidekick-jobs-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func citedAnswer() -> Answer {
        .found(
            FoundAnswer(
                text: "Fixture reply. FAKE-DOC-2JZ p. 999.",
                citations: [HighlightViewerScript.fixtureCitation]
            )!
        )
    }

    private func userText(_ message: Message) throws -> String {
        guard case let .user(user) = message else {
            XCTFail("expected a user message")
            throw JobFileTestFailure()
        }
        return user.text
    }

    private func assistantText(_ message: Message) throws -> String {
        guard case let .assistant(assistant) = message else {
            XCTFail("expected an assistant message")
            throw JobFileTestFailure()
        }
        return assistant.answer.text
    }

    private func citation(_ message: Message) throws -> Citation {
        guard case let .assistant(assistant) = message, case let .found(found) = assistant.answer else {
            XCTFail("expected a found answer")
            throw JobFileTestFailure()
        }
        return try XCTUnwrap(found.citations.first)
    }
}

private struct JobFileTestFailure: Error {}

private let goldenVersionOne = """
{
  "jobs" : [
    {
      "conversation" : {
        "id" : "job-1",
        "messages" : [
          {
            "id" : "user-1",
            "role" : "user",
            "text" : "Rough idle after a cold start"
          },
          {
            "answer" : {
              "citations" : [
                {
                  "doc_id" : "FAKE-DOC-2JZ",
                  "page" : 999,
                  "snippet" : "FAKE-SNIPPET"
                }
              ],
              "kind" : "answer",
              "text" : "Fixture reply. FAKE-DOC-2JZ p. 999."
            },
            "id" : "assistant-1",
            "role" : "assistant"
          }
        ]
      },
      "createdAt" : "2026-10-10T19:28:00Z",
      "garagePhotoID" : null,
      "id" : "job-1",
      "notes" : "",
      "outcome" : null,
      "photoID" : null,
      "steps" : [

      ],
      "tags" : [

      ],
      "title" : "Rough idle after",
      "whatFixed" : ""
    }
  ],
  "version" : 1
}
"""

private struct IdleJobClient: ChatClient {
    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        throw ChatClientError.offline
    }
}

private struct ScriptedJobClient: ChatClient {
    var answer: Answer

    func send(_ conversation: Conversation, demoPhotoID: String?) async throws -> Answer {
        _ = conversation
        _ = demoPhotoID
        return answer
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
