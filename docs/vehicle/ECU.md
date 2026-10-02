# ECU identification plan

**Result: TBD until delivery.** This page is a read-off plan and a Phase 2 decision tree. It does not identify this truck's ECU.

The truck is a 1990 Land Cruiser LJ78 with a 2JZ-GE swap and a Lexus donor ECU. Donor year, ECU number, OBD protocol, harness, and dongle result are all `TBD` in [TRUCK.md](TRUCK.md). Do not fill those rows from this page.

Citation style: every claim has a source. Claims without a source are marked **unverified**. Vehicle-specific values stay `TBD` until photographed or cited into [TRUCK.md](TRUCK.md). Phase 1 document IDs live in [`docs/MANUALS.md`](../MANUALS.md) (`2jz-ge-rm`, `lj78-wiring`). The troubleshooting and diagnostics pages cited here are not those IDs, so these citations still use title + page.

Do not write torque values, pinouts, wire colors, or model-year-to-protocol maps from memory. This page does not list connector pins.

## Terms

| Term | Meaning here | Source |
|---|---|---|
| ECM / ECU | Toyota/Lexus **engine control module** / **engine control computer** that runs the 2JZ-GE. | Toyota 2JZ-GE troubleshooting calls it the Engine Control Module (ECM) ([MK4 Supra 2JZ-GE troubleshooting, EG-384][tsrm-eg384]). Lexus TSB L-SB-0109-17 calls it Computer, Engine Control (ECM/PCM) ([NHTSA copy][lsb-0109-17]). |
| `89661-xxxxx` | Toyota/Lexus **part number prefix** for Computer, Engine Control (ECM/PCM). The full printed number is the catalog identity of one engine control computer. | Lexus TSB L-SB-0109-17 names the part "Computer, Engine Control (ECM/PCM)" and uses `89661-` numbers as the ECM part number ([NHTSA copy][lsb-0109-17]). Toyota T-SB-0077-16 does the same ([NHTSA copy][tsb-0077-16]). Dealer catalogs list **part name code 89661** ([Lexus listing][lexus-89661]). Suffixes in those documents are **not** this truck. |
| OBD-II path | Standardized emissions diagnostics: SAE J1979 data through a SAE J1962 vehicle connector, read with an ELM327-class tool over BLE. | [40 CFR 86.1806-05(h)][cfr-1806]; [SAE J1962][j1962]; [SAE J1979][j1979]; [ELM327][elm327]. |
| OBD1 path | This project's name for **non-J1979** Toyota diagnostics (DLC1/DLC2 and MIL blink codes in the 2JZ-GE troubleshooting manual). Not California's 1988 "OBD I" regulation. | [MK4 Supra 2JZ-GE troubleshooting, EG-384–EG-385][tsrm-eg384]; EPA's OBD I vs OBD II contrast ([EPA420-F-03-042][epa-qa]). |
| DLC1 / DLC2 | Toyota **data link connector 1** (engine compartment) and **data link connector 2** (cabin) in the MK4 Supra 2JZ-GE troubleshooting manual. | [EG-385][tsrm-eg385], [EG-484][tsrm-eg484]. Presence on **this** LJ78 is `TBD`. |
| DLC3 | Toyota **data link connector 3**. A 2JZ-GE OBD II diagnostics manual says its terminal arrangement complies with SAE J1962. | [2JZ-GE engine diagnostics, DI-3 to DI-5][ge-di3]. Presence and location on **this** LJ78 is `TBD`. |

## Where the ECU and the label are

### On this truck (what to do)

The ECU is the Lexus donor engine computer, mounted wherever the swap builder put it. **Location on this LJ78 is `TBD`.** Search by following the engine harness, not by assuming a donor-car map.

On delivery day:

1. Find a metal engine-control box with a bolt-type multi-pin connector (the MK4 Supra 2JZ-GE procedure describes waterproof bolt-type ECM connectors: [EG-404][tsrm-eg404]). **Whether this unit matches that connector style is unverified until seen.**
2. Photograph **every face** of the case, including the underside. Toyota ECM part-number stickers are not guaranteed to face the technician; which face carries the label on this unit is **unverified**.
3. Photograph the connectors on the box (count and shape only; do not probe pins).
4. Write the location into [TRUCK.md](TRUCK.md) as an owner observation (for example "passenger footwell, photo …").

