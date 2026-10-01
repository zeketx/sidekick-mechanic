# Mock mode

Mock mode answers from the committed contract fixtures so the UI can run with no backend. The default client kind is mock. `highlight` in the message selects the highlight fixture and shows the bay-photo slot.

## Sub-features

- `mock-default` is the client kind when `SIDEKICK_CHAT_CLIENT` is unset.
- `mock-highlight` shows the highlight slot for a message that contains `highlight`.
- `mock-switch` selects `refusal.json`, `with_highlight.json`, `with_citations.json`, or `plain.json` from the user text.

## How to get to it (user POV)

- Launch the app without a backend URL. Replies still appear.
- Ask to highlight a part. The card shows a bay-photo slot labeled with the fixture photo id and part id.
- Set `SIDEKICK_CHAT_CLIENT=live` only when `SIDEKICK_BACKEND_URL` points at a backend. That path is not this recipe.

## Driving it with verify-ios

Preconditions:

- `python3 .cursor/skills/verify-ios/scripts/verify_ios.py doctor` exits 0.
- The UI test sets `SIDEKICK_CHAT_CLIENT=mock` before launch.
- Fixtures resolve from `backend/contracts/fixtures` in this checkout.

- **Highlight slot.** Run `python3 .cursor/skills/verify-ios/scripts/verify_ios.py drive mock-mode`. The test types `highlight the intake` and taps Send. `answerCard.highlight` reads `Highlight image slot. Photo fake-bay-photo-front. Part fake-part-intake.` Screenshot: `evidence/latest/mock-highlight.png`.
- **Other fixture words.** `show the citation please` is the answer-card drive. `this is a refusal not found` is the refusal drive. `Why is it hard to start?` is the chat drive and stays on `plain.json`.

## Gotchas

- `swift test` in `app/SidekickCore` checks `MockChatClient` fixture selection. It does not show the highlight slot. Keep that result on `verify-backend`. This map is verified only by the screenshot.
- The highlight ids `fake-bay-photo-front` and `fake-part-intake` are fixtures, not a labeled bay photo.
- Mock mode sleeps about 350 ms. Wait for `answerCard.highlight`, not a fixed short sleep in the shell.
- If the fixture directory cannot be found, the composer shows `Mock answers could not be loaded.` That is a failed launch, not a highlight proof.
