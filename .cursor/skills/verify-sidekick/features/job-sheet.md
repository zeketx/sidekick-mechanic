# Job sheet

The job sheet is a white bottom sheet on dimmed chat: collapsed peek, half with steps and Outcome, full almost to the status bar. Closeout is half height with Worked selected. The outline on the thumb is a polygon, never a box.

## Sub-features

- `job-sheet-collapsed` shows Job · Cold idle, Open, and the photo peek.
- `job-sheet-half` shows the answer, chips, steps, and Outcome (Worked / Partly / Didn't).
- `job-sheet-full` uses the full-height detent: photo, answer, chips, steps, Notes, Tags (+ add), How did it go?, and What fixed it?.
- `job-sheet-closeout` is half with Outcome = Worked underlined.
- `job-sheet-scrim` dims chat; tap `jobSheet.dim` collapses the sheet when it is not collapsed.
- `job-sheet-drag` moves detents from `jobSheet.handle`.

## How to get to it (user POV)

- Launch `-screen job-sheet-collapsed|job-sheet-half|job-sheet-full|job-sheet-closeout`.
- From Jobs, choose a row (Cold idle). That opens the sheet at half. Jobs is later (#114); on main use `-screen job-sheet-half`.
- Drag the handle, choose Open / Close, or tap the dimmed chat.

## Driving it with verify-sidekick

Preconditions:

- Doctor is green on a Mac, or you are about to `run` which boots and installs.
- `-demoPhoto hilux` unless the recipe names another photo.
- Feature map for Jobs is [job-history.md](./job-history.md) when the entry point is a row tap. That path is later (#114).

- **Collapsed.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens job-sheet-collapsed`. Identifiers `jobSheet.collapsed`, `jobSheet.open`, `jobSheet.peek`. Scrim is light. Composer can still show.
- **Half.** `--screens job-sheet-half`. Identifiers `jobSheet.half`, `jobSheet.body`, `jobSheet.outcome`. Outcome labels are Worked, Partly, Didn't. Scrim is stronger. Tap `jobSheet.dim` is enabled.
- **Full.** `--screens job-sheet-full`. Identifier `jobSheet.full`. The sheet reaches the bottom of the screen. Rounded top corners only. No gray strip under the sheet. Title + Close sit below the status bar / Dynamic Island (`jobSheet.notes`, `jobSheet.tags`, `jobSheet.tags.add`, `jobSheet.outcome.*`, `jobSheet.whatFixed`).
- **Closeout.** `--screens job-sheet-closeout`. Half height. `jobSheet.outcome.worked` is selected (underlined).
- **Drag.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh taps` runs `testDragSheetCollapsedToHalf`. Handle `jobSheet.handle`. Result `jobSheet.half`. Shots `taps/taps-sheet-before-drag.png` then `taps/taps-sheet-after-drag.png`.
- **Scrim tap.** `testTapScrimCollapsesHalfSheet`. `jobSheet.dim` then `jobSheet.collapsed`. Shots `taps/taps-sheet-before-scrim.png` then `taps/taps-sheet-after-scrim.png`.
- **Proof.** Side-by-sides `compare/job-sheet-collapsed.png`, `job-sheet-half.png`, `job-sheet-full.png`. The edge-to-edge row is measured per shot in `compare/checklist.md` (first white pixel from each side, gap under the sheet at full, scrim colour). `JobSheetLayout.horizontalInset` is `0` on main; re-measure. Quoted 8 pt frames were from the #114 Mac proof, not this checkout.

## Gotchas

- Full paper is edge to edge, including under the status-bar band. Header content uses the top safe-area inset so title + Close are not under the Dynamic Island. Notes, tags, How did it go?, and What fixed it? are on this detent.
- `-showDemoChrome 1` adds tab-bar inset (`bottomChromeInset`). Default shots omit it so the sheet can sit on the home indicator.
- Outcome `Didn't` uses identifier `jobSheet.outcome.didnt` (raw value `didnt`), not `didnt-work`. The `jobSheet.outcome` row needs `.accessibilityElement(children: .contain)` or it hides all three.
- There is no `jobSheet` id on the sheet body. The detent ids carry the sheet frame. Re-measure on main (`horizontalInset` is 0). The checklist prints those frames next to the pixel scan.
- The photo thumb must show a part-shaped outline, not a rectangle, when the job has a photo.
- Closeout has no dedicated #94 wireframe. `features/figma/job-sheet-closeout.png` is the half-frame until a Figma export exists.
