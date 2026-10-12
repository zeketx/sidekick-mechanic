import Foundation
import XCTest
@testable import SidekickCore

@MainActor
final class PageContextTests: XCTestCase {
    func testStarterTextsAreTheLiterals() {
        XCTAssertEqual(StarterQuestion.allCases.map(\.text), [
            "Explain this page simply",
            "What tools do I need?",
            "Which connector is this?",
        ])
        XCTAssertEqual(StarterQuestion.allCases.filter(\.wantsPlugPhoto), [.whichConnector])
    }

    func testAskAboutPinsThePageOnTheOwningJob() throws {
        let earlier: [Message] = [
            .user(try userMessage("msg-0", "Why is it hard to start?")),
            .assistant(AssistantMessage(id: try messageID("msg-00"), answer: plainAnswer())),
        ]
        let model = makeModel(messages: earlier)
        XCTAssertEqual(model.starterQuestions, [])

        model.askAbout(try fakePage())

        XCTAssertEqual(model.target, .job(try jobID("convo-1")))
        XCTAssertEqual(model.messages, earlier)
        XCTAssertEqual(model.draftAttachment, .page(try fakePage()))
        XCTAssertEqual(model.starterQuestions, StarterQuestion.allCases)

        model.composerText = "typing"
        XCTAssertEqual(model.starterQuestions, [])
        model.composerText = ""
        model.unpinPage()
        XCTAssertNil(model.draftAttachment)
        XCTAssertEqual(model.starterQuestions, [])
    }

    func testStarterSendAppendsAPageAskAndKeepsThePagePinned() async throws {
        let client = ScriptedChatClient(results: [.success(plainAnswer())])
        let model = makeModel(client: client, isDemoMode: true, selectedDemoPhotoID: "FAKE-PHOTO")
        model.askAbout(try fakePage())

        await model.send(.tools)

        XCTAssertEqual(client.sent.count, 1)
        XCTAssertEqual(client.sent[0].id.rawValue, "convo-1")
        XCTAssertEqual(client.sentDemoPhotoIDs, [nil])
        guard case let .user(user) = client.sent[0].messages.last else {
            return XCTFail("expected the user turn last")
        }
        XCTAssertEqual(user.text, "What tools do I need?\nFAKE-DOC · p. 999")
        XCTAssertEqual(user.attachment, .page(try fakePage()))
        XCTAssertEqual(model.draftAttachment, .page(try fakePage()))
        XCTAssertEqual(model.target, .job(try jobID("convo-1")))
        XCTAssertEqual(model.messages.count, 4)
        XCTAssertEqual(try userText(model.messages[2]), "What tools do I need?\nFAKE-DOC · p. 999")
    }

    func testAFollowUpWhilePinnedCarriesThePageOnEveryUserTurn() async throws {
        let client = ScriptedChatClient(results: [.success(plainAnswer()), .success(plainAnswer())])
        let model = makeModel(client: client, isDemoMode: true, selectedDemoPhotoID: "FAKE-PHOTO")
        model.askAbout(try fakePage())
        await model.send(.explainSimply)

        model.composerText = "and this part?"
        await model.send()

        XCTAssertEqual(client.sentDemoPhotoIDs, [nil, nil])
        let followUp = client.sent[1]
        let userPages = followUp.messages.compactMap { message -> PageRef? in
            guard case let .user(user) = message else { return nil }
            return user.attachment?.page
        }
        XCTAssertEqual(userPages, [try fakePage(), try fakePage()])
        guard case let .user(latest) = followUp.messages.last else {
            return XCTFail("expected the follow-up last")
        }
        XCTAssertNil(latest.attachment?.plugPhoto)
        XCTAssertEqual(latest.text, "and this part?\nFAKE-DOC · p. 999")
        let body = ChatHTTPBody(followUp, demoPhotoID: "FAKE-PHOTO")
        let json = try encodedBody(body)
        XCTAssertFalse(json.contains("\"demo\""))
        XCTAssertFalse(json.contains("\"photo\""))
        XCTAssertEqual(json.components(separatedBy: "\"doc_id\":\"FAKE-DOC\"").count - 1, 2)
    }

    func testDemoModeCanSendAPageTurnWithoutABayPhoto() throws {
        let model = makeModel(isDemoMode: true)
        model.composerText = "What does this page say?"
        XCTAssertFalse(model.canSend)

        model.askAbout(try fakePage())

        XCTAssertTrue(model.canSend)
    }

