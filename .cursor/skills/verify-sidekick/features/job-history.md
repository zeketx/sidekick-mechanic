# Job history and scan log

Jobs is a list of past asks (Cold idle, Hard start, Battery light, Hose check) with outcome badges. Scan log is a 3×3 of photos and outlines. Both use the same outline renderer as the highlight card. Headers are plain text Back / Scan log, not glass capsules.

Chat keeps Garage (`chat.garage`). Jobs (`chat.jobs`) and Scan log (`chat.scanLog`) sit on the same paper header. Opening a Jobs row pops look-back and shows that job sheet at half with the dark scrim.

## Sub-features

- `job-history-list` shows One row per ask and four rows.
- `job-history-open` opens that job's sheet at half from a row tap.
- `scan-log-grid` shows chips and nine cells; one reference cell keeps a short banner.
- `scan-log-open` opens the highlight card from a cell.

## How to get to it (user POV)

- Choose Jobs on chat (`chat.jobs`).
- Launch `-screen job-history` or `-screen scan-log` plus `-sidekick.onboarding.completed YES`.
- From Jobs, choose Scan log (`jobHistory.scanLog`).
- Choose Back (`lookBack.back`) to return.

## Driving it with verify-sidekick

Preconditions:

- `test -f app/SidekickMechanic/JobHistoryView.swift` and `test -f app/SidekickMechanic/ScanLogView.swift`.
- Doctor is green on a Mac.
- Scripted rows match `JobHistoryScript` (Cold idle / Today / Worked, Hard start / Yesterday / Partly, Battery light / Sep 28 / Didn't, Hose check / Sep 20 / Worked).

- **Jobs via launch arg.** `.cursor/skills/verify-sidekick/scripts/verify-ios.sh screens --screens job-history`. Identifiers `jobHistory.list`, `lookBack.back`, `lookBack.title`, `jobHistory.row.cold-idle`. Header: Back, Jobs, Scan log as plain text below the island. Background `#F4F4F4`.
- **Jobs via tap.** `testOpenJobsThenColdIdleRow`. Tap `chat.jobs`, shot `taps/taps-jobs-list.png`, tap `jobHistory.row.cold-idle`, expect `jobSheet.half` and `jobSheet.dim`, shot `taps/taps-job-row-opened.png`.
- **Scan log via launch arg.** `--screens scan-log`. Identifier `scanLog.grid`. Selected chip `intake`. Cell `scanLog.cell.scan-log-0`. Tiles are 1:1 aspect-fill. Outlines are ~2pt polygons; empty cells show no box highlight.
- **Scan log via Jobs header.** `testScanLogFromJobsHeader` taps `jobHistory.scanLog`. Result `scanLog.grid`. Shot `taps/taps-scan-log.png`.
- **Proof.** `compare/job-history.png` and `compare/scan-log.png` against `features/figma/job-history.png` and `scan-log.png`. List every difference vs Figma.

## Gotchas

- Do not treat chat or the job sheet as Jobs. A `-screen job-sheet-half` shot is not a history-row proof.
- Opening a history row does not append chat (later work). The sheet is the proof, not a new user bubble.
- Row identifiers slug the title: `jobHistory.row.cold-idle`, `jobHistory.row.hard-start`, `jobHistory.row.battery-light`, `jobHistory.row.hose-check`.
- Scan-log cell ids are `scan-log-0` … `scan-log-8`, not part names.
- `jobHistory.list` and `scanLog.grid` sit on the whole screen including the header inset. Without `.accessibilityElement(children: .contain)` they replace `lookBack.back`, `jobHistory.scanLog` and the row / cell ids.
- The overlay composer is hidden while Jobs or Scan log is on the navigation stack. Hose check must stay fully visible.
- Scan-log tiles are full squares (`fillsContainer: true`, clip 1:1) with `HighlightOutlineInk.lookBackTile` (~2pt stroke, fill 0.08). The crop centers on the outline bounding box, not the photo center, so an edge part stays in the tile. A filled blob or landscape aspect-fit gap is a fail.
- At Accessibility XXXL, Jobs rows stack thumbnail, wrapping title, date, then badge. Chat Jobs / Scan log become icon-only so Garage stays on screen.
- Thumbs reuse the highlight renderer. A box highlight is a fail.
