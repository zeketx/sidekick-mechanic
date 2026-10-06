# Chat, answer card, and composer

Chat is the home screen: a `#F4F4F4` paper list, plain Jobs / Scan log text, a pill composer labeled Describe the problem, and assistant turns as answer cards with citation chips and an optional highlight thumb.

## Sub-features

- `chat-empty` shows Describe a problem. and the pill composer on one background color.
- `chat-header` shows Sidekick with plain-text Jobs and Scan log, not glass capsules.
- `chat-composer` accepts text and enables Send (`chat.send`).
- `chat-answer` renders an assistant card (`answerCard.found` or `answerCard.refusal`).
- `chat-chip` opens the cited page from `answerCard.chip.0`.

## How to get to it (user POV)

- Default launch with no `-screen` (helper screen id `chat`).
- Choose Jobs or Scan log in the paper header.
- Type in Describe the problem and choose Send.
- From a job-sheet-collapsed launch, chat is visible above the sheet.

## Driving it with verify-sidekick

Preconditions:

- Doctor reports the app installed on a booted iPhone simulator.
- `GET http://127.0.0.1:8000/openapi.json` is Sidekick Mechanic when you will Send a live message.
- No `-showDemoChrome 1` unless the recipe is the demo banner.

- **Empty chat.** Run `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens chat`. The shot shows `chat.composer`, `chat.jobs`, `chat.scanLog`, status bar 9:41, and `#F4F4F4` paper. Titles are readable (no black-on-black).
- **Composer pill.** In that shot the field is a fully rounded pill, not a box, and the color above and below the composer is the same. Fail the checklist if a gray bar and a white bar meet behind it. `run` measures this: corner radius vs half height on `screenshots/chat.png`, again after `testComposerStaysPillWhenMultiline` types a long problem (`taps/taps-composer-multiline.png`), and the colour above / below / left of the field. A fixed radius that only looks round on one line fails.
- **Header.** Buttons read `Jobs` and `Scan log` as plain text (`chat.jobs`, `chat.scanLog`). Fail if they are truncated capsules.
- **Collapsed sheet on chat.** `--screens job-sheet-collapsed`. Chat remains in the background. Composer may hide once the sheet has a job (`jobSheet.blocksChat` is false only when collapsed). Identifier `jobSheet.collapsed`.
- **Answer card from live send (optional).** Type a question and tap `chat.send` only if you mean to hit `/chat`. Prefer the mock-mode recipe in `.cursor/skills/verify-ios/` for fixture copy `This is a fixture-only reply with no manual citations.`
- **Proof.** `screenshots/chat.png` plus `compare/chat.png` against `features/figma/chat.png` (the #94 collapsed-sheet wireframe until a dedicated chat frame exists). Fill the composer and header rows of the design checklist. The composer and nav-button rows arrive pre-measured in `compare/checklist.md`; check the numbers against the shot.

## Gotchas

- `-showDemoChrome 1` adds Chat/Readings tabs and a demo banner. That is not the v1 chrome. Default shots omit it.
- The composer `TextField` with `axis: .vertical` may appear as a text view in XCUITest. Query `chat.composer` with descendants, not only `textFields`.
- `chat.jobs` / `chat.scanLog` live in the scroll view's top inset. `chat.messageList` needs `.accessibilityElement(children: .contain)` or its identifier replaces theirs and every Jobs tap test fails with "chat.jobs is missing".
- Do not treat `swift test` ChatViewModel tests as this screen.
- `features/figma/chat.png` is the job-sheet-collapsed wireframe. List that as a difference until a real chat Figma export is stored.
