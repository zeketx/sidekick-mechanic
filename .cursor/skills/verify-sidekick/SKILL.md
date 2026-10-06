---
name: verify-sidekick
description: "Drive the Sidekick Mechanic SwiftUI iPhone app on a Mac: xcodebuild for the iPhone 17 Pro simulator, simctl -screen launches, XCUITest taps, screenshots vs Figma, and the standing design checklist. Use when changing Sidekick UI. Linux stops at doctor."
---

# Verify Sidekick Mechanic (iPhone)

Prove a UI change by driving the real app: build it, boot the simulator, open the screen the way a user would (launch arguments, then real taps), screenshot it at 9:41, put that shot next to the Figma frame, and fill the design checklist. Do not report done without those files.

This skill runs on a **macOS host** with Xcode. This cloud VM is Linux and has no iOS Simulator. A Linux run stops at doctor, writes `artifacts/verify/<run-id>/owner-only.json`, and may stitch a committed screenshot against a Figma ref. That file is an unmet precondition, not a passing UI proof. End-to-end proof is still pending on Zeke's Mac.

The older `.cursor/skills/verify-ios/` skill covers mock-mode chat send. Reach for **this** skill for v1 screens (chat, job sheet, highlight viewer, Jobs, scan log, onboarding).

The iOS Simulator is a shared machine. Do not start a second verify-sidekick run against the same sim. Do not drive a simulator session the owner is using unless doctor says it already has `com.zeketx.SidekickMechanic` from this checkout.

## Launch

Target: Xcode 26.0.1, iPhone 17 Pro, iOS 26.0, scheme `SidekickMechanic`, bundle id `com.zeketx.SidekickMechanic`. Build Debug with `CODE_SIGNING_ALLOWED=NO`. Swift 6 strict concurrency is on (`SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete` in `app/project.yml` and the pbxproj).

From the repository root, first command on a Mac:

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor
```

Full run (build, boot, each `-screen`, taps, Figma stitch, cleanup):

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh run
```

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

`run` starts that uvicorn itself when :8000 is free, records the pid, and stops only that pid. `GET /demo/photos` is on PR #92 (`cursor/demo-mode-backend-27ef`), which is not in this UI stack. Highlights still render from placeholder images. Doctor records demo-photos as false in that case; it is not a hard fail.

Launch arguments (parsed in `DemoLaunchOptions` / `OnboardingLaunchOptions`). Pass them after the bundle id with `simctl launch`, or as XCTest `launchArguments`.

| Arg | What it opens |
| --- | --- |
| `-screen onboarding-1\|2\|3` plus `-resetOnboarding` | First-open pages. **Not in this checkout.** Onboarding is PR #111 (`cursor/v1-onboarding-5c2a`). |
| `-sidekick.onboarding.completed YES` | UserDefaults key `sidekick.onboarding.completed`. Harmless no-op until #111. |
| `-screen highlight-confident\|highlight-unsure\|highlight-not-found\|highlight-reference` | Full-bleed highlight card. `-screen highlight-unsure` also turns on the internal unsure flag. |
| `-screen job-sheet-collapsed\|job-sheet-half\|job-sheet-full\|job-sheet-closeout` | Job sheet detents. Closeout is half height with Outcome = Worked. |
| `-screen job-history` | Jobs list. |
| `-screen scan-log` | Scan log grid. |
| `-demoPhoto hilux\|supra\|hrymx\|flickr` | Demo bay photo. Default `hilux` → `commons-hilux-2jz`. |
| `-showDemoChrome 1` | Demo toggle, demo banner, Chat/Readings tabs. |
| `-flagUnsureHighlight 1` | Internal unsure card. Off in v1 unless the screen is `highlight-unsure`. |

The helper terminates the app between `-screen` launches and waits (2.5–4 s) so the next shot is that screen, not a leftover cover.

Teardown: `verify-ios.sh cleanup`. See Cleanup.

## Doctor

