# Backlog

Generated from `backlog/issues.json` by `scripts/render_backlog.py`. Edit the JSON, not this file.

Create these on GitHub with `scripts/create_issues.sh` (see `docs/KANBAN.md`).

Labels: `phase:1/2/3`, `area:ios/ml/telemetry/rag/highlight/docs`, `type:feature/chore/spike/bug`, `size:S/M/L`.

| Milestone | Issues |
|---|---|
| M0: Repo, tooling, and ECU check | 8 |
| M1: Chat sidekick shell | 9 |
| M2: Grounded answers over the manuals | 8 |
| M3: Bay map and highlight engine | 9 |
| M4: Pre-delivery groundwork for Phase 2 | 2 |
| M5: Truck day one | 4 |
| M6: Phase 1 release | 2 |
| M7: On-device part detection | 1 |
| M8: Live telemetry | 2 |
| M9: Live overlay with anchored readings | 1 |
| M10: Garage projector feasibility | 1 |

## M0: Repo, tooling, and ECU check

Repo and tooling ready for agents and the owner. ECU identification planned.

### 1. Scaffold repo layout, README, and .gitignore

**Labels:** `phase:1` `area:docs` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want a predictable repo layout so agents and I always know where code, models, and docs go.

**Acceptance criteria**

- [ ] Folders exist: `app/`, `backend/`, `ml/`, `docs/`, `docs/build-log/`, `docs/vehicle/`, `scripts/`, `backlog/`
- [ ] README explains the project in under 20 lines and links VISION, ROADMAP, BACKLOG, AGENTS
- [ ] `.gitignore` covers Xcode user data, DerivedData, Python venvs and caches, model weights, datasets, and `manuals/`
- [ ] No generated or binary files committed

### 2. Create Xcode SwiftUI app and SidekickCore Swift package

**Labels:** `phase:1` `area:ios` `type:chore` `size:M`  
**Size:** M

**Goal.** As the owner, I want the Xcode project and a pure-Swift core package so UI lives in Xcode and logic can be built and tested on Linux by cloud agents.

**Acceptance criteria**

- [ ] `app/SidekickMechanic.xcodeproj` (owner creates on the Mac) launches a placeholder screen in the iOS Simulator
- [ ] `app/SidekickCore/` is a Swift package with no Apple-only imports (no SwiftUI, UIKit, AVFoundation, Vision, Core ML, CoreBluetooth)
- [ ] `swift build && swift test` passes for `SidekickCore` on Linux
- [ ] App target depends on `SidekickCore` and imports it
- [ ] Minimum iOS version recorded in the README (proposed iOS 17, owner confirms)

**Notes.** Agents cannot compile the app target on Linux. The owner creates and builds the Xcode project. Agents may add code to `SidekickCore` and verify it with `swift test`.

### 3. Linux CI for backend tests and SidekickCore

**Labels:** `phase:1` `area:ios` `area:rag` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want every PR checked automatically so agent PRs arrive with green tests.

**Acceptance criteria**

- [ ] GitHub Actions workflow on `ubuntu-latest` runs backend tests
- [ ] Same workflow runs `swift test` in `app/SidekickCore` with a pinned Swift toolchain
- [ ] CI is required to pass before merge (branch protection, owner sets it)
- [ ] CI finishes in under 10 minutes

### 4. PR and issue templates, then create labels, milestones, issues, and board

**Labels:** `phase:1` `area:docs` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want templates and a populated Projects board so work is tracked the same way every time.

**Acceptance criteria**

- [ ] `.github/pull_request_template.md` has: linked issue, what changed, how verified, screenshots (UI PRs), sources cited (vehicle facts)
- [ ] Issue templates for feature, spike, bug, chore
- [ ] Owner runs `scripts/create_issues.sh` once. Labels, milestones, and issues exist
- [ ] Projects board configured per `docs/KANBAN.md` with all issues in Backlog

**Notes.** Run the script with `DRY_RUN=1` first to review what it will create.

### 5. Build log template and first entry

**Labels:** `phase:1` `area:docs` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want a consistent build log so employers can follow the project and see measured progress.

**Acceptance criteria**

