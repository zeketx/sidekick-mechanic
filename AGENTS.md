# AGENTS.md

Guidance for AI coding agents working in `zeketx/sidekick-mechanic`. Read this first, then the issue you are working on.

## What this project is

Sidekick Mechanic is a chat-first AI mechanic on iPhone for one truck: the owner's 1990 Land Cruiser LJ78 with a 2JZ-GE swap and a Lexus donor ECU. You describe a problem. It answers from the real manuals with page citations, and shows a photo of the owner's engine bay with the relevant part highlighted.

It is also a portfolio project for hardware and AI employers. Measured results and a clean build log matter as much as features.

Read [VISION.md](VISION.md) for the why and [ROADMAP.md](ROADMAP.md) for the plan.

## Current phase

**Phase 1: chat sidekick.** Chat UI, grounded answers over the 2JZ-GE repair manual and LJ78 wiring docs, and the highlight engine. A highlight is a precise outline of the part, or of a group of parts, on any still photo, including one that has never been traced. A bounding box is never the highlight. Styles stay outline, saturate, circle, and dim the rest. Phase 1 does not track the live camera. The hand-traced bay map is optional: an accuracy boost on the owner's reference photos, and the answer key for mask IoU.

The pipeline is not chosen. [Issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85) compares three candidates. A (preferred) is a vision model that grounds the part, then SAM 2 cuts the mask. B (open baseline) is Grounding DINO plus SAM 2. C is a vision model that draws the mask directly. Zeke approved a paid vision API on 2026-10-02. The provider is OpenRouter. Paths A and C are unblocked for the #85 spike. The cost target is still ≤ $0.03 per photo. The key is a Railway secret for the product and is never committed. Do not put it in the repo.

Highlight targets are proposed, pending Zeke's confirmation after #85. On confident highlights: wrong part ≤ 5%, right part ≥ 85%. Median mask IoU ≥ 0.6, reported in part-size buckets. Abstain (unsure + not found) up to 40% is acceptable for v1. p95 ≤ 8 s end to end on the backend, and ≤ $0.03 per photo. If no candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship. [#85](https://github.com/zeketx/sidekick-mechanic/issues/85) and [#88](https://github.com/zeketx/sidekick-mechanic/issues/88) call the two rates wrong-highlight and correct-part.

The answer highlight is still `bay_photo_id` and `part_id`. Contract v2 is [issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86): photo ref, polygons plus an optional mask, labels, state, method (`traced` or `inferred`), and scores. It reopens [issue #9](https://github.com/zeketx/sidekick-mechanic/issues/9) and [issue #10](https://github.com/zeketx/sidekick-mechanic/issues/10). Do not change that schema, or the tests, until #86. The bay-map-only resolver from [issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32) is reworked through #86 and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33). Order: [issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84) → #85 → Engineer design PR → #86 → [issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87) → [issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31) → #33 → #88.

Do not start Phase 2 (live camera, YOLO, BLE telemetry) or Phase 3 work unless the issue says so. The M4 groundwork issues (telemetry simulator, ML dry run) are the only Phase 2 exceptions.

**The truck has not been delivered.** The ECU type (OBD1 vs OBD-II), donor year, and harness details are TBD. Before delivery, the highlight engine uses public 2JZ-GE bay photos. Those photos do not have to be traced first.

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
```

Issues live on [GitHub Issues](https://github.com/zeketx/sidekick-mechanic/issues). Milestones live on [GitHub milestones](https://github.com/zeketx/sidekick-mechanic/milestones).

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
- **Large text.** Read [docs/DYNAMIC_TYPE.md](docs/DYNAMIC_TYPE.md) before building or changing SwiftUI. Every screen is designed and checked at the default size and at Accessibility XXXL. New screen tests call `assertFitsOnScreen`. The verify-sidekick large-text section is mandatory on UI PRs.
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
