# Sidekick Mechanic: Vision

## One line

A chat-first AI mechanic on iPhone that knows my truck. Ask it about a problem and it answers from the real manuals, cites the page, and shows a photo of my own engine bay with the part to check highlighted.

## The truck

- 1990 Toyota Land Cruiser LJ78 (Prado 70-series).
- Swapped to a 2JZ-GE, running a Lexus donor ECU.
- **Donor year: TBD.** So whether the ECU speaks OBD1 or OBD-II is **TBD**.
- **Harness details: TBD.** The truck has not been delivered yet.

Every vehicle-specific fact stays marked TBD until it is confirmed on the truck and recorded in `docs/vehicle/TRUCK.md`.

## The problem

Working on a swapped, 35-year-old truck is slow for three reasons:

1. **The information is scattered.** The engine manual, the chassis wiring docs, and forum posts each cover a different part of the vehicle. None of them describe this exact combination.
2. **"Where is that part?" eats time.** The manual says "check the idle air control valve." It does not show where it sits in *this* bay, around *this* swap's plumbing.
3. **Generic AI answers are dangerous here.** A chatbot that guesses a torque spec or a pin number can break parts or hurt someone.

Sidekick Mechanic fixes this with grounded answers, cited sources, and a picture of my bay with the right part lit up.

## What it looks like

> **Me:** Rough idle after cold start.
>
> **Sidekick:** Start with the intake side. The manual's troubleshooting table for this symptom points at the intake and idle control first *(Source: 2JZ-GE repair manual, page TBD)*. Check the intake manifold area first.
>
> *[Photo of my engine bay. Intake manifold outlined and saturated. Rest of the bay dimmed.]*

The person asking knows nothing about engines or part names. Pointing at the right thing is the core of the product.

## How it works

The highlight is a precise outline. It follows the part's actual shape, or the shape of a group of parts, such as a whole assembly. A bounding box is never the highlight. The treatments stay the same: outline, saturate, circle, and dim the rest.

Highlighting works on any still photo, including a new photo that has never been traced. Phase 1 does not track anything live.

A hand-traced bay map is optional. It is reference photos of my bay, from fixed angles, with part regions drawn and confirmed by hand. On those photos it is an accuracy boost. It is also the answer key for scoring a highlight: IoU against the hand labels. A highlight does not wait for a trace.

Finding the part on a new photo, and cutting a pixel-precise mask, is the spike in [issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85). It compares three pipelines. Each one ends with a verify pass that sets confidence. No pipeline is chosen yet.

- **A (preferred).** A vision model grounds the part, then SAM 2 cuts the mask.
- **B (open baseline).** Grounding DINO plus SAM 2.
- **C.** A vision model draws the mask directly.

