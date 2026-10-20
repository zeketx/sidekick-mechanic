# Roadmap

Phase 1 is detailed. Phases 2 and 3 are lighter and will be re-planned when Phase 1 ships.

Every milestone ends with a build log entry in `docs/build-log/` that reports its exit metrics.

Issues for each milestone live on [GitHub Issues](https://github.com/zeketx/sidekick-mechanic/issues) and [GitHub milestones](https://github.com/zeketx/sidekick-mechanic/milestones).

## Timeline at a glance

```
Before delivery:  M0 → M1 → M2 → M3 → M4 (M2/M3 can overlap)
Delivery day:     M5
After delivery:   M6 (Phase 1 release) → Phase 2 (M7–M9) → Phase 3 (M10)
```

The truck delivery date is TBD. M0 through M4 do not need the truck. M5 is the only milestone that is blocked on it.

---

## Phase 1: Chat sidekick

### M0: Repo, tooling, and ECU check

**Goal.** A working repo that cloud agents and the owner can both build in, plus a plan for identifying the ECU on day one.

**Deliverables**
- Repo layout: `app/`, `backend/`, `ml/`, `docs/`, `docs/build-log/`, `scripts/`.
- Xcode SwiftUI project in `app/` (created by the owner on the Mac) and a pure-Swift `SidekickCore` package that also builds on Linux.
- Linux CI running backend tests and `swift test` for `SidekickCore`.
- PR and issue templates. Labels, milestones, and issues are on [GitHub Issues](https://github.com/zeketx/sidekick-mechanic/issues). Projects board set up per `docs/KANBAN.md`.
- `docs/vehicle/TRUCK.md`: a registry of every vehicle fact with status (TBD or confirmed), source, and date.
- `docs/vehicle/ECU.md`: how to read the ECU label (89661-xxxxx) and a decision tree for OBD-II vs OBD1.
- Manual inventory and storage policy (PDFs stay out of git).
- Build log template and first entry.

**Exit criteria**
- [ ] App shows a placeholder screen in the iOS Simulator on the owner's Mac.
- [ ] `swift build && swift test` passes for `SidekickCore` on Linux CI.
- [ ] Backend test suite runs green on CI (even if it only has one test).
- [ ] All labels, milestones, and issues exist on GitHub. Board shows them.
- [ ] ECU type is either confirmed in `TRUCK.md`, or explicitly marked "TBD, blocked on delivery" with both the OBD-II and OBD1 paths planned in `ECU.md`.

### M1: Chat sidekick shell

**Goal.** Chat on the phone end to end, with a real LLM behind it, before any grounding.

**Deliverables**
- Conversation data model designed with `/architect`: message, answer, citation, highlight reference.
- Shared JSON contract for an answer (text, citations, optional highlight), with fixtures tested on both the Swift and Python sides.
- SwiftUI chat screen: message list, composer, answer cards with citation chips and an image slot.
- iOS network client with a mock mode, so UI work never needs the backend.
- Backend `/chat` endpoint. LLM behind an adapter interface. Keys from environment only.
- Safety preamble for procedure answers.
- Project-local verification skills, generated with `/create-verification-skill` once the app runs.

**Exit criteria**
- [ ] On the phone, send a message and get an LLM reply rendered as an answer card.
- [ ] Mock mode renders every fixture in the contract, including one with citations and one with a highlight slot.
- [ ] Contract fixtures decode in `SidekickCore` tests and validate in backend tests.
- [ ] p50 latency from send to render measured and logged (no target yet, baseline only).
- [ ] Verification skill runs end to end at least once and leaves evidence.

### M2: Grounded answers over the manuals

**Goal.** Answers come from the 2JZ-GE repair manual and the LJ78 wiring docs, with page citations. Specs are never guessed.

**Deliverables**
- Ingestion: PDF to page-level chunks, each tagged with document ID and page number.
- Embedding and retrieval index. Store choice made in an `/architect` session (keep it lightweight).
- Citation format: every claim from a manual carries `{doc_id, page, snippet}`.
- Spec guard: a post-generation check that blocks any number-with-unit or pinout not present in the retrieved text.
- Spike on wiring diagrams: text extraction vs citing the page image.
- Golden question set (target 50 questions) with expected pages, including unanswerable spec questions.
- Eval harness producing a metrics JSON file for the build log.
- Citation viewer on iOS: tap a chip, see the page.

**Exit criteria**
- [ ] Retrieval recall@5 ≥ 0.85 on the golden set.
- [ ] Citation accuracy ≥ 0.95 on the golden set.
- [ ] Spec refusal correctness = 100% on the unanswerable subset.
- [ ] Zero uncited numeric specs across the full eval run.
- [ ] Eval runs in CI on every backend PR and posts the numbers.
- [ ] p50 < 4 s and p95 < 8 s end to end, or a written plan to get there.

### M3: Bay map and highlight engine

**Goal.** "Check the intake manifold first" comes with a photo where that part, or that assembly, is clearly lit up. The mark is a precise outline of the actual shape. A bounding box is never the highlight. The person asking does not know engines or part names. Pointing at the right thing is the point. It works on any still photo, including one that has never been traced. Prototyped on public 2JZ-GE bay photos. Phase 1 does not track the live camera.

**Already merged, and slated to be reworked.** The answer highlight is `highlight_ref`: `bay_photo_id` plus `part_id`. The resolver ([issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32), closed) only highlights a part with a confirmed region on the bay map. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33) replace that path. Do not extend the closed vocabulary as the way a new photo gets a highlight.

**Deliverables**
- Highlight on untraced photos, precise mask. Any still photo, with no prior trace. Styles stay outline, saturate, circle, and dim the rest.
- [Issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84). Held-out labeled photo set. About 20 public photos, disjoint from the prototype set. About 100–160 photo×part queries, including "not visible". Polygon labels. No boxes for those labels.
- [Issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85). Spike, time box about 2–3 days. Three pipelines. Each adds a verify pass that sets confidence.
  - **A (preferred).** A vision model grounds the part, then SAM 2 cuts the mask.
  - **B (open baseline).** Grounding DINO plus SAM 2.
  - **C.** A vision model draws the mask directly.
  - Zeke approved a paid vision API on 2026-10-02. The provider is OpenRouter. Paths A and C are unblocked for the #85 spike. The cost target is still ≤ $0.03 per photo. The key is a Railway secret for the product and is never committed.
  - If no candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship.
- Engineer design PR after the spike, before the contract change. It records the pipeline choice, backend vs on-device, and the contract shape.
- [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86). Answer contract v2: photo ref, polygons plus an optional mask, labels, state (`confident`, `unsure`, `not_found`), method (`traced` or `inferred`), and scores. Reopens the highlight shape from [issue #9](https://github.com/zeketx/sidekick-mechanic/issues/9) and [issue #10](https://github.com/zeketx/sidekick-mechanic/issues/10). The schema in the repo stays as it is until this issue.
- [Issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87). Confidence UX. Confident: a precise outline. Unsure: a softer highlight and "Is this it?" with Yes and Not this, logged as eval data. Not found: no highlight, plus a pointer to the manual diagram. Precision-first. A wrong highlight is worse than none. A confirmed highlight can be saved back as a traced region.
- Bay map schema: camera angles, photos, parts, region polygons, confirmation, source, license. Optional. An accuracy boost on the owner's reference photos, and the answer key for mask IoU. Not required before a photo can be highlighted.
- Labeling workflow: draw regions, export, convert to the bay map schema. Used for #84 and for traces the owner confirms. A highlight region follows the part. A box is not a highlight.
- A small set of public 2JZ-GE bay photos, each with its license and source noted. Prototype use only. The #84 set is disjoint from these.
- Highlight renderer prototype in Python: outline, saturate, circle, dim the rest, on a precise outline. Golden-image tests. The unsure state gets a softer treatment in #87.
- Visual style bakeoff with `/arena` to pick the treatment that reads best on a phone. The four treatments stay available.
- [Issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31). Swift renderer (Core Image) that matches the Python goldens within a pixel tolerance. After #87.
- [Issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33). End-to-end: the chat answer shows the highlighted photo, including a photo that was not in the bay map.
- [Issue #88](https://github.com/zeketx/sidekick-mechanic/issues/88). Acceptance eval on the held-out set.

**Order.** #84 → #85 → Engineer design PR → #86 → #87 → #31 → #33 → #88.

**Exit criteria.** Proposed, pending Zeke's confirmation after #85. [#85](https://github.com/zeketx/sidekick-mechanic/issues/85) and [#88](https://github.com/zeketx/sidekick-mechanic/issues/88) call the two rates wrong-highlight and correct-part. These replace correct-part ≥ 0.90 and region IoU ≥ 0.80.

- [ ] On confident highlights, wrong part ≤ 5% and right part ≥ 85%, on the held-out set.
- [ ] Median mask IoU ≥ 0.6, reported in part-size buckets (large, medium, small-or-thin).
- [ ] Abstain (unsure + not found) up to 40% is acceptable for v1.
- [ ] p95 latency ≤ 8 s end to end on the backend, and ≤ $0.03 per photo.
- [ ] If no spike candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship.
- [ ] Swift and Python renderers agree within the chosen tolerance on every golden image.
- [ ] Demo clip of the full flow on the phone, in the build log.

### M4: Pre-delivery groundwork for Phase 2

**Goal.** De-risk Phase 2 while waiting for the truck. Labeled `phase:2`, scheduled before delivery.

**Deliverables**
- `TelemetrySource` protocol in `SidekickCore` plus a simulator that replays scripted scenarios (for example, cold start, warm idle).
- ML pipeline dry run: public bay photos → Roboflow labels → YOLO11n training with Ultralytics → Core ML export → one inference on the phone.

**Exit criteria**
- [ ] Simulator drives a live-updating readings view in the app, no hardware.
- [ ] Protocol has a documented seam for an ELM327 source and an OBD1 source.
- [ ] Core ML model runs on device. Inference ms per frame recorded as a baseline.
- [ ] Every pipeline step is a script in `ml/` that reruns from a clean checkout.

### M5: Truck day one

**Goal.** Turn every TBD that can be resolved in a day into a confirmed fact, and capture reference photos of the bay. Highlighting those photos does not wait on hand traces.

**Deliverables** (checklist lives in `docs/vehicle/DAY_ONE.md`)
- Read and photograph the ECU label (89661-xxxxx). Record the full number in `TRUCK.md`. Decide the OBD path.
- Photograph the bay from the fixed angle list, with the same phone position and lighting notes each time.
- Photograph the harness and the firewall pass-through.
- Test the BLE dongle: does it connect, which protocol, any readings.
- Optional bay map v1 from my own photos. Hand traces are an accuracy boost and the IoU answer key. A highlight I confirm can be saved back as a traced region. [Issue #40](https://github.com/zeketx/sidekick-mechanic/issues/40) is that labeling pass.

**Exit criteria**
- [ ] ECU number recorded with a photo. OBD1 vs OBD-II decided and written down.
- [ ] Every angle on the shot list captured.
- [ ] Dongle result recorded (works, partial, or not compatible).
- [ ] Hand labels exist for owner photos that will be scored, or the build log says which parts are still unlabeled. Highlighting the day-one photos does not wait on those labels.
- [ ] Highlight eval re-run on my truck's photos, against those hand labels. Numbers in the build log.

### M6: Phase 1 release

**Goal.** A version I use in the garage and can show an employer.

**Deliverables**
- `docs/METRICS.md` current (generated by the M2 eval script).
- TestFlight build on my phone.
- Demo video and a portfolio write-up linking the build log.

**Exit criteria**
- [ ] All M2 targets met, and the M3 highlight targets (once Zeke confirms them after #85) met on the acceptance eval.
- [ ] Used for at least one real diagnostic session, logged in the build log.
- [ ] Demo video under 2 minutes.

---

## Phase 2: Live AR and telemetry (lighter)

### M7: On-device part detection
- Train YOLO11n on my bay photos (Roboflow, Ultralytics). Export to Core ML. Run on the ANE.
- **Exit:** mAP50 and ms per frame reported against the M4 baseline. Sustained FPS measured on device.

### M8: Live telemetry
- BLE ELM327 source over CoreBluetooth behind `TelemetrySource`. OBD1 fallback source only if M5 says the ECU is pre-OBD-II.
- **Exit:** read latency and Hz per signal measured on the truck. Simulator and real source pass the same protocol tests.

### M9: Live overlay with anchored readings
- Vision framework overlay on the camera feed. Readings drawn on the detected part they describe.
- **Exit:** overlay drift and end-to-end latency measured. Works in garage lighting.

## Phase 3: Garage projector (moonshot)

### M10: Feasibility study
- Ceiling camera plus projector over the bay. Calibrate projector to camera. Light up one part and one tool.
- **Exit:** a written go/no-go with measured projection alignment error and a cost estimate.

## Parked: exploded teardown

Not a milestone. [Issue #157](https://github.com/zeketx/sidekick-mechanic/issues/157) stays in the backlog until Phase 1 ships, then gets its own milestone. It is not M7, M8, M9, or M10.

The owner wants the Land Cruiser pulled apart on the phone into pieces they are curious about or that need addressing, with a cited instruction list for the piece they pick. The reference is a shop screen that explodes one engine in removal order and keeps a status ledger. The machining pipeline in that screenshot (CAD kernel, datums, toolpaths) is out of scope. Procedures stay on cited manual pages. The model does not decide what needs work. Truck-specific condition stays TBD until `docs/vehicle/TRUCK.md` says otherwise.
