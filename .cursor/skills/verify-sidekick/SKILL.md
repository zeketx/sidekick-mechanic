---
name: verify-sidekick
description: "Drive the Sidekick Mechanic SwiftUI iPhone app on a Mac: xcodebuild for the iPhone 17 Pro simulator, simctl -screen launches, XCUITest taps, screenshots vs Figma, and the standing design checklist. Use when changing Sidekick UI. Linux stops at doctor."
---

# Verify Sidekick Mechanic (iPhone)

Prove a UI change by driving the real app: build it, boot the simulator, open the screen the way a user would (launch arguments, then real taps), screenshot it at 9:41, put that shot next to the Figma frame, and fill the design checklist. Do not report done without those files.

This skill runs on a **macOS host** with Xcode. This cloud VM is Linux and has no iOS Simulator. A Linux run stops at doctor, writes `artifacts/verify/<run-id>/owner-only.json`, and may stitch a committed screenshot against a Figma ref. That file is an unmet precondition, not a passing UI proof. End-to-end proof is still pending on Zeke's Mac.

The older `.cursor/skills/verify-ios/` skill covers mock-mode chat send. Reach for **this** skill for v1 screens (onboarding, chat, job sheet, highlight viewer, Jobs, Scan log).

The iOS Simulator is a shared machine. Do not start a second verify-sidekick run against the same sim. Do not drive a simulator session the owner is using unless doctor says it already has `com.zeketx.SidekickMechanic` from this checkout.

## Launch

Target: Xcode 26.0.1, iPhone 17 Pro, iOS 26.0, scheme `SidekickMechanic`, bundle id `com.zeketx.SidekickMechanic`. Build Debug with `CODE_SIGNING_ALLOWED=NO`. Swift 6 strict concurrency is on (`SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete` in `app/project.yml` and the pbxproj).

From the repository root, first command on a Mac:

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor
```

Doctor exits 1 before the first run if the simulator is not booted, the app is not installed, or :8000 is down. That is expected: `pending_for_run` in its JSON lists what `run` will do about it. Only exit 2 (owner-only: no Xcode, Linux, missing scheme) blocks a run.

Full run (build, boot, each `-screen`, taps, Figma stitch, measured checklist, cleanup). This one line is the whole UI proof:

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh run
```

`run` exit codes: `0` harness and taps passed, no measured design FAIL (REVIEW cells still need you); `1` build, launch or a tap test failed (screenshots, side-by-sides and checklist are still written); `2` owner-only; `3` harness and taps passed but the design checklist has measured FAIL rows. It takes about 4–5 minutes on an M-series Mac (build, onboarding + chat + highlight + job sheet + citation page + Jobs + Scan log, UI tests).

The last lines print the taps result, each failed test, and the checklist verdict with its path. Read `artifacts/verify/latest/compare/checklist.md` and open every `compare/<screen>.png` before reporting.

Ready means all of these are true:

- `xcodebuild -version` reports Xcode 26 (warn if it does not; still drive if an iPhone simulator exists).
- `xcrun simctl` shows the chosen iPhone as `Booted`.
- `xcrun simctl get_app_container <udid> com.zeketx.SidekickMechanic` succeeds after install.
- `GET http://127.0.0.1:8000/openapi.json` returns title `Sidekick Mechanic`.
- Screenshots for the requested screens exist under `artifacts/verify/<run-id>/screenshots/`.

The helper prefers iPhone 17 Pro on iOS 26.0, then any iPhone 17, then the first available iPhone. It boots with `xcrun simctl boot` and waits with `xcrun simctl bootstatus <udid> -b`. If that simulator was already booted, it leaves it booted.

Backend, from `backend/` when port 8000 is free and doctor does not already see the app:

```bash
python3 -m pip install -r backend/requirements.txt
uvicorn app:app --host 127.0.0.1 --port 8000
```