- [ ] `docs/build-log/TEMPLATE.md` with sections: date, milestone, what shipped, metrics (table), what broke, next
- [ ] First entry `docs/build-log/<date>-kickoff.md` covering M0
- [ ] README links the build log

### 6. Vehicle fact registry (TRUCK.md) with TBD tracking

**Labels:** `phase:1` `area:docs` `type:chore` `size:S`  
**Size:** S

**Goal.** As an agent, I want one file that says which vehicle facts are confirmed and which are TBD, so I never guess.

**Acceptance criteria**

- [ ] `docs/vehicle/TRUCK.md` lists facts as a table: fact, value, status (TBD / confirmed), source, date
- [ ] Rows exist for: donor ECU number, OBD protocol, donor model year, harness notes, dongle compatibility, bay photo angle list
- [ ] All values that are not yet confirmed read `TBD`
- [ ] AGENTS.md points to this file as the source of truth

**Notes.** Never invent part numbers, torque values, pinouts, or wire colors. Anything vehicle-specific stays TBD until confirmed in `docs/vehicle/TRUCK.md`.

### 7. Spike: ECU identification plan and OBD-II vs OBD1 decision tree

**Labels:** `phase:1` `area:telemetry` `type:spike` `size:S`  
**Size:** S

**Goal.** As the owner, I want to know exactly what to read off the ECU on day one and what each answer means for Phase 2.

**Acceptance criteria**

- [ ] `docs/vehicle/ECU.md` explains where the label is likely to be and what the 89661-xxxxx number tells us
- [ ] Decision tree: OBD-II path (ELM327 over BLE) vs OBD1 path (fallback source), with what each needs
- [ ] Every claim cites a source (manual page, or a linked reference). Unverified claims are marked as such
- [ ] Result recorded as TBD until delivery

**Notes.** Never invent part numbers, torque values, pinouts, or wire colors. Anything vehicle-specific stays TBD until confirmed in `docs/vehicle/TRUCK.md`.

### 8. Manual inventory and storage policy

**Labels:** `phase:1` `area:rag` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want a list of the manuals we use and a rule for where the PDFs live, so ingestion is reproducible and copyrighted PDFs stay out of git.

**Acceptance criteria**

- [ ] `docs/MANUALS.md` lists each document: ID, title, edition (TBD if unknown), page count, SHA-256
- [ ] PDFs live in a gitignored `manuals/` folder or external storage. Only the manifest is committed
- [ ] Ingestion reads the manifest and fails loudly on a checksum mismatch

## M1: Chat sidekick shell

Chat on the phone end to end with a real LLM, before grounding.

### 9. Architect: conversation and answer data model

**Labels:** `phase:1` `area:ios` `type:spike` `size:M`  
**Size:** M

**Goal.** As a developer, I want the core types designed before UI and backend code, so the chat, citations, and highlights share one shape.

**Acceptance criteria**

- [ ] Run `/architect`. Sketch lands in `SidekickCore` with types and signatures
- [ ] Types cover: Message, Conversation, Answer (text, citations, optional highlight), Citation (doc ID, page, snippet), HighlightRef (bay photo ID, part ID)
- [ ] Illegal states are unrepresentable (for example, a citation without a page)
- [ ] Rationale doc in `docs/design/` with the alternatives considered

### 10. Shared answer contract (JSON Schema) with fixtures

**Labels:** `phase:1` `area:rag` `area:ios` `type:feature` `size:S`  
**Size:** S

**Goal.** As a developer, I want one JSON contract between backend and app, tested on both sides, so they never drift.

**Acceptance criteria**

- [ ] `backend/contracts/answer.schema.json` defines the answer payload
- [ ] At least 4 fixtures: plain answer, answer with citations, answer with highlight, refusal (not found in manual)
- [ ] Backend tests validate fixtures against the schema
- [ ] `SidekickCore` tests decode every fixture with `Codable`

### 11. Chat screen: message list and composer

**Labels:** `phase:1` `area:ios` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want to type a problem and see the conversation, so the app feels like texting a mechanic.

**Acceptance criteria**

- [ ] SwiftUI screen with a scrolling message list and a composer
- [ ] Send disabled while empty or while a reply is loading
- [ ] Loading state shown while waiting
- [ ] Works in light and dark mode and with Dynamic Type at large sizes
- [ ] PR includes simulator screenshots

