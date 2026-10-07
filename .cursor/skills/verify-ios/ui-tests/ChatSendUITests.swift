import XCTest

/// UI test the owner adds to the `SidekickMechanicUITests` target.
///
/// The test runner is a Mac process. `xcodebuild` does not reliably forward
/// an evidence directory, so verify-ios writes that absolute path to
/// `/tmp/sidekick-verify-ios/evidence-path` before launching the test.
final class ChatSendUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChatSendShowsPlainFixture() throws {
        let app = launch()
        let composer = try composer(in: app)
        composer.tap()
        composer.typeText("Why is it hard to start?")
        try writeShot("chat-composer.png")
        app.buttons["chat.send"].tap()

        let answer = app.descendants(matching: .any)["answerCard.text"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertEqual(answer.label, "This is a fixture-only reply with no manual citations.")
        XCTAssertTrue(app.descendants(matching: .any)["answerCard.found"].exists)
        try writeShot("chat-answer.png")
    }

    func testAnswerCardShowsCitationChip() throws {
        let app = launch()
        let composer = try composer(in: app)
        composer.tap()
        composer.typeText("show the citation please")
        app.buttons["chat.send"].tap()

        let chip = app.descendants(matching: .any)["answerCard.chip.0"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "FAKE-DOC-2JZ · p. 999")
        XCTAssertTrue(app.descendants(matching: .any)["answerCard.found"].exists)
        try writeShot("answer-card.png")
    }

    func testAnswerCardShowsRefusal() throws {
        let app = launch()
        let composer = try composer(in: app)
        composer.tap()
        composer.typeText("this is a refusal not found")
        app.buttons["chat.send"].tap()

        let status = app.descendants(matching: .any)["answerCard.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Not found in the manual")
        let answer = app.descendants(matching: .any)["answerCard.text"]
        XCTAssertEqual(
            answer.label,
            "Not found in the manual. I do not have a cited page for this."
        )
        XCTAssertTrue(app.descendants(matching: .any)["answerCard.refusal"].exists)
        try writeShot("answer-card-refusal.png")
    }

    func testMockModeShowsHighlightSlot() throws {
        let app = launch()
        let composer = try composer(in: app)
        composer.tap()
        composer.typeText("highlight the intake")
        app.buttons["chat.send"].tap()

        let slot = app.descendants(matching: .any)["answerCard.highlight"]
        XCTAssertTrue(slot.waitForExistence(timeout: 5))
        XCTAssertEqual(
            slot.label,
            "Highlight image slot. Photo fake-bay-photo-front. Part fake-part-intake."
        )
        try writeShot("mock-highlight.png")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SIDEKICK_CHAT_CLIENT"] = "mock"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["chat.composer"].waitForExistence(timeout: 5))
        return app
    }

    private func composer(in app: XCUIApplication) throws -> XCUIElement {
        let field = app.textFields["chat.composer"]
        if field.exists {
            return field
        }
        let view = app.textViews["chat.composer"]
        if view.exists {
            return view
        }
        let any = app.descendants(matching: .any)["chat.composer"]
        XCTAssertTrue(any.waitForExistence(timeout: 2))
        return any
    }

    private func writeShot(_ name: String) throws {
        let pointer = URL(fileURLWithPath: "/tmp/sidekick-verify-ios/evidence-path")
        let path = try String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: directory.appendingPathComponent(name))
    }
}
