# Sidekick Mechanic verification map

This directory is the maintained source for verifying the user-facing iPhone UI. Read the index before driving the app, then use the matching feature file as the recipe.

## Baseline preconditions

- Run on macOS with Xcode. Linux writes `artifacts/verify/<run-id>/owner-only.json` and stops.
- From the repo root, run `.cursor/skills/verify-sidekick/scripts/verify-ios.sh doctor`.
- Backend: `GET http://127.0.0.1:8000/openapi.json` title `Sidekick Mechanic`. The helper starts `uvicorn app:app --host 127.0.0.1 --port 8000` when the port is free.
- App identity: scheme `SidekickMechanic`, bundle id `com.zeketx.SidekickMechanic`, Debug, `CODE_SIGNING_ALLOWED=NO`.
- Prefer iPhone 17 Pro / iOS 26.0. Status bar time `9:41`.
- Never drive a simulator this run did not record in `.cursor/skills/verify-sidekick/run/state.json`.
- Onboarding (`-screen onboarding-1|2|3`) is compiled only on PR #111. Skip those recipes on this stack and say so.

## Driving conventions

- Start every recipe from a terminated app. The helper terminates between `-screen` launches.
- Prefer accessibility identifiers over coordinates. The only relative gesture is a drag from `jobSheet.handle`.
- `testIdentifierAudit` (`taps/identifiers.json`) checks every identifier the map names. If one is missing, fix the map or the view before trusting a tap failure.
- Treat every command as literal. Keep `-screen` values and identifiers unchanged.
- Launch-arg screens go through `verify-ios.sh screens --screens <id>`.
- Taps go through `verify-ios.sh taps` (`DriveUITests`).
- Restore nothing in the app (session-only demo data). Do not delete `artifacts/verify/` during cleanup.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen.
- UI proof is a simulator screenshot plus a Figma side-by-side in `compare/` plus a filled design checklist. `run` pre-fills measurable rows (sheet edge to edge, composer pill, plain nav buttons, status bar / `#F4F4F4`) with PASS / FAIL and numbers; you fill the REVIEW cells.
- Record the feature ID and entry point (`-screen …` or the XCTest method) on every artifact.
- Report an unreachable path with the attempted command and the unmet precondition (onboarding not in checkout, demo photos 404, Garage missing).
- Do not report a skipped entry point as verified through a different path.
- `swift test` in `app/SidekickCore` is not a screenshot proof.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with verify-sidekick` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

Figma / #94 wireframe PNGs: [figma/](./figma/). `chat.png` and `job-sheet-closeout.png` reuse the collapsed / half wireframes until dedicated frames exist. Prefer a later Figma export over the grayscale wireframe.

## Features

- [Onboarding](./onboarding.md) covers first-open pages 1–3, Skip, and the Garage sheet. Not in this checkout.
- [Chat, answer card, and composer](./chat.md) covers the paper header, pill composer, answer card, and citation chip.
- [Job sheet](./job-sheet.md) covers collapsed / half / full / closeout, scrim, handle drag, and Outcome.
- [Highlight viewer](./highlight-viewer.md) covers confident, unsure (dashed), not-found, and reference.
- [Job history and scan log](./job-history.md) covers Jobs rows, Scan log cells, and opening a sheet or highlight from them.
