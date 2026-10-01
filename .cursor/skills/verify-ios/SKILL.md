---
name: verify-ios
description: "Drive the Sidekick Mechanic iPhone app on the owner's Mac. xcodebuild, simctl, a UI test that sends a chat message, and screenshots of chat, the answer card, and mock mode. Cloud agents and Linux cannot run it. Use when proving the SwiftUI chat UI."
---

# Verify the Sidekick Mechanic iOS app

Prove the chat screen by building the app, booting a simulator, and running a UI test that types a message and taps Send. This skill runs on the owner's Mac. Linux has no Xcode. A Linux run stops at doctor and writes `evidence/latest/owner-only.json`. That file is a record of the unmet precondition, not a passing UI proof.

There is no `app/SidekickMechanic.xcodeproj` in the repo yet. The owner creates it. Until that project exists, doctor exits 2 on a Mac as well.

## Launch

Owner setup, once:

1. Create `app/SidekickMechanic.xcodeproj` with a shared scheme named `SidekickMechanic`.
2. The app target links `app/SidekickCore` and shows `ChatScreen` as the root view. Build the model with `ChatClients.make(kind: ChatClientKind.load())`. The default kind is mock, which reads `backend/contracts/fixtures`. The app must be built from this repo so that lookup can walk up to those files.
3. Add `.cursor/skills/verify-ios/ui-tests/ChatSendUITests.swift` to a UI test target named `SidekickMechanicUITests`. The class is `ChatSendUITests`.
4. Confirm the deployment target is iOS 17.

Doctor:

```bash
python3 .cursor/skills/verify-ios/scripts/verify_ios.py doctor
```

Exit 0 only on macOS when `xcodebuild` and `xcrun` exist, the project exists, and `xcodebuild -list` shows scheme `SidekickMechanic`.

The full run boots a simulator and runs the UI test class:

```bash
python3 .cursor/skills/verify-ios/scripts/verify_ios.py run
```

Ready means the simulator state is `Booted` and `xcodebuild test` exits 0. The helper prefers an available iPhone 16 simulator, otherwise the first available iPhone. It boots with `xcrun simctl boot` and waits with `xcrun simctl bootstatus <udid> -b`. If that simulator was already booted, the helper leaves it booted.

Do not run two copies. The state file remembers one simulator.

## Doctor

```bash
python3 .cursor/skills/verify-ios/scripts/verify_ios.py doctor
```

This is read-only. It does not boot a simulator and does not install the app. Run it before a drive. On Linux it exits 2.

## Drive

The UI test sets `SIDEKICK_CHAT_CLIENT=mock`, taps `chat.composer`, types, and taps `chat.send`. Mock mode waits about 350 ms. The test waits up to 5 seconds for the answer identifier.

```bash
python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive chat
python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive answer-card
python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive refusal
python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive mock-mode
```

`xcodebuild` invocation inside the helper:

```bash
xcodebuild test \
  -project app/SidekickMechanic.xcodeproj \
  -scheme SidekickMechanic \
  -destination "platform=iOS Simulator,id=<udid>" \
  -only-testing:SidekickMechanicUITests/ChatSendUITests \
  -resultBundlePath .cursor/skills/verify-ios/evidence/latest/ChatSendUITests.xcresult
```

`drive` appends the test method to `-only-testing`. Before `xcodebuild`, the helper writes the absolute evidence directory to `/tmp/sidekick-verify-ios/evidence-path`. The test runner is a Mac process and reads that file when it saves screenshots.

Expected results, all fixture text:

- `chat` — composer text `Why is it hard to start?`, then answer text `This is a fixture-only reply with no manual citations.` and identifier `answerCard.found`.
- `answer-card` — message `show the citation please`, chip label `FAKE-DOC-2JZ · page 999`, identifier `answerCard.chip.0`.
- `refusal` — message `this is a refusal not found`, status `Not found in the manual`, identifier `answerCard.refusal`.
- `mock-mode` — message `highlight the intake`, highlight label `Highlight image slot. Photo fake-bay-photo-front. Part fake-part-intake.`

`run` executes the whole class, which covers those four methods.

## Evidence

Screenshots and the xcodebuild log go to `.cursor/skills/verify-ios/evidence/latest/`.

| File | What it proves |
| --- | --- |
| `chat-composer.png` | Composer filled, before Send |
| `chat-answer.png` | Plain fixture answer on screen |
| `answer-card.png` | Citation chip |
| `answer-card-refusal.png` | Refusal card |
| `mock-highlight.png` | Highlight slot from mock mode |
| `xcodebuild.txt` | Build and test log |
| `owner-only.json` | Written only when doctor cannot run. Not a pass. |

The test writes the PNG from `XCUIScreen.main.screenshot()` after the tap and after the assertion, so the shot is the resulting state, not an empty shell. `FAKE-*` and page 999 are fixtures.

## Cleanup

```bash
python3 .cursor/skills/verify-ios/scripts/verify_ios.py cleanup
```

If this skill booted the simulator, cleanup runs `xcrun simctl shutdown <udid>`. If the simulator was already booted, cleanup leaves it alone. Cleanup deletes `.cursor/skills/verify-ios/run/state.json` and `/tmp/sidekick-verify-ios/evidence-path`. It does not delete `evidence/`.

`run` and `drive` call cleanup in a `finally` block. After that returns, the screenshots must still exist. On Linux, cleanup has no simulator to shut down, and `owner-only.json` must still exist.

## Helpers

```bash
python3 .cursor/skills/verify-ios/scripts/verify_ios.py run
```

The UI test source is `.cursor/skills/verify-ios/ui-tests/ChatSendUITests.swift`. It is not in an Xcode target until the owner adds it.

`app/SidekickCore` tests are the Linux stand-in for mock fixture selection. Run them with `verify-backend` (`swift test`). They do not open the SwiftUI screen. Do not report them as this skill's screenshot proof.

## Maintenance

After the owner adds a screen, run `/maintain-verification-skill` on a Mac and correct this map from a live `run`.
