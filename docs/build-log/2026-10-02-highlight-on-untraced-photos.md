# Highlight on any photo

Requirement change. No code, schema, or tests changed. The approach is a spike, then an Engineer design PR. This is not an M3 close-out.

## Date

2026-10-02

## Milestone

M3 — Bay map and highlight engine (checkpoint)

## What shipped

The owner changed the highlight rule, and the product lead and the engineer agreed the follow-on issues.

- A highlight works on any still photo, including one that has never been traced. The mark is a precise outline of the part, or of a group of parts. A bounding box is never the highlight. Styles stay outline, saturate, circle, and dim the rest. Phase 1 does not track the live camera.
- The hand-traced bay map is optional. It is an accuracy boost on the owner's reference photos, and the answer key for mask IoU. A confirmed highlight can be saved back as a traced region.
- The pipeline is not chosen. [Issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85) compares three candidates. A (preferred): a vision model grounds the part, then SAM 2 cuts the mask. B (open baseline): Grounding DINO plus SAM 2. C: a vision model draws the mask directly. Each adds a verify pass that sets confidence.
- Open decision: whether the product may call a paid vision API. A and C need that call. Until Zeke decides, only B runs, and nothing calls a paid vision API.
- Confidence ([issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87)). Confident: a precise outline. Unsure: a softer highlight and "Is this it?" with Yes and Not this, logged as eval data. Not found: no highlight, plus a pointer to the manual diagram. A wrong highlight is worse than none.
- The answer highlight is still `bay_photo_id` plus `part_id`. The bay-map-only resolver from [issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32) stays in the tree. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) (contract v2; reopens [issue #9](https://github.com/zeketx/sidekick-mechanic/issues/9) and [issue #10](https://github.com/zeketx/sidekick-mechanic/issues/10)) and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33) rework that path. The schema was not edited.
- Order: [issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84) → #85 → Engineer design PR → #86 → #87 → [issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31) → #33 → [issue #88](https://github.com/zeketx/sidekick-mechanic/issues/88).
- Ship targets below replace correct-part ≥ 0.90 and region IoU ≥ 0.80. They are proposed, pending Zeke's confirmation after #85. If no candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship.

Living text is in [VISION.md](../../VISION.md), [ROADMAP.md](../../ROADMAP.md), [AGENTS.md](../../AGENTS.md), [docs/BAY_MAP.md](../BAY_MAP.md), and [docs/design/bay-map.md](../design/bay-map.md). The 2026-10-01 kickoff still shows the old highlight targets, with a pointer here.

## Metrics

Docs only. The harness was not re-run. Last harness output is [docs/METRICS.md](../METRICS.md) (2026-10-01). That file is generated and still scores confirmed bay-map polygons. Product rows from [VISION.md](../../VISION.md) are `not measured` here.

| Area | Metric | Value | Target | Source |
|---|---|---|---|---|
| RAG | Retrieval recall@5 | not measured | ≥ 0.85 | harness not re-run |
| RAG | Citation accuracy | not measured | ≥ 0.95 | harness not re-run |
| Safety | Spec refusal correctness | not measured | 100% | harness not re-run |
| Safety | Uncited numbers | not measured | 0 | harness not re-run |
| Chat | End-to-end latency | not measured | p50 < 4 s, p95 < 8 s | harness not re-run |
| Highlight | Wrong part, confident | not measured | ≤ 5% (proposed) | pending Zeke's confirmation after #85 |
| Highlight | Right part, confident | not measured | ≥ 85% (proposed) | pending Zeke's confirmation after #85 |
| Highlight | Median mask IoU | not measured | ≥ 0.6, bucketed by part size (proposed) | pending Zeke's confirmation after #85 |
| Highlight | Abstain | not measured | up to 40% acceptable for v1 (proposed) | pending Zeke's confirmation after #85 |
| Highlight | Photo latency and cost | not measured | p95 ≤ 8 s and ≤ $0.03 per photo (proposed) | pending Zeke's confirmation after #85 |
| ML (Phase 2) | Detection quality | not measured | baseline first | Phase 2 |
| ML (Phase 2) | On-device inference | not measured | baseline first | Phase 2 |
| Telemetry (Phase 2) | Read latency and rate | not measured | baseline first | Phase 2 |
| Process | Build log cadence | this entry | ≥ 1 per milestone | `docs/build-log/` |

## What broke

Nothing in the running app. The merged highlight path still requires a confirmed bay-map region. That is the gap #86 and #33 close.

## Next

1. #84 held-out labeled photo set.
2. #85 spike. Only path B until the paid-API decision.
3. Engineer design PR.
4. #86 answer contract v2. Schema stays put until then.
5. #87 confidence UX, then #31, then #33, then #88.
6. Zeke confirms or revises the proposed targets after #85. If no candidate gets wrong-part ≤ 5%, stop and rethink.
