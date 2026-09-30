# Kanban board

One GitHub Projects (v2) board named **Sidekick Mechanic** tracks all work in `zeketx/sidekick-mechanic`.

## Columns

Use the board's built-in **Status** field with these options, in this order.

| Column | Means | Who moves it here |
|---|---|---|
| **Backlog** | Written, not yet ready. May be missing details or blocked on the truck. | Default for new issues |
| **Ready** | Acceptance criteria are clear, dependencies are done, anyone (human or agent) can start. | Owner |
| **In Progress** | Someone is working on it. One owner per issue. | Whoever starts it |
| **In Review** | PR open and linked with `Closes #N`. Waiting on review, CI, or owner build in Xcode. | PR author |
| **Done** | PR merged and the issue's acceptance criteria are checked off. | Automatic on merge |

Rules:
- Keep **In Progress** to 3 items or fewer.
- Anything blocked on truck delivery stays in **Backlog** with a `TBD: delivery` note in the issue body.
- An agent only picks up issues in **Ready**.

## Labels

Every issue gets exactly one `phase`, one `type`, one `size`, and one or more `area` labels.

| Group | Labels | Meaning |
|---|---|---|
| Phase | `phase:1` | Chat sidekick, bay map, grounded answers (current) |
| | `phase:2` | Live AR, ML detection, telemetry |
| | `phase:3` | Garage projector moonshot |
| Area | `area:ios` | SwiftUI app and the `SidekickCore` package |
| | `area:ml` | Datasets, training, Core ML export |
| | `area:telemetry` | OBD, BLE, `TelemetrySource`, simulator |
| | `area:rag` | Backend, ingestion, retrieval, citations, LLM |
| | `area:highlight` | Bay map and highlight rendering |
| | `area:docs` | Docs, build log, vehicle facts |
| Type | `type:feature` | New user-visible behavior |
| | `type:chore` | Setup, tooling, maintenance |
| | `type:spike` | Time-boxed investigation that ends in a written result |
| | `type:bug` | Something is broken |
| Size | `size:S` | Under a day |
| | `size:M` | One to three days |
| | `size:L` | More than three days. Split it before moving to Ready. |

Epics for Phases 2 and 3 are `size:L` issues with titles starting `Epic:`. Split them when their phase starts.

## Milestones

Milestones match [ROADMAP.md](../ROADMAP.md): M0 to M6 for Phase 1, M7 to M9 for Phase 2, M10 for Phase 3. Definitions live in `backlog/milestones.json`.

## Setup (owner, once GitHub access is set up)

1. Preview: `DRY_RUN=1 scripts/create_issues.sh`
2. Create labels, milestones, and issues: `scripts/create_issues.sh`
3. Create the board (needs `gh auth refresh -s project`):
   `gh project create --owner zeketx --title "Sidekick Mechanic"`
4. Link it to the repo: `gh project link <number> --owner zeketx --repo zeketx/sidekick-mechanic`
5. In the board settings, set the Status options to the five columns above.
6. Turn on the built-in workflows: "Item added to project → Backlog", "Pull request merged → Done", "Item closed → Done".
7. Add all issues: re-run step 2 with `PROJECT="Sidekick Mechanic"` for new issues, or bulk-add existing ones from the board's "Add item" menu.

Suggested views: **Board** grouped by Status. **Table** grouped by Milestone. **Phase 1** filtered to `label:phase:1`.

## Editing the backlog

`backlog/issues.json` is the source of truth until the issues exist on GitHub. After that, GitHub is the source of truth.

- Edit the JSON, then run `python3 scripts/render_backlog.py` to refresh `BACKLOG.md`.
- `scripts/create_issues.sh` skips issues whose exact title already exists, so re-running it only adds new ones.
