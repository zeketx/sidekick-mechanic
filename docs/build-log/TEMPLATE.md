# Build log entry template

Copy this file to `docs/build-log/YYYY-MM-DD-<slug>.md` when a milestone closes, or at a checkpoint that employers should be able to follow. Fill every section.

Metrics must come from a command, file, or GitHub query you actually ran. Copy numbers from eval JSON (`backend/eval/results/`) when that harness exists. Write `not measured` when it does not. Do not invent a value, and do not paste a vehicle spec, torque, pinout, or part number from memory.

## Date

YYYY-MM-DD

## Milestone

M? — title from [ROADMAP.md](../../ROADMAP.md). Say whether this is a checkpoint or a close-out.

## What shipped

- Merged work, with issue numbers. Link PRs when they help a reader find the diff.

## Metrics

| Area | Metric | Value | Target | Source |
|---|---|---|---|---|
| | | | | |

Keep the [VISION.md](../../VISION.md) portfolio rows in the table even when the value is `not measured`, so later entries stay comparable.

## What broke

Failures, reopened issues, blocked work. Write `Nothing reported` if the checkpoint was clean.

## Next

Concrete follow-ups: issue numbers, owner-only tasks, or the next milestone's first issue.
