# Day-one checklist

Print this and take it to the truck. It is the delivery-day procedure for one 1990 Land Cruiser LJ78 with a 2JZ-GE swap and a Lexus donor ECU.

Nothing in the blank cells is a fact yet. Copy what you see. Leave a cell `TBD` when you did not see it. Do not fill a cell from memory, a forum, or a "typical" swap.

Do not write a torque value, spec, clearance, pinout, wire color, connector ID, or part number that you did not read off a label in a photo from this visit. This page does not list any of those.

Tick these before you leave:

- [ ] ECU label photographed and the printed number transcribed
- [ ] ECU connectors photographed (count and shape only)
- [ ] All five bay angles shot
- [ ] Harness runs photographed
- [ ] Each firewall pass-through photographed
- [ ] Dongle test recorded, or marked not tested
- [ ] Tables below filled in
- [ ] [TRUCK.md](TRUCK.md) updated the same day

Work in this order. Bay photos need daylight. Ignition stays off until the dongle test.

1. Fixed-angle bay photos
2. ECU label and connectors
3. Harness and firewall pass-throughs
4. Dongle test
5. Copy results into [TRUCK.md](TRUCK.md)

Ignition off and the key out for steps 1–3. Do not unplug the ECU, probe pins, or open connectors. Step 4 is the only time the ignition is on, and the engine stays off. Do not clear codes or write to the ECU ([VISION.md](../../VISION.md)).

## File names

Rename files the same day, before they get mixed with anything else.

```text
YYYY-MM-DD_<id>_<nn>.ext
```

| Piece | Rule |
|---|---|
| `YYYY-MM-DD` | The day you shot it |
| `<id>` | The subject, from this page |
| `<nn>` | Frame of that subject: `01`, `02`, … |
| `.ext` | The extension the phone wrote (`.jpg`, `.heic`, or `.png`) |

Lowercase, hyphens inside an id, no spaces. The underscore separates `<id>` from `<nn>` only.

Highlight ids have no number of their own: `front`, `overhead`, `vehicle-left`, `vehicle-right`, `firewall`. Frame `01` is the one the bay map uses. A blurry spare of the same angle is frame `02`. Log frame `01`.

Everything else puts the subject number in the id, and uses `<nn>` as the frame: `ecu-case-01`, `ecu-connector-01`, `diag-plug-01`, `harness-run-01`, `firewall-passthrough-01`. A second firewall opening is a new id (`firewall-passthrough-02`), not frame `03` of the first.

Pattern examples only, not real files:

- `YYYY-MM-DD_front_01.jpg`
- `YYYY-MM-DD_ecu-label_01.jpg`
- `YYYY-MM-DD_firewall-passthrough-01_01.jpg` (wide)
- `YYYY-MM-DD_firewall-passthrough-01_02.jpg` (closer)

Keep the phone's original if a rename would throw away the only copy. Write the name you actually have in the filename cell.

## Where results go

