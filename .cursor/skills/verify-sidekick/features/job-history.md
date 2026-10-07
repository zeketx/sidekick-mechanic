# Job history and scan log

Jobs is a list of past asks (Cold idle, Hard start, Battery light, Hose check) with outcome badges. Scan log is a 3×3 of photos and outlines. Both use the same outline renderer as the highlight card. Headers are plain text Back / Scan log, not glass capsules.

**Later (#114).** This checkout (main / v1) does not compile `JobHistoryView.swift` or `ScanLogView.swift`. There is no `chat.jobs`, `jobHistory.list`, or `scanLog.grid`. Skip these recipes the same way onboarding skipped before #111.

## Sub-features

- `job-history-list` shows One row per ask and four rows.
- `job-history-open` opens that job's sheet at half from a row tap.
- `scan-log-grid` shows chips and nine cells; one reference cell keeps a short banner.
- `scan-log-open` opens the highlight card from a cell.

## How to get to it (user POV)

- Choose Jobs on chat (`chat.jobs`) — only when #114 is in the checkout.
- Launch `-screen job-history` or `-screen scan-log`.
- From Jobs, choose Scan log (`jobHistory.scanLog`).
- Choose Back (`lookBack.back`) to return.

## Driving it with verify-sidekick

Preconditions:

- `test -f app/SidekickMechanic/JobHistoryView.swift` and `test -f app/SidekickMechanic/ScanLogView.swift`. On main both fail: write `screenshots/skipped.json` with reason `JobHistoryView.swift is not in this checkout (PR #114, later).` and XCTSkip the Jobs / Scan log tests. Do not fail the Mac run.
- Doctor is green on a Mac.
- Scripted rows match `JobHistoryScript` (Cold idle / Today / Worked, Hard start / Yesterday / Partly, Battery light / Sep 28 / Didn't, Hose check / Sep 20 / Worked) once the files exist.

- **Detect the gap.** Confirm the files are missing. `DriveUITests.testOpenJobsThenColdIdleRow` and `testScanLogFromJobsHeader` XCTSkip and write `taps/job-history-unmet.json` / `taps/scan-log-unmet.json`. Do not invent Jobs or Scan log buttons.
- **Jobs via launch arg (when present).** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens job-history`. Identifiers `jobHistory.list`, `jobHistory.row.cold-idle`. Header: Back, Jobs, Scan log as plain text. Background `#F4F4F4`.
- **Jobs via tap (when present).** `testOpenJobsThenColdIdleRow`. Tap `chat.jobs`, shot `taps/taps-jobs-list.png`, tap `jobHistory.row.cold-idle`, expect `jobSheet.half`, shot `taps/taps-job-row-opened.png`.
- **Scan log via launch arg (when present).** `--screens scan-log`. Identifier `scanLog.grid`. Selected chip `intake`. Cell `scanLog.cell.scan-log-0`. Outlines are polygons; empty cells show no box highlight.
- **Scan log via Jobs header (when present).** `testScanLogFromJobsHeader` taps `jobHistory.scanLog`. Result `scanLog.grid`. Shot `taps/taps-scan-log.png`.
- **Proof (when present).** `compare/job-history.png` and `compare/scan-log.png` against `features/figma/job-history.png` and `scan-log.png`. List every difference vs Figma.

## Gotchas

- Do not treat chat or the job sheet as Jobs. A `-screen job-sheet-half` shot is not a history-row proof.
- Opening a history row does not append chat (later work). The sheet is the proof, not a new user bubble.
- Row identifiers slug the title: `jobHistory.row.cold-idle`, `jobHistory.row.hard-start`, `jobHistory.row.battery-light`, `jobHistory.row.hose-check`.
- Scan-log cell ids are `scan-log-0` … `scan-log-8`, not part names.
- `jobHistory.list` and `scanLog.grid` sit on the whole screen including the header inset. Without `.accessibilityElement(children: .contain)` they replace `lookBack.back`, `jobHistory.scanLog` and the row / cell ids.
- Composer hiding on look-back is part of #114. Main always shows the composer on chat.
- Thumbs reuse the highlight renderer. A square crop that clips the outline is a fail even if the list layout matches.