    func testPlugPhotoAppendsIntoTheOwningJobThenThePageStaysPinned() async throws {
        let client = ScriptedChatClient(results: [.success(plainAnswer())])
        let model = makeModel(client: client, isDemoMode: true, selectedDemoPhotoID: "FAKE-PHOTO")
        let photo = try fakePhoto()
        model.askAbout(try fakePage())

        model.attachPlugPhoto(photo)

        XCTAssertEqual(model.composerText, "Which connector is this?")
        XCTAssertEqual(model.draftAttachment, .plugPhoto(photo, page: try fakePage()))
        XCTAssertEqual(model.starterQuestions, [])

        await model.send()

        guard case let .user(user) = client.sent[0].messages.last else {
            return XCTFail("expected the user turn last")
        }
        XCTAssertEqual(user.attachment, .plugPhoto(photo, page: try fakePage()))
        XCTAssertEqual(user.text, "Which connector is this?\nFAKE-DOC · p. 999")
        XCTAssertEqual(client.sentDemoPhotoIDs, [nil])
        XCTAssertEqual(model.draftAttachment, .page(try fakePage()))
        XCTAssertEqual(model.target.jobID?.rawValue, "convo-1")
        let saved = try JSONEncoder().encode(model.messages)
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains(photo.jpegData.base64EncodedString()))
    }

    func testPlugPhotoNeedsAPinnedPage() throws {
        let model = makeModel()

        model.attachPlugPhoto(try fakePhoto())

        XCTAssertNil(model.draftAttachment)
        XCTAssertEqual(model.composerText, "")
    }

    func testPlugPhotoAcceptsOnlyABoundedJPEG() {
        XCTAssertNil(PlugPhoto(jpegData: Data("FAKE-NOT-A-JPEG".utf8)))
        XCTAssertNil(PlugPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0x00])))
        XCTAssertNil(PlugPhoto(jpegData: Data([0xFF, 0xD8, 0xFF]) + Data(count: PlugPhoto.maxBytes) + Data([0xFF, 0xD9])))
        let photo = PlugPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0x46, 0xFF, 0xD9]))
        XCTAssertEqual(photo?.description, "PlugPhoto(6 bytes)")
    }

    func testBodySendsPageIdentityOnUserTurnsAndPhotoBytesOnlyOnTheLast() throws {
        let page = try fakePage()
        let photo = try fakePhoto()
        let conversation = Conversation(
            id: try XCTUnwrap(ConversationID(rawValue: "convo-test")),
            messages: [
                .user(try userMessage("msg-1", "Which connector is this?", attachment: .plugPhoto(photo, page: page))),
                .assistant(AssistantMessage(id: try messageID("msg-2"), answer: plainAnswer())),
                .user(try userMessage("msg-3", "Which connector is this?", attachment: .plugPhoto(photo, page: page))),
            ]
        )

        let json = try encodedBody(ChatHTTPBody(conversation, demoPhotoID: "FAKE-PHOTO"))

        let page999 = #""page":{"doc_id":"FAKE-DOC","page":999}"#
        XCTAssertEqual(json, """
        {"messages":[\
        {\(page999),"role":"user","text":"Which connector is this?"},\
        {"role":"assistant","text":"FAKE-SPEC reply"},\
        {\(page999),"photo":{"data":"\(photo.jpegData.base64EncodedString())","media_type":"image/jpeg"},\
        "role":"user","text":"Which connector is this?"}]}
        """)
    }

    func testBodyKeepsTheDemoPhotoForAGeneralTurnAfterAPageTurn() throws {
        let conversation = Conversation(
            id: try XCTUnwrap(ConversationID(rawValue: "convo-test")),
            messages: [
                .user(try userMessage("msg-1", "Explain this page simply", attachment: .page(try fakePage()))),
                .assistant(AssistantMessage(id: try messageID("msg-2"), answer: plainAnswer())),
                .user(try userMessage("msg-3", "Where is the throttle body?")),
            ]
        )

        let json = try encodedBody(ChatHTTPBody(conversation, demoPhotoID: "FAKE-PHOTO"))

        XCTAssertEqual(json, """
        {"demo":{"photo_id":"FAKE-PHOTO"},"messages":[\
        {"page":{"doc_id":"FAKE-DOC","page":999},"role":"user","text":"Explain this page simply"},\
        {"role":"assistant","text":"FAKE-SPEC reply"},\
        {"role":"user","text":"Where is the throttle body?"}]}
        """)
    }

    func testPageAnswerDoesNotReplaceJobNotes() async throws {
        let client = ScriptedChatClient(results: [.success(plainAnswer())])
        let id = try jobID("convo-1")
        let seeded = JobSheetState(
            id: id,
            title: "Earlier note",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            conversation: Conversation(
                id: ConversationID(rawValue: id.rawValue)!,
                messages: [
                    .user(try userMessage("msg-0", "Why is it hard to start?")),
                    .assistant(AssistantMessage(id: try messageID("msg-00"), answer: plainAnswer())),
                ]
            ),
            outcome: .worked,
            notes: "FAKE-NOTE checked the cover."
        )
        let ids = SequentialMessageIDs(values: ["page-q", "page-a"])
        let jobs = JobsModel(source: .memory([seeded]), client: client, makeID: { ids.next().rawValue })
        let ask = PageAsk(
            messageID: try messageID("page-ask-1"),
            citation: try fakeCitation(),
            question: "Explain this page simply",
            plugPhoto: try fakePhoto()
        )

        let written = try jobs.append(.page(ask), to: .job(id), options: .none)
        XCTAssertEqual(written, id)
        await jobs.waitForReply(in: id)

        XCTAssertEqual(jobs.job(id)?.notes, "FAKE-NOTE checked the cover.")
        XCTAssertEqual(jobs.job(id)?.outcome, .worked)
        XCTAssertEqual(jobs.job(id)?.conversation.messages.count, 4)
        guard case let .user(user) = jobs.job(id)?.conversation.messages[2] else {
            return XCTFail("expected the page ask")
        }
        XCTAssertEqual(user.attachment?.plugPhoto, try fakePhoto())
        XCTAssertEqual(client.sentDemoPhotoIDs, [nil])
    }

    private func makeModel(
        client: any ChatClient = ScriptedChatClient(results: []),
        messages: [Message] = [],
        isDemoMode: Bool = false,
        selectedDemoPhotoID: String? = nil
    ) -> ChatViewModel {
        let ids = SequentialMessageIDs(values: ["msg-1", "msg-2", "msg-3", "msg-4"])
        let seeded = [seededJob(messages: messages)]
        let jobs = JobsModel(
            source: .memory(seeded),
            client: client,
            makeID: { ids.next().rawValue }
        )
        return ChatViewModel(
            jobs: jobs,
            target: .job(seeded[0].id),
            isDemoMode: isDemoMode,
            selectedDemoPhotoID: selectedDemoPhotoID
        )
    }

    private func seededJob(messages: [Message]) -> JobSheetState {
        let id = JobID(rawValue: "convo-1")!
        let history = messages.isEmpty
            ? [Message.user(UserMessage(id: MessageID(rawValue: "seed-user")!, text: "Earlier note")!),
               .assistant(AssistantMessage(id: MessageID(rawValue: "seed-assistant")!, answer: plainAnswer()))]
            : messages
        return JobSheetState(
            id: id,
            title: "Earlier note",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            conversation: Conversation(id: ConversationID(rawValue: id.rawValue)!, messages: history)
        )
    }

    private func fakePage() throws -> PageRef {
        PageRef(
            docID: try XCTUnwrap(DocumentID(rawValue: "FAKE-DOC")),
            page: try XCTUnwrap(PageNumber(rawValue: 999))
        )
    }

    private func fakeCitation() throws -> Citation {
        try XCTUnwrap(Citation(
            docID: XCTUnwrap(DocumentID(rawValue: "FAKE-DOC")),
            page: XCTUnwrap(PageNumber(rawValue: 999)),
            snippet: "FAKE-SNIPPET"
        ))
    }

    private func fakePhoto() throws -> PlugPhoto {
        try XCTUnwrap(PlugPhoto(jpegData: Data([0xFF, 0xD8, 0xFF]) + Data("FAKE-PHOTO".utf8) + Data([0xFF, 0xD9])))
    }

    private func plainAnswer() -> Answer {
        .found(FoundAnswer(text: "FAKE-SPEC reply")!)
    }

    private func jobID(_ raw: String) throws -> JobID {
        try XCTUnwrap(JobID(rawValue: raw))
    }

    private func messageID(_ raw: String) throws -> MessageID {
        try XCTUnwrap(MessageID(rawValue: raw))
    }

    private func userMessage(_ id: String, _ text: String, attachment: TurnAttachment? = nil) throws -> UserMessage {
        try XCTUnwrap(UserMessage(id: messageID(id), text: text, attachment: attachment))
    }

    private func userText(_ message: Message) throws -> String {
        guard case let .user(user) = message else {
            XCTFail("expected a user message")
            throw SampleFailure()
        }
        return user.text
    }

    private func encodedBody(_ body: ChatHTTPBody) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }
}

private struct SampleFailure: Error {}

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
