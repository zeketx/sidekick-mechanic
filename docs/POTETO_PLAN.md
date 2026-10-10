# Poteto plan

How to run this build with **poteto mode**, the agent playbooks in the pstack plugin. This page says which skill to use at which milestone, and how to keep cost down.

Every skill named here exists in pstack today. The skill descriptions below are summarized from each skill's `SKILL.md`. If a skill is renamed or removed, fix this page in its own PR.

## When to use poteto-mode

The pstack plugin is enabled by the repo in [`.cursor/settings.json`](../.cursor/settings.json) (`plugins.pstack.enabled`). Role models are pinned in [`.cursor/rules/pstack-models.mdc`](../.cursor/rules/pstack-models.mdc) (`alwaysApply: true`). That file is the project copy of the rule `/setup-pstack` would write at `~/.cursor/rules/pstack-models.mdc`, which does not travel with the repo.

Checked on this cloud agent on 2026-10-10. `/poteto-mode` and the routed skills (`how`, `why`, `arena`, `swarm`, `architect`, `interrogate`, `reflect`) resolved from the user plugin cache (`~/.cursor/plugins/cache`, pstack `source: user` in `.cloud-plugin-manifest.json`). The checkout this VM booted was behind `main` and did not contain `.cursor/settings.json` until it was fetched, so that run does not show the project file installing the plugin by itself. A subagent in that same session received `AGENTS.md` as an always-applied rule and did not receive the model rule, which was added after the session started. `~/.cursor/rules/pstack-models.mdc` was absent. Locally, if `/poteto-mode` is missing after opening the repo, run `/add-plugin pstack` once and reload the window. pstack's setup guide still documents that command. Do not copy the plugin into `.cursor/skills/` unless that install fails.

Every PR declares a mode on its first line: `Mode: HARD (reason)` or `Mode: LIGHT (reason)`. The `PR mode declared` check fails unless the body has a line matching `^Mode: (HARD|LIGHT)\b` (`HARD` and `LIGHT` are case-sensitive).

- **HARD** — multi-subsystem work, answer/data/retrieval quality, a design decision, about five or more files, or verify failed twice. Use `/poteto-mode`.
- **LIGHT** — one agent, smallest diff. Do not run the poteto-mode playbooks.

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
| `/setup-pstack` | Writes a user-level `~/.cursor/rules/pstack-models.mdc`. This repo already pins every role in `.cursor/rules/pstack-models.mdc`. | Do not run it for this repo. A user-level file would not travel, and it can hide the project pin on that machine. |
| `/how`, `/show-me-your-work` | `how` explains how existing code works before changing it. `show-me-your-work` keeps a decision log for long or unattended runs. | Pulled in by the skills above. Rarely called directly. |

## Cost policy

1. **Every pstack role is `cursor-grok-4.6-xhigh`.** The pin is [`.cursor/rules/pstack-models.mdc`](../.cursor/rules/pstack-models.mdc). pstack's built-in defaults send judgment and prose to Claude, so a missing line spends more than intended. Bare `grok-4.6` is not a Task slug. On 2026-10-10 Task rejected it and listed `cursor-grok-4.6-xhigh` as the grok-4.6 slug at the large (`xhigh`) budget. No Claude, GPT, or Gemini unless the owner asks for that task.
2. **Panels stay small.** `arena runners`, `architect runners`, and `interrogate reviewers` are lists, and each entry is one subagent. Default to two entries, both `cursor-grok-4.6-xhigh`. Only widen to three, or add other model families, for the one-way-door decisions marked ★ below, and only when the owner says so for that task.
3. **Small UI work skips the nested-agent playbooks.** No `architect`, `arena`, `interrogate`, `swarm`, or `no-comments` (it spawns its own subagent). One agent does the work directly and follows AGENTS.md. A task counts as small UI work when all of these are true:
   - It changes SwiftUI views only (layout, copy, styling, previews).
   - It adds or changes no types in `SidekickCore` or `backend/contracts/`.
   - It is under about 150 changed lines.
   Small UI PRs still need screenshots and the definition of done.
4. **Don't repeat design work.** A second `arena` on a settled design is waste (pstack's own `figure-it-out` says the same). Re-architect only when implementation proves the sketch wrong.

## Playbook by milestone

★ = one-way door. Get it right before building on it. Widening the panel is allowed here with owner approval.

### M0: Repo, tooling, and ECU check
- Models are already pinned in `.cursor/rules/pstack-models.mdc`. Do not run `/setup-pstack` for this repo.
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
- Highlight on an untraced photo is the product rule. The mark is a precise outline, never a bounding box. Phase 1 does not track the live camera. The hand-traced bay map is optional: an accuracy boost and the IoU answer key.
- Order: [issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84) → [issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85) → Engineer design PR → [issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) → [issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87) → [issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31) → [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33) → [issue #88](https://github.com/zeketx/sidekick-mechanic/issues/88).
- ★ [Issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85) is the spike. A (preferred) is a vision model that grounds the part, then SAM 2. B (open baseline) is Grounding DINO plus SAM 2. C is a vision model that draws the mask. Do not pick a winner in an implementation PR before the spike and the Engineer design PR. Zeke approved a paid vision API on 2026-10-02. The provider is OpenRouter. Paths A and C are unblocked for the #85 spike. The cost target is still ≤ $0.03 per photo. The key is a Railway secret for the product and is never committed. Proposed targets are pending Zeke's confirmation after this spike. If no candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship.
- ★ Answer contract v2 ([issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86)) reopens #9 and #10. It replaces `highlight_ref` (`bay_photo_id` + `part_id`) and the bay-map-only resolver from #32, together with #33. Run `/blast-radius` before that schema edit, then `/interrogate`.
- ★ Bay map schema: already designed. Optional for highlighting. Any later schema change runs `/blast-radius`, since the schema feeds the renderer, the resolver, the eval, and the Phase 2 detector.
- Highlight renderer: prototype in Python so agents can run golden-image tests on Linux. The part resolver from #32 stays until #86 and #33 rework it.
- Highlight visual style: `/arena` with at least three style candidates. Rubric: part obvious within one second on a phone, context still readable, works on dark and bright bays.
- Swift port of the renderer ([issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31)): `/poteto-mode` Feature playbook, after #87. The owner verifies on the Mac with `verify-ios`.
- End-to-end wiring ([issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33)): Feature playbook, then `/interrogate` on the PR. After #31.
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
