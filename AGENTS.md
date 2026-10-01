# AGENTS.md

Guidance for AI coding agents working in `zeketx/sidekick-mechanic`. Read this first, then the issue you are working on.

## What this project is

Sidekick Mechanic is a chat-first AI mechanic on iPhone for one truck: the owner's 1990 Land Cruiser LJ78 with a 2JZ-GE swap and a Lexus donor ECU. You describe a problem. It answers from the real manuals with page citations, and shows a photo of the owner's engine bay with the relevant part highlighted.

It is also a portfolio project for hardware and AI employers. Measured results and a clean build log matter as much as features.

Read [VISION.md](VISION.md) for the why and [ROADMAP.md](ROADMAP.md) for the plan.

## Current phase

**Phase 1: chat sidekick.** Chat UI, grounded answers over the 2JZ-GE repair manual and LJ78 wiring docs, the bay map, and the highlight engine.

Do not start Phase 2 (live camera, YOLO, BLE telemetry) or Phase 3 work unless the issue says so. The M4 groundwork issues (telemetry simulator, ML dry run) are the only Phase 2 exceptions.

**The truck has not been delivered.** The ECU type (OBD1 vs OBD-II), donor year, and harness details are TBD. Before delivery, the highlight engine uses public 2JZ-GE bay photos.

## Repo layout (proposed)

```
app/                    Xcode SwiftUI project (owner builds on a Mac)
app/SidekickCore/       Pure Swift package: models, contracts, logic. Builds on Linux.
backend/                RAG service: ingestion, retrieval, citations, LLM adapter, eval
backend/contracts/      JSON Schemas shared with the app (answer, bay map)
backend/eval/           Golden questions and eval harness
ml/                     Dataset scripts, training, Core ML export (Phase 2 dry run in M4)
docs/                   Design docs, KANBAN.md, METRICS.md, MANUALS.md, BAY_MAP.md
docs/vehicle/           TRUCK.md (fact registry), ECU.md, DAY_ONE.md
docs/build-log/         Dated build log entries with metrics
backlog/                issues.json and milestones.json
scripts/                Repo tooling (create_issues.sh, render_backlog.py)
```

If you need a new top-level folder, say why in the PR.

## You cannot compile iOS on Linux

Cloud agents run on Linux. Xcode, the iOS SDK, SwiftUI, UIKit, AVFoundation, Vision, Core ML, and CoreBluetooth are not available. The owner builds the app in Xcode on his Mac.

So:
- **Put logic in `app/SidekickCore/`.** Keep it free of Apple-only imports so `swift build && swift test` runs on Linux. Verify your Swift there.
- **Keep app-target Swift simple.** Thin SwiftUI views over `SidekickCore` types. Standard APIs only. No clever generics, macros, or result builders you cannot check.
- **Say what you could not verify.** In the PR, list every file you changed that you could not compile, and what the owner should check in Xcode.
- **No new Swift packages or pods** without an issue that approves them.
- Prototype visual logic (like the highlight renderer) in Python in `backend/` first, where you can run golden-image tests, then port.

## Safety rule: never invent vehicle facts

This app gives advice about real machinery. A wrong number can break parts or hurt someone.

[`docs/vehicle/TRUCK.md`](docs/vehicle/TRUCK.md) is the source of truth for vehicle facts.

- **Never write a torque value, spec, clearance, pinout, connector ID, wire color, or part number from memory.** Not in code, prompts, fixtures, tests, or docs.
- **Every vehicle fact cites a source**: document ID and page (from `docs/MANUALS.md`), or an owner observation recorded in `docs/vehicle/TRUCK.md`.
- **Unknown means TBD.** If a fact is not confirmed in `TRUCK.md`, write `TBD`. Do not fill it with a "typical" value.
- **Test fixtures use obviously fake values** (for example `"page": 999`, `"value": "FAKE-SPEC"`) so they are never mistaken for real data.
- **Simulated telemetry is labeled as simulated** in code and UI.
- **Do not weaken the spec guard** (the check that blocks uncited numbers) without an issue that says so and owner approval.
- Do not commit manual PDFs or page images. They stay in the gitignored `manuals/` folder.

## Coding conventions

**General**
- Name the data shape first. Types before logic.
- Small functions, clear names. Comments only for a non-obvious *why*.
- Validate at boundaries (network, files, LLM output). Trust internal types.
- No secrets in the repo. Read keys from environment. Keep `.env.example` current.

**Swift**
- Swift with SwiftUI, `async`/`await`, and the Observation framework. Target iOS version recorded in the README (proposed iOS 17, owner confirms).
- Value types (`struct`, `enum`) by default. Make illegal states unrepresentable.
- `Codable` models in `SidekickCore` match `backend/contracts/` exactly. Decode every fixture in tests.
- Hardware and services sit behind protocols with a fake or simulator (`TelemetrySource`, network client).

**Python (backend, ml)**
- Python 3.11+, type hints, `ruff` for lint and format, `pytest` for tests.
- Pin dependencies. Scripts rerun from a clean checkout.
- Eval output is JSON in `backend/eval/results/`. Metrics come from there, never from hand-typed numbers.

**Tests**
- Test behavior through public entry points. Assert literal expected values.
- A test that would pass if the function returned nothing is not a test.

## Pull requests

- **One issue per PR.** Link it with `Closes #N` in the description.
- **Keep PRs small.** Aim for under about 300 changed lines. Split larger work into stacked PRs.
- **UI PRs include screenshots** (or a short screen recording) of each changed state: light, dark, and large Dynamic Type where relevant. If you cannot run the app, attach SwiftUI preview code and ask the owner to capture screenshots in Xcode. Say so plainly.
- **Vehicle-fact PRs list their sources** in a "Sources" section.
- **Metric changes** (RAG, highlight, latency) include before and after numbers from the eval harness.
- Branch names: `<issue-number>-short-slug`. Commit messages in the imperative ("Add citation chip").

## Definition of done

An issue is done when all of these are true:

- [ ] Every acceptance criterion in the issue is checked, with evidence in the PR.
- [ ] CI is green (backend tests, `SidekickCore` tests, eval subset where relevant).
- [ ] App-target changes build in Xcode on the owner's Mac, confirmed by the owner.
- [ ] UI changes have screenshots in the PR.
- [ ] No uncited vehicle facts. Unknowns marked TBD.
- [ ] Docs updated if behavior, setup, or contracts changed.
- [ ] Metric-affecting work has numbers in the PR. Milestone-closing work has a build log entry.
- [ ] Merged, and the board shows Done.

## Working style

This repo is built with pstack's poteto mode. See [docs/POTETO_PLAN.md](docs/POTETO_PLAN.md) for which playbook to use when, and the cost policy.
