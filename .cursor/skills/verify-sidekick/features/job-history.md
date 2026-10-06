# Job history and scan log

Jobs is a list of past asks (Cold idle, Hard start, Battery light, Hose check) with outcome badges. Scan log is a 3×3 of photos and outlines. Both use the same outline renderer as the highlight card. Headers are plain text Back / Scan log, not glass capsules.

## Sub-features

- `job-history-list` shows One row per ask and four rows.
- `job-history-open` opens that job's sheet at half from a row tap.
- `scan-log-grid` shows chips and nine cells; one reference cell keeps a short banner.
- `scan-log-open` opens the highlight card from a cell.

## How to get to it (user POV)

- Choose Jobs on chat (`chat.jobs`).
- Launch `-screen job-history` or `-screen scan-log`.
- From Jobs, choose Scan log (`jobHistory.scanLog`).
- Choose Back (`lookBack.back`) to return.

## Driving it with verify-sidekick

Preconditions:

- Doctor is green on a Mac.
- Chat paper header is visible when not using `-screen`.
- Scripted rows match `JobHistoryScript` (Cold idle / Today / Worked, Hard start / Yesterday / Partly, Battery light / Sep 28 / Didn't, Hose check / Sep 20 / Worked).

- **Jobs via launch arg.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens job-history`. Identifiers `jobHistory.list`, `jobHistory.row.cold-idle`. Header: Back, Jobs, Scan log as plain text. Background `#F4F4F4`.
- **Jobs via tap.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh taps` runs `testOpenJobsThenColdIdleRow`. Tap `chat.jobs`, shot `taps/taps-jobs-list.png`, tap `jobHistory.row.cold-idle`, expect `jobSheet.half`, shot `taps/taps-job-row-opened.png`.
- **Scan log via launch arg.** `--screens scan-log`. Identifier `scanLog.grid`. Selected chip `intake`. Cell `scanLog.cell.scan-log-0`. Outlines are polygons; empty cells show no box highlight.
- **Scan log via Jobs header.** `testScanLogFromJobsHeader` taps `jobHistory.scanLog`. Result `scanLog.grid`. Shot `taps/taps-scan-log.png`.
- **Proof.** `compare/job-history.png` and `compare/scan-log.png` against `features/figma/job-history.png` and `scan-log.png`. List every difference vs Figma (thumb photos vs gray squares on the #94 wireframe, badge fill, chip wrap). Fill the header-button and outline rows.

## Gotchas

- Opening a history row does not append chat (later work). The sheet is the proof, not a new user bubble.
- Row identifiers slug the title: `jobHistory.row.cold-idle`, `jobHistory.row.hard-start`, `jobHistory.row.battery-light`, `jobHistory.row.hose-check`.
- Scan-log cell ids are `scan-log-0` … `scan-log-8`, not part names.
- Thumbs reuse the highlight renderer. A square crop that clips the outline is a fail even if the list layout matches.
- Do not verify Jobs by only launching `-screen job-sheet-half`. That skips the row tap.