### 12. Answer card: text, citation chips, and highlight image slot

**Labels:** `phase:1` `area:ios` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want answers shown as cards with sources and a picture slot, so I can trust and act on them.

**Acceptance criteria**

- [ ] Answer card renders text, a row of citation chips (doc + page), and an image slot
- [ ] Refusal fixture renders a clear "not found in the manual" state
- [ ] All contract fixtures render in SwiftUI previews
- [ ] PR includes screenshots of each fixture

### 13. iOS network client with mock mode

**Labels:** `phase:1` `area:ios` `type:feature` `size:S`  
**Size:** S

**Goal.** As a developer, I want the app to run against fixtures or the real backend with one switch, so UI work never waits on the backend.

**Acceptance criteria**

- [ ] Client protocol in `SidekickCore`. Live and mock implementations
- [ ] Mock returns contract fixtures with a configurable delay
- [ ] Backend URL comes from build configuration, not hardcoded
- [ ] Errors (offline, timeout, bad payload) map to a user-visible message

### 14. Backend /chat endpoint skeleton

**Labels:** `phase:1` `area:rag` `type:feature` `size:M`  
**Size:** M

**Goal.** As a developer, I want a minimal backend that returns contract-valid answers, so the app can talk to something real.

**Acceptance criteria**

- [ ] `POST /chat` accepts a conversation and returns a schema-valid answer
- [ ] Runs locally with one command documented in `backend/README.md`
- [ ] Tests cover a happy path and an invalid request
- [ ] Stack choice (proposed: Python + FastAPI) recorded in the README

### 15. Cloud LLM adapter behind an interface

**Labels:** `phase:1` `area:rag` `type:feature` `size:M`  
**Size:** M

**Goal.** As a developer, I want the LLM behind a small interface, so the provider can change without touching chat logic.

**Acceptance criteria**

- [ ] One interface, one real provider, one fake for tests
- [ ] API keys read from environment only. `.env.example` committed, `.env` gitignored
- [ ] Timeouts and retries configured. Errors return a contract-valid error answer
- [ ] Token usage and latency logged per request

### 16. Safety preamble for procedure answers

**Labels:** `phase:1` `area:rag` `area:ios` `type:feature` `size:S`  
**Size:** S

**Goal.** As the owner, I want hazard reminders before any hands-on step, so the app is safety-first by default.

**Acceptance criteria**

- [ ] Answers that include procedure steps start with a short safety note (for example: engine cool, battery disconnected when relevant, vehicle supported properly)
- [ ] Safety note text lives in one place and is reviewed by the owner
- [ ] Eval fixture checks that procedure answers include it

### 17. Generate verification skills with /create-verification-skill

**Labels:** `phase:1` `area:docs` `type:chore` `size:M`  
**Size:** M

**Goal.** As the owner, I want agents to prove behavior by driving the real app and backend, not by saying "it compiles".

**Acceptance criteria**

- [ ] `verify-backend` skill: launch backend, send a chat request, capture the response as evidence. Runs on Linux
- [ ] `verify-ios` skill: build with `xcodebuild`, boot a simulator with `simctl`, run a UI test that sends a message, save screenshots. Runs on the owner's Mac
- [ ] Each skill executed end to end once. Evidence survives cleanup
- [ ] Feature map seeded with chat, answer card, and mock mode

## M2: Grounded answers over the manuals

Answers grounded in the 2JZ-GE repair manual and LJ78 wiring docs, with page citations and a spec guard.

### 18. Manual ingestion: PDF to page-level chunks

**Labels:** `phase:1` `area:rag` `type:feature` `size:M`  
**Size:** M

**Goal.** As a developer, I want each manual split into chunks that keep their page number, so every answer can cite a page.

**Acceptance criteria**

- [ ] Script reads `docs/MANUALS.md` manifest and the local PDFs
- [ ] Every chunk carries doc ID, page number, and text
- [ ] Pages with no extractable text are listed in an ingestion report
- [ ] Re-running ingestion is idempotent (same input, same output)

### 19. Architect: retrieval index and store

**Labels:** `phase:1` `area:rag` `type:spike` `size:M`  
**Size:** M

**Goal.** As a developer, I want a lightweight retrieval design chosen deliberately, so it runs cheaply now and can move on-device later.

