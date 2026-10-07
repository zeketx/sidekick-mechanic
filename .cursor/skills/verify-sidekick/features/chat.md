# Chat, answer card, and composer

Chat is the home screen: a `#F4F4F4` paper list, a Garage nav button, a pill composer labeled Describe the problem, and assistant turns as answer cards with citation chips and an optional highlight thumb.

## Sub-features

- `chat-empty` shows Describe a problem. and the pill composer on one background color.
- `chat-header` shows Sidekick with plain-text Garage (Jobs / Scan log are later, #114).
- `chat-composer` accepts text and enables Send (`chat.send`).
- `chat-answer` renders an assistant card (`answerCard.found` or `answerCard.refusal`).
- `chat-chip` opens the cited page from `answerCard.chip.0`.

## How to get to it (user POV)

- Default launch with no `-screen` (helper screen id `chat`), after onboarding is completed.
- Choose Garage in the paper header (`chat.garage`). It is not a toolbar item: iOS 26 draws Liquid Glass behind `ToolbarItem` even with `.buttonStyle(.plain)`.
- Type in Describe the problem and choose Send.
- From a job-sheet-collapsed launch, chat is visible above the sheet.

## Driving it with verify-sidekick

Preconditions:

- Doctor reports the app installed on a booted iPhone simulator.
- `GET http://127.0.0.1:8000/openapi.json` is Sidekick Mechanic when you will Send a live message.
- No `-showDemoChrome 1` unless the recipe is the demo banner.
- Helper launches chat with `-sidekick.onboarding.completed YES`.

- **Empty chat.** Run `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens chat`. The shot shows `chat.composer`, `chat.garage`, status bar 9:41, and `#F4F4F4` paper. Titles are readable (no black-on-black).
- **Composer pill.** In that shot the field is a fully rounded pill, not a box, and the color above and below the composer is the same. Fail the checklist if a gray bar and a white bar meet behind it. `run` measures this: corner radius vs half height on `screenshots/chat.png`, again after `testComposerStaysPillWhenMultiline` types a long problem (`taps/taps-composer-multiline.png`), and the colour above / below / left of the field.
- **Header.** Button reads `Garage` as plain text (`chat.garage`) on the `#F4F4F4` paper header, not a toolbar glass pill. Fail if a white capsule or drop shadow sits behind the letters. `design_checks.py` measures a halo around the glyph versus the bar; a style-flag PASS is not enough. At Accessibility XXXL the centered title is hidden so it cannot overlap Garage (`testAccessibilityXXXLHeaderAndHalfSheet`). Do not fail this checkout for missing `chat.jobs` / `chat.scanLog` — those are later (#114).
- **Collapsed sheet on chat.** `--screens job-sheet-collapsed`. Chat remains in the background. Composer may hide once the sheet has a job (`jobSheet.blocksChat` is false only when collapsed). Identifier `jobSheet.collapsed`.
- **Answer card from live send (optional).** Type a question and tap `chat.send` only if you mean to hit `/chat`. Prefer the mock-mode recipe in `.cursor/skills/verify-ios/` for fixture copy `This is a fixture-only reply with no manual citations.`
- **Citation chip.** `--screens citation-page` opens the white sheet for `FAKE-DOC-2JZ · p. 999` with `citation.viewer`, `citation.pageImage`, and `citation.goDeeper`. Or from `--screens job-sheet-half`, tap `jobSheet.chip.0`. `taps` runs `testOpenCitationFromJobChip`: chip → page + Go deeper → Close. Close must leave `jobSheet.half` and the chip. Shots `taps/taps-citation-page.png` then `taps/taps-citation-closed.png`. At Accessibility XXXL, `citation.close` and `citation.title` sit below the status bar / Dynamic Island (`testAccessibilityXXXLHeaderAndHalfSheet`, shot `taps-citation-page-axxxl.png`). There is no Figma export for this sheet yet; list that as a difference.
- **Proof.** `screenshots/chat.png` plus `compare/chat.png` against `features/figma/chat.png` (the #94 collapsed-sheet wireframe until a dedicated chat frame exists). Fill the composer and header rows of the design checklist. The composer and nav-button rows arrive pre-measured in `compare/checklist.md`; check the numbers against the shot.

## Gotchas

- `-showDemoChrome 1` adds Chat/Readings tabs and a demo banner. That is not the v1 chrome. Default shots omit it.
- The composer `TextField` with `axis: .vertical` may appear as a text view in XCUITest. Query `chat.composer` with descendants, not only `textFields`. The chat overlay ignores `.container` (home indicator) but not `.keyboard`, so a long problem stays above the software keyboard. `testComposerStaysPillWhenMultiline` asserts that when a keyboard is present.
- `chat.messageList` needs `.accessibilityElement(children: .contain)` or its identifier replaces child ids. Do not put a container id on the navigation bar (`chat.header` was removed for that reason). Garage lives in the paper header with the nav bar hidden; putting it in a `ToolbarItem` brings iOS 26 Liquid Glass back.
- Composer hiding on Jobs / Scan log is later (#114). On main the composer stays on chat.
- Do not treat `swift test` ChatViewModel tests as this screen.
- `features/figma/chat.png` is the job-sheet-collapsed wireframe. List that as a difference until a real chat Figma export is stored.
