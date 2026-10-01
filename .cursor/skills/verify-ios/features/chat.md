# Chat

Chat is the message list and the composer. The owner describes a problem, taps Send, and the reply appears in the list.

## Sub-features

- `chat-compose` shows the composer and accepts text.
- `chat-send` sends the trimmed text and shows the assistant reply.
- `chat-plain` shows the plain fixture when the message does not ask for a citation, a highlight, or a refusal.

## How to get to it (user POV)

- Launch Sidekick. The navigation title is `Sidekick`.
- The empty list says `Describe a problem.`
- Tap the field `Describe the problem`, type, and tap Send.

## Driving it with verify-ios

Preconditions:

- `python3 .cursor/skills/verify-ios/scripts/verify_ios.py doctor` exits 0.
- Scheme `SidekickMechanic` builds `ChatScreen` with the mock client.

- **Compose.** Run `python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive chat`. The test taps `chat.composer` and types `Why is it hard to start?`. `evidence/latest/chat-composer.png` shows that text before Send.
- **Send.** The same command taps `chat.send`. Within 5 seconds, `answerCard.text` reads `This is a fixture-only reply with no manual citations.` and `answerCard.found` exists. `evidence/latest/chat-answer.png` shows the reply.
- **Whole class.** Run `python3 .cursor/skills/verify-ios/scripts/verify_ios.py run` to drive chat, the answer card, and mock mode together.

## Gotchas

- A multi-line `TextField` can be a text view. The test checks `chat.composer` as a text field, then a text view.
- Send stays disabled until the trimmed composer text is non-empty. Type before looking for an enabled Send button.
- There is no Xcode project in the repo yet. On Linux, and on a Mac until the owner creates the project, doctor exits 2 and the only artifact is `owner-only.json`.
- The words `citation`, `highlight`, `refusal`, and `not found` select other fixtures. This recipe avoids them so the reply stays the plain fixture.
