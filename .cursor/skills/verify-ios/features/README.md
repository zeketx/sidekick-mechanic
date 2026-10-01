# iOS verification map

This directory is the maintained source for the iPhone chat UI. Read it before driving the app, then use the feature file.

Linux cannot run these recipes. `verify-ios` writes `evidence/latest/owner-only.json` and exits 2. That is an unmet precondition, not a verified screen.

## Baseline preconditions

- macOS with Xcode. `xcodebuild` and `xcrun simctl` are on `PATH`.
- `app/SidekickMechanic.xcodeproj` exists, with shared scheme `SidekickMechanic`.
- The app's root view is `ChatScreen`, backed by `ChatClients.make(kind: ChatClientKind.load())`.
- `.cursor/skills/verify-ios/ui-tests/ChatSendUITests.swift` is in target `SidekickMechanicUITests`.
- `python3 .cursor/skills/verify-ios/scripts/verify_ios.py doctor` exits 0.
- The app is built from this repo so mock mode can find `backend/contracts/fixtures`.

## Driving conventions

- Launch with `SIDEKICK_CHAT_CLIENT=mock`. The UI test sets that itself. The code default is already mock.
- Query `chat.composer`, `chat.send`, `answerCard.text`, `answerCard.chip.0`, `answerCard.highlight`, and `answerCard.status` by accessibility identifier.
- Wait for the identifier. Mock mode delays about 350 ms. The test allows 5 seconds.
- `run` drives every feature in this map. `drive <feature>` runs one test method.
- Do not delete screenshots during cleanup.

## Proof and skip reporting

- Each test writes a screenshot after the user action and after the expected text is on screen.
- A Linux `owner-only.json` does not verify a feature. Say which command was attempted and which precondition failed.
- Do not treat `swift test` in `app/SidekickCore` as a substitute for these screenshots.

## Feature entry contract

Each feature file starts with an H1 and one paragraph, then exactly four H2 sections: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify-ios`, and `Gotchas`.

## Features

- [Chat](./chat.md) covers the message list, the composer, and Send.
- [Answer card](./answer-card.md) covers a found answer, citation chips, and the refusal card.
- [Mock mode](./mock-mode.md) covers fixture selection without the backend, including the highlight slot.
