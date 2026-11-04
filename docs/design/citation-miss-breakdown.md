# Golden citation misses

Issue #155. This page is the diagnosis for the golden-set citation score. It does not change retrieval, ingest, or the answer pipeline.

The decision it supports is which fix to try first. The M6 bar is citation accuracy of at least 0.85 on the 23 answerable questions, which is at least 20 of 23, with no new invented vehicle fact and no loss of a correct answer.

## What was measured

Two commands are documented in `backend/README.md`. Both were run from this checkout of `main` (`0a40312`). The retrieval and answer code on that commit is the same code as `d25969f`, the commit named in issue #155. Commits after `d25969f` are the README, the license, user stories, and `docs/oxr-manual-extraction.md`.

### Command that runs here

```bash
make eval
```

That is `cd backend && python3 -m eval --metrics`. It scores `backend/eval/golden.jsonl` (50 questions, 23 answerable) through `InProcessChatRunner`, which uses `FakeLLMClient` and does not read an index. This session's run printed `Smoke test: retrieval did not run. Exit 0 is not a quality result.` and these values.

| Metric | This run |
| --- | --- |
| citation accuracy | 0.000000 |
| refusal correctness | 0.000000 |
| recall@5 | not available |
| runner | `inprocess_chat_fake_llm` |

Those zeros are the fake model. They are not the manual baseline. The results file and `docs/METRICS.md` from this smoke run were restored and are not part of the change.

### Command that needs the manual

```bash
cd backend && python3 -m eval --backend http://127.0.0.1:8001
```

This session ran that client against `http://127.0.0.1:8001` with `--timeout 5` and an output directory outside the repo. It failed immediately with `eval failed: POST /chat failed`. Nothing was listening. `SIDEKICK_LLM_API_KEY` is unset. `backend/.ingest` is absent, so there is no `chunks.jsonl` and no FTS index. The manuals are gitignored and are not on this machine. The Railway account signed in here has no Sidekick service to call instead.

There is no committed results file for a live golden run. The #152 agent transcript does not contain a 0.609 run. The recorded live numbers are the owner's Mac run written in issue #155, at commit `d25969f`.

### Recorded live baseline

Issue #155 states one Mac run of `python -m eval --backend`.

| Metric | Recorded value | Count |
| --- | --- | --- |
| citation accuracy | 0.609 | 14 of 23 answerable |
| recall@5 | 0.717 | see the check below |
| refusal correctness | 0.926 | matches 25 of 27 unanswerable |
| uncited-number count | 59 | harness counter, empty chunk list |

The harness has no answer-correctness metric. It does not score whether the sentence is right. It scores whether every cited `(doc_id, page)` is in the question's expected set. A correct sentence with an extra page scores 0. A refusal of an answerable question scores 0. Refusal correctness is a different denominator, the 27 unanswerable questions.

`citation_is_accurate` is a fraction over the 23 answerable rows. `round(14 / 23, 6)` is 0.608696. The issue prints 0.609. Same count, three-decimal rounding. One run only. The same Mac notes say the squeal answer flips between a citation and general advice, so a second run can move a borderline row by one question, which is about 0.043 on this set.

Recall is the mean, over the 23, of how many expected pages appear in the first 5 lexical hits. Every expected set here has one page or two, so each question contributes 0, 0.5, or 1. A mean of 0.717 is what you get from a recall sum of 16.5. 16.5 divided by 23 is 0.717391. The nine citation misses below account for 4.0 of the 6.5 points missing from a perfect 23. The other 2.5 points sit on questions that still passed citation accuracy. A missing sibling page does not fail the citation score when the cited page is expected.

The uncited-number count of 59 is `SpecGuardUncitedCounter`. The harness calls `guard_answer` with an empty chunk list, and citation snippets are not evidence. A found answer's measurements count even when the live guard allowed them. A refusal counts as 0. The rising series in the issue (47, then 53, then 59) follows more found answers, which is what the #153 notes already described.

`ps-pump-bolt-torque` and `alternator-bolt-torque` are the two refusal misses inside the 0.926. They are unanswerable rows. They are outside the 9. The duplicate squeal chip on page 1234 is not a golden row.

## How a miss is scored

The results row in `backend/eval/harness.py` still stores a boolean and a recall fraction. The trace file stores the cited pages, the lexical top 5 with scores, and the spec-guard decision. The live client reads that top 5 from the `X-Sidekick-Retrieval` header. `searched_pages` fills the header from the lexical search, before `judge_pages` drops anything, and appends the score search already computed. Issue #155 is a summary of an earlier run of that header. It does not list the other hits, and it does not list the cited page except where it says a question was refused.

A row in the table below is one bucket.

- **(a) Retrieval miss.** Every expected page is outside the top 5.
- **(b) Citation selection.** At least one expected page is in the top 5, and the score is still 0. The score is 0 when the answer is a refusal, when the citation list is empty, or when any cited page is outside the expected set. `citation_is_accurate` accepts a non-empty subset of the expected pages. It does not require both pages of a pair.
- **(c) Corpus gap.** The expected page is not in the ingested chunks. `backend/eval/GOLDEN.md` records that `python3 -m eval.golden_gate` admitted these pages from `chunks.jsonl` on the Mac. The plain text of page 153 names the oil-control-valve row. Page 159 names the throttle-body bracket. Page 152 is the SFI page for the fuel pump, the injector, and the MAF meter. None of the nine is a missing page.