**Acceptance criteria**

- [ ] Run `/architect` comparing at least two designs (for example, SQLite with a vector extension vs a flat file index)
- [ ] Chosen design documented with the on-device option noted
- [ ] Index builds from ingestion output with one command
- [ ] Top-k query returns chunks with doc ID and page

### 20. Page-anchored citations in every grounded answer

**Labels:** `phase:1` `area:rag` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want every claim from a manual to show its document and page, so I can check it myself.

**Acceptance criteria**

- [ ] LLM prompt requires citations as structured fields, not free text
- [ ] Each citation references a retrieved chunk. Citations to unretrieved pages are rejected
- [ ] Answers with no supporting chunks return the refusal shape
- [ ] Tests cover a cited answer and a refusal

### 21. Spec guard: block uncited numbers and pinouts

**Labels:** `phase:1` `area:rag` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want the system to refuse to state any torque value, spec, or pinout that is not in the retrieved manual text, so it never guesses.

**Acceptance criteria**

- [ ] Post-generation check finds numbers with units and pin/connector references in the answer
- [ ] Each must appear in a cited chunk, or the answer is replaced with a refusal naming what was not found
- [ ] Unit tests with adversarial cases (model invents a number, model rounds a number, correct cited number)
- [ ] Guard failures are logged and counted in the eval

**Notes.** Never invent part numbers, torque values, pinouts, or wire colors. Anything vehicle-specific stays TBD until confirmed in `docs/vehicle/TRUCK.md`.

### 22. Spike: wiring diagrams, text extraction vs page-image citation

**Labels:** `phase:1` `area:rag` `type:spike` `size:S`  
**Size:** S

**Goal.** As a developer, I want to know if wiring diagram pages can be searched as text, or if we should cite the page image, before building pinout lookups.

**Acceptance criteria**

- [ ] Try text extraction and OCR on 5 sample wiring pages
- [ ] Report accuracy and failure modes with examples
- [ ] Recommendation: which approach for M2, and what stays out of scope
- [ ] No pinout or wire color is stated in the report unless quoted with its page

**Notes.** Never invent part numbers, torque values, pinouts, or wire colors. Anything vehicle-specific stays TBD until confirmed in `docs/vehicle/TRUCK.md`.

### 23. Golden question set

**Labels:** `phase:1` `area:rag` `type:chore` `size:M`  
**Size:** M

**Goal.** As the owner, I want a fixed set of real questions with known answer pages, so quality is measured, not guessed.

**Acceptance criteria**

- [ ] `backend/eval/golden.jsonl` with target 50 questions
- [ ] Each question has expected doc ID and page(s), and whether it is answerable
- [ ] At least 10 unanswerable spec or pinout questions (the right answer is a refusal)
- [ ] At least 10 questions name a part that will be in the bay map (feeds M3)
- [ ] Owner reviews and approves the set

### 24. Eval harness: recall@5, citation accuracy, refusals, latency

**Labels:** `phase:1` `area:rag` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want one command that scores the system, so every change shows its effect in numbers.

**Acceptance criteria**

- [ ] `make eval` (or equivalent) runs the golden set and writes `eval/results/<date>.json`
- [ ] Reports recall@5, citation accuracy, refusal correctness, uncited-number count, p50/p95 latency
- [ ] CI runs a fast subset on backend PRs and posts the numbers in the PR
- [ ] A script regenerates `docs/METRICS.md` (metric, target, current value, date) from the latest results

### 25. Citation viewer: tap a chip to see the manual page

**Labels:** `phase:1` `area:ios` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want to tap a citation and see the actual page, so checking the source takes one tap.

**Acceptance criteria**

- [ ] Tapping a citation chip opens the cited page image with the snippet noted
- [ ] Page images come from the backend or a local cache, not bundled in the repo
- [ ] Missing page shows a clear error, not a blank screen
- [ ] PR includes screenshots

## M3: Bay map and highlight engine

Bay map schema, highlight renderer, and part resolver, prototyped on public 2JZ-GE photos.

### 26. Architect: bay map schema

**Labels:** `phase:1` `area:highlight` `type:spike` `size:M`  
**Size:** M

