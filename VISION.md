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

Highlights come from a **bay map**: a set of reference photos of my bay, shot from fixed angles, with each part's region drawn and confirmed by hand. Phase 1 does not track anything live.

## The three phases

### Phase 1: Chat sidekick (current focus)

- Chat UI on iPhone.
- Grounded answers over the 2JZ-GE repair manual and the LJ78 wiring docs, with page citations.
- A bay map of my truck built from fixed-angle reference photos with confirmed part regions.
- A highlight engine that outlines, saturates, circles, and dims to point at one part.
- Before delivery, prototype on public 2JZ-GE bay photos. After delivery, switch to my own photos.

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

| Area | Metric | How measured | Initial target |
|---|---|---|---|
| RAG | Retrieval recall@5 | Golden question set with known answer pages | ≥ 0.85 |
| RAG | Citation accuracy | % of answers whose cited page actually supports the claim | ≥ 0.95 |
| Safety | Spec refusal correctness | % of unanswerable spec/pinout questions answered "not found" instead of a number | 100% |
| Safety | Uncited numbers | Count of numeric specs shown without a citation, across the eval set | 0 |
| Chat | End-to-end latency | p50 / p95 from send to rendered answer | p50 < 4 s, p95 < 8 s |
| Highlight | Correct-part rate | % of golden questions where the highlighted part is the right one | ≥ 0.90 |
| Highlight | Region quality | IoU of rendered region vs held-out hand label | ≥ 0.80 |
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
