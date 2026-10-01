---
name: Spike
about: Time-boxed investigation that ends in a written result
title: "Spike: "
labels: ["type:spike", "phase:1"]
---

## Goal

As a developer, I want to know ... so we can choose ...

## Time box

## Written result

Path to the doc this spike produces (for example `docs/design/` or `docs/vehicle/`).

## Acceptance criteria

- [ ] Investigation finished inside the time box
- [ ] Written result committed, with a recommendation and what was tried
- [ ] Every claim cited (manual page from `docs/MANUALS.md`, or `docs/vehicle/TRUCK.md`). Unverified claims marked as such

## Labels

Exactly one phase, one type, one size, and one or more area (`docs/KANBAN.md`). This template applies `type:spike` and `phase:1` (current). Add area and size; change phase if this is not Phase 1.

- Phase: `phase:1` (chat sidekick) | `phase:2` (live AR, ML, telemetry) | `phase:3` (garage projector)
- Area: `area:ios` | `area:ml` | `area:telemetry` | `area:rag` | `area:highlight` | `area:docs`
- Size: `size:S` (under a day) | `size:M` (one to three days) | `size:L` (split before Ready)

## Notes

- A spike ends in a written result, not shipped product behavior.
- Never invent vehicle facts. Unknowns are TBD until confirmed in `docs/vehicle/TRUCK.md`.
- Blocked on truck delivery: leave in Backlog with a `TBD: delivery` note.