**Goal.** As a developer, I want a bay map format designed before labeling starts, so photos, parts, and regions stay consistent from prototype to my truck.

**Acceptance criteria**

- [ ] Run `/architect`. Schema lands in `SidekickCore` and as JSON Schema in `backend/contracts/`
- [ ] Covers: angle ID, photo ID, image size, parts (ID, display name, aliases), region polygons, confirmation status, confirmed by, source, license
- [ ] Unconfirmed regions can never be used for a highlight
- [ ] Run `/blast-radius` on any later schema change

### 27. Collect public 2JZ-GE bay photos for prototyping

**Labels:** `phase:1` `area:highlight` `type:chore` `size:S`  
**Size:** S

**Goal.** As a developer, I want a small set of reference photos to build the highlight engine before the truck arrives.

**Acceptance criteria**

- [ ] 10 to 20 photos from sources that allow this use, each with URL, license, and author recorded
- [ ] Photos stored outside git or in LFS. Manifest committed
- [ ] Photos grouped into rough angles that match the planned shot list
- [ ] Clearly marked prototype-only. Replaced in M5

### 28. Labeling workflow: draw regions and convert to bay map

**Labels:** `phase:1` `area:highlight` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want a quick way to draw part regions and get them into the bay map, so building the map for my truck takes an afternoon, not a week.

**Acceptance criteria**

- [ ] Pick an existing tool (for example Roboflow, CVAT, or Label Studio). No custom labeling UI
- [ ] Converter script turns its export into bay map JSON that validates against the schema
- [ ] Labels from this step can also feed the Phase 2 detector
- [ ] Documented step by step in `docs/BAY_MAP.md`

### 29. Highlight renderer prototype (Python) with golden-image tests

**Labels:** `phase:1` `area:highlight` `type:feature` `size:M`  
**Size:** M

**Goal.** As a developer, I want a reference renderer that outlines, saturates, circles, and dims, so the look is defined in code that agents can test on Linux.

**Acceptance criteria**

- [ ] Function: (photo, polygon, style) to image
- [ ] Styles: outline, saturate part, circle, dim the rest. Parameters in one config
- [ ] Golden-image tests with a pixel tolerance
- [ ] Renders a 12 MP photo in under 1 second on a laptop

### 30. Arena: highlight visual style bakeoff

**Labels:** `phase:1` `area:highlight` `type:spike` `size:S`  
**Size:** S

**Goal.** As the owner, I want the highlight that reads best at a glance on a phone in a garage, chosen by comparison, not by first try.

**Acceptance criteria**

- [ ] Run `/arena` with at least 3 style candidates on the same 5 photos
- [ ] Rubric: part obvious within 1 second, context still readable, works on dark and bright bays
- [ ] Winner and grafts recorded in a synthesis note
- [ ] Winning config committed as the default

### 31. Swift highlight renderer (Core Image) matching the prototype

**Labels:** `phase:1` `area:ios` `area:highlight` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want highlights rendered on the phone, so they work with any bay photo and stay sharp.

**Acceptance criteria**

- [ ] Core Image implementation of the winning style
- [ ] Test harness (on the Mac) compares Swift output to Python goldens within the tolerance
- [ ] Renders in under 200 ms on the owner's iPhone (measured)
- [ ] PR includes side-by-side screenshots

### 32. Part resolver: answer to bay map part ID

**Labels:** `phase:1` `area:rag` `area:highlight` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want the answer to pick the right part to highlight from my bay map, and show nothing when it is unsure.

**Acceptance criteria**

- [ ] LLM selects a part ID from the bay map's closed list, or none
- [ ] Unknown or unmapped part gives no highlight, and the answer says the part is not mapped yet
- [ ] Choice of photo: the angle where the part region is largest
- [ ] Tests with ambiguous and unmapped parts

### 33. End to end: chat answer shows the highlighted bay photo

**Labels:** `phase:1` `area:ios` `type:feature` `size:M`  
**Size:** M

**Goal.** As the owner, I want to ask a question and get the answer plus my bay photo with the part lit up, in one reply.

**Acceptance criteria**

- [ ] Backend returns highlight reference in the answer contract
- [ ] App renders the highlighted photo inside the answer card
- [ ] Tap to view full screen with pinch zoom
- [ ] Demo clip and screenshots in the PR

