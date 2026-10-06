# Job sheet

The job sheet is a white bottom sheet on dimmed chat: collapsed peek, half with steps and Outcome, full almost to the status bar. Closeout is half height with Worked selected. The outline on the thumb is a polygon, never a box.

## Sub-features

- `job-sheet-collapsed` shows Job · Cold idle, Open, and the photo peek.
- `job-sheet-half` shows the answer, chips, steps, and Outcome (Worked / Partly / Didn't).
- `job-sheet-full` uses the full-height detent.
- `job-sheet-closeout` is half with Outcome = Worked underlined.
- `job-sheet-scrim` dims chat; tap `jobSheet.dim` collapses the sheet when it is not collapsed.
- `job-sheet-drag` moves detents from `jobSheet.handle`.

## How to get to it (user POV)

- Launch `-screen job-sheet-collapsed|job-sheet-half|job-sheet-full|job-sheet-closeout`.
- From Jobs, choose a row (Cold idle). That opens the sheet at half.
- Drag the handle, choose Open / Close, or tap the dimmed chat.

## Driving it with verify-sidekick

Preconditions:

- Doctor is green on a Mac, or you are about to `run` which boots and installs.
- `-demoPhoto hilux` unless the recipe names another photo.
- Feature map for Jobs is [job-history.md](./job-history.md) when the entry point is a row tap.

- **Collapsed.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens job-sheet-collapsed`. Identifiers `jobSheet.collapsed`, `jobSheet.open`, `jobSheet.peek`. Scrim is light. Composer can still show.
- **Half.** `--screens job-sheet-half`. Identifiers `jobSheet.half`, `jobSheet.body`, `jobSheet.outcome`. Outcome labels are Worked, Partly, Didn't. Scrim is stronger. Tap `jobSheet.dim` is enabled.
- **Full.** `--screens job-sheet-full`. Identifier `jobSheet.full`. The sheet reaches the bottom of the screen. Rounded top corners only. No gray strip under the sheet.
- **Closeout.** `--screens job-sheet-closeout`. Half height. `jobSheet.outcome.worked` is selected (underlined).
- **Drag.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh taps` runs `testDragSheetCollapsedToHalf`. Handle `jobSheet.handle`. Result `jobSheet.half`. Shot `taps/taps-sheet-after-drag.png`.
- **Scrim tap.** `testTapScrimCollapsesHalfSheet`. `jobSheet.dim` then `jobSheet.collapsed`. Shot `taps/taps-sheet-after-scrim.png`.
- **Proof.** Side-by-sides `compare/job-sheet-collapsed.png`, `job-sheet-half.png`, `job-sheet-full.png`. Fill the edge-to-edge sheet row. If `JobSheetLayout.horizontalInset` is not 0, that row fails (today it is 8).

## Gotchas

- Full is a detent only. Steps, notes, and tags beyond the two scripted checkboxes stay in later work. Do not fail the shot for missing editors.
- `-showDemoChrome 1` adds tab-bar inset (`bottomChromeInset`). Default shots omit it so the sheet can sit on the home indicator.
- Outcome `Didn't` uses identifier `jobSheet.outcome.didnt` (raw value `didnt`), not `didnt-work`.
- The photo thumb must show a part-shaped outline, not a rectangle, when the job has a photo.
- Closeout has no dedicated #94 wireframe. `features/figma/job-sheet-closeout.png` is the half-frame until a Figma export exists.
