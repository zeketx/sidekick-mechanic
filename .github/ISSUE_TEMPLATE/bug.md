---
name: Bug
about: Something is broken
title: ""
labels: ["type:bug", "phase:1"]
---

## What broke


## Expected


## Actual


## Steps to reproduce

1.
2.
3.

## Environment

- App / backend:
- Simulator or device:
- Mock or live backend:

## Acceptance criteria

- [ ] Failure is reproduced
- [ ] Fix verified (tests and/or screenshots)

## Labels

Exactly one phase, one type, one size, and one or more area (`docs/KANBAN.md`). This template applies `type:bug` and `phase:1` (current). Add area and size; change phase if this is not Phase 1.

- Phase: `phase:1` (chat sidekick) | `phase:2` (live AR, ML, telemetry) | `phase:3` (garage projector)
- Area: `area:ios` | `area:ml` | `area:telemetry` | `area:rag` | `area:highlight` | `area:docs`
- Size: `size:S` (under a day) | `size:M` (one to three days) | `size:L` (split before Ready)

## Notes

- UI bugs need PR screenshots of the broken and fixed states (light, dark, large Dynamic Type where relevant).
- Never invent vehicle facts in a repro or expected result. Cite `docs/MANUALS.md` or `docs/vehicle/TRUCK.md`, or write TBD.