### 34. Highlight eval: correct-part rate and IoU

**Labels:** `phase:1` `area:highlight` `type:feature` `size:S`  
**Size:** S

**Goal.** As the owner, I want numbers on how often the highlight is right, so the build log shows real accuracy.

**Acceptance criteria**

- [ ] Correct-part rate on golden questions that name a mapped part
- [ ] IoU of rendered region vs held-out hand labels
- [ ] Count of highlights on unmapped parts (must be 0)
- [ ] Added to the eval harness output

## M4: Pre-delivery groundwork for Phase 2

Telemetry protocol plus simulator, and an ML pipeline dry run, before the truck arrives.

### 35. TelemetrySource protocol and simulator

**Labels:** `phase:2` `area:telemetry` `type:feature` `size:M`  
**Size:** M

**Goal.** As a developer, I want a swappable telemetry interface with a simulator, so live readings can be built and tested without the truck.

**Acceptance criteria**

- [ ] Protocol in `SidekickCore`: start, stop, stream of typed readings with timestamps and units
- [ ] Simulator replays scripted scenarios from JSON (for example, cold start, warm idle)
- [ ] Documented seams for an ELM327 source and an OBD1 source
- [ ] `swift test` covers the simulator. A readings view in the app shows it live

**Notes.** Simulated values are illustrative. They are not specs for this engine and must be labeled as simulated in the UI.

### 36. ML pipeline dry run: Roboflow to YOLO11n to Core ML

**Labels:** `phase:2` `area:ml` `type:spike` `size:M`  
**Size:** M

**Goal.** As a developer, I want the whole detector pipeline run once on public photos, so Phase 2 starts with a working pipeline.

**Acceptance criteria**

- [ ] Scripts in `ml/` for: export labels, train YOLO11n with Ultralytics, export to Core ML
- [ ] Each step reruns from a clean checkout with pinned dependencies
- [ ] Model runs one inference on the owner's iPhone. ms per frame recorded as a baseline
- [ ] Build log entry with the numbers

## M5: Truck day one

Resolve vehicle TBDs on delivery day and capture bay photos.

### 37. Day-one checklist and fixed-angle shot list

**Labels:** `phase:1` `area:docs` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want a printed checklist for delivery day, so nothing gets missed and photos are repeatable.

**Acceptance criteria**

- [ ] `docs/vehicle/DAY_ONE.md` covers: ECU label, bay photos, harness and firewall pass-through photos, dongle test
- [ ] Shot list defines each angle: name, where to stand, phone height, lens, lighting notes
- [ ] Includes a place to record each result and link photos

### 38. Record ECU label and decide the OBD path

**Labels:** `phase:1` `area:telemetry` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want the ECU identified on day one, so Phase 2 knows whether to build the ELM327 path or the OBD1 fallback.

**Acceptance criteria**

- [ ] ECU label photographed. Full 89661 number recorded in `TRUCK.md`
- [ ] Donor model year and OBD protocol recorded, with how each was determined
- [ ] BLE dongle tested: connects or not, protocol reported, sample readings if any
- [ ] `ECU.md` decision tree resolved to one path

**Notes.** Never invent part numbers, torque values, pinouts, or wire colors. Anything vehicle-specific stays TBD until confirmed in `docs/vehicle/TRUCK.md`.

### 39. Photograph bay from fixed angles plus harness and firewall pass-through

**Labels:** `phase:1` `area:highlight` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want a complete, repeatable photo set of my bay, so the bay map is built on my truck, not a stranger's.

**Acceptance criteria**

- [ ] Every angle on the shot list captured
- [ ] Harness runs and the firewall pass-through photographed
- [ ] Photos stored per `docs/BAY_MAP.md`, manifest updated
- [ ] Harness notes added to `TRUCK.md` as observations, not guesses

### 40. Build truck bay map v1 and re-run evals

**Labels:** `phase:1` `area:highlight` `type:feature` `size:L`  
**Size:** L

**Goal.** As the owner, I want my own bay map with every region confirmed by me, so highlights point at my actual parts.

**Acceptance criteria**

- [ ] All parts in the golden question set labeled on my photos
- [ ] Owner confirms each region. Unconfirmed regions are excluded
- [ ] Public prototype photos removed from the live bay map
- [ ] Highlight eval re-run. Numbers in the build log