Read-only. Does not boot a simulator, install the app, or start uvicorn.

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor
```

Exit 0 only on macOS when Xcode is present, scheme `SidekickMechanic` lists, the preferred (or fallback) iPhone is **Booted**, this checkout's app is installed, and `GET /openapi.json` on :8000 is Sidekick Mechanic. On Linux it exits 2 and writes `owner-only.json`.

The JSON always includes `git.branch`, `git.sha`, `xcodebuild` version when available, simulator name/udid/state, `app_installed`, and `backend.openapi` / `backend.demo_photos`.

Run doctor first whenever anything looks off, and again after a failed drive.

## Drive

Stable handles are accessibility identifiers on the views, not coordinates.

### Launch-arg screens (simctl)

```bash
.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens
.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens job-history,scan-log
```

Inside the helper, after install and `simctl status_bar override --time 9:41`:

```bash
xcrun simctl terminate <udid> com.zeketx.SidekickMechanic
xcrun simctl launch <udid> com.zeketx.SidekickMechanic -screen job-history
# wait
xcrun simctl io <udid> screenshot artifacts/verify/<run-id>/screenshots/job-history.png
```

`screens` leaves the simulator running so you can inspect. `run` calls cleanup.

### Real taps (XCUITest)

Launch args cannot open the Garage sheet, tap a Jobs row, drag the sheet, or tap the scrim. Those go through `app/SidekickMechanicUITests/DriveUITests.swift` on target `SidekickMechanicUITests`.

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
| `testOpenJobsThenColdIdleRow` | Chat → Jobs → Cold idle | `chat.jobs`, `jobHistory.row.cold-idle` | `jobSheet.half` |
| `testDragSheetCollapsedToHalf` | Drag the sheet handle up | `jobSheet.handle` | `jobSheet.collapsed` → `jobSheet.half` |
| `testTapScrimCollapsesHalfSheet` | Tap the dimmed chat | `jobSheet.dim` | `jobSheet.half` → `jobSheet.collapsed` |
| `testScanLogFromJobsHeader` | Jobs → Scan log | `jobHistory.scanLog` | `scanLog.grid` |
| `testOpenGarageIfPresent` | Chat → Garage | `chat.garage` | **XCTSkip on this stack.** Garage is PR #111 (`onboarding.garage`, `garage.done`). |

The drag uses a vector from `jobSheet.handle`, not a raw screen coordinate of the sheet.

If `xcodegen generate` is run from `app/project.yml`, it recreates the UI test target. The committed `app/SidekickMechanic.xcodeproj` already includes it so a Mac without XcodeGen can still `xcodebuild test`.

### Identifiers (this checkout)

Chat: `chat.header`, `chat.jobs`, `chat.scanLog`, `chat.composer`, `chat.send`, `chat.messageList`, `chat.attach`, `demo.toggle`. Garage `chat.garage` only on #111.

Job sheet: `jobSheet`, `jobSheet.collapsed` / `.half` / `.full`, `jobSheet.handle`, `jobSheet.open` / `.close`, `jobSheet.dim`, `jobSheet.outcome.worked` / `.partly` / `.didnt`.

Highlight: `highlightViewer`, `highlightViewer.close`, `highlightViewer.photo`, `demo.confirm.yes` / `.notThis`.

Jobs / scan log: `jobHistory.list`, `jobHistory.row.cold-idle`, `lookBack.back`, `scanLog.grid`, `scanLog.cell.scan-log-0`.

Recipes for each feature: [features/README.md](features/README.md).

## Evidence

Proof goes to `artifacts/verify/<run-id>/` (gitignored). `latest` is a symlink to the last run. Cleanup must not delete this tree.

| Path | What it proves |
| --- | --- |
| `doctor.json` | Xcode, sim, app, backend, branch, SHA |
| `screenshots/<screen>.png` | That `-screen` after terminate + wait, status bar 9:41 |
| `taps/taps-jobs-list.png` | Jobs list after tapping `chat.jobs` |
| `taps/taps-job-row-opened.png` | Cold idle sheet at half after the row tap |
| `taps/taps-sheet-after-drag.png` | Detent change from the handle |
| `taps/taps-sheet-after-scrim.png` | Collapsed after tapping `jobSheet.dim` |
| `compare/<screen>.png` | Figma (or #94 wireframe) left, simulator right |
| `compare/checklist.md` | Standing design checklist, pass/fail filled by the agent |
| `owner-only.json` | Linux / missing Xcode. Not a pass. |

Proof standards:

- Drive the real user path. Launch args are the product's screenshot hooks, not test-only endpoints. Taps use XCUITest on the installed app.
- Capture the action and the resulting state (composer before send, sheet before and after a drag).
- Side effects: Jobs row opens **that** job at half (`JobHistoryRow.openedSheet()`), scrim collapses, handle changes detent.
- Mocks only at a production boundary: `FakeLLMClient` when `SIDEKICK_LLM_API_KEY` is unset; demo photos are labeled demo. Do not treat a SwiftUI preview as this skill's proof.
- `swift test` in `app/SidekickCore` is the Linux stand-in for launch-arg parsing and copy. It does not open the SwiftUI screen.

### Standing design checklist

Every UI change must copy this table into the PR (and into `compare/checklist.md`) with pass/fail and a screenshot path. Fail the PR if any row is fail or unfilled.

| Rule | Pass / Fail | Evidence |
| --- | --- | --- |
| Highlights are precise outlines that follow the part's shape, **never** a box or rectangle. Low confidence is a hedged (dashed) outline or none. |  |  |
| Bottom sheets go **edge to edge** in collapsed, half, and full: full screen width with no side inset; at full height they run to the bottom of the screen with no bottom padding, gray strip, or squared-off bottom. Rounded top corners only. The sheet is white. Content behind is dimmed with a dark scrim (none or very light at collapsed, stronger at half and full). |  |  |
| The chat composer ("Describe the problem") is a fully rounded **pill** with no boxy corners, sitting on one consistent background color (no different colors above and below it). |  |  |
| Nav and header buttons are plain text ("Close", "Jobs", "Scan log", "Back"), never truncated glass capsules. |  |  |
| Status bar and titles stay visible (no black-on-black). Nothing clipped or overlapping. Neutral `#F4F4F4` background. |  |  |
| Match the Figma frame for the screen: list **every** visible difference, not just the ones asked about. |  |  |

Current layout notes the next agent must still photograph, not assume:

- `JobSheetLayout.horizontalInset` is `8`, so the sheet is **not** full width yet. That row should fail until the inset is 0.
- Composer corner radius is 18 on a rounded rectangle, not a capsule.

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

`run` calls cleanup in a `finally` block. Confirm the evidence directory is still there after it returns.

## Helpers

All four are executable. Invoke them from the repository root.

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
  --sim artifacts/verify/<id>/screenshots/job-history.png \
  --figma .cursor/skills/verify-sidekick/features/figma/job-history.png \
  --out artifacts/verify/<id>/compare/job-history.png \
  --screen job-history
```

`verify-ios.sh` is a bash front door. `verify_sidekick.py` does the work. `compare_figma.py` needs Pillow (`python3 -m pip install pillow`).

UI tests live at `app/SidekickMechanicUITests/DriveUITests.swift` so Xcode compiles them. Figma / #94 wireframe refs live at `features/figma/<screen>.png`.

## Maintenance

After a screen lands (onboarding merge, Garage button, real Figma export), run `/maintain-verification-skill` on a Mac and correct the map from a live `run`, not from memory.
