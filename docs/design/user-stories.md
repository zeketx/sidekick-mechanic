# User stories (for owner review)

Design only. **Zeke files GitHub issues from this file.** Do not open issues from this PR. Do not build until the journey is accepted.

Copy format matches the feature template: *As Zeke, I want … so that …*, then 3–5 acceptance checks, a size, and v1 or later.

v1 is lean for the **12 Oct 2026** plan end. Later stories stay in this file so they are not lost.

**Tags** (when a story mentions chips): system areas `cooling`, `ignition`, `intake`, `electrical`, `fuel`; status `inspected`, `replaced`, `watch`. User-defined tags are allowed. Chips never carry a torque, pin, wire color, or part number.

Placeholder copy in fixtures stays `FAKE-DOC-2JZ`, `p. 999`, `FAKE-SPEC`. Unknown truck facts stay **TBD** in `docs/vehicle/TRUCK.md`.

Wireframes: [user-journey.md](user-journey.md).

---

## Epic: Onboarding

### ONB-1 · Three first-open screens · S · **v1**

As Zeke, I want three short screens that say what this app is, so that I am not dropped into a blank chat with no context.

- [ ] Screen 1 states: chat-first mechanic, one truck (1990 Land Cruiser LJ78, 2JZ-GE swap, no turbo).
- [ ] Screen 2 states the loop: chat → cited answer → outline on a photo. Citation example is `FAKE-DOC-2JZ · p. 999`.
- [ ] Screen 3 is the garage list (see ONB-3). A primary button ends on chat.
- [ ] Skip is on every screen and lands on chat.
- [ ] No animation. No vehicle spec, pin, or part number.

### ONB-2 · Skip always works · S · **v1**

As Zeke, I want to skip onboarding, so that a reinstall does not trap me.

- [ ] Skip from any of the three screens opens chat.
- [ ] Onboarding does not repeat on the next launch after Skip or Finish.
- [ ] There is a way back (Settings or Garage) without wiping chat.

### ONB-3 · Garage shows TBD instead of guesses · S · **v1**

As Zeke, I want the garage to show only confirmed truck facts, so that the app never asks me to invent a number.

- [ ] Confirmed rows match `TRUCK.md` (chassis, 2JZ-GE swap, Lexus donor ECU).
- [ ] Donor year, OBD type, harness, and photo angles render as **TBD**.
- [ ] No field accepts a torque, pinout, wire color, or part number.
- [ ] Copy says TBD stays TBD until it is confirmed in `TRUCK.md`.

### ONB-4 · Onboarding motion · L · **later**

As Zeke, I want a short 2JZ animation on first open, so that the outline language is memorable.

- [ ] Picks one idea from [onboarding-animation-ideas.md](onboarding-animation-ideas.md) after Zeke chooses.
- [ ] No turbo. No real manual page. No spec callouts.
- [ ] Reduced Motion plays the static screens instead.
- [ ] Still skippable.

---

## Epic: Highlight card

Existing demo states from PRs #92 / #93: Confident outline, Unsure (“Is this it?”), Not found. v1 user-facing states add the reference-photo fallback from draft PR #89 and **do not** show Unsure.

### HL-1 · Confident outline on my photo · M · **v1**

As Zeke, I want a precise outline on my photo when the part is known, so that I can find it under the hood without knowing its shop name.

- [ ] Traced photo + known part → outline on **my** photo (the fuchsia treatment already chosen).
- [ ] Card is full-bleed, one photo at a time, Close returns to the job sheet.
- [ ] Copy does not invent a spec. Everyday language is enough (“air box on top”).
- [ ] Opening the card does not require me to know a part name.

### HL-2 · Not found points at the diagram · S · **v1**

As Zeke, I want a clear miss when the part is not in the photo, so that I am not staring at a blank bay wondering if I failed.

- [ ] No outline on the photo.
- [ ] A control opens the cited diagram (`FAKE-DOC-2JZ · p. 999` in fixtures; real answers use a real cited page).
- [ ] The answer text still says the part is not in this photo.

### HL-3 · Reference photo when mine is untraced · M · **v1**

As Zeke, I want the part outlined on a labeled reference photo when my snap is new, so that I still see *where it usually sits* without a guessed outline on my truck.

- [ ] No outline on my untraced photo.
- [ ] Outline is on the closest traced reference. Banner: **Reference, not your truck.**
- [ ] Diagram link is present.
- [ ] Retake hint is present. Angle list is **TBD** (do not print unconfirmed angles as fact).
- [ ] Public prototype bays used before delivery stay labeled as not my truck.

### HL-4 · Pinch to zoom · S · **v1**

As Zeke, I want to pinch the highlight card, so that a small part is still findable.

- [ ] Pinch and double-tap zoom on the card.
- [ ] Outline stays locked to the photo while zooming.
- [ ] A visible zoom control (magnifier) is on the card so the gesture is discoverable.