## The nine misses

Expected pages are from `backend/eval/golden.jsonl` in this checkout. They match the pages in issue #155. "Not recorded" means the issue does not contain that field for the `d25969f` run. Mac notes at `3a3682d` and `46dcbaa` are an older tree. They are not used as this run's cited pages. The oil-drain row names the earlier refusal because the `d25969f` note does not.

| Question | Expected pages | Cited page | Retrieved top 5 | Bucket | Reason |
| --- | --- | --- | --- | --- | --- |
| `vvti-ocv-bolt-torque` | 153 | not recorded | 153 absent. The other hits were not written down. | (a) | The issue says this spec page was never in the top 5. |
| `fuel-pressure-spec` | 152 | not recorded | 152 absent. The other hits were not written down. | (a) | The issue says this spec page was never in the top 5. |
| `maf-tha-resistance` | 152 | not recorded | 152 absent. The other hits were not written down. | (a) | The issue says this spec page was never in the top 5. |
| `spark-plug-torque` | 159, 985 | none. The issue says the answer was refused. | One of 159 or 985 was in the top 5. Which one, and the other hits, were not written down. | (b) | One expected page was retrieved. A refusal has no citation, so the score is 0. The missing sibling page would not fail the score by itself. |
| `cam-pulley-bolt-torque` | 766, 149 | not recorded | One of 766 or 149 was in the top 5. The rest were not written down. | (b) | One expected page was retrieved and the citation score still failed, so the citation list was empty or contained a page outside that pair. |
| `valve-clearance-cold` | 146 | not recorded | 146 was in the top 5. The other hits were not written down. | (b) | The issue says the page was found and the score was still wrong, from an extra page or a blocked number. |
| `oil-drain-plug-torque` | 157 | not recorded | 157 was in the top 5. The other hits were not written down. | (b) | Same group. At `46dcbaa` this question was a refusal. The `d25969f` note does not repeat that. |
| `throttle-body-bracket-torque` | 159 | not recorded | 159 was in the top 5. The other hits were not written down. | (b) | Same group. The page is the one the golden gate says is the torque table. |
| `cam-sensor-resistance` | 158 | not recorded | 158 was in the top 5. The other hits were not written down. | (b) | Same group. The page was retrieved and the citation score still failed. |

## Bucket counts

| Bucket | Misses | Questions |
| --- | --- | --- |
| (b) Citation selection | 6 | `spark-plug-torque`, `cam-pulley-bolt-torque`, `valve-clearance-cold`, `oil-drain-plug-torque`, `throttle-body-bracket-torque`, `cam-sensor-resistance` |
| (a) Retrieval miss | 3 | `vvti-ocv-bolt-torque`, `fuel-pressure-spec`, `maf-tha-resistance` |
| (c) Corpus gap | 0 | none |

Bucket (b) is the largest. Six of the nine misses already have an expected page in the lexical top 5.

## The fix to try

The smallest fix for bucket (b) is in citation selection, in `LlmAnswerProducer.produce`.

Three functions sit between the lexical top 5 and the score, and any one of them produces a 0.

1. `judge_pages` can drop a hit before the model sees it. Recall still counts the lexical page, because `searched_pages` runs before that filter.
2. `supporting_page_mask` returns `None` when the answer states no extracted claim, or when no cited page contains one. The caller then keeps every citation. An extra page outside the expected set fails the score. If the filter later removes every citation, `produce` returns unavailable, which also scores 0.
3. `guard_answer` replaces the answer with a refusal when the stated claim is not in the cited page text. A refusal scores 0.

#153 already shipped the extra-page drop and the unit normalization (split decimals, range endpoints, `N·m` table rows). These six questions are still misses on the commit that contains that fix. Another pass on the same string rules assumes the premise those changes already tested.

The change to make is narrow. When one retrieved page contains a claim the answer states, cite that page and drop the neighbor. When that filter would remove every citation, keep a page `_lexical_support` has already marked yes, and leave `guard_answer` in place. The guard still refuses a claim that page text does not contain.

**Expected gain.** Clearing all 6 moves the score from 14 of 23 to 20 of 23. `round(20 / 23, 6)` is 0.869565, which clears 0.85. Clearing none of them leaves 0.609. The issue's own words for the four single-page rows are "wrong or extra page cited, or the number blocked." Those are different functions. The gain is the whole range, 0 to 6, until one Mac run prints, per question, the lexical top 5, the pages `judge_pages` kept, the cited pages, and whether `guard_answer` replaced the answer. The harness does not store those fields today.

