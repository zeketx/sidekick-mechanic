# Golden question set (`golden.jsonl`)

Issue #23. Owner approval pending. The eval harness (`python3 -m eval`) loads `eval/golden.jsonl` when it exists, otherwise `eval/golden.sample.jsonl`. CI still runs `golden.sample.jsonl` (`python -m eval --golden eval/golden.sample.jsonl --ci` in the eval-subset job). This file does not change that CI command.

A separate, smaller retrieval-only set lives in [`fixtures/retrieval-real.jsonl`](fixtures/retrieval-real.jsonl). `python3 -m eval.retrieval_real` scores hit@1 and hit@3 against the FTS index. It skips when `manuals/2jz-ge-rm.pdf` or `manuals/is300-engine-wiring.pdf` is absent, so CI stays green without the PDFs. Expected pages in that fixture were read from `pdftotext`. The fixture does not store spec values.

## Row format

One JSON object per line, validated by [`golden.schema.json`](golden.schema.json) (unchanged).

| Field | Meaning |
| --- | --- |
| `id` | Stable, unique slug. |
| `question` | What the owner would type into the chat. |
| `answerable` | `true` if an ingest manual holds the answer. `false` means the correct output is a contract refusal because those manuals do not have the fact. |
| `expected` | `{doc_id, page}` pairs that hold the answer. Empty when `answerable` is `false`. |
| `part_id` | Optional bay-map part the answer is about (feeds M3 / #40). |
| `ci` | `true` puts the row in the `--ci` subset. |

No answer values are stored here. The answer is whatever is printed on the cited page. That keeps manual text and specs out of git.

## Pages

`page` is the 1-based PDF page index, as a PDF viewer shows it and as `ingest.py` numbers chunks (`enumerate(reader.pages, start=1)`). It is **not** the printed section page (for example `SS-17` or `A-32`).

The answerable pages are the previous file's `2jz-ge-rm` pages. They were not re-read against `chunks.jsonl` here because that file is not on disk. `python3 -m eval.golden_gate` exits 2 until chunks exist. A structural screen is not a page check.

`screen_questions` is the structural check. It reads the manifest and the question file. It does not read chunks and it does not open `manuals/`. Page text is checked only by `python3 -m eval.golden_gate` when `backend/.ingest/chunks.jsonl` exists. A missing chunk file skips that check and does not bless the pages.

## Document IDs

Doc identity, status, page count, and SHA-256 stay in `docs/MANUALS.md` only. Every answerable citation in this file is `2jz-ge-rm`. `is300-engine-wiring` is also an ingest manual and is not cited here. A row for it waits until `python3 -m eval.golden_gate` admits the page from chunk text. This change does not copy pages from the retrieval fixture.

## Bay-map part IDs (provisional)

No real bay map exists yet (#40). `part_id` values are `PROVISIONAL_PART_IDS` in [`golden_gate.py`](golden_gate.py). #40 should use those ids when it labels the photos, or change them there. This file does not keep a second list.

## Counts

50 questions, 26 answerable, 24 unanswerable, 17 with a `part_id`, 10 with `ci` true.