Zeke approved a paid vision API on 2026-10-02. The provider is OpenRouter. Paths A and C are unblocked for the [#85](https://github.com/zeketx/sidekick-mechanic/issues/85) spike. The cost target is still ≤ $0.03 per photo. The key is a Railway secret for the product and is never committed.

Confidence is [issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87). Thresholds are precision-first. A wrong highlight is worse than none.

- **Confident.** A precise outline.
- **Unsure.** A softer highlight, and the prompt "Is this it?" with **Yes** and **Not this**. The answer is logged as eval data. Yes keeps the highlight. Not this is treated as not found.
- **Not found.** No highlight, plus a pointer to the manual diagram.

A highlight the user confirms can be saved back as a traced region, so the app improves on this truck over time.

Today the answer contract's highlight is `bay_photo_id` plus `part_id`, resolved against a pre-traced bay map. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) replaces that with contract v2: a photo ref, polygons plus an optional mask, labels, a state, a method (`traced` or `inferred`), and scores. That reopens the highlight shape from [issue #9](https://github.com/zeketx/sidekick-mechanic/issues/9) and [issue #10](https://github.com/zeketx/sidekick-mechanic/issues/10). The schema stays as it is until #86. The bay-map-only resolver from [issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32) is reworked through #86 and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33).

The work order is [issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84), then #85, then an Engineer design PR, then #86, then #87, then [issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31), then #33, then [issue #88](https://github.com/zeketx/sidekick-mechanic/issues/88).

## The three phases

### Phase 1: Chat sidekick (current focus)

- Chat UI on iPhone.
- Grounded answers over the 2JZ-GE repair manual and the LJ78 wiring docs, with page citations.
- A highlight engine that outlines, saturates, circles, and dims the rest. The mark is a precise outline of the part or assembly, on any still photo, including one that has never been traced. Phase 1 does not track the live camera.
- An optional bay map of my truck: fixed-angle reference photos with confirmed part regions. An accuracy boost on those photos, and the hand labels that score mask IoU.
- Before delivery, prototype on public 2JZ-GE bay photos. After delivery, the same highlighter runs on my own photos, traced or not.

### Phase 2: Live AR and telemetry

- YOLO11n part detector trained with Roboflow and Ultralytics, exported to Core ML, running on the Apple Neural Engine.
- Vision framework overlay on the live camera feed.
- BLE ELM327 OBD-II dongle over CoreBluetooth. Live readings anchored on the parts they describe.
- A swappable telemetry data-source protocol with a simulator, so all of this is testable without the truck.
- An OBD1 fallback data source if the ECU turns out to be pre-OBD-II (TBD).

### Phase 3: Garage projector (moonshot)

A ceiling-mounted camera and projector over the engine bay. It lights up the part to work on and the tool to grab, like a master mechanic guiding an apprentice. Phase 3 starts as a feasibility study, not a commitment.

## Principles

1. **Grounded.** Answers come from retrieved manual text, not model memory. When retrieval finds nothing, the answer says so.
2. **Cited.** Every spec, procedure step, connector, and pinout names its source document and page. No citation, no number.
3. **Safety-first.** Never invent torque values, pinouts, wire colors, or part numbers. Flag hazards (hot engine, fuel, battery, jacking) before procedure steps. When unsure, say "I don't know, check the manual" instead of guessing.
4. **Built for my truck first.** One vehicle, done well. Generalizing to other vehicles is a later question.
5. **Measured.** Every milestone ends with numbers in the build log, not adjectives.
6. **Simple and swappable.** Hardware-facing pieces (telemetry, camera, detector) sit behind small protocols with simulators, so they can be built and tested before the hardware exists.

## Portfolio metrics to track

These are the numbers the build log reports. Targets are starting points, to be revised once a baseline exists.

Highlight rows are **proposed, pending Zeke's confirmation after [#85](https://github.com/zeketx/sidekick-mechanic/issues/85)**. They replace the earlier targets (correct-part ≥ 0.90, region IoU ≥ 0.80). [#85](https://github.com/zeketx/sidekick-mechanic/issues/85) and [#88](https://github.com/zeketx/sidekick-mechanic/issues/88) call the two rates wrong-highlight and correct-part. If no spike candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship.

| Area | Metric | How measured | Initial target |
|---|---|---|---|
| RAG | Retrieval recall@5 | Golden question set with known answer pages | ≥ 0.85 |
| RAG | Citation accuracy | % of answers whose cited page actually supports the claim | ≥ 0.95 |
| Safety | Spec refusal correctness | % of unanswerable spec/pinout questions answered "not found" instead of a number | 100% |
| Safety | Uncited numbers | Count of numeric specs shown without a citation, across the eval set | 0 |
| Chat | End-to-end latency | p50 / p95 from send to rendered answer | p50 < 4 s, p95 < 8 s |
| Highlight | Wrong part, confident | Share of confident highlights that name the wrong part, on the held-out set | ≤ 5% (proposed) |
| Highlight | Right part, confident | Share of confident highlights that name the right part, on the held-out set | ≥ 85% (proposed) |
| Highlight | Mask quality | Median IoU of the precise outline vs held-out hand labels, reported in part-size buckets (large, medium, small-or-thin) | ≥ 0.6 (proposed) |
| Highlight | Abstain | Unsure plus not found, as a share of queries. Acceptable for v1, not a goal | up to 40% (proposed) |
| Highlight | Photo latency and cost | p95 end to end on the backend, and dollars per photo | ≤ 8 s and ≤ $0.03 (proposed) |
| ML (Phase 2) | Detection quality | mAP50 on a held-out set of my bay | Baseline first |
| ML (Phase 2) | On-device inference | ms per frame on ANE, sustained FPS | Baseline first |
| Telemetry (Phase 2) | Read latency and rate | ms per PID read, Hz per signal over BLE | Baseline first |
| Process | Build log cadence | Entries per milestone, each with metrics | ≥ 1 per milestone |

## Non-goals

- Supporting other vehicles in Phase 1.
- Live part tracking in Phase 1. That is Phase 2.
- Writing to the ECU, tuning, or clearing codes. Read-only.
- Replacing the manual. The app points to the manual, it does not stand in for it.
- A public App Store release. TestFlight for me is enough.
- Shipping copyrighted manual PDFs in the repo.
