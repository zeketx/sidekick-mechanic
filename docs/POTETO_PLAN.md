# Poteto plan

How to run this build with **poteto mode**, the agent playbooks in the pstack plugin. This page says which skill to use at which milestone, and how to keep cost down.

Every skill named here exists in pstack today. The skill descriptions below are summarized from each skill's `SKILL.md`. If a skill is renamed or removed, fix this page in its own PR.

## The skills we use

All of these are invoked explicitly (they set `disable-model-invocation: true`). Type the slash command.

| Skill | What it does | Use it here for |
|---|---|---|
| `/poteto-mode` | Working style: concise replies, deliberate subagents, simple code, verified work. Routes each task to a playbook (Feature, Bug fix, Prototype, Hillclimb, and others). | Default mode for any non-trivial issue. |
| `/architect` | Sketch types, signatures, and module boundaries before code. Runs `arena` to get at least two structurally different designs, synthesizes one, then implements against it. Scraps the sketch if implementation keeps fighting it. | Core data shapes and module boundaries. |
| `/arena` | Fan out N parallel attempts at the same task, score them on a rubric, pick a base, graft the best parts of the others. | Choices you want compared, not guessed (visual style, prompt design). |
| `/figure-it-out` | Designs a bespoke, auditable playbook when no narrower one fits. Falsifiable definition of done, riskiest-first sequencing, hypothesis loop, decision trail. | Big multi-part efforts: truck day one integration, Phase 2 kickoff. |
| `/interrogate` | Several reviewers (one per configured model) adversarially review a change. Returns a verdict sorted into Act on, Consider, Noted, Dismissed. Does not auto-apply fixes. | PR review for non-trivial and safety-relevant PRs. |
| `/blast-radius` | Finds what a change could break outside the diff, and proves the one fact it is safe because of by running real code. | Changes to shared contracts and schemas. |
| `/create-verification-skill` | Generates a project-local `verify-<app>` skill that launches the app, drives it like a user, captures evidence, and cleans up. Proves the skill by running it once. | As soon as the app and backend run (end of M1). |
| `/maintain-verification-skill` | Periodic pass that keeps the verify skill and its feature map honest. | After each milestone that adds user-facing features. |
| `/no-comments` | Spawns a reviewer that removes comments that explain *what* instead of *why*, fixes accepted findings, and offers to encode claimed constraints as tests or lints. | Before review on medium and large PRs. |
| `/automate-me` | Turns the owner's working conventions into a personal `-mode` skill (for example `zeke-mode`) by mining recent transcripts and asking a few questions. | Once there are a few weeks of agent sessions (around M3). |
| `/setup-pstack` | Writes `~/.cursor/rules/pstack-models.mdc`, which sets the model for every pstack role. | Once, in M0, to apply the cost policy. |
| `/how`, `/show-me-your-work` | `how` explains how existing code works before changing it. `show-me-your-work` keeps a decision log for long or unattended runs. | Pulled in by the skills above. Rarely called directly. |

## Cost policy

1. **Cloud agents default to `grok-4.6`.** Run `/setup-pstack` once and set every role to `grok-4.6`. pstack's built-in defaults point at larger multi-family models, so without this step it will spend more than intended. `/setup-pstack` only writes model slugs it can detect, so confirm the exact `grok-4.6` slug when it asks.
2. **Panels stay small.** `arena runners`, `architect runners`, and `interrogate reviewers` are lists, and each entry is one subagent. Default to two entries, both `grok-4.6`. Only widen to three, or add other model families, for the one-way-door decisions marked ★ below, and only when the owner says so for that task.
3. **Small UI work skips the nested-agent playbooks.** No `architect`, `arena`, `interrogate`, `swarm`, or `no-comments` (it spawns its own subagent). One agent does the work directly and follows AGENTS.md. A task counts as small UI work when all of these are true:
   - It changes SwiftUI views only (layout, copy, styling, previews).
   - It adds or changes no types in `SidekickCore` or `backend/contracts/`.
   - It is under about 150 changed lines.
   Small UI PRs still need screenshots and the definition of done.
4. **Don't repeat design work.** A second `arena` on a settled design is waste (pstack's own `figure-it-out` says the same). Re-architect only when implementation proves the sketch wrong.

## Playbook by milestone

★ = one-way door. Get it right before building on it. Widening the panel is allowed here with owner approval.

### M0: Repo, tooling, and ECU check
- `/setup-pstack` first, per the cost policy.
- Repo scaffold, CI, templates: plain `/poteto-mode`. Mechanical work, no architect.
- ECU identification spike: `/poteto-mode` (its Investigation playbook fits: read-only, cited answer). Every claim cited. Result stays TBD until delivery.