| What | Where |
|---|---|
| Notes and filenames from this visit | The tables in this file |
| Donor ECU number, OBD protocol, donor model year, harness notes, dongle compatibility, bay photo angle list, delivery date, truck delivered | [TRUCK.md](TRUCK.md). A row stays `TBD` until that file's evidence rule is met. |
| OBD-II vs OBD1 decision | [ECU.md](ECU.md). Leave **OBD protocol** as `TBD` until [issue #38](https://github.com/zeketx/sidekick-mechanic/issues/38) records the live result. |
| Image files | On your machine, in `bay-photos/day-one/`, next to the repo. Do not `git add` them from this checklist. [Issue #39](https://github.com/zeketx/sidekick-mechanic/issues/39) stores them the way `docs/BAY_MAP.md` says. That page is [issue #28](https://github.com/zeketx/sidekick-mechanic/issues/28) and is not on `main` yet. |
| Part regions on these photos | [Issue #40](https://github.com/zeketx/sidekick-mechanic/issues/40), after the bay map schema ([issue #26](https://github.com/zeketx/sidekick-mechanic/issues/26)). That schema is not on `main` yet. When it lands, the angle id column below is the schema's angle ID, and the `_01` filename is the photo ID. Do not draw regions on delivery day. |

Public prototype bay photos ([issue #27](https://github.com/zeketx/sidekick-mechanic/issues/27)) are a different set. Keep them out of `bay-photos/day-one/`. Their manifest is [`backend/data/prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json). From `backend/`, `python3 prototype_photos.py fetch` writes them into `bay-photos/prototype/`. That directory is gitignored. Every file in it is a prototype stand-in, not this truck, and is replaced in M5.

## Fixed-angle bay photos

Five angles. These are the highlight set for [issue #39](https://github.com/zeketx/sidekick-mechanic/issues/39) and [issue #40](https://github.com/zeketx/sidekick-mechanic/issues/40). Harness close-ups are later in this page and are not extra angles.

Same phone for every angle. Hood fully open and propped. Landscape. Rear camera only.

**Lens (every angle):** 1× main camera. Not 0.5× ultrawide, not telephoto, not portrait mode, no filter, no flash.

**Lighting (every angle):** diffuse daylight (overcast or open shade) if you can get it. Write the sun direction in the log: behind you, to your left, to your right, or in the frame. No flash and no flashlight on these five. If the light is wrong, wait and note the wait. A reshoot uses the same stance and the height you write down.

Left and right mean the truck's left and right as you sit in it facing forward.

If you cannot shoot one of these, leave its row `TBD` and say why. Do not invent a sixth angle id on the truck. A missing angle stays missing until this page has a new id.

### front — from the grille

- **Where to stand:** At the front bumper, centered on the grille, facing the engine. Toes at the bumper.
- **Phone height:** Lens level with the front lip of the open hood. Crouch or use a step if you need to, and write which.
- **Lens:** 1× main, as above.
- **Lighting:** Sun behind you when you can (you are looking toward the firewall). Diffuse light preferred. No flash.
- **Frame:** Whole bay, radiator support to firewall, both inner fenders in frame.

### overhead — looking down

- **Where to stand:** Beside the front bumper, leaning over the center of the bay. Use a step if you need height. Do not stand on the engine, the battery, or the core support.
- **Phone height:** Lens about one forearm-length above the highest point you can see in the bay, pointed straight down. Write whether you used a step.
- **Lens:** 1× main, as above. If the bay does not fit, leave the crop wide and say so. Do not switch to ultrawide.
- **Lighting:** Your body will shadow the bay. Shift until the center is lit, or shoot in diffuse light and note the shadow.
- **Frame:** Centered on the bay. Include both fender tops when they fit.

### vehicle-left — across the bay from the left

- **Where to stand:** Beside the left front wheel, facing across the bay.
- **Phone height:** Lens level with the top of the left inner fender.
- **Lens:** 1× main, as above.
- **Lighting:** Note whether this side is in sun or shade.
- **Frame:** Across the engine toward the right inner fender, including the parts on the left side.

### vehicle-right — across the bay from the right

- **Where to stand:** Beside the right front wheel, facing across the bay.
- **Phone height:** Lens level with the top of the right inner fender.
- **Lens:** 1× main, as above.
- **Lighting:** Note whether this side is in sun or shade.
- **Frame:** Across the engine toward the left inner fender, including the parts on the right side.

### firewall — rear wall of the bay

- **Where to stand:** Front bumper, centered, same feet as `front`, camera aimed at the firewall. If the engine blocks that view, stand just ahead of the firewall on the vehicle-left side and write `stood vehicle-left` in the log. Reshoot from that same side.
- **Phone height:** Lens level with the base of the windshield, without leaning on the engine. If you cannot reach that height, write the height you did use.
- **Lens:** 1× main, as above.
- **Lighting:** This wall is often in shade. No flash. If edges are not visible, wait for brighter diffuse light and note the wait.
- **Frame:** The firewall and the rear face of the engine. This is not a close-up of a grommet. Grommets are in the pass-through section.

| Angle id | Shot (yes / no) | Phone height you used | Light you had | Filename |
|---|---|---|---|---|
| `front` | TBD | TBD | TBD | TBD |
| `overhead` | TBD | TBD | TBD | TBD |
| `vehicle-left` | TBD | TBD | TBD | TBD |
| `vehicle-right` | TBD | TBD | TBD | TBD |
| `firewall` | TBD | TBD | TBD | TBD |

When every row is `yes` and has a filename, set **Bay photo angle list** in [TRUCK.md](TRUCK.md) to these five ids, status `confirmed`, source `owner observation, photos listed in DAY_ONE.md`, date the shoot date. Until then the value stays `TBD`.

## ECU label and connectors

The box is wherever the swap put it. Location on this truck is `TBD`. Find it by following the engine harness. Do not assume a cabin or engine-bay mount.

The identification plan and OBD decision tree are in [ECU.md](ECU.md). This section is the photos and the transcription. It does not decide the protocol.

- [ ] Photo of the box in place, showing how it is mounted (`ecu-mounted_01`)
- [ ] Photo of every face of the case, including the underside if you can see it without unbolting (`ecu-case-01_01`, `ecu-case-02_01`, …)
- [ ] Photo of the label, readable (`ecu-label_01`)
- [ ] One photo per connector housing on the box (`ecu-connector-01_01`, …). Count housings. Do not unplug them.

Transcribe the full part number printed on the label, every character, including leading zeros. The project plan expects a Toyota/Lexus engine-control number beginning `89661-` ([ROADMAP.md](../../ROADMAP.md)). If the label shows a different string, copy that string. If you cannot read a character, write `?` for that character and shoot the label again. Other printed marks (lot codes, maker marks) go in the next row as characters only. Do not decide what they mean. Do not decode a protocol or a model year from the number. Donor year stays `TBD` until [issue #38](https://github.com/zeketx/sidekick-mechanic/issues/38).

| Field | Result |
|---|---|
| Where the box is mounted | TBD |
| Full number printed on the label | TBD |
| Other printed marks (characters only) | TBD |
| Connector housings you can see (count) | TBD |
| Housing shape, in your own words | TBD |
| `ecu-mounted` filename | TBD |
| `ecu-label` filename | TBD |
| `ecu-case` filenames | TBD |
| `ecu-connector` filenames | TBD |

Diagnostic plugs, if you see any: photograph each one (`diag-plug-01_01`, …). Write where it sits and how many holes you can count. Leave the name as the id above. Jumper nothing. What a plug is called, and what that means for OBD, is `ECU.md` ([issue #7](https://github.com/zeketx/sidekick-mechanic/issues/7)) after the photo exists.

| Id | Where it is | Holes you counted | Filename |
|---|---|---|---|
| `diag-plug-01` | TBD | TBD | TBD |
| `diag-plug-02` | TBD | TBD | TBD |
| `diag-plug-03` | TBD | TBD | TBD |

## Harness and firewall pass-throughs

These photos feed harness notes ([issue #39](https://github.com/zeketx/sidekick-mechanic/issues/39)). They are not highlight angles. Do not cut tape, unplug connectors, or pull a grommet.

Walk the visible harness from the ECU toward the engine, and from the engine toward the firewall. Each time the path turns, goes under a cover, or crosses a panel, take one photo (`harness-run-01_01`, …).

- **Where to stand:** Wherever that run is visible without removing parts.
- **Phone height:** About a forearm from the harness, lens square to it.
- **Lens:** 1× main.
- **Lighting:** Ambient light. A flashlight is allowed on harness and pass-through photos only. Write `flashlight` in the notes when you use one.

Each firewall opening is its own id. Frame `_01` shows the opening on the wall. Frame `_02` is closer: lens square to the opening, with the hole or grommet and some sheet metal around it. The next opening is `firewall-passthrough-02`, not frame `_03`.

- **Where to stand:** In the bay or in the cabin, whichever side shows the opening. Write which side.
- **Phone height:** Wide frame, then the closer frame, as above.
- **Lens:** 1× main.
- **Lighting:** Ambient, or flashlight with `flashlight` written in the notes.

Write the side and whether a harness passes through. Stop there. No wire color, connector ID, or circuit name.

| Id | What you saw | Side (bay / cabin / vehicle-left / vehicle-right) | Filename |
|---|---|---|---|
| `harness-run-01` | TBD | TBD | TBD |
| `harness-run-02` | TBD | TBD | TBD |
| `harness-run-03` | TBD | TBD | TBD |
| `firewall-passthrough-01` | TBD | TBD | wide `_01`: TBD; close `_02`: TBD |
| `firewall-passthrough-02` | TBD | TBD | wide `_01`: TBD; close `_02`: TBD |

Add rows if you have more openings. Copy the "what you saw" cells into **Harness notes** in [TRUCK.md](TRUCK.md) as owner observations, with these filenames. Guesses stay out. If you saw nothing you can describe, leave the row `TBD`.

## Dongle test

Read-only check of the BLE dongle against whatever diagnostic plug is actually on this truck. The Sidekick app's simulated readings are not this test. The simulator is labeled `Simulated` and is not engine data ([docs/design/telemetry-source.md](../design/telemetry-source.md)). Use the dongle vendor's own app.

- [ ] Ignition was off for the photo sections above
- [ ] Found a plug the dongle fits, or stopped because there is no plug
- [ ] Ignition on, engine off
- [ ] Wrote down whether BLE connected
- [ ] Copied the protocol text from the app, character for character
- [ ] Noted whether any live reading appeared
- [ ] Did not clear codes or send a write
- [ ] Ignition off, dongle unplugged
- [ ] Photo of the app screen showing the protocol line (`dongle-screen_01`), if the app showed one

If you do not find a plug, stop. Overall result: `not tested`. Leave the protocol `TBD`.

If a reading shows a number, you may copy it into the notes prefixed with `dongle test observation`. That number is not a spec and does not go in a manual citation.

| Field | Result |
|---|---|
| Plug found, and where | TBD |
| BLE connected (yes / no) | TBD |
| Protocol text copied from the app | TBD |
| Live data returned (yes / no) | TBD |
| Overall (`works` / `partial` / `not compatible` / `not tested`) | TBD |
| `dongle-screen` filename | TBD |
| Notes | TBD |

Use one overall word:

| Word | When |
|---|---|
| `works` | BLE connected, the app showed a protocol, and live data returned |
| `partial` | BLE connected, and either the protocol line or the live data was missing |
| `not compatible` | A plug was found and the dongle did not link |
| `not tested` | No plug, or you did not run the test |

A failed link on one adapter is the result for that adapter. Write the adapter name in the notes if it is printed on the device. Do not treat the failure as a protocol confirmation. **OBD protocol** in [TRUCK.md](TRUCK.md) stays `TBD` until [issue #38](https://github.com/zeketx/sidekick-mechanic/issues/38) applies the decision tree in `ECU.md`.

## Copy into TRUCK.md

Same day. Edit [TRUCK.md](TRUCK.md) only from the tables above.

| TRUCK.md fact | Copy from | Leave `TBD` until |
|---|---|---|
| Delivery date | The shoot date | You are at the truck |
| Truck delivered | `yes` once you have the truck | You are at the truck |
| Donor ECU number | ECU label row | The label photo exists and the transcription matches it |
| Donor model year | Do not copy from the sticker | [Issue #38](https://github.com/zeketx/sidekick-mechanic/issues/38), with a cited lookup |
| OBD protocol | Do not infer it here | [Issue #38](https://github.com/zeketx/sidekick-mechanic/issues/38) and `ECU.md` ([issue #7](https://github.com/zeketx/sidekick-mechanic/issues/7)) |
| Dongle compatibility | Dongle overall word, plus the protocol text as a note | The dongle table is filled from this visit |
| Harness notes | Harness and pass-through "what you saw" cells | Those cells are observations from the photos |
| Bay photo angle list | The five angle ids | Every highlight row is `yes` with a filename |

Set **Status** to `confirmed`, **Source** to `owner observation` plus the filename, and **Date** to the visit date only when the "leave TBD until" cell is satisfied. Otherwise change nothing in that row.