### HL-5 · Unsure: Is this it? · M · **later** (flag exists now)

As Zeke, I want Yes / Not this only when the app is allowed to show Unsure, so that a shaky outline is not silently treated as fact.

- [ ] Hidden in v1. The demo flag stays off for TestFlight / owner daily use.
- [ ] When the flag is on: dashed or softer outline, copy “Is this it?”, Yes and Not this.
- [ ] Yes keeps the outline. Not this drops it (same as not found) and logs the miss.
- [ ] Ships user-facing only after the bars in `open-world-part-masks.md` (draft PR #89).

### HL-6 · Tag chips on the card · S · **later**

As Zeke, I want area and status chips on the highlight card, so that I can mark what I looked at without opening Settings.

- [ ] System chips: cooling, ignition, intake, electrical, fuel.
- [ ] Status chips: inspected, replaced, watch.
- [ ] I can add my own chip. No chip stores a spec or part number.

---

## Epic: Job sheet / bottom sheets

Chat stays the home list. The job sheet is the bottom sheet for **one** ask.

### JS-1 · Collapsed and half sheet · M · **v1**

As Zeke, I want a job sheet I can peek or half-open from chat, so that the photo, the answer, and the page chips live in one place.

- [ ] Collapsed: drag handle, job title, photo peek, way to open.
- [ ] Half: photo (or highlight), answer, citation chips, outcome peek.
- [ ] Dragging or tapping Open / Close moves between collapsed, half, and (later) full.
- [ ] Chat behind the half sheet is dimmed and not editable until Close.

### JS-2 · Attach a photo to this job · S · **v1**

As Zeke, I want to snap or attach a bay photo onto the job I just asked, so that the highlight has something to draw on.

- [ ] Attach is on the job (composer or sheet), not a separate app area.
- [ ] v1 supports the source Zeke picks in the open questions (camera, library, or both).
- [ ] The photo belongs to this job. It is not silently reused as a traced bay-map frame.

### JS-3 · Close out Worked / Partly / Didn't · S · **v1**

As Zeke, I want to mark how the job went, so that I can remember what I already tried.

- [ ] Three outcomes: Worked, Partly, Didn't. Exactly one is selected.
- [ ] Closing does not require a part name or a spec.
- [ ] Optional one-line “what fixed it?” if Zeke wants it in v1; otherwise omit.

### JS-4 · Full sheet · M · **later**

As Zeke, I want the job sheet to go full screen, so that steps, notes, and tags fit without leaving chat.

- [ ] Full height shows photo, answer, chips, steps, notes, tags, outcome.
- [ ] Same job as the collapsed / half sheet. No second object.

### JS-5 · Steps checklist · M · **later**

As Zeke, I want a short checklist on the job sheet, so that I can tick work at the truck with dirty hands.

- [ ] Steps come from the cited answer, not from memory.
- [ ] A step that would need an uncited number is omitted (spec guard still applies).
- [ ] Large checkboxes. Progress shows as “1 of 3”.

### JS-6 · Notes · S · **later**

As Zeke, I want a notes field on the job, so that I can write what I saw in my own words.

- [ ] Free text, optional.
- [ ] Notes are not treated as manual citations.
- [ ] Do not auto-insert specs into the note.

### JS-7 · Tags on the job · S · **later**

As Zeke, I want the same chips on the job sheet as on the highlight card, so that Jobs and the scan log can filter later.

- [ ] Same chip set as HL-6, including user-defined tags.
- [ ] Chips set on the card and on the sheet stay in sync.

---

## Epic: Job history

### JH-1 · List with outcome badges · M · **later**

As Zeke, I want a list of past jobs, so that I can see what I already tried last weekend.

- [ ] One row per job: title, date, photo peek, badge Worked / Partly / Didn't.
- [ ] Tapping a row opens that job sheet.
- [ ] Empty state is one sentence, not a fake job.

### JH-2 · Open a past job and keep chatting · S · **later**

As Zeke, I want to reopen a job and keep asking, so that a “Partly” job can continue.

- [ ] Reopened job shows the same photo, answer, chips, and outcome.
- [ ] New messages append; they do not spawn a silent duplicate job unless I start a new ask.

---

## Epic: Scan log

### SL-1 · Grid of past photos and highlights · L · **later**

As Zeke, I want a grid of every snap and outline, so that I can flip through what the bay looked like without hunting chat.

- [ ] Grid of photos. Outlined frames still show the outline.
- [ ] Reference-photo frames keep the “not your truck” label in the grid.
- [ ] Tapping a cell opens the highlight card for that job.

### SL-2 · Filter by tag chips · M · **later**

As Zeke, I want to filter the grid by area or status, so that I can find “cooling, watch” without scrolling.

- [ ] Filters include cooling, ignition, intake, electrical, fuel, inspected, replaced, watch, plus user-defined chips.
- [ ] Multi-select is allowed. “all” clears filters.
- [ ] An empty filter result is an empty grid, not an invented photo.