`run` starts that uvicorn itself when :8000 is free, records the pid, and stops only that pid. If something already answers on :8000 with title `Sidekick Mechanic` (for example the PR #92 demo backend from another checkout), `run` uses it and leaves it running. `GET /demo/photos` is on PR #92 (`cursor/demo-mode-backend-27ef`), which is not in this UI stack. Highlights still render from placeholder images. Doctor records demo-photos as false in that case; it is not a hard fail.

Launch arguments (parsed in `DemoLaunchOptions` / `OnboardingLaunchOptions`). Pass them after the bundle id with `simctl launch`, or as XCTest `launchArguments`.

| Arg | What it opens |
| --- | --- |
| `-screen onboarding-1\|2\|3` plus `-resetOnboarding` | First-open pages (#111). Default `run` captures these. |
| `-sidekick.onboarding.completed YES` | UserDefaults key `sidekick.onboarding.completed`. Required on every non-onboarding launch so first-open does not steal the shot. |
| `-screen highlight-confident\|highlight-unsure\|highlight-not-found\|highlight-reference` | Full-bleed highlight card. `-screen highlight-unsure` also turns on the internal unsure flag. |
| `-screen job-sheet-collapsed\|job-sheet-half\|job-sheet-full\|job-sheet-closeout` | Job sheet detents. Closeout is half height with Outcome = Worked. |
| `-screen citation-page` | White citation sheet for `FAKE-DOC-2JZ · p. 999` plus Go deeper. Also opens the job sheet at half so Close returns to the job. |
| `-screen job-history` | Jobs list. Also pass `-sidekick.onboarding.completed YES`. |
| `-screen scan-log` | Scan log grid. Also pass `-sidekick.onboarding.completed YES`. |
| `-demoPhoto hilux\|supra\|hrymx\|flickr` | Demo bay photo. Default `hilux` → `commons-hilux-2jz`. |
| `-showDemoChrome 1` | Demo toggle, demo banner, Chat/Readings tabs. |
| `-dynamicTypeSize accessibility5` | Accessibility XXXL. UI tests use this for `testAccessibilityXXXLHeaderAndHalfSheet`. |
| `-flagUnsureHighlight 1` | Internal unsure card. Off in v1 unless the screen is `highlight-unsure`. |

The helper terminates the app between `-screen` launches and waits (2.5–4 s) so the next shot is that screen, not a leftover cover. Every non-onboarding screen also gets `-sidekick.onboarding.completed YES`.

Teardown: `verify-ios.sh cleanup`. See Cleanup.

## Doctor

Read-only. Does not boot a simulator, install the app, or start uvicorn. A standalone doctor writes `artifacts/verify/doctor/doctor.json` and does not move `latest`, so `compare` still finds the last run.

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor
```

Exit 0 only on macOS when Xcode is present, scheme `SidekickMechanic` lists, the preferred (or fallback) iPhone is **Booted**, this checkout's app is installed, and `GET /openapi.json` on :8000 is Sidekick Mechanic. Otherwise exit 1 with `pending_for_run` (not a blocker; `run` fixes those). On Linux it exits 2 and writes `owner-only.json`.

The JSON always includes `git.branch`, `git.sha`, `xcodebuild` version when available, simulator name/udid/state, `app_installed`, and `backend.openapi` / `backend.demo_photos`.

Run doctor first whenever anything looks off, and again after a failed drive.

## Drive

Stable handles are accessibility identifiers on the views, not coordinates.

### Launch-arg screens (simctl)

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens
.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens onboarding-1,chat,job-sheet-half
```

Inside the helper, after install and `simctl status_bar override --time 9:41`:

```bash
xcrun simctl terminate <udid> com.zeketx.SidekickMechanic
xcrun simctl launch <udid> com.zeketx.SidekickMechanic -resetOnboarding -screen onboarding-1
# wait
xcrun simctl io <udid> screenshot artifacts/verify/<run-id>/screenshots/onboarding-1.png
```

`screens` leaves the simulator running so you can inspect. `run` calls cleanup.

### Real taps (XCUITest)

Launch args cannot open the Garage sheet, skip onboarding, drag the sheet, tap the scrim, or type in the composer. Those go through `app/SidekickMechanicUITests/DriveUITests.swift` on target `SidekickMechanicUITests`. Before `xcodebuild test`, the helper uninstalls `com.zeketx.SidekickMechanicUITests.xctrunner` (and the UI test bundle) so a newly added method is not skipped by a stale runner. A tap failure does not stop `run`: it records `taps/result.json` (passed / failed / skipped tests and the assertion lines), still stitches and measures, then exits 1. **0 tests executed is also exit 1**, not a pass. Jobs / Scan log tests run on this checkout (`testOpenJobsThenColdIdleRow`, `testScanLogFromJobsHeader`).

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh taps
```

`xcodebuild` inside the helper:

```bash
xcodebuild test \
  -project app/SidekickMechanic.xcodeproj \
  -scheme SidekickMechanic \
  -destination "platform=iOS Simulator,id=<udid>" \
  -derivedDataPath /tmp/sidekick-verify-sidekick/DerivedData \
  -only-testing:SidekickMechanicUITests/DriveUITests \
  -resultBundlePath artifacts/verify/<run-id>/taps/DriveUITests.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

| Test | User action | Identifier | Expected |
| --- | --- | --- | --- |
| `testSkipOnboardingIfPresent` | `-resetOnboarding -screen onboarding-1`, Skip | `onboarding.welcome`, `onboarding.skip` | `chat.composer`. XCTSkip if onboarding is absent. |
| `testOpenGarageIfPresent` | Chat → Garage | `chat.garage` | `onboarding.garage`, dismiss `garage.done`. XCTSkip if Garage is absent. |
| `testOpenJobsThenColdIdleRow` | Chat → Jobs → Cold idle | `chat.jobs`, `jobHistory.row.cold-idle` | `jobSheet.half` plus the dark job-sheet scrim |
| `testDragSheetCollapsedToHalf` | Drag the sheet handle up | `jobSheet.handle` | `jobSheet.collapsed` → `jobSheet.half` |
| `testTapScrimCollapsesHalfSheet` | Tap the dimmed chat | `jobSheet.dim` | `jobSheet.half` → `jobSheet.collapsed` |
| `testScanLogFromJobsHeader` | Jobs → Scan log | `jobHistory.scanLog` | `scanLog.grid` |
| `testOpenCitationFromJobChip` | Half sheet → tap `jobSheet.chip.0` → Close | `citation.viewer`, `citation.goDeeper`, `citation.close` | Page + Go deeper, then `jobSheet.half` still there. Shots `taps-citation-page.png`, `taps-citation-closed.png`. |
| `testComposerStaysPillWhenMultiline` | Tap the composer, type a long problem | `chat.composer` | `taps/taps-composer-multiline.png` + `taps/layout-composer-multiline.json` for the pill check |
| `testRecordLayoutFrames` | Launch chat, collapsed / half / full (Jobs if present) | leaf ids per screen | `taps/layout-frames.json` (points) for the composer and nav-button checks |
| `testIdentifierAudit` | Launch each screen | every id listed under Identifiers | `taps/identifiers.json` found / missing / skipped; fails if a documented-on-this-checkout id is unreachable |
| `testAccessibilityXXXLHeaderAndHalfSheet` | `-dynamicTypeSize accessibility5` on chat, Jobs, Scan log, job-sheet-half, job-sheet-closeout, citation-page | `chat.garage`, `chat.jobs`, `chat.scanLog`, `lookBack.back`, `lookBack.title`, `jobSheet.title`, `jobSheet.close`, `jobSheet.step.2`, `jobSheet.outcome.worked`, `citation.close`, `citation.document` | Garage / Jobs / Scan log stay hittable; look-back Back and title sit below the island; last step fully visible above Outcome; Worked is tappable; job and citation headers sit below the island |

The drag uses a vector from `jobSheet.handle`, not a raw screen coordinate of the sheet. The drag and scrim tests also save a before shot (`taps-sheet-before-drag.png`, `taps-sheet-before-scrim.png`). Every test launches with `-sidekick.onboarding.completed YES` unless it passes an onboarding flag itself.

SwiftUI trap that broke three of these tests on the first Mac run (on the #114 stack): `.accessibilityIdentifier` on a container **overwrites every child identifier** unless the container has `.accessibilityElement(children: .contain)` first. `chat.messageList` swallowed header buttons, `jobSheet.outcome` swallowed the Worked / Partly / Didn't ids, `highlightViewer` swallowed its close button, `onboarding.onboarding-1` would swallow Skip / Next. A plain `VStack` with `.contain` can also drop out of the tree entirely, which is why `chat.header` and `jobSheet` were never added on this branch. Put new ids on leaves, add `.contain` to any container id, and let `testIdentifierAudit` catch regressions.

If `xcodegen generate` is run from `app/project.yml`, it recreates the UI test target. The committed `app/SidekickMechanic.xcodeproj` already includes it so a Mac without XcodeGen can still `xcodebuild test`.

### Identifiers (this checkout)

Chat: `chat.garage`, `chat.jobs`, `chat.scanLog`, `chat.composer`, `chat.send`, `chat.messageList`, `chat.attach` (only when attach is shown), `demo.toggle` (`-showDemoChrome 1`).

Onboarding: `onboarding.welcome`, `onboarding.howItWorks`, `onboarding.garage`, `onboarding.skip`, `onboarding.next`, `onboarding.start`, `garage.done`. Root id `onboarding.onboarding-1` (etc.) uses `.contain` so those leaves stay reachable.

Job sheet: `jobSheet.collapsed` / `.half` / `.full` (the sheet frame itself; `horizontalInset` is 0 on main), `jobSheet.handle`, `jobSheet.title`, `jobSheet.peek`, `jobSheet.open` / `.close`, `jobSheet.dim`, `jobSheet.body`, `jobSheet.answer`, `jobSheet.photo`, `jobSheet.chips`, `jobSheet.chip.0`, `jobSheet.steps`, `jobSheet.outcome`, `jobSheet.outcome.worked` / `.partly` / `.didnt`. Full also has `jobSheet.notes`, `jobSheet.tags`, `jobSheet.tags.add`, `jobSheet.whatFixed`.

Citation sheet: `citation.viewer`, `citation.close`, `citation.title`, `citation.document`, `citation.pageNumber`, `citation.pageImage`, `citation.goDeeper`, `citation.snippet`.

Highlight: `highlightViewer`, `highlightViewer.close`, `highlightViewer.photo`, `demo.confirm.yes` / `.notThis`.

Jobs / scan log: `jobHistory.list`, `jobHistory.row.cold-idle`, `lookBack.back`, `lookBack.title`, `jobHistory.scanLog`, `scanLog.grid`, `scanLog.cell.scan-log-0`.

Recipes for each feature: [features/README.md](features/README.md).

## Evidence

Proof goes to `artifacts/verify/<run-id>/` (gitignored). `latest` is a symlink to the last run. Cleanup must not delete this tree.

| Path | What it proves |
| --- | --- |
| `doctor.json` | Xcode, sim, app, backend, branch, SHA |
| `manifest.json` | Command, git, shot lists, taps result and checklist verdict |
| `screenshots/<screen>.png` | That `-screen` after terminate + wait, status bar 9:41 |
| `screenshots/citation-page.png` | Cited page + Go deeper (`-screen citation-page`) |
| `taps/result.json` | Which UI tests passed / failed / skipped, assertion lines |
| `taps/taps-jobs-list.png` | Jobs list after tapping `chat.jobs` |
| `taps/taps-job-row-opened.png` | Cold idle sheet at half after the row tap |
| `taps/taps-sheet-before-drag.png`, `taps-sheet-after-drag.png` | Collapsed, then half from the handle |
| `taps/taps-sheet-before-scrim.png`, `taps-sheet-after-scrim.png` | Half, then collapsed after tapping `jobSheet.dim` |
| `taps/taps-scan-log.png` | Scan log after Jobs → Scan log |
| `taps/taps-composer-multiline.png` | Composer after typing a long problem |
| `taps/taps-chat-axxxl.png`, `taps-job-sheet-half-axxxl.png`, `taps-job-sheet-closeout-axxxl.png`, `taps-citation-page-axxxl.png` | Accessibility XXXL: Garage vs title, half/closeout below the island with a chat sliver, citation Close / Manual page below the island |
| `taps/taps-citation-page.png`, `taps-citation-closed.png` | Chip → page + Go deeper, then Close back on the job |
| `taps/layout-frames.json`, `layout-composer-multiline.json` | XCUITest element frames (points) the checklist measures against |
| `taps/identifiers.json` | Documented ids found / missing per screen |
| `taps/DriveUITests.xcresult` | Full XCTest result bundle |
| `compare/<screen>.png` | Figma (or #94 wireframe) left, simulator right |
| `compare/checklist.md` | Per-screen checklist: measured PASS / FAIL with numbers, REVIEW cells for you |
| `compare/design-checks.json` | Every measurement behind the checklist |
| `owner-only.json` | Linux / missing Xcode. Not a pass. |

Proof standards:

- Drive the real user path. Launch args are the product's screenshot hooks, not test-only endpoints. Taps use XCUITest on the installed app.
- Capture the action and the resulting state (composer before send, sheet before and after a drag).
- Side effects: Jobs row opens **that** job at half (`JobHistoryRow.openedSheet()`), scrim collapses, handle changes detent.
- Mocks only at a production boundary: `FakeLLMClient` when `SIDEKICK_LLM_API_KEY` is unset; demo photos are labeled demo. Do not treat a SwiftUI preview as this skill's proof.
- `swift test` in `app/SidekickCore` is the Linux stand-in for launch-arg parsing and copy. It does not open the SwiftUI screen.

### Standing design checklist

Every UI change must copy this table into the PR (and into `compare/checklist.md`) with pass/fail and a screenshot path. Fail the PR if any row is fail or unfilled.

`compare_figma.py --run-dir` (called by `run` and `compare`) pre-fills it through `scripts/design_checks.py`, per screen:

- **Edge to edge** (job-sheet-*): scans for the white sheet and reports the first white pixel from each side (px and pt), the gap under the sheet at full, rounded top corners, sheet colour and the scrim colour above it. Any side inset, a bottom gap at full, a non-white sheet, a dark scrim at collapsed or a light one at half/full is FAIL.
- **Composer** (chat + the multiline tap shot): finds the outline around the `chat.composer` frame, fits the corner radius and compares it with half the height (pill needs fitted radius / half height ≥ 0.75 on one line **and** after typing a long problem; the circular fit reads `.continuous` corners ~15–20% small, hence 0.75), and samples the background above, below and left of it.
- **Nav buttons** (chat, onboarding, half, full; Jobs when present): measures pixels around each `chat.garage` / `onboarding.skip` / `jobSheet.close` frame (and `chat.jobs` / `lookBack.back` / `jobHistory.scanLog` on #114). Samples the bar ~28–56pt beside the glyph, then a halo around the label. A brighter glass fill, a drop shadow, or a capsule edge is FAIL. Do not trust a SwiftUI style flag: iOS 26 Liquid Glass sits outside `.buttonStyle(.plain)` and outside a 4pt ring (that ring is still inside the pill). Truncation is still yours to check.
- **Selected outcome filled** (job-sheet-full, job-sheet-closeout): `jobSheet.outcome.worked` must be a filled segment (dark fill in light mode), not paper plus underline.
- **Status bar / #F4F4F4**: status bar time contrast on every screen, `#F4F4F4` on chat / Jobs / Scan log. Can only FAIL; clipping and overlap stay REVIEW.
- **Highlight outline** and **Matches Figma** are always REVIEW: open the side-by-side and list every difference.

The overall verdict is never PASS from the script; the best it says is NEEDS REVIEW.

| Rule | Pass / Fail | Evidence |
| --- | --- | --- |
| Highlights are precise outlines that follow the part's shape, **never** a box or rectangle. Low confidence is a hedged (dashed) outline or none. |  |  |
| Bottom sheets go **edge to edge** in collapsed, half, and full: full screen width with no side inset; at full height they run to the bottom of the screen with no bottom padding, gray strip, or squared-off bottom. Rounded top corners only. The sheet is white. Content behind is dimmed with a dark scrim (none or very light at collapsed, stronger at half and full). |  |  |
| The chat composer ("Describe the problem") is a fully rounded **pill** with no boxy corners, sitting on one consistent background color (no different colors above and below it). |  |  |
| Nav and header buttons are plain text ("Close", "Jobs", "Scan log", "Back"), never truncated glass capsules. |  |  |
| Status bar and titles stay visible (no black-on-black). Nothing clipped or overlapping. Neutral `#F4F4F4` background. |  |  |
| Match the Figma frame for the screen: list **every** visible difference, not just the ones asked about. |  |  |

Current layout notes (code on main vs the Mac proof):

- `JobSheetLayout.horizontalInset` is `0` on main (#113). The Mac proof at `eb2f356` / `16c68be` was on the #114 stack (inset 8, paper Jobs header). Re-measure on main; do not treat those quoted 8 pt frames as current.
- Composer on main is a SwiftUI `Capsule()`, not a fixed 18 pt corner. Re-check the pill row on main after typing a long problem.

Do not report done without screenshots.

## Cleanup

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh cleanup
```

Cleanup uses `.cursor/skills/verify-sidekick/run/state.json` (gitignored):

- If this run booted the simulator, `xcrun simctl shutdown <udid>`. If it was already booted, leave it.
- If this run overrode the status bar, `xcrun simctl status_bar <udid> clear`.
- If this run started uvicorn, SIGTERM then SIGKILL that **process group**. Never `pkill uvicorn`.
- Deletes the state file and `/tmp/sidekick-verify-sidekick/evidence-path`.
- Does **not** delete `artifacts/verify/`. After `run`, the screenshots and `compare/` files must still exist.

`run` calls cleanup in a `finally` block. Confirm the evidence directory is still there after it returns. Cleanup leaves the app terminated (the simulator shows the home screen); relaunch with `xcrun simctl launch booted com.zeketx.SidekickMechanic -screen job-sheet-half -demoPhoto hilux -sidekick.onboarding.completed YES` if someone needs the app on screen afterwards.

`run_ui_tests` uninstalls `com.zeketx.SidekickMechanicUITests.xctrunner` before `xcodebuild test`. If `taps/result.json` still reports 0 tests, that is a harness FAIL (exit 1), not a pass.

## Helpers

All of them are executable. Invoke them from the repository root.

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor
.cursor/skills/verify-sidekick/scripts/verify-ios.sh run
.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens chat,job-sheet-half
.cursor/skills/verify-sidekick/scripts/verify-ios.sh taps
.cursor/skills/verify-sidekick/scripts/verify-ios.sh compare
.cursor/skills/verify-sidekick/scripts/verify-ios.sh compare --self-test
.cursor/skills/verify-sidekick/scripts/verify-ios.sh cleanup
```

```bash
python3 .cursor/skills/verify-sidekick/scripts/compare_figma.py \
  --sim artifacts/verify/<id>/screenshots/chat.png \
  --figma .cursor/skills/verify-sidekick/features/figma/chat.png \
  --out artifacts/verify/<id>/compare/chat.png \
  --screen chat
```

```bash
python3 .cursor/skills/verify-sidekick/scripts/design_checks.py --run-dir artifacts/verify/latest
python3 .cursor/skills/verify-sidekick/scripts/design_checks.py --self-test
```

`verify-ios.sh` is a bash front door. `verify_sidekick.py` does the work. `compare_figma.py` stitches and writes the checklist; `design_checks.py` measures the automated rows. Both need Pillow (`python3 -m pip install pillow`). XcodeGen is optional: the committed `.xcodeproj` already has the UI test target.

UI tests live at `app/SidekickMechanicUITests/DriveUITests.swift` so Xcode compiles them. Figma / #94 wireframe refs live at `features/figma/<screen>.png`.

## Maintenance

After this PR lands, run `/maintain-verification-skill` on a Mac and correct the map from a live `run`, not from memory. Re-screenshot Jobs and Scan log after the square-tile / 2pt outline fix.
