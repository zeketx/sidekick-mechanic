# Spec guard

Post-generation check that blocks torque values, other numbers with units, and pinouts that are not in the retrieved manual text. The truck's real specs stay out of this module. Tests use fake values such as `999 Nm`, `pin 999`, and `connector FAKE-C9`.

## Call

```python
result = guard_answer(answer, cited_chunk_texts)
```

`answer` is an object shaped like `backend/contracts/answer.schema.json`. `cited_chunk_texts` is the retrieved page text, one string per chunk. The function does not read citation snippets. A model can put an invented number in `snippet`, and that string is not evidence.

`result.answer` is either the same payload (a shallow copy) or a refusal:

```json
{
  "kind": "refusal",
  "text": "Not found in the cited manual text: 999 Nm, pin 999.",
  "reason": "not_found_in_manual"
}
```

The refusal names each missing claim. A payload that is already `kind: "refusal"` is returned with the same fields and is not scanned. Scanning it would refuse the refusal, because the text names the missing claim.

Claims must sit entirely inside one chunk. A number in one chunk and its unit in another do not count. `25` does not match `125`, and `999` does not match `999.4` or `999.0`. The guard does not convert units: `999 Nm` does not match `999 kgfm`.

## What is extracted

From answer text only:

- A number followed by a unit in the table in `backend/spec_guard.py` (torque, pressure, voltage, resistance, length, temperature, current, speed, volume, angle, percent).
- `pin`, `connector`, and `terminal` references. The id is a single letter (`pin Q`) or a token that contains a digit (`pin 999`, `connector FAKE-C9`). `pins 999 and 998` is two claims. `pin` and `connector` do not match each other.

Bare numbers with no unit are not claims. `step 3 in the manual` is not a clearance. Lowercase `a` is not amperes (`999 a bit`); capital `A`, `amp`, and `ampere` are.

## Normalization

Both the answer and each chunk go through the same steps before comparison. The executable list is `_UNIT_PATTERNS` and `_prepare` in `backend/spec_guard.py`.

Allowed:

- HTML entities decoded, then Unicode compatibility normalization (NFKC), then casefolding of the compared form.
- Whitespace collapsed, including between a number and its unit (`999   Nm` matches `999Nm`).
- `*`, `` ` ``, and `_` removed so markdown cannot hide a unit.
- Zero-width characters removed.
- Unicode minus and dashes become `-`.
- Spaces between digits removed (`9 999` matches `9999`).
- Thousands-grouping commas removed (`9,999` matches `9999`). A comma followed by one or two digits stays, so `999,5` does not match `999.5`.
- Unit spelling aliases, including `N·m` / `N-m` / `newton meters` → `nm`, `ft-lb` / `ft lb` / `ft·lbf` / `ft-lbf` / `ft·lb` → `ftlbf`, `kgf·cm` → `kgfcm`, `volts` → `v`, `ohms` / `Ω` → `ohm`. `ft·lbf` does not match `feet` or `ft`. `kgf·cm` does not match `cm` or `kgf·m`.
- Ohm signs are spelled out before casefolding so `MΩ` (megohm) does not match `mΩ` (milliohm). The refusal quotes that spelled-out form.
- The exponent marker `e` is casefolded (`9.99e2` matches `9.99E2`). The exponent text otherwise stays (`9.99e+2` does not match `9.99e2`).
- Pin ids are casefolded (`FAKE-C9` matches `fake-c9`).

Not allowed, and tested:

- Rounding or padding (`999.4` vs `999`, `999` vs `999.0`).
- A different unit (`999 mm` vs `999 m`).
- Ranges, leading minuses, and fractions as different numbers (`999-1000`, `-999`, and `9/9` do not match the bare number).
- Matching a claim as a substring of a longer number.

A repeated normalized claim is one claim. The refusal quotes the first surface in the answer.

## Eval counter

Logger name: `sidekick.spec_guard`. Each blocked answer logs one warning:

```text
spec guard blocked 2 uncited claim(s): 999 Nm, pin 999
```

`GuardResult.uncited_count` is the number of distinct missing claims on that answer, `0` when the answer is allowed through. The eval uncited-number count is the sum of those counts.

`python -m eval` passes `SpecGuardUncitedCounter` to `run_harness`. Its `count` calls `guard_answer(answer, ())` and returns `uncited_count`. The harness answer has no chunk text, so every claim still in a found answer counts. A refusal counts as zero. `run_harness` without a counter still uses the local digit counter.

`stats()` returns process totals since `reset_stats()`:

| Field | Meaning |
| --- | --- |
| `checks` | Found answers whose text was inspected |
| `failures` | Those answers replaced with a refusal |
| `uncited_claims` | Sum of `uncited_count` |

Refusals that enter the guard are not checks and are not failures. `failures` counts blocked answers. `uncited_claims` counts blocked claims. The eval metric is the claim count.

## POST /chat

`POST /chat` calls `guard_answer` on the producer payload, then `apply_safety_preamble` on the guarded payload, then contract validation. The safety note is appended after the guard, so the note is never scanned.

Chunk text comes from `CitedChunkSource.cited_chunk_texts` on the producer (`backend/producer.py`). `LlmAnswerProducer` implements that method. It returns the page text of citations that survived the snippet check, not every retrieved hit. A spec that appears only on a hit the answer did not cite is refused. With no retriever, no index file, or no surviving citations, the chunk list is empty and any spec in the answer is refused.

The guard does not retrieve pages and does not call a model.

## Residual gaps

These are not extracted. A value written only in one of these forms is not blocked:

- Numbers spelled out (`ninety-nine Nm`).
- Unit words that are not in the alias table.
- Part numbers and wire colors.
- Homoglyphs that NFKC does not fold.

A fraction, range, or scientific form that the guard does extract must still match that same form in a chunk.
