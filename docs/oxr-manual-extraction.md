# Pulling specs out of the service manuals

## TL;DR

Sidekick's chat mechanic should only quote specs (torques, clearances) that are really printed in the service manual.
Plain PDF text scrambles tables, so we ran the 2JZ-GE repair manual through OXR, a page-reading model, and checked every number it found three ways.
On a 193-page spec sample, the share of numbers we'd trust went from **72.1%** to **94.3%**. On the other 1,809 pages it's **64.9%**, and diagnostics is the weak spot.
The full-manual run cost **about $1.81**. None of it is in the app's search index yet, so answers still come from the old plain-text pages.

## What this doc is

The chat mechanic in Sidekick is only supposed to repeat a torque, a clearance, or a spec that's actually printed in the service manual. This doc records how we pulled those numbers out of the 2JZ-GE repair manual, how we checked them, and what still isn't safe to trust.

There's an interactive picture of the same pipeline in [PR #165](https://github.com/zeketx/sidekick-mechanic/pull/165). It was drawn from an earlier test on public pages. This doc is the later write-up, and it covers the full manual.

The raw count files live on the bot's machine. They are not in the repo.

## The short version, in numbers

Text pulled straight out of the PDF scrambles tables. One OCR pass (software that reads text off a page image) misreads sizes. A wrong torque can snap a bolt.

So we ran the pages through OXR on a rented GPU (the graphics card that runs the model). Then we checked every number three ways:

- Do the units convert?
- Does another reader see the same digits?
- Does a vision model (an AI that reads images) read the same crop of the page the same way?

Here's how it came out:

- On the 193-page spec sample, the share we'd trust went from **72.1%** to **94.2%** to **94.3%** as the checker got smarter.
- On the other 1,809 pages of the repair manual it's **64.9%**. It was 61.8% before the last checker fix.
- If you set aside two pages where OXR's table got cut off, that becomes **76.6%**.
- The back of the book is about **89%**. The diagnostics section is about **54%**.
- The whole full-manual pass cost **about $1.81**. OXR took **about 0.95 seconds a page** on an A40 (the GPU model we rented).

The catch: those checked numbers aren't in the search index yet. Until they are, the app still answers from the old plain-text pages.

## Why we needed this