### M1: Chat sidekick shell
- ★ Conversation and answer data model: `/architect` **before** any chat UI or backend code. The answer shape (text, citations, highlight reference) is shared by the app, backend, and eval, so it is expensive to change later.
- Shared answer contract: implement from the architect sketch. Any later change runs `/blast-radius` first.
- Chat screen, answer card, composer polish: small UI work, single agent, screenshots.
- Backend `/chat` and LLM adapter: `/poteto-mode` Feature playbook.
- **As soon as the app and backend run:** `/create-verification-skill`. The skills live in the repo:
  - `.cursor/skills/verify-backend/` runs on Linux. Launch the backend, send a chat request, save the response. The same run covers `swift test` and `make eval`.
  - `.cursor/skills/verify-ios/` runs on the owner's Mac. `xcodebuild`, boot a simulator with `simctl`, drive a UI test, save screenshots. Cloud agents cannot run this one. They hand it to the owner.
- PR review: `/interrogate` on the contract PR and the LLM adapter PR.

### M2: Grounded answers over the manuals
- ★ Retrieval index and store: `/architect`. Compare at least two designs, including one that could later move on-device.
- Ingestion, citations: `/poteto-mode` Feature playbook.
- ★ Spec guard (blocks uncited numbers and pinouts): `/architect` for the check's design, then `/interrogate` on the PR. This is the main safety control. It always gets a full interrogate, even if small.
- Wiring diagram spike: `/poteto-mode` Prototype playbook. Settle text extraction vs page-image citation by trying both.
- Improving recall@5 or citation accuracy after the harness exists: `/poteto-mode` Hillclimb playbook. One metric, before and after numbers, one commit per accepted win.
- Citation viewer: small UI work.

### M3: Bay map and highlight engine
- ★ Bay map schema: `/architect` before labeling any photos. Any later schema change runs `/blast-radius`, since the schema feeds the renderer, the resolver, the eval, and the Phase 2 detector.
- ★ Highlight engine module (renderer interface and part resolver): `/architect`. Prototype the renderer in Python so agents can run golden-image tests on Linux.
- Highlight visual style: `/arena` with at least three style candidates. Rubric: part obvious within one second on a phone, context still readable, works on dark and bright bays.
- Swift port of the renderer: `/poteto-mode` Feature playbook. The owner verifies on the Mac with `verify-ios`.
- End-to-end wiring: Feature playbook, then `/interrogate` on the PR.
- After M3: `/maintain-verification-skill` to add bay map and highlight to the feature map. `/automate-me` to draft `zeke-mode` from the sessions so far.

### M4: Pre-delivery groundwork
- ★ `TelemetrySource` protocol and simulator: `/architect`. The protocol must fit an ELM327 source and an OBD1 source without change.
- ML pipeline dry run: `/poteto-mode` Prototype playbook. Throwaway is fine. The deliverable is working scripts and a baseline number.

### M5: Truck day one
- `/figure-it-out`. This is a multi-part run with real unknowns (ECU type, dongle compatibility, photo quality). Let it design the run, keep a decision trail with `show-me-your-work`, and resolve TBDs in `TRUCK.md` only from photographed or measured evidence.
- If the ECU result changes the telemetry plan, run `/blast-radius` on the `TelemetrySource` seams.

### M6: Phase 1 release
- Demo video, write-up, TestFlight: owner work plus plain `/poteto-mode` for docs. No nested playbooks.
- `/maintain-verification-skill` before the release build.

### Phase 2 and Phase 3
- Phase 2 kickoff: `/figure-it-out` to plan M7 to M9 against the M4 baselines.
- Detector accuracy and on-device latency: Hillclimb playbook.
- ★ Overlay anchoring design: `/architect`.
- Phase 3 feasibility study: `/figure-it-out` with a falsifiable go/no-go predicate.

## PR review routing

| PR kind | Review |
|---|---|
| Small UI work | Owner review plus screenshots. No `interrogate`. |
| Normal feature or chore | `/no-comments` before review. `/interrogate` only if the owner asks. |
| Contracts, schemas, `TelemetrySource` | `/blast-radius`, then `/interrogate`. |
| Spec guard, citations, anything that decides what vehicle facts reach the user | Always `/interrogate`. Treat "Act on" findings as blocking. |

## Rules that apply in every playbook

- AGENTS.md wins over any playbook default. In particular: never invent vehicle facts, and say what you could not compile.
- `interrogate` returns a verdict. It does not change code. The PR author decides what to apply.
- A verify skill run beats a claim. When `verify-ios` cannot run on Linux, the PR says so and the owner runs it.
