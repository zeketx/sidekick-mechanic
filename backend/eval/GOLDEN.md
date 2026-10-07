# Golden question set (`golden.jsonl`)

Issue #23. Owner approval pending. The eval harness (`python3 -m eval`) loads `eval/golden.jsonl` when it exists, otherwise `eval/golden.sample.jsonl`. CI's eval subset still runs the fake sample, so this file does not change CI.

A separate, smaller retrieval-only set lives in [`fixtures/retrieval-real.jsonl`](fixtures/retrieval-real.jsonl). `python3 -m eval.retrieval_real` scores hit@1 and hit@3 against the FTS index. It skips when `manuals/2jz-ge-rm.pdf` or `manuals/is300-engine-wiring.pdf` is absent, so CI stays green without the PDFs. Expected pages were read from `pdftotext`; the fixture does not store spec values.

## Row format

One JSON object per line, validated by [`golden.schema.json`](golden.schema.json) (unchanged by this PR).

| Field | Meaning |
| --- | --- |
| `id` | Stable, unique slug. |
| `question` | What the owner would type into the chat. |
| `answerable` | `true` if the manuals hold the answer. `false` means the correct output is a contract refusal (the manuals do not have it, or only IS300 data exists for an LJ78-swap-specific question). |
| `expected` | `{doc_id, page}` pairs that hold the answer. Empty when `answerable` is `false`. |
| `part_id` | Optional bay-map part the answer is about (feeds M3 / #40). |
| `ci` | `true` puts the row in the `--ci` subset. |

No answer values are stored here. The answer is whatever is printed on the cited page. That keeps manual text and specs out of git.

## Pages

`page` is the 1-based PDF page index, as a PDF viewer shows it and as `ingest.py` numbers chunks (`enumerate(reader.pages, start=1)`). It is **not** the printed section page (for example `SS-17` or `A-32`).

Every expected page was checked by finding the answer on that page in a local text extraction: `pdftotext -layout` for text PDFs, and `tesseract` 5 OCR for the scanned RM183E and EWD117F.

## Document IDs

The manual PDFs are copyrighted and stay outside git (`manuals/` is gitignored). The owner keeps them on the eval box. `docs/MANUALS.md` lists `2jz-ge-rm`, `is300-engine-wiring`, and `lj78-wiring`. This set also uses three other IDs. Before ingestion can use them, they each need a row in `docs/MANUALS.md`. A `blocked` row may be missing on disk; an `ingest` row still fails if its PDF is missing.

| ID | File the owner has | PDF pages | SHA-256 |
| --- | --- | --- | --- |
| `2jz-ge-rm` | 2004 Lexus IS300 repair manual RM1054U (2JZ-GE VVT-i) | 1959 | `4464676a7fda45ada554909dc875ce12c4554f96d45c9ef400788e5e20d6008d` |
| `lj78-wiring` | Land Cruiser 70 EWD117F (Dec 1990, LJ7x) | 84 | `eff462ba654ae488df12dbacb040771dba20d4f12eb8e5926024e8f03f632851` |
| `lc70-chassis-rm` (new) | Land Cruiser 70 chassis & body RM183E (1990, scanned) | 1024 | `87bfe6af06cfd8094954616bbe8bb1b26c1732227ece05c7b487149a20a4497e` |
| `a340f-a343f-rm` (new) | A340F/A343F overhaul extract RM479U | 121 | `af7fd90e8755634f5c9c929fa8180c4d89548d1675e36f5319384536c39a9ced` |
| `is300-ecu-pinout` (new) | IS300 2002–2005 ECU pinout (bee-mfg, third party) | 5 | `a1f06f25dcce0b4342ce32b431b19596e76ef7d887d5b4b52ab8d668a65eff72` |

Hashes and page counts come from the files on the owner's eval box (`sha256sum`, `pdfinfo`).

## Bay-map part IDs (provisional)

No real bay map exists yet (#40). These `part_id` values follow the `docs/BAY_MAP.md` rule (a short lowercase id, not a catalog number). #40 should use the same ids when it labels the photos, or rename them here:

`alternator`, `brake-master-cylinder`, `camshaft-position-sensor`, `ect-sensor`, `ignition-coil`, `maf-meter`, `oil-control-valve`, `power-steering-pump`, `radiator-cap`, `starter-relay`, `thermostat`, `throttle-body`, `timing-belt-cover`.

## Counts

52 questions: 40 answerable, 12 unanswerable (refusal expected), 15 with a `part_id` (13 distinct parts), 13 in the CI subset. The transmission is unknown (R151F or A343F), so both get a few questions.