### Donor-chassis locations (search hints only)

These are locations in **other** 2JZ-GE vehicles. They are not facts about this LJ78.

- MK4 Supra 2JZ-GE troubleshooting: access the ECM by turning up the **passenger-side floor carpet** and removing the ECM protector ([EG-404][tsrm-eg404]).
- Lexus GS300 / IS300 engine-bay box, SC300 carpet, glove-box mounts, and similar lists from independent repair shops are **unverified** here. Use a donor-year service manual only after the donor application is known from the `89661` lookup.

A swap can relocate the box. A donor-manual location is a search order, not a confirmation.

## What the `89661-xxxxx` number tells us

Lexus TSB L-SB-0109-17 (RX 350, not this truck) names the ECM part "Computer, Engine Control (ECM/PCM)", lists `89661-` part numbers, and shows "Replacement ECM (PCM) Part Number (i.e., 89661-0E762)" on the authorized-modifications label figure ([NHTSA copy][lsb-0109-17]). Toyota T-SB-0077-16 uses the same part name and `89661-` pattern ([NHTSA copy][tsb-0077-16]). Dealer catalogs call the name code **89661** / COMPUTER, ENGINE CON ([Lexus listing][lexus-89661]). Different full numbers are different catalog applications. The suffixes in those bulletins are **not** this truck.

After you photograph the sticker:

| Read this | What it is | What to do with it |
|---|---|---|
| Full `89661-` number, every character | Toyota/Lexus catalog identity of **this** engine control computer | Transcribe into [TRUCK.md](TRUCK.md) **Donor ECU number**. Look the **exact** string up in Toyota/Lexus EPC / a dealer parts catalog. |
| Catalog fitment returned by that lookup | The vehicle / engine application Toyota filed for that number | Use it as a **candidate** donor model and year range. Copy into [TRUCK.md](TRUCK.md) only as "catalog application from EPC lookup of \<photographed number\>", still pending owner confirmation. |
| Other numbers on the same sticker (maker marks, lot, internal codes) | **Unverified** until identified from a cited Toyota document or the EPC | Photograph and transcribe. Do not treat them as the Toyota part number. |

### What the number does **not** tell us

- It does **not** encode OBD-II vs OBD1 in any source cited here. Do not decode the suffix into a protocol.
- It does **not** prove the donor market (US vs JDM). EPA OBD rules apply to US-certified light-duty vehicles ([EPA420-F-03-042][epa-qa]; [40 CFR 86.1806-05][cfr-1806]). A JDM application from EPC is **not** an EPA OBD-II guarantee.
- Example `89661-` suffixes on public parts pages are **not** this truck. Do not copy them into [TRUCK.md](TRUCK.md).

## Delivery-day read-off list

Print this. Record answers in [TRUCK.md](TRUCK.md) only from photos or notes taken on the truck.

**On the ECU case**

- [ ] Photo of each side of the box, in place, showing how it is mounted
- [ ] Photo of the label, readable, with the full `89661-` string
- [ ] Transcribed `89661-` number (every character, including leading zeros)
- [ ] Any other printed numbers, transcribed without interpretation
- [ ] Connector count and housing shape (observation only)

**Diagnostic connectors on this truck**

- [ ] Is there a 16-pin connector that matches the SAE J1962 vehicle diagnostic connector shape? ([SAE J1962][j1962]; [40 CFR 86.1806-05(h)(2)(iii)][cfr-1806]) Where? Photo.
- [ ] Is there a Toyota DLC1-style connector in the engine bay? ([EG-385][tsrm-eg385], [EG-484][tsrm-eg484]) Photo. Do not jumper terminals until you have the matching manual page in front of you.
- [ ] Is there a Toyota DLC2-style connector in the cabin? Same pages. Photo.
- [ ] Do those connectors look wired (harness actually plugged through), or empty shells? Observation only; harness notes stay `TBD` until written in [TRUCK.md](TRUCK.md).

**Live test (read-only)**

