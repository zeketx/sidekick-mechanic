# Answer card

The answer card is the assistant bubble. A found answer shows the reply and citation chips. A refusal shows the status `Not found in the manual` and no chips.

## Sub-features

- `answer-card-citation` shows chip `FAKE-DOC-2JZ · page 999` for a citation fixture.
- `answer-card-refusal` shows the refusal status and the refusal body.
- `answer-card-found` uses identifier `answerCard.found` for a found answer and `answerCard.refusal` for a refusal.

## How to get to it (user POV)

- Send a message from the chat composer. The assistant turn is the card.
- Ask for a citation. The card shows a chip with the document id and page.
- Ask for something the mock marks as not found. The card shows `Not found in the manual`.

## Driving it with verify-ios

Preconditions:

- `python3 .cursor/skills/verify-ios/scripts/verify_ios.py doctor` exits 0.
- Mock mode is on. The UI test sets `SIDEKICK_CHAT_CLIENT=mock`.

- **Citation chip.** Run `python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive answer-card`. The test types `show the citation please` and taps Send. `answerCard.chip.0` reads `FAKE-DOC-2JZ · page 999`. `answerCard.found` exists. Screenshot: `evidence/latest/answer-card.png`.
- **Refusal.** Run `python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive refusal`. The test types `this is a refusal not found` and taps Send. `answerCard.status` reads `Not found in the manual`. `answerCard.text` reads `Not found in the manual. I do not have a cited page for this.` `answerCard.refusal` exists. Screenshot: `evidence/latest/answer-card-refusal.png`.

## Gotchas

- The chip label joins the document id and the page with ` · ` (U+00B7). Assert that string, not a hyphen.
- Page `999` and `FAKE-DOC-2JZ` are fixtures. They are not a manual page.
- The refusal status is a SwiftUI `Label`. If the spoken label grows past `Not found in the manual`, the test expectation has to change with it. Do not treat a missing status as a pass.
- Citation snippets are not on this card. The chip is the document id and the page only.