**Risk to a correct answer.** The guard stays the authority on the number. This change does not add a vehicle fact. The risk that already showed up is the other direction. At `46dcbaa`, dropping citations to remove an extra page turned `spark-plug-torque` and `oil-drain-plug-torque` into refusals. A refusal still scores 0, and the owner loses the answer. Keeping the page that contains the claim, instead of refusing the turn, is what protects the answer. If the number the model wrote lives only on the neighbor, the guard will refuse once that neighbor is dropped. That case should stay a refusal. It should not become a citation of a page that lacks the number.

### Runner-up

Put the OXR verified values into the search index, which is step 1 of `docs/oxr-manual-extraction.md`. Only `VERIFIED` would be served. `FLAGGED` and `RAW` stay out. The spec guard still has the last word.

That is the right patch if the trace shows `guard_answer` blocking a number because the pypdf chunk scrambled the table row. It is an ingest change, larger than the citation filter. It does not create the nine pages. They are already in the chunks the golden gate admitted, so step 1 does not cover a bucket (c) hole. Bucket (c) is empty. Step 1 can still change the text the guard compares, on pages that are already retrieved.

A further ranking change for the three bucket (a) pages has a lower ceiling. Three more hits is 17 of 23, and `round(17 / 23, 6)` is 0.739130, under 0.85. #153 already added phrase and anchor fetches aimed at those queries, and issue #155 says pages 152 and 153 are still outside the top 5. The earlier ranking loosen also cited an off-topic page for an unanswerable question and dropped refusal correctness from 0.926 to 0.889 until it was tightened. Ranking is the second fix, after the six selection misses are split by the trace.

## Run the traced eval on the Mac

The index and the model key stay on the Mac. This checkout has neither. Build them, start the server from this branch, then run the harness against it. The same command is the before run and the after run. Only the trace label changes.

From `backend/`, with `manuals/` holding the PDFs named in `docs/MANUALS.md`:

```bash
python3 ingest.py
python3 retrieval.py build
```

`ingest.py` writes `backend/.ingest/chunks.jsonl`. `retrieval.py build` writes `backend/.ingest/index.sqlite`. Both paths are gitignored.

Put the key in `backend/.env` (gitignored). Load it into the server process by name. Do not print the value.

```bash
set -a && source .env && set +a
uvicorn app:app --host 127.0.0.1 --port 8001
```

The names the server reads are `SIDEKICK_LLM_API_KEY`, and optionally `SIDEKICK_LLM_BASE_URL`, `SIDEKICK_LLM_MODEL`, `SIDEKICK_LLM_TIMEOUT_SECONDS`, and `SIDEKICK_LLM_MAX_RETRIES`.

In a second shell, from `backend/`:

```bash
python3 -m eval --backend http://127.0.0.1:8001 --timeout 180 --trace-label before
```

That writes `backend/eval/traces/before.json`. Each question stores `answer_text` and `refused`, plus the cited pages, the top 5 with scores, and the guard decision. A later fix run uses `--trace-label after` and the same flag set, so both files come from this harness. `--trace PATH` replaces the default path. With neither flag the file is `backend/eval/traces/<UTC date>.json`.

After a row gains `label_status`, `expected_value`, and `unit`, recompute `value_match` from the saved answers. This does not call the model.

```bash
python3 -m eval --rescore eval/traces/before.json
```

`--golden PATH` selects a different label file. The default is `golden.jsonl` when that file exists. Only rows with `label_status` `ok` and a non-empty `expected_value` are scored. `needs_review`, a missing status, and an empty value stay out. `source_page` and `source_quote` are stored on the row and are not scored. A refusal on a scored row is a miss and adds to `refused count`.

`golden.jsonl` does not label those fields yet, so a rescore of today's trace reports `value_match` as not available and excludes every question. Do not fill a real value from memory. A test value stays fake, such as `999` with unit `Nm`.

## Bucket (b) split

This table is empty until `backend/eval/traces/before.json` exists. One row per bucket (b) question from the miss table above. The split is one of three values.

- `neighbor` when an expected page is in `top5`, `guard.decision` is `allowed`, and `cited_pages` also contains a page outside the expected set.
- `guard` when `guard.decision` is `blocked`.
- `other` for every remaining shape, including a refusal that is not a spec-guard block.

| Question | Split | Evidence from the trace |
| --- | --- | --- |
| | | |

## Where this lives

- Questions and expected pages: `backend/eval/golden.jsonl`, described in `backend/eval/GOLDEN.md`.
- Score: `citation_is_accurate`, `recall_at_5`, and `value_match` in `backend/eval/metrics.py` and `backend/eval/value_match.py`. The trace writer is `backend/eval/trace.py`.
- Lexical top 5: `Fts5Index.search` in `backend/retrieval.py`, exposed on the eval header by `searched_pages`.
- Selection and the guard: `judge_pages` in `backend/general_advice.py`, `_citations_that_support` and `produce` in `backend/producer.py`, `guard_answer` in `backend/spec_guard.py`.

## What this leaves out

Wiring and EWD, issue #139, and Phase 2. No pipeline code in this change. The next implementation still needs one live `python -m eval --backend` on a machine that has the index, and it needs the per-question trace above before anyone calls the citation gain a win.
