# Vehicle fact registry

This file is the source of truth for facts about this truck. Agents must not invent values, fill in "typical" numbers, or copy ECU numbers, protocols, part numbers, pinouts, wire colors, or years from memory or the web.

**The truck has not been delivered.** Confirmed rows are only facts already stated in this repo's planning docs. Everything else is `TBD`.

## How a row becomes confirmed

A row stays `TBD` until it is confirmed by one of:

1. **Owner observation** — photographed or written down from the truck, then recorded here with the date and a source note (for example, "owner observation, photo of ECU label").
2. **Manual page** — a document ID and page listed in `docs/MANUALS.md`.

To confirm a row: set **Value** to the observed or cited fact, set **Status** to `confirmed`, and fill **Source** and **Date**. Do not confirm from memory, forums, or a "typical" value for similar vehicles.

## Facts

| Fact | Value | Status | Source | Date |
|---|---|---|---|---|
| Chassis | 1990 Toyota Land Cruiser LJ78 (Prado 70-series) | confirmed | [VISION.md](../../VISION.md) | 2026-09-30 |
| Engine | 2JZ-GE swap | confirmed | [VISION.md](../../VISION.md), [AGENTS.md](../../AGENTS.md) | 2026-09-30 |
| Donor ECU | Lexus donor ECU | confirmed | [VISION.md](../../VISION.md), [AGENTS.md](../../AGENTS.md) | 2026-09-30 |
| Donor ECU number | TBD | TBD | Identification plan: [ECU.md](ECU.md). Value stays TBD until a photo of the `89661-` label is recorded here. | — |
| OBD protocol | TBD | TBD | Identification plan: [ECU.md](ECU.md). TBD until delivery; do not infer from a guessed year. | — |
| Donor model year | TBD | TBD | Identification plan: [ECU.md](ECU.md). Catalog lookup of the photographed `89661-` number may identify an application after delivery. | — |
| Harness notes | TBD | TBD | Diagnostic-connector photos: [ECU.md](ECU.md). | — |
| Dongle compatibility | TBD | TBD | Identification plan: [ECU.md](ECU.md). | — |
| Bay photo angle list | TBD | TBD | Planned angles: [DAY_ONE.md](DAY_ONE.md). Value stays TBD until those photos are recorded here. | — |
| Truck delivered | no | confirmed | [VISION.md](../../VISION.md), [AGENTS.md](../../AGENTS.md) | 2026-09-30 |
| Delivery date | TBD | TBD | — | — |

Unconfirmed rows are blocked on delivery. Do not treat a planning mention (for example a future telemetry path) as a confirmed hardware fact.

Delivery day is [DAY_ONE.md](DAY_ONE.md). Fill TBD rows from that checklist. The checklist is not a confirmation.

## Changelog

| Date | Change |
|---|---|
| 2026-10-01 | Registry created. Confirmed rows copied from [VISION.md](../../VISION.md) and [AGENTS.md](../../AGENTS.md). Remaining rows `TBD`, blocked on delivery. |
| 2026-10-01 | Pointed the bay photo angle list at [DAY_ONE.md](DAY_ONE.md). Value stays TBD until the photos exist. |
| 2026-10-01 | Linked [ECU.md](ECU.md) from the ECU / OBD / donor-year / harness / dongle TBD rows. Values unchanged. |