## M6: Phase 1 release

Phase 1 metrics met on my truck. TestFlight build, demo video, write-up.

### 41. TestFlight build

**Labels:** `phase:1` `area:ios` `type:chore` `size:S`  
**Size:** S

**Goal.** As the owner, I want the app on my phone through TestFlight, so I can use it in the garage.

**Acceptance criteria**

- [ ] Archive and upload from Xcode (owner)
- [ ] Backend URL and keys configured for the build without committing secrets
- [ ] Install and smoke test on device. Result in the build log

### 42. Demo video and portfolio write-up

**Labels:** `phase:1` `area:docs` `type:chore` `size:M`  
**Size:** M

**Goal.** As the owner, I want a short demo and a write-up that shows the ML, systems, and measured results, for employers.

**Acceptance criteria**

- [ ] Demo video under 2 minutes: problem, chat, citation, highlight
- [ ] Write-up covers architecture, safety design, metrics table, and what I would do next
- [ ] Links the build log and METRICS.md

## M7: On-device part detection

Phase 2. YOLO11n part detector on Core ML and the ANE.

### 43. Epic: On-device part detection (YOLO11n on Core ML and the ANE)

**Labels:** `phase:2` `area:ml` `type:feature` `size:L`  
**Size:** L

**Goal.** As the owner, I want the phone to find parts in the live camera view, so highlights follow the camera instead of fixed photos.

**Acceptance criteria**

- [ ] Dataset built from my bay photos (reuse bay map labels)
- [ ] YOLO11n trained, exported to Core ML, running on the ANE
- [ ] mAP50, ms per frame, and sustained FPS reported against the M4 baseline
- [ ] Break into issues when Phase 1 ships

## M8: Live telemetry

Phase 2. BLE ELM327 telemetry, OBD1 fallback if needed.

### 44. Epic: BLE ELM327 telemetry over CoreBluetooth

**Labels:** `phase:2` `area:telemetry` `type:feature` `size:L`  
**Size:** L

**Goal.** As the owner, I want live engine readings from the dongle, behind the same protocol as the simulator.

**Acceptance criteria**

- [ ] ELM327 source implements `TelemetrySource`
- [ ] Passes the same protocol tests as the simulator
- [ ] Read latency and Hz per signal measured on the truck
- [ ] Only built if M5 confirms the ECU supports OBD-II

### 45. Epic: OBD1 fallback telemetry source

**Labels:** `phase:2` `area:telemetry` `type:spike` `size:L`  
**Size:** L

**Goal.** As the owner, I want a fallback data source if the donor ECU is pre-OBD-II, so live readings are still possible.

**Acceptance criteria**

- [ ] Only started if M5 records an OBD1 ECU
- [ ] Spike first: what data the ECU exposes and what hardware is needed, all cited
- [ ] Implements `TelemetrySource`. Passes the shared protocol tests

**Notes.** Never invent part numbers, torque values, pinouts, or wire colors. Anything vehicle-specific stays TBD until confirmed in `docs/vehicle/TRUCK.md`.

## M9: Live overlay with anchored readings

Phase 2. Vision overlay with live readings anchored on parts.

### 46. Epic: Live overlay with readings anchored on parts

**Labels:** `phase:2` `area:ios` `area:ml` `area:telemetry` `type:feature` `size:L`  
**Size:** L

**Goal.** As the owner, I want live readings drawn on the part they describe in the camera view.

**Acceptance criteria**

- [ ] Vision framework overlay on the AVFoundation camera feed
- [ ] Readings anchored to detected part boxes
- [ ] Overlay drift and end-to-end latency measured in garage lighting

## M10: Garage projector feasibility

Phase 3. Ceiling camera and projector feasibility study.

### 47. Epic: Garage projector feasibility study

**Labels:** `phase:3` `area:highlight` `area:ml` `type:spike` `size:L`  
**Size:** L

**Goal.** As the owner, I want to know if a ceiling camera and projector can light up the right part and tool, before spending money on it.

**Acceptance criteria**

- [ ] Camera to projector calibration prototype on a bench
- [ ] Projection alignment error measured
- [ ] Cost estimate and go/no-go written up in the build log