Sidekick answers from the factory manuals: the Toyota LJ78 chassis book, the 2JZ-GE engine repair manual, and the ECU docs (the ECU is the truck's engine computer).

Each reply cites a page. Then a spec guard (a check on the answer) throws out any number that isn't in the text we stored for that page.

The problem is that the guard is only as good as the stored text. If the stored line is the wrong row, or a misread, the guard will happily keep a bad torque.

### The test that settled it

[Issue #163](https://github.com/zeketx/sidekick-mechanic/issues/163) tested this on public-domain pages before anyone touched the copyrighted manuals. It spot-checked 35 table values:

| Reader | Values it got right |
| --- | --- |
| `pypdf`, the current ingester (the same call `ingest.py` uses) | **5 of 35** |
| Tesseract (another OCR reader), for reference | 12 of 35 |
| OXR | **33 of 35** |

OXR still misread fastener fractions, and a second run misread them differently (5/16 came back as 1/6).

So OXR was worth using. Its raw output was not worth trusting.

## How the checking works

OXR (SoMark OXR-1.0) reads each page into text, tables, and pictures. We hosted it ourselves on vLLM 0.25.1, on a Runpod GPU (Runpod rents out GPUs). We did that because the manual pages shouldn't go to someone else's document API.

Every number OXR wrote down then went through the checks from the #163 design:

1. **Unit rules.** Torque, length, and temperature conversions have to agree: N·m against kgf·cm against ft·lbf, mm against inches, °C against °F. If they don't, the number gets flagged. The rule never "fixes" the number.
2. **A vote.** OXR's digits have to match another reader on that page. That's either the PDF's built-in text layer (read with `pypdf`) or Tesseract. On a scanned page with no text layer, only Tesseract can vote.
3. **A blind re-read.** Gemini flash-lite (`gemini-3.5-flash-lite` on OpenRouter, a service for calling AI models) copies down the cropped table without seeing OXR's answer. The number has to show up with the same value. We kept this blind mode on purpose. We also tried a confirm mode, where the model was shown OXR's cells and asked to judge them, and it let bad row-shifts (values landing in the wrong row) through.
4. **Show the crop.** When the checks still aren't sure, the owner should see the snippet of the page, not a bare number. This layer is proposed. It is not built.

Here's the same flow as a diagram:

```mermaid
flowchart TD
    page["Service-manual page"] --> oxr["OXR reads the page on a rented GPU"]
    oxr -->|"table cut off, or stuck repeating one cell"| raw["RAW: never trusted"]
    oxr --> num["Each number OXR writes down"]
    num --> rules["Layer 1: do the units convert?"]
    rules -->|"no: RULE-FAIL"| flagged["FLAGGED"]
    rules -->|"yes"| vote["Layer 2: pypdf and Tesseract vote"]
    vote -->|"readers disagree"| disagreed["DISAGREED"]
    disagreed --> flagged
    vote -->|"a reader agrees"| vision["Layer 3: blind re-read of the crop"]
    vision -->|"different value"| mismatch["MISMATCH"]
    mismatch --> flagged
    vision -->|"same value, same row"| verified["VERIFIED, counted in strict"]
    vision -->|"same text, row did not line up"| loose["VERIFIED, left out of strict"]
    flagged -.->|"proposed, not built"| crop["Layer 4: show the source crop"]
```

### What the labels mean

| Label | Meaning |
| --- | --- |
| **VERIFIED** | Passed the unit rule, matched at least one other reader, and passed the blind re-read. This is the only state that should be served as a fact. |
| **FLAGGED** | At least one check failed, and the reason is attached. The reason can be a unit rule (`RULE-FAIL`), readers that disagree (`DISAGREED`), a vision reading that differs (`MISMATCH`), both, or a crop the vision model couldn't read (`UNREADABLE`). |
| **RAW** | OXR's table was cut off or stuck in a loop. These values are never trusted and can never become VERIFIED. |
| **strict** | The tighter VERIFIED count. Sometimes the vision model saw the same text somewhere in the table, but the rows didn't line up. That value is still VERIFIED, but strict leaves it out, because we confirmed the digits and not which row they belong to. |

`DISAGREED` and `MISMATCH` are reasons on the way to `FLAGGED`. In the end, every value is stored as `VERIFIED`, `FLAGGED`, or `RAW`.

## What we got

We did two runs, both on the owner's manuals. Neither is committed, because the PDFs stay out of git.

### Run 1: the 193-page spec sample (72.1% to 94.2% to 94.3%)

The sample had 193 pages:

- SS-1 through SS-50 and EM-1 through EM-100 of RM1054U, the 2JZ-GE repair manual. That's 150 pages, the torque and clearance sections.
- All 43 pages of EWD451U, the IS300 engine wiring book.

The wiring book produced **0 values**. OXR returns those diagrams as pictures.

The percentages below are the share of extracted numbers marked VERIFIED. We didn't run the GPU a second time. We re-scored the same OXR output each time the checker improved.

| Checker | Numbers scored | VERIFIED | Strict |
| --- | --- | --- | --- |
| v1 | 3,379 | 2,437 (**72.1%**) | n/a |
| v2 | 2,910 | 2,742 (**94.2%**) | 91.6% |
| v3 | 2,984 | 2,813 (**94.3%**) | 91.7% |

**Why v2 looks like such a big jump.** Mostly because v1 was counting a broken page. On EM-9 (PDF p749), OXR got stuck in a loop and wrote the same shim cell, `2.500 (0.0008)`, about 480 times.

All of those were flagged or, after v2, dropped. v2 deleted 477 duplicate cells, left 3 as RAW, and scored the real shim-number table on that page (25 values, all verified).

The big shim-selection grid on the same page is a picture. It was never extracted, so it isn't in these percentages.

Nothing that was VERIFIED in v1 lost that mark in v2 or v3.

### Run 2: the rest of the repair manual (61.8% to 64.9%)

The next run covered the other **1,809 pages** of RM1054U. Add the 150-page SS/EM slice and that's the whole 1,959-page manual.

Checker v2.1 scored it, then v3 scored the same pages again. OXR itself was not re-run.

| | v2.1 | v3 |
| --- | --- | --- |
| Numbers scored | 5,595 | 6,403 |
| VERIFIED | 3,455 (**61.8%**) | 4,156 (**64.9%**) |
| Strict | 3,315 (59.2%) | 4,032 (63.0%) |
| VERIFIED, without the 2 RAW pages | 74.9% | **76.6%** (strict 74.3%) |
| FLAGGED | 1,160 | 1,267 |
| RAW | 980 | 980 |
| Unit-rule fails | 72 | 16 |

**Why the percentage only moved a few points.** v3 changed what gets counted, in both directions:

- It started scoring 1,002 rows the old header parser had swallowed (685 of them verified).
- It stopped scoring 194 page references such as `See page SA-88`.

On the 5,401 numbers present in both versions, **165 flags cleared and zero verified numbers flipped back to flagged.**

#### Which parts of the manual came out well

| Slice | Numbers | VERIFIED | Strict |
| --- | --- | --- | --- |
| All 1,809 pages | 6,403 | 4,156 (64.9%) | 4,032 (63.0%) |
| Without DI PDF p0210 and p0528 (980 RAW values) | 5,423 | 76.6% | 74.3% |
| Diagnostics block, PDF pp. 192-740 | 4,168 | 2,267 (**54.4%**) | 52.7% |
| Front of the book, before p142 | 460 | 315 (68.5%) | 57.8% |
| Back of the book, after p840 | 1,775 | 1,574 (**88.7%**) | 88.5% |

The back of the manual (after PDF p840) is in good shape.

Diagnostics (DI) is the weak part. It's full of scanned fault-code matrices, plus long code tables where the readers don't line up.

#### Why the 1,267 flagged values got flagged

| Why it was flagged | Values |
| --- | --- |
| Vision read a different value (`MISMATCH` only) | 496 |
| The other readers disagreed (`DISAGREED` only) | 475 |
| Both | 269 |
| Unit rule failed, and vision also mismatched | 3 |
| Unit rule failed on its own | 13 |
| Vision model could not read the cell | 11 |

331 of those flags are on scanned pages with no text layer. 322 of them are on the 12 DTC monitor matrices (DTC means fault code; these are DI PDF pp. 210-215 and 528-533).

Two of those twelve pages are the RAW ones. Their values are separate from this flag count.

#### Spot checks

We ran four spot checks of 40 verified numbers each. All of them matched the page.

Most were found in the PDF text layer. A handful on picture pages were checked by eye against the page render. These are samples, not a full audit. The breakdown is in [Technical details](#technical-details).

### What each checker update fixed

The short version:

- **v1 to v2** taught the checker to read messy table layouts (cells that span rows, wrapped row names, several specs stacked in one cell) and collapsed the EM-9 loop.
- **v2 to v2.1** stopped real fault-code tables from being mistaken for loops.
- **v2.1 to v3** stopped treating fault codes and page references as broken numbers, and recovered diagnostics rows the header parser had been swallowing.

<details><summary>Technical details: every checker fix</summary>

**v1 to v2** (193-page sample, same OXR output, one extra vision call at $0.0012):

- A cell that spans rows is scored once, where it starts. In v1 the spanning cell got mixed into every row and broke the match.
- Row names are matched as words. Long names wrap, and a name like "No. 1" was hiding its digit inside the number check.
- Stacked cells (several specs in one printed cell) are checked one line at a time if the whole row fails.
- Small-integer lookup grids (the bearing-selection charts) count as a match when a reader line has that exact digit sequence.
- Torque tables with two unit groups get both groups checked. v1 only checked the last group, and because of that it missed a real rounding inconsistency on SS-2.
- The EM-9 loop is collapsed. Repeats of 8 or more identical cells are removed. A cut-off table can never be VERIFIED.
- The vision check can confirm a value from another column of the same row. It can also confirm one from the same text elsewhere in the table when the rows don't line up. That second case is the "not strict" one.

**v2 to v2.1** (full-manual copy only): the loop detector was calling real DTC tables a loop, because they repeat "OK" eight or more times. Now a table counts as a loop only when its markup is cut off (no closing `</table>`) or it has a run of 20 or more identical cells. A cut-off table is always RAW.

**v2.1 to v3** (both sets, no GPU):

- DTC codes are codes. `P0030,50` and `C0279/12` are not broken numbers. A real number with a unit in the same cell is still checked. On the full run this cleared the 58 DTC-code false alarms inside the 72 rule fails. Sixteen rule fails remain.
- Header detection no longer swallows a whole diagnostics table. That recovery is the 1,002 newly scored values.
- A cell whose only digits are a page reference isn't a spec. That removal is the 194 dropped values, including the SS-38 "See page SA-88" false alarm.
- Glued lines (`P0301 (DI-164)`) are checked one printed line at a time.
- The vision step reuses the cached read when it already covers the table. It also decodes escaped characters, and lines a row up when there's a single unique cell match.

</details>

### Typos that are really printed in the manual

The unit rule caught these, and the PDF text layer shows the same pairs. So they're printed in the manual itself, not misreads.

They stay flagged. Don't use them as specs.

From the SS/EM sample:

| Where | Printed | What the conversion expects |
| --- | --- | --- |
| SS-9, PDF p150 | 49 N·m / 500 kgf·cm / **30** ft·lbf | about 36 ft·lbf |
| SS-9, PDF p150 | 119 N·m / **1,120** kgf·cm | about 1,213 kgf·cm |
| SS-9, PDF p150 | 6.0 / 60 / 53, no unit on the last number | 53 is in.·lbf, and the unit is missing |
| SS-27, PDF p168 | 9.8 N·m / **10** kgf·cm | about 100 kgf·cm |
| SS-27, PDF p168 | 25 N·m / **25.5** kgf·cm | about 255 kgf·cm |
| SS-30, PDF p171 | 6.4 / 65 / 56, no in.·lbf unit on that row | unit missing |
| SS-19, PDF p160 | 29.0 mm (**1.412** in.) | about 1.142 in. |
| SS-2, PDF p143 | 5 N·m / 55 kgf·cm / **48** in.·lbf | 5 N·m is about 44 in.·lbf; 48 matches 55 kgf·cm (about 5.4 N·m). A rounding inconsistency. v1 never checked this column group. |

From the rest of the manual:

| Where | Printed | What the conversion expects |
| --- | --- | --- |
| DI-355, PDF p546 | ATF temperature 110 °C (176 °F) | 110 °C is 230 °F, and 176 °F is 80 °C |
| RS-23, PDF p1347 | Width 185 mm (7.87 in.) | 185 mm is 7.28 in., and 7.87 in. is 200 mm |
| DI-279, PDF p470 | Engine coolant temperature, maximum 0°C (0°F) | 0 °C is 32 °F. Treated as a likely typo. |
| ST-7, PDF p1003 | Minimum diameter 29.0 mm (1.412 in.) | same pair as SS-19 |
| MT-8, PDF p1057 | 9.8 N·m (10 kgf·cm, 7 ft·lbf) | same pair as SS-27 |

There was also one thing OXR made up, separate from the printed typos. On EM-91 (PDF p831) it added "0.06 mm (0.0001 in)" next to the real "0.06 mm (0.0024 in.)". The unit rule and the vote both caught it.

### Cost and speed

Here's the full-manual pass, added up after Runpod billing posted:

| Piece | Cost |
| --- | --- |
| Runpod A40, about 48 minutes, billed | $0.46 ($0.4617) |
| OpenRouter, the full-run vision check, 1,343 calls | $0.95 ($0.9543) |
| OpenRouter, the v3 re-check, 338 new calls, the rest from cache | $0.40 ($0.3983) |
| **Total** | **$1.81** |

OXR's main pass on that A40 took 1,724 seconds, **0.95 s/page**, at concurrency 8 (8 pages in flight at once).

Four pages timed out around 245 seconds and succeeded on a retry. The pod (the rented GPU machine) has been terminated.

The earlier 193-page GPU run isn't inside that $1.81. It used a smaller card (a 24 GB slice), ran at about 1.73 s/page, and cost about $0.43 for that pass. Details are in [Technical details](#technical-details).

## What's still missing

- **Scanned diagnostics matrices.** Twelve DTC monitor pages are pictures with no text layer, so Tesseract is the only reader that can vote. 322 flags sit there. On two of them, DI PDF p0210 and p0528, OXR's table was cut off and 980 values are RAW.
- **Wiring diagrams.** OXR returns the drawing as a picture, and we score pictures as nothing. The 43-page EWD451U run extracted 0 values. Inside RM1054U, 78 pages contain a wiring diagram. None of those pages is diagram-only, so the words on them were still checked. But 47 of them had nothing extracted from the drawing.
- **The EM-9 shim-selection grid.** It's image only: about 41 shim-thickness columns by about 50 clearance rows. We counted those off the page image, so the counts are approximate. There's no text layer, Tesseract garbles the digits on the grid lines, and OXR didn't transcribe it. So the grid isn't in the scored numbers. The small shim-number table on the same page is separate, and those 25 values are verified.
- **Dense tables where the readers disagree about layout.** Think bearing-selection grids, bolt tables with a class cell spanning rows, sensor-resistance stacks, and DI label matrices. Hundreds of `DISAGREED` and `MISMATCH` flags come from these, not from a known wrong digit. They stay flagged until someone looks.
- **Temperature differences.** Eleven values such as `3 °C (5.4 °F)` are a change in temperature, printed as a difference. The rule treats them as thermometer readings (3 °C would be about 37 °F) and flags them. We left the rule strict on purpose. They're false alarms.
- **Layer 4 isn't built.** A flagged number still has nowhere to show the crop.
- **The LJ78 chassis and ECU manuals haven't been run.** `lj78-wiring` is blocked: the file is image-only and AES-encrypted, and it doesn't name LJ78 ([MANUALS.md](MANUALS.md), [ewd-ingest-unblock.md](design/ewd-ingest-unblock.md)). We need a readable chassis wiring manual before that run means anything. The ECU book depends on which computer is in the truck. That stays unknown until there's a photo of the `89661-` label ([ECU.md](vehicle/ECU.md)).
- **Nothing is in the repo or the search index.** Outputs live on the bot's box under `/workspace/oxr-2jz/`. The pod is gone. Today's ingest is still one plain-text chunk per page, and the [spec guard](design/spec-guard.md) checks answers against that text.

## What to do next

In this order:

1. **Put the checked values in the search index, with their state attached.** Only `VERIFIED` gets served as a fact. `FLAGGED` gets shown with the source crop (that's layer 4). `RAW` stays out. The spec guard still has the last word.
2. **Use a different approach for scanned matrices and wiring.** OXR's table reader is the wrong tool for a picture of a fault-code grid or a connector drawing. Use a vision model aimed at pins, connectors, and matrix cells, and keep those results in their own check. The earlier wiring spike already points toward citing the page image when the text isn't trustworthy ([wiring-diagram-spike.md](design/wiring-diagram-spike.md)).
3. **Then the LJ78 manual and the ECU manual.** That waits on a readable LJ78 wiring manual, and on a photo of the ECU's `89661-` number so we know which book to open.

## Technical details

Everything from here down is the deep dive. You don't need it to follow the rest of the doc.

The numbers in this doc come from the comments on [#163](https://github.com/zeketx/sidekick-mechanic/issues/163) and from the v3 count files on the bot's box (`full/out/v3/counts.json`, `full/out/v3/compare_v2_v3.json`, and the 193-page `compare_v2_v3.json`). Those JSON files are not committed.

Where a comment rounds and the count file has pennies or a tenth of a percent, both are shown.

### Deep dive: how a value moves through the checks

Layer 2 (the vote) agrees when **at least one** independent reader matches OXR. On the first 193-page scoring that was 2,624 agreed and 755 disagreed, out of 3,379.

A tighter cut that required **both** readers to match was 2,433 agreed and 946 disagreed.

That "both readers" cut is not the **strict** column in the tables above. Strict, in v2 and v3, is only about the vision step. It drops VERIFIED values whose match was "the text appears in this table, and the rows did not line up."

Vision unreadable is a flag, not a pass. On v1 that was 529 values, mostly the EM-9 loop and spanned tables. On v3 of the full run it's 11.

OXR often rewrites `in.·lbf` as `in lbf` or `in ibf`. When the number was right, we treated that as punctuation and didn't flag it.

### Deep dive: the 193-page run, checker v1

OXR returned 85 table blocks, all of them in RM1054U, plus 1,263 text blocks, 351 pictures, and 316 titles. EWD451U was 39 pictures, 3 captions, and 2 titles.

3,379 numbers on 98 pages were checked: 3,217 table cells and 162 inline specs. 73 tables had numeric cells.

| Layer | v1 result |
| --- | --- |
| Unit rules | 3,358 passed, 21 failed |
| Vote | 2,624 agreed, 755 disagreed |
| Blind vision | 2,700 confirmed, 150 mismatch, 529 unreadable |
| Final | 2,437 VERIFIED (72.1%), 942 FLAGGED |

480 of the flags were the EM-9 loop. With that page set aside: 2,874 numbers, 2,437 VERIFIED (84.8%), 437 flagged.

By section on v1: SS had 2,152 verified and 326 flagged. EM had 285 verified and 616 flagged.

**The machine.** A Secure RTX PRO 6000 MIG slice (a 24 GB slice of the card, $0.69/hr), at concurrency 4.

**Speed.** 193 pages in 333.7 seconds of wall clock, **1.73 s/page**. That includes a 243-second failed EM-9 request (OXR error 1137). With the 87-second retry, it's about **2.2 s/page**.

Median request time: wiring 0.31 s, EM 5.7 s, SS 8.0 s. Tesseract on the same machine, with 12 processes, finished the 193 pages in 121 seconds.

**Cost of that run.** About **$0.22** of GPU time and **$0.2085** of OpenRouter (218 calls, 0 errors). About **$0.43** together. The GPU figure is an estimate from the clock (about 0.33 GPU-hours), not a posted bill.

The later checker-only calls are extra: **$0.0012** for v2 (1 call) and **$0.0371** for the v3 re-score of this set (19 calls).

The $0.0371 is included in the full-manual $1.81, because that's how the v3 bill was totaled. The $0.22, the $0.2085, and the $0.0012 are not.

### Deep dive: checker v2 on that same output

| | v1 | v2 |
| --- | --- | --- |
| Scored | 3,379 | 2,910 |
| VERIFIED | 2,437 (72.1%) | 2,742 (94.2%); strict 2,665 (91.6%) |
| FLAGGED | 942 | 165 |
| RAW | n/a | 3 |
| Unit-rule fails | 21 | 24 |
| Disagreed | 755 | 81 |
| Vision mismatch | 150 | 51 |
| Unreadable / skipped | 529 / 0 | 22 / 3 |

The 24 v2 rule fails include the SS/EM printed typos in the typo table above, the EM-91 misread, the new SS-2 catch, and the SS-38 "See page SA-88" false alarm. v3 drops that false alarm (it's the one reference removed on this set).

v2 also added 8 grid row-label cells on EM-85 and removed the 477 duplicate EM-9 cells. Newly verified: 305. All 2,437 v1 verified values stayed verified.

The v2 write-up splits the 165 flags like this. The buckets overlap a little: two of the 22 unreadable cells also disagreed, and 2 of the 24 rule fails also carry another reason. The 3 RAW leftovers sit outside the 165.

| Why | Values |
| --- | --- |
| Disagreed only | 70 |
| Vision mismatch only | 44 |
| Unreadable | 22 |
| Unit-rule fail | 24 |
| Disagreed and mismatch | 5 |

v3's flag mix on this set wasn't broken out the same way. v3 has 168 flagged and the same 3 RAW.

v3 on this set: 2,813 / 2,984 verified (94.3%, strict 91.7%). One reference removed, 75 values added (66 verified, 9 flagged), 5 flags cleared, 0 regressions.

### Deep dive: the four spot checks

Each sample was 40 verified values:

1. **Newly verified v2 values.** 36 matched in `pdftotext -layout`. The other 4 are EM-9 shim-table cells with no text layer, confirmed by eye (shims 1, 3, 14, and 16).
2. **v1 verified values.** All 40 found in the PDF text layer.
3. **Full-run v2.1 verified values.** 37 in `pdftotext`, and 3 on raster (picture-only) pages confirmed from the 300 dpi render.
4. **v3 newly verified values across both sets.** All 40 in `pdftotext -layout`.

### Deep dive: full run, v2.1 (before the v3 re-score)

1,809 pages: diagnostics block 549, front 141, back 1,119. Every page was sent.

1,098 pages had nothing to check (procedure text and figures). 94 pages were picture or title only.

Section page counts, from the headers on those pages: DI 469, BO 238, BE 230, SF 136, PP 86, AC 83, RS 79, SA 65, IN 60, SR 59, BR 56, MT 47, AT 41, CO 36, ST 19, CH 17, CL 17, EC 14, IG 14, LU 13, PR 12, EM 9, MA 5, SS 2, GL 2.

v2.1 verified rate by section, on the values it scored (the DI row is 1,611 / 3,381):

| Section | VERIFIED | Section | VERIFIED |
| --- | --- | --- | --- |
| DI | 47.6% | AT | 68.8% |
| PP | 69.2% | BR | 98.1% |
| BE | 83.9% | SA | 95.9% |
| BO | 90.2% | SR | 86.2% |
| SF | 82.4% | IN | 49.3% |
| AC | 91.2% | | |
| MT | 99.1% | | |

The v2.1 write-up called everything else at least 78%. v3 re-scored these pages, so the table in the next section is the current one.

**v2.1 flag reasons:** mismatch only 429, disagreed only 375, both 275, unit-rule 72, unreadable 9.

Of the 72 rule fails, 58 were DTC codes read as broken thousands-separators, 10 were temperature differences, and 4 were the printed typos (DI-355, RS-23, ST-7, MT-8).

364 flags were on raster pages, 356 of them on the 12 DTC matrix pages.

**Timeouts.** Four OXR timeouts at about 245 seconds: DI PDF p0210, p0528, p0530, and p0533. All four succeeded on retry. p0210 and p0528 came back truncated, and those are the 980 RAW values.

**The machine.** One Secure A40 in EU-SE-1, $0.59/hr, concurrency 8, Tesseract with 4 processes. Setup took about 10 minutes.

OXR main pass: 1,724 s (0.95 s/page), or 1,865 s including retries. Tesseract: 1,912 s. Pod lifetime was about 48 minutes. The vision check was about 1,343 calls.

**Spend before the v3 re-score.** About $0.47 of GPU (the estimate at the time) and $0.9543 of OpenRouter, about $1.42. Billing later posted the GPU at $0.4617.

### Deep dive: full run, v3 (current counts)

Compare-file totals:

- 194 references dropped (149 had been VERIFIED, 45 flagged).
- 1,002 values added (685 verified, 317 flagged).
- 165 flags cleared on values both versions scored.
- 0 regressions.
- 850 newly verified in all (685 plus 165).

On the 5,401 shared values, verified went from 61.2% to 64.3%.

Here's v3 by section, on the 1,809-page run only. This comes from the count file, not the v2.1 table, and it doesn't include the SS/EM pilot. The SS and EM rows are the few pages of those sections that fell outside the pilot range.

| Section | Values | VERIFIED | % | Strict % | Flagged | RAW |
| --- | --- | --- | --- | --- | --- | --- |
| AC | 141 | 128 | 90.8 | 90.8 | 13 | 0 |
| AT | 105 | 75 | 71.4 | 71.4 | 30 | 0 |
| BE | 541 | 455 | 84.1 | 83.9 | 86 | 0 |
| BO | 248 | 223 | 89.9 | 89.9 | 25 | 0 |
| BR | 87 | 85 | 97.7 | 97.7 | 2 | 0 |
| CH | 25 | 24 | 96.0 | 96.0 | 1 | 0 |
| CL | 18 | 18 | 100.0 | 100.0 | 0 | 0 |
| CO | 45 | 38 | 84.4 | 84.4 | 7 | 0 |
| DI | 4,110 | 2,237 | 54.4 | 52.7 | 893 | 980 |
| EC | 6 | 6 | 100.0 | 100.0 | 0 | 0 |
| EM | 10 | 10 | 100.0 | 100.0 | 0 | 0 |
| GL | 6 | 5 | 83.3 | 83.3 | 1 | 0 |
| IG | 22 | 22 | 100.0 | 100.0 | 0 | 0 |
| IN | 69 | 46 | 66.7 | 66.7 | 23 | 0 |
| LU | 25 | 20 | 80.0 | 80.0 | 5 | 0 |
| MA | 4 | 4 | 100.0 | 100.0 | 0 | 0 |
| MT | 117 | 115 | 98.3 | 98.3 | 2 | 0 |
| PP | 407 | 277 | 68.1 | 56.0 | 130 | 0 |
| PR | 20 | 20 | 100.0 | 90.0 | 0 | 0 |
| RS | 32 | 27 | 84.4 | 84.4 | 5 | 0 |
| SA | 99 | 94 | 94.9 | 93.9 | 5 | 0 |
| SF | 154 | 132 | 85.7 | 85.7 | 22 | 0 |
| SR | 82 | 69 | 84.1 | 84.1 | 13 | 0 |
| SS | 3 | 3 | 100.0 | 100.0 | 0 | 0 |
| ST | 27 | 23 | 85.2 | 85.2 | 4 | 0 |

**DI section vs. DI page block.** These are two different cuts. The DI **section** is 4,110 values. The DI **page block** is 4,168 values (PDF pp. 192-740). Both come out to 54.4% verified. The block includes a few pages whose header is another section. The 980 RAW values are in both cuts.

**The 16 remaining rule fails.** 11 are temperature-difference false alarms on DI PDF pp. 285, 298, 423, and 444. The other five are the printed values in the typo table (DI-279, DI-355, ST-7, MT-8, RS-23).

The count file's checker message for the 29.0 mm pair says "expected ≈1.14", while the SS-19 note says "≈1.142". It's the same printed pair.

**Strict vs. verified gaps.** PP's strict rate (56.0%) is well under its verified rate (68.1%). A lot of those verified values are the "right text, row not lined up" kind. The front-of-book strict rate (57.8% against 68.5% verified) is the same gap.

### Deep dive: bills, added up

| Piece | Calls | Amount | Inside the $1.81 |
| --- | --- | --- | --- |
| 193-page Runpod, estimate | n/a | about $0.22 | no |
| 193-page OpenRouter, first vision pass | 218 | $0.2085 | no |
| v2, one new vision call | 1 | $0.0012 | no |
| Full-run Runpod A40, billed | n/a | $0.4617 | yes |
| Full-run OpenRouter | 1,343 | $0.9543 | yes |
| v3 OpenRouter, full run | 319 | $0.3612 | yes |
| v3 OpenRouter, 193-page re-score | 19 | $0.0371 | yes |

v3's two OpenRouter lines sum to $0.3983 across 338 calls, 0 errors. $0.4617 + $0.9543 + $0.3983 = $1.81.

Before any of this, a public-page layer-3 test picked the vision model. That cost a separate **$0.88**. A 175-cell pilot of the same model was $0.009 and scored 175/175. That spend isn't in the table.

### Where the files are

They're on the bot's box, not in git:

- Full run: `/workspace/oxr-2jz/full/`. OXR output is in `oxr/`, Tesseract in `tess2/`, and v3 results in `out/v3/` (`l3_cells.json`, `counts.json`, `compare_v2_v3.json`). Page lists (wiring, picture-only, empty) are in `out/v2/page_lists.json`.
- 193-page v3 results: `/workspace/oxr-2jz/out/v3/`.
- Running summary: `/workspace/oxr-2jz/summary.md`.

### License

OXR's code and weights use the OXR Open Source License, which is Apache-2.0 plus extra terms.

Commercial use without a separate license is only allowed while funding and annual revenue are each at or below $2,000,000. An online service that uses it has to name "SoMark OXR" in the UI or the public docs.

It's fine for this project. Check the terms again before the parser goes on the hosted backend. Source and the full terms are in [#163](https://github.com/zeketx/sidekick-mechanic/issues/163).
