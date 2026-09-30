# Roadmap

Phase 1 is detailed. Phases 2 and 3 are lighter and will be re-planned when Phase 1 ships.

Every milestone ends with a build log entry in `docs/build-log/` that reports its exit metrics.

Issues for each milestone live in [BACKLOG.md](BACKLOG.md) and `backlog/issues.json`.

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
- Repo layout: `app/`, `backend/`, `ml/`, `docs/`, `docs/build-log/`, `scripts/`, `backlog/`.
- Xcode SwiftUI project in `app/` (created by the owner on the Mac) and a pure-Swift `SidekickCore` package that also builds on Linux.
- Linux CI running backend tests and `swift test` for `SidekickCore`.
- PR and issue templates. Labels, milestones, and issues created from `backlog/issues.json`. Projects board set up per `docs/KANBAN.md`.
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

**Goal.** "Check the intake manifold first" comes with a photo where the intake manifold is clearly lit up. Prototyped on public 2JZ-GE bay photos.

**Deliverables**
- Bay map schema designed with `/architect`: camera angles, photos, parts, region polygons, confirmation status, source, license.
- A small set of public 2JZ-GE bay photos, each with its license and source noted. Prototype use only.
- Labeling workflow: draw regions in an existing tool, export, convert to the bay map schema with a script.
- Highlight renderer prototype in Python: outline, saturate, circle, dim the rest. Golden-image tests.
- Visual style bakeoff with `/arena` to pick the treatment that reads best on a phone.
- Swift renderer (Core Image) that matches the Python goldens within a pixel tolerance.
- Part resolver: the LLM picks a part ID from the bay map's closed vocabulary. Unknown part means no highlight, and the answer says so.
- End-to-end: chat answer shows the highlighted bay photo.
- Highlight eval: correct-part rate and IoU.

**Exit criteria**
- [ ] Correct-part rate ≥ 0.90 on golden questions that name a mapped part.
- [ ] Region IoU ≥ 0.80 against held-out hand labels.
- [ ] Swift and Python renderers agree within the chosen tolerance on every golden image.
- [ ] Zero highlights on parts that are not in the bay map (checked by eval).
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

**Goal.** Turn every TBD that can be resolved in a day into a confirmed fact, and capture the photos the bay map needs.

**Deliverables** (checklist lives in `docs/vehicle/DAY_ONE.md`)
- Read and photograph the ECU label (89661-xxxxx). Record the full number in `TRUCK.md`. Decide the OBD path.
- Photograph the bay from the fixed angle list, with the same phone position and lighting notes each time.
- Photograph the harness and the firewall pass-through.
- Test the BLE dongle: does it connect, which protocol, any readings.
- Build bay map v1 from my own photos. The owner confirms each part region.

**Exit criteria**
- [ ] ECU number recorded with a photo. OBD1 vs OBD-II decided and written down.
- [ ] Every angle on the shot list captured.
- [ ] Dongle result recorded (works, partial, or not compatible).
- [ ] Bay map v1 covers at least the parts in the golden question set, all confirmed.
- [ ] Highlight eval re-run on my truck's photos. Numbers in the build log.

### M6: Phase 1 release

**Goal.** A version I use in the garage and can show an employer.

**Deliverables**
- `docs/METRICS.md` current (generated by the M2 eval script).
- TestFlight build on my phone.
- Demo video and a portfolio write-up linking the build log.

**Exit criteria**
- [ ] All M2 and M3 metric targets met on my truck's bay map.
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
