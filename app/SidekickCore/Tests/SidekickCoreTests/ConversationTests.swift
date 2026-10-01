import Foundation
import XCTest
@testable import SidekickCore

final class ConversationTests: XCTestCase {
    func testUserMessageRejectsEmptyText() {
        XCTAssertNil(UserMessage(id: MessageID(rawValue: "msg-1")!, text: ""))
    }

    func testConversationAppendsMessagesInOrder() throws {
        let conversationID = try XCTUnwrap(ConversationID(rawValue: "convo-1"))
        let user = Message.user(
            try XCTUnwrap(
                UserMessage(
                    id: try XCTUnwrap(MessageID(rawValue: "msg-1")),
                    text: "Rough idle after cold start."
                )
            )
        )
        let assistant = Message.assistant(
            AssistantMessage(
                id: try XCTUnwrap(MessageID(rawValue: "msg-2")),
                answer: .found(
                    try XCTUnwrap(
                        FoundAnswer(text: "This is a fixture-only reply with no manual citations.")
                    )
                )
            )
        )

        let conversation = Conversation(id: conversationID)
            .appending(user)
            .appending(assistant)

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages[0].id.rawValue, "msg-1")
        XCTAssertEqual(conversation.messages[1].id.rawValue, "msg-2")
        guard case .user(let userMessage) = conversation.messages[0] else {
            return XCTFail("first message should be a user turn")
        }
        XCTAssertEqual(userMessage.text, "Rough idle after cold start.")
        guard case .assistant(let assistantMessage) = conversation.messages[1] else {
            return XCTFail("second message should be an assistant turn")
        }
        XCTAssertEqual(
            assistantMessage.answer,
            .found(
                try XCTUnwrap(
                    FoundAnswer(text: "This is a fixture-only reply with no manual citations.")
                )
            )
        )
    }

    func testConversationRoundTripJSON() throws {
        let conversation = Conversation(
            id: try XCTUnwrap(ConversationID(rawValue: "convo-1")),
            messages: [
                .user(
                    try XCTUnwrap(
                        UserMessage(
                            id: try XCTUnwrap(MessageID(rawValue: "msg-1")),
                            text: "Rough idle after cold start."
                        )
                    )
                ),
                .assistant(
                    AssistantMessage(
                        id: try XCTUnwrap(MessageID(rawValue: "msg-2")),
                        answer: .refusal(
                            try XCTUnwrap(
                                Refusal(
                                    text: "Not found in the manual. I do not have a cited page for this."
                                )
                            )
                        )
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(conversation)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded, conversation)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "convo-1")
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["text"] as? String, "Rough idle after cold start.")
        XCTAssertNil(messages[0]["answer"])
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        let answer = try XCTUnwrap(messages[1]["answer"] as? [String: Any])
        XCTAssertEqual(answer["kind"] as? String, "refusal")
        XCTAssertNil(messages[1]["text"])
    }

    func testUserMessageWithAnswerFailsToDecode() {
        let json = Data(
            #"""
            {
              "role": "user",
              "id": "msg-1",
              "text": "Rough idle after cold start.",
              "answer": {
                "kind": "answer",
                "text": "Should not be here.",
                "citations": []
              }
            }
            """#.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(Message.self, from: json))
    }
}