- [ ] If a J1962-style plug exists: ignition ON, engine may be off. Plug in the BLE ELM327-class adapter. Let it search. Record the protocol it reports and whether a current-data request returns. See [OBD-II path](#obd-ii-path-elm327-over-ble).
- [ ] Do **not** clear codes or write to the ECU ([VISION.md](../../VISION.md) non-goal: read-only).

**After the truck**

- [ ] EPC lookup of the photographed `89661-` number
- [ ] Walk the [decision tree](#decision-tree)
- [ ] Update [TRUCK.md](TRUCK.md) values only from the photos and the live test

## Decision tree

```
Photographed 89661-xxxxx
        |
        v
Look up exact number in Toyota/Lexus EPC
(catalog application = candidate donor, not protocol)
        |
        v
Inspect this truck's diagnostic plugs
        |
        +-- J1962-style 16-pin present ----------------------+
        |                                                    |
        |   Plug ELM327, ignition ON, auto protocol search   |
        |                                                    |
        |   Responds with a listed OBD-II protocol           |
        |   AND current data (SAE J1979)                    |
        |           |                                        |
        |          yes -----> OBD-II path                    |
        |           |                                        |
        |          no  -----> do not guess; go to OBD1 check |
        |                     (unwired plug, clone dongle,   |
        |                      or non-J1979 ECU are all open)|
        |                                                    |
        +-- no J1962-style plug, or ELM327 never speaks -----+
                            |
                            v
              DLC1 and/or DLC2 present?
                            |
               yes -----> OBD1 path (fallback)
               no  -----> ambiguous: record photos,
                          keep both Phase 2 seams,
                          do not pick #44 or #45 yet
```

Decide the path from **this truck's connectors plus a live test**, not from donor year folklore.

US light-duty context (not a mapping for this ECU): EPA required OBD on 1994 and later light-duty vehicles, with waivers common in 1994–1995, and **1996** as the first year of full implementation without those waivers ([EPA420-F-03-042, Q7][epa-qa]; original rule 58 FR 9468, 19 Feb 1993). For 1996–2007, [40 CFR 86.1806-05(h)(1)(iii)][cfr-1806] allowed SAE J1850, ISO 9141-2, or ISO 14230-4; model year 2008 and later light-duty must use ISO 15765-4 CAN ([40 CFR 86.1806-05(h)(1)(i)][cfr-1806]). Use that only as background for what an ELM327 might find. **Do not infer this Lexus ECU's protocol from a guessed year.**

One 2JZ-GE OBD II diagnostics manual uses DLC3, an OBD II scan tool complying with SAE J1978, SAE J2012 DTCs, and says DLC3 complies with SAE J1962 ([DI-3 to DI-5][ge-di3]). The MK4 Supra 2JZ-GE troubleshooting manual instead reads codes from MIL blinks with TE1 and E1 connected at DLC1 or DLC2 ([EG-384][tsrm-eg384], [EG-385][tsrm-eg385]). Both exist in 2JZ-GE literature. **Which interface this donor ECU implements is `TBD`.**

## OBD-II path (ELM327 over BLE)

Take this path only if the live test on **this** truck returns a supported OBD-II protocol and current data.

### What it needs

| Need | Why | Source |
|---|---|---|
| SAE J1962 vehicle connector wired to this ECU | Standardized OBD tool interface | [40 CFR 86.1806-05(h)(2)(iii)][cfr-1806]; [SAE J1962][j1962] |
| ECU that answers SAE J1979 (at least current powertrain data) | That is the scan-tool data this path will stream | [SAE J1979][j1979]; [40 CFR 86.1806-05(h)(2)(i)][cfr-1806] |
| ELM327-class interpreter that speaks SAE J1850 PWM/VPW, ISO 9141-2, ISO 14230-4, and ISO 15765-4 | Covers the federal OBD-II protocol set the chip claims | [ELM327 product page][elm327]; [ELM327 datasheet][elm327-ds] (UART/RS232 bridge, automatic protocol search, AT commands) |
| BLE wrapper around that UART | Phase 2 talks to the dongle with CoreBluetooth on iPhone | [ROADMAP.md](../../ROADMAP.md) M8; [VISION.md](../../VISION.md). The ELM327 IC itself is RS232, not BLE ([datasheet][elm327-ds]). Which BLE GATT UART the dongle uses is **unverified** until the specific adapter is tested. |
| `TelemetrySource` ELM327 implementation | Same protocol as the simulator | Issue #35 (M4 seam), issue #44 (M8, only if M5 confirms OBD-II) |

### Day-one dongle test

1. Adapter in the J1962-style plug, ignition ON.
2. Record whether the adapter enumerates over BLE.
3. Record the protocol it reports after search (ELM327 `AT DP` / equivalent).
4. Record whether current-data / Mode 01 style requests return (SAE J1979 current powertrain diagnostic data).
5. Write **Dongle compatibility** and **OBD protocol** in [TRUCK.md](TRUCK.md) from that log.

A 16-pin shell with no data is **not** an OBD-II ECU. Cheap "ELM327" dongles are often clones; a failed test is inconclusive until repeated with a known-good adapter (**unverified** until that retest).

### Phase 2 meaning

- Build issue **#44** (BLE ELM327 `TelemetrySource`).
- Do **not** start issue **#45** (OBD1 fallback).
- Keep the issue **#35** simulator; label simulated readings as simulated.

## OBD1 path (fallback source)

Take this path if there is no working J1979 session: no J1962-style plug, or the plug never speaks a listed OBD-II protocol after a fair dongle test.

### What the 2JZ-GE troubleshooting manual gives us

On the MK4 Supra 2JZ-GE application, the ECM stores diagnostic trouble codes and the MIL blinks them when TE1 and E1 on DLC1 or DLC2 are connected, using SST 09843-18020 ([EG-384][tsrm-eg384], [EG-385][tsrm-eg385]). DLC1 is in the engine compartment; DLC2 is in the cabin; TE2 exists only on DLC2 ([EG-484][tsrm-eg484]).

That is a **blink-code** interface. It is not SAE J1979 live PIDs. It is not enough by itself for Phase 2 anchored live readings.

This page does not describe how to jumper those terminals on **this** truck. Pin and wire assignment for this harness is `TBD`. Do not copy pin maps from other cars.

### What the fallback source still needs (all `TBD` until issue #45)

| Need | Status | Source |
|---|---|---|
| DLC1 and/or DLC2 actually present and wired on this LJ78 | `TBD` | Owner photos; [EG-385][tsrm-eg385] / [EG-484][tsrm-eg484] as the manual names for those connectors |
| A cited description of what live data this ECU can emit, if any | `TBD` | Issue **#45** spike; do not invent a Toyota serial protocol |
| Hardware to read that data from an iPhone | `TBD` | Same spike. ELM327 is specified for the standard OBD-II set ([ELM327][elm327]), not for Toyota MIL blink codes |
| `TelemetrySource` implementation behind the M4 seam | Only if M5 records OBD1 | [ROADMAP.md](../../ROADMAP.md) M8; issue **#45** |

### Phase 2 meaning

- Start issue **#45** with a cited hardware spike. Do not build a reader from forum pinouts.
- Do **not** treat issue **#44** as the live source.
- Keep issue **#35** so UI and tests still run on the simulator.

## Ambiguous / both / neither

Record the photos and leave **OBD protocol** as `TBD` when:

- Both a J1962-style plug and DLC1/DLC2 exist (possible on some Toyota OBD-II applications; **unverified** for this swap).
- Neither connector exists (swap omitted diagnostics; **unverified** until seen).
- The `89661` EPC application and the live test disagree.

Phase 2 then keeps **both** `TelemetrySource` seams from issue #35 and starts neither #44 nor #45 until [TRUCK.md](TRUCK.md) has a confirmed protocol.

## How to record the result

When delivery-day evidence exists, update [TRUCK.md](TRUCK.md) only:

| Fact | Confirm from |
|---|---|
| Donor ECU number | Photo of the `89661-` label |
| Donor model year | EPC catalog application of that number, plus any donor-VIN evidence the owner has, cited |
| OBD protocol | Live ELM327 result, or a written OBD1 finding with the connector photos |
| Dongle compatibility | That same live test (works / partial / no link) |
| Harness notes | Photos of DLC wiring and firewall pass-through, as observations |

Until then every one of those values stays `TBD`. Resolving the tree is issue **#38** (M5), not this spike.

## Sources

Manual pages (PDFs stay out of git; these spike sources are not the Phase 1 IDs in [`docs/MANUALS.md`](../MANUALS.md)):

- [MK4 Supra 2JZ-GE engine troubleshooting, EG-384 — diagnosis system][tsrm-eg384]
- [Same, EG-385 — MIL check; DLC1/DLC2; TE1–E1][tsrm-eg385]
- [Same, EG-404 — ECM under passenger-side floor carpet; bolt-type connectors][tsrm-eg404]
- [Same, EG-484 — DLC1 in engine compartment, DLC2 in cabin][tsrm-eg484]
- [Toyota 2JZ-GE engine diagnostics, DI-3 to DI-5 — OBD II scan tool, DLC3, SAE J1978 / J1962 / J2012][ge-di3]

Linked references:

- [Lexus L-SB-0109-17 (NHTSA): Computer, Engine Control (ECM/PCM), `89661-` ECM part numbers][lsb-0109-17] (example suffixes are **not** this truck)
- [Toyota T-SB-0077-16 (NHTSA): Computer, Engine Control, `89661-` ECM part numbers][tsb-0077-16] (example suffixes are **not** this truck)
- [Lexus dealer parts: part name code 89661 = COMPUTER, ENGINE CON][lexus-89661] (example suffix on that page is **not** this truck)
- [EPA420-F-03-042, Dec 2003 — OBD vs OBD II; 1994 start; 1996 full implementation][epa-qa]
- [58 FR 9468, 19 Feb 1993 — federal OBD beginning 1994 MY][fr-1993] (as cited in later EPA documents)
- [40 CFR 86.1806-05 — OBD; SAE J1962 / J1979; 1996–2007 protocols; 2008+ CAN][cfr-1806]
- [SAE J1962 — diagnostic connector][j1962] ([DOI][j1962-doi])
- [SAE J1979 — diagnostic test modes][j1979] ([DOI][j1979-doi])
- [ELM Electronics ELM327 — OBD-II protocols][elm327]
- [ELM327 datasheet — RS232 interpreter, protocol search][elm327-ds]
- [VISION.md](../../VISION.md), [ROADMAP.md](../../ROADMAP.md), [TRUCK.md](TRUCK.md)

## Unverified

- Physical location of this swap's ECU and of its part-number sticker
- Whether this unit uses bolt-type waterproof connectors
- Whether DLC1, DLC2, and/or DLC3 exist on this LJ78, and whether they are wired
- Donor market, donor chassis, and donor year
- Mapping any `89661` suffix to a protocol or year without an EPC lookup of the photographed number
- BLE GATT details of the specific dongle; genuineness of cheap ELM327 clones
- Any live serial protocol, pinout, or wire color for the OBD1 fallback (issue #45)
- Independent "Toyota/Lexus ECM location" shop lists as applied to this truck

[lexus-89661]: https://www.lexuspartsnow.com/parts/lexus-computer-engine-con~89661-0el80.html
[lsb-0109-17]: https://static.nhtsa.gov/odi/tsbs/2017/MC-10131772-9999.pdf
[tsb-0077-16]: https://static.nhtsa.gov/odi/tsbs/2016/MC-10132910-9999.pdf
[tsrm-eg384]: https://tsrm.sasquatchvc.com/mk4/tsrm/TGE/4
[tsrm-eg385]: https://tsrm.sasquatchvc.com/mk4/tsrm/TGE/5
[tsrm-eg404]: https://tsrm.sasquatchvc.com/mk4/tsrm/TGE/24
[tsrm-eg484]: https://tsrm.sasquatchvc.com/mk4/tsrm/TGE/104
[ge-di3]: https://www.2jzgarage.com/wp-content/uploads/Supra/Workshop_Manual/2JZGE/2JZ-GE%20Engine%20Diagnostics.pdf
[epa-qa]: https://nepis.epa.gov/Exe/ZyPURL.cgi?Dockey=P100LW9G.TXT
[fr-1993]: https://www.govinfo.gov/content/pkg/FR-1995-08-18/html/95-20539.htm
[cfr-1806]: https://www.govinfo.gov/content/pkg/CFR-2014-title40-vol19/pdf/CFR-2014-title40-vol19-sec86-1806-05.pdf
[j1962]: https://saemobilus.sae.org/standards/j1962_201607-diagnostic-connector
[j1962-doi]: https://doi.org/10.4271/J1962_201607
[j1979]: https://saemobilus.sae.org/standards/j1979_199709-e-e-diagnostic-test-modes
[j1979-doi]: https://doi.org/10.4271/J1979_199709
[elm327]: https://elmelectronics.com/products/ics/obd/
[elm327-ds]: https://www.elmelectronics.com/wp-content/uploads/2020/05/ELM327DSL.pdf
