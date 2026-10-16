# Backend

Python 3.11+ and FastAPI. This is the RAG service for Sidekick Mechanic.

`POST /chat` accepts a conversation and returns a payload that validates against
[`contracts/answer.schema.json`](contracts/answer.schema.json). Answers come from
`LlmAnswerProducer`, which calls an `LLMClient`. On each request, if
`.ingest/index.sqlite` exists, the producer searches that FTS5 index and then
calls the model. The model must reply with one JSON object. Each citation has
`doc_id`, an integer `page`, and a `snippet` copied from that page. A citation
stays only when that page was in the hits and the snippet is a contiguous span
of that page. Whitespace may collapse. A rearrangement of the page's tokens is
not a quote. An empty search, a missing index file, or a JSON object with an
empty `citations` array asks for general advice (`kind: general_advice`).
The reply says the manual does not cover the question, then lists one to
five cheap checks. Related pages are a second search on the fault words,
with speed and place words left out, over a wider candidate pool than the
answer. That pool stays in search order. Only the first eight openings are
judged, one page at a time, yes or no. At most three yes pages are shown,
best first. A page is kept when that check says the opening is the same
problem. The part
that has the fault, or a part whose name says it stops that fault, still
counts when the fault word is missing. Words for how fast or where can be
missing. A different job that only shares a word is not kept. A failed
check shows no page. Related pages are not
the pages that answered. A missing index does call the model for those checks.
Engine-wiring questions (ECM, injectors, ignition coils, VVT, EFI, the 2JZ
engine harness) search `is300-engine-wiring` and cite that EWD. While
`lj78-wiring` is `blocked` in `docs/MANUALS.md`, a chassis or body wiring
question specific to the LJ78 / 70-series truck uses that same reason and
says the wiring manual is not ingested yet, even if the IS300 EWD would have
matched a fuse or relay. A generic wiring, harness, pinout, or EWD question
that matches nothing uses that same miss while `lj78-wiring` is blocked.
When that row is not blocked, the miss is general advice. Those wiring
refusals have no citations.
Non-JSON completions, citations that all fail that check, provider errors, and
a blank completion return a provider error (`kind: error`,
`reason: provider_unavailable`). That payload is not a manual answer. With no
API key, `FakeLLMClient` answers from the retrieved pages. Each
citation is `doc_id`, `page`, and a snippet copied from that page, so the
provenance check can keep it. The answer text is a local stand-in, not a model
procedure. An empty search calls the client for general advice. Related
pages search again on the fault words, ignoring how fast or where. The
first eight openings are judged one page at a time. At most three yes pages
are shown, best first. With no API key the stand-in keeps a page that names the fault
or the part that has it, and it drops a different job that only shares a
word. It ignores words for how fast or where. A failed check shows no page.
The model writes the checks, cheapest first, and names a vehicle
only when the garage summary includes one. The stand-in step starts with
`FAKE-STEP` and is not a real procedure. Do not
treat the stand-in, or an empty-citation reply, as a real procedure.

Design: [`docs/design/retrieval-index.md`](../docs/design/retrieval-index.md).

The bay map is a separate contract,
[`contracts/bay_map.schema.json`](contracts/bay_map.schema.json). `load_bay_map`
in `bay_map.py` is the Python loader. A highlight on an answer is still only
`bay_photo_id` and `part_id`. That pair is the current contract. The product
requirement is a precise outline on any still photo, including one that has
never been traced. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86)
will carry an arbitrary photo plus a mask or outline. The schema is unchanged
until then. See [`docs/design/bay-map.md`](../docs/design/bay-map.md).

## Run locally

From this directory, after installing dependencies:

```bash
uvicorn app:app --reload --host 127.0.0.1 --port 8000
```

Example request:

```bash
curl -sS http://127.0.0.1:8000/chat \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","text":"Why is it hard to start?"}]}'
```

The app may also send a compact `garage` object (truck facts, part notes, and
open to-dos). That text is added to the system prompt so the model can mention
what the owner already wrote down. It is not a manual citation. Omit `garage`
when there is nothing to send. Long notes are trimmed.

With no `SIDEKICK_LLM_API_KEY`, the default producer uses `FakeLLMClient` (no
network). After ingestion has written `.ingest/chunks.jsonl`, build the index
with `python3 retrieval.py build`. A question that matches indexed pages then
returns those pages as citations. Each snippet is an exact span of the page
text, and the answer sentence is a stand-in so `/chat` can be tried without a
key. A question that matches nothing returns general advice, unless it is
the wiring-not-ingested case above.
An engine-wiring question cites `is300-engine-wiring` when that EWD is in
the index. A chassis or body wiring question specific to the LJ78 / 70-series
truck, while `lj78-wiring` is blocked, says the wiring manual is not ingested
yet. A generic wiring question that matches nothing uses that same miss
while `lj78-wiring` is blocked, and general advice when it is not.
If the index file is missing, the reply is general advice.

Cited pages:

```bash
curl -sS -o /tmp/page.png http://127.0.0.1:8000/manuals/FAKE-DOC-2JZ/pages/999.png
curl -sS http://127.0.0.1:8000/manuals/FAKE-DOC-2JZ/pages/999/go-deeper
```

`GET /manuals/{doc_id}/pages/{page}.png` rasterizes `manuals/<id>.pdf` with
pdftoppm (1-based viewer pages, 150 DPI). `FAKE-DOC*` ids return a generated
stand-in. Only `docs/MANUALS.md` rows with status `ingest` are served.
`blocked` rows (including encrypted `lj78-wiring`), unknown ids, and missing
PDFs are HTTP 404. Tests skip the owner manuals when `manuals/` is empty.
Ingested wiring docs still return the page image. Go deeper is
`GET /manuals/{doc_id}/pages/{page}/go-deeper`. That JSON is spec-guarded
against the cited page only. Diagram pages omit test/tools instead of
guessing pinouts. Do not commit PDFs or rendered pages.

To call a real model, copy [`.env.example`](.env.example) to `.env`
(gitignored), set a key, and load it into the shell before starting uvicorn:

```bash
cp .env.example .env
# edit .env — never commit it
set -a && source .env && set +a
uvicorn app:app --reload --host 127.0.0.1 --port 8000
```

## Retrieval index

After ingestion has written `.ingest/chunks.jsonl`:

```bash
python3 retrieval.py build
python3 retrieval.py query "starter motor" --k 5
```

`build` reads `.ingest/chunks.jsonl` and replaces `.ingest/index.sqlite`. `query`
prints top-k JSON lines with `doc_id`, `page`, `rank`, `score`, and `text`. The
index stores a boosted `labels` column (headings and `NAME NO. N` components)
plus page `text`, tokenized with FTS5 `porter unicode61`. Search drops
stopwords and vehicle tokens, unions an AND pool with a broader OR pool, then reranks. Shop wording such as "tight" can surface a matching spec table. It does not pull in unrelated tables.
Tests use generated `FAKE-*` chunks, not real manuals.

Real-PDF ranking (optional, skips without `manuals/*.pdf`):

```bash
python3 -m eval.retrieval_real
```

That scores `eval/fixtures/retrieval-real.jsonl` for hit@1 and hit@3. CI does
not have the PDFs, so the eval exits 0 with a skip line.

## Tests

```bash
pip install -r requirements.txt
pytest
```

Linux CI (#3) runs the same `pytest` from `backend/`. Tests never make network
calls: the fake client is in-process, and the OpenAI-compatible client is driven
with `httpx.MockTransport`.

## Eval

From the repository root:

```bash
make eval
```

That runs `golden.jsonl` when the file exists, otherwise
[`eval/golden.sample.jsonl`](eval/golden.sample.jsonl), through in-process
`POST /chat` with `FakeLLMClient`. It writes `eval/results/<UTC date>.json`
and regenerates [`docs/METRICS.md`](../docs/METRICS.md). `make metrics`
rebuilds the doc from the latest results file without re-running questions.

To score the same file against a backend that is already running:

```bash
cd backend && python3 -m eval --backend http://127.0.0.1:8001
```

That posts each question to `{backend}/chat` with the request header
`X-Sidekick-Eval: retrieval`. Citation accuracy comes from the answer.
Refusal correctness counts a contract refusal, and also general advice whose
honesty line says the manual does not cover the question. A found answer
that cites a page does not count. Related pages on that advice are not
citations. When the backend sends `X-Sidekick-Retrieval`, recall@5 uses
those doc id and page pairs. The header is absent on a normal client, and
the answer body stays the contract. The header value is not written to the
results file. A user or key in the URL is not sent and is not written to
the results file. The timeout is 120 seconds. `make eval` does not pass
`--backend`, so CI still uses the fake model.

The sample set is fake (`FAKE-*` document ids, page 999) so the harness and CI
have rows before the real golden set exists. Do not put real manual pages in
the sample. The golden-set issue owns `eval/golden.jsonl`.
See [`eval/GOLDEN.md`](eval/GOLDEN.md) for the fields and the note that the manual PDFs live outside git.

Each JSONL row matches [`eval/golden.schema.json`](eval/golden.schema.json):
`id`, `question`, `answerable`, `expected` (`doc_id` and `page`), optional
bay-map `part_id`, and optional `ci`. Answerable rows need at least one
expected page. `ci: true` marks the fast subset.

CI runs that subset and writes the table to the Actions job summary. The
workflow token stays `contents: read`, so the check does not post a PR comment.

Recall@5 stays null until a runner supplies retrieval hits. The default runner
does not, and cited pages are not treated as hits. `python -m eval` passes
`SpecGuardUncitedCounter` to `run_harness(..., uncited_counter=...)`, so the
uncited-number total uses the spec guard. `run_harness` without a counter
still uses `LocalUncitedNumberCounter`.

Highlight metrics use the bay map and a held-out hand-label file. A part is
mapped when it has a confirmed region. Correct-part rate is the fraction of
golden questions whose `part_id` is mapped and whose answer highlight names
that part. Region IoU is the mean intersection-over-union of each hand label
against the confirmed polygons the highlight renderer draws for that photo
and part. It does not depend on which questions ran. `python -m eval` exits
1 when any answer highlights a part that is not mapped. The results file
still records that count.

That is the current harness. It still scores confirmed bay-map polygons.
Hand labels stay the answer key. The living targets are the proposed ones in
[VISION.md](../VISION.md), pending Zeke's confirmation after
[issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85). They
replace correct-part ≥ 0.90 and region IoU ≥ 0.80.
[Issue #88](https://github.com/zeketx/sidekick-mechanic/issues/88) is the
acceptance eval for highlights on photos that were never traced.
[`docs/METRICS.md`](../docs/METRICS.md) is generated from this harness. Do not
hand-edit it to paste the proposed targets.

Until `eval/hand_labels.json` and `eval/bay_map.json` exist, the run uses
[`eval/fixtures/fake-hand-labels.json`](eval/fixtures/fake-hand-labels.json)
and
[`contracts/fixtures/bay-map/fake-bay-map.json`](contracts/fixtures/bay-map/fake-bay-map.json).
Those polygons are `fake-*` fixtures, not truck parts. The fixture label
covers half of the confirmed `fake-part-intake` triangle on
`fake-bay-photo-wide`, so that synthetic IoU is 0.5. Rings must be convex.
A concave ring fails the run instead of publishing a wrong IoU.

## Wiring-diagram spike

Separate from ingestion and from the eval harness. It needs the system
packages `tesseract-ocr`, `poppler-utils`, and `fonts-dejavu-core`. From this
directory:

```bash
python3 spikes/wiring_spike.py --output eval/results/wiring-spike.json
```

The written result is [docs/design/wiring-diagram-spike.md](../docs/design/wiring-diagram-spike.md).
`eval/results/wiring-spike.json` has no `generated_at`, so `make metrics` keeps
the dated harness file. The script is not part of ingestion.

## Prototype bay photos

Public stand-ins for the highlight engine, before the truck arrives. They are
not the owner's truck and they are replaced in M5. The manifest is
[`data/prototype_bay_photos.json`](data/prototype_bay_photos.json). It records
the source URL, author, license, and attribution for each file, and groups
files by the five angle ids in [`docs/vehicle/DAY_ONE.md`](../docs/vehicle/DAY_ONE.md).

The image files are not in git. From this directory:

```bash
python3 prototype_photos.py validate
python3 prototype_photos.py fetch
```

`fetch` writes `bay-photos/prototype/` at the repo root (gitignored) and checks
each file's SHA-256. A photo is accepted only when its license is CC0, CC BY,
or CC BY-SA and the source's own words name a 2JZ-GE. The committed set is
short of 10 photos. The `gaps` object says what is missing and what was left out.

## Highlight style

`HighlightConfig` in [`highlight.py`](highlight.py) is the bakeoff default: an 8 px fuchsia outline, saturation 3.0, and dim factor 1.0. The comparison is [docs/design/highlight-style-bakeoff.md](../docs/design/highlight-style-bakeoff.md).

## Bay map labels

Label Studio draws the regions. `bay_map_labels.py` turns a JSON export into
a bay map that `load_bay_map` accepts. Owner photos stay in gitignored
`bay-photos/day-one/`. Prototype stand-ins stay in `bay-photos/prototype/`.
The steps, the manifest, and the COCO and YOLO export path for a later
detector are in [`docs/BAY_MAP.md`](../docs/BAY_MAP.md).

```bash
python3 bay_map_labels.py \
  --export /path/to/label-studio.json \
  --manifest /path/to/manifest.json \
  --output /path/to/bay-map.json
```

The committed fixtures under `tests/fixtures/` use `FAKE-*` labels. The script
does not train a detector.

## Stack

| Piece | Choice |
| --- | --- |
| Language | Python 3.11+ |
| HTTP | FastAPI |
| Server | uvicorn |
| Answer contract | `jsonschema` against `contracts/answer.schema.json` |
| Bay map | `jsonschema` plus `bay_map.py` against `contracts/bay_map.schema.json` |
| Labels | Label Studio JSON via `bay_map_labels.py` |
| LLM | OpenAI-compatible `POST /chat/completions` over `httpx`, behind `LLMClient` |
| Tests | pytest + FastAPI `TestClient` |
| Retrieval | SQLite FTS5 (stdlib `sqlite3`), see `retrieval.py` |
| Manual pages | `GET /manuals/{doc_id}/pages/{page}.png` via pdftoppm for `ingest` rows; Go deeper JSON |
| Highlight | Pillow renderer in `highlight.py` |

## Request shape

The body is a conversation:

```json
{
  "messages": [
    {"role": "user", "text": "Why is it hard to start?"}
  ]
}
```

`role` is `user` or `assistant`. `text` must be non-empty. Extra properties are
rejected. Invalid bodies return HTTP 422.

The response is an answer, general advice, or a refusal as defined by the
shared contract. The
app must not invent vehicle facts; fixture citations use `page: 999` and
`FAKE-*` values.

## Spec guard

`spec_guard.guard_answer(answer, cited_chunk_texts)` runs on the producer
payload before the safety note is applied, so the note is never scanned.
It extracts numbers with units and pin, connector, and terminal references.
On a found answer, each one must appear in a cited chunk. On general advice,
each step is scanned on its own and chunk text is not evidence. Otherwise
the payload is replaced with a `not_found_in_manual` refusal that names the
missing claims.
Normalization is specified in
[`docs/design/spec-guard.md`](../docs/design/spec-guard.md).

Citation snippets are not evidence. `POST /chat` passes chunk text from
`CitedChunkSource.cited_chunk_texts` when the producer implements it, and
passes no chunks otherwise. With no chunks, any spec in the answer is refused.
`LlmAnswerProducer` implements that protocol. `cited_chunk_texts` returns the
page text of citations that survived, from the same search as the answer.
The search query is every user message in the conversation, not only the last
one. With no index file, no hits, or no surviving citations, it returns no
chunks.

Failures log a warning on the `sidekick.spec_guard` logger.
`SpecGuardUncitedCounter` (`name` is `spec_guard`) is the harness hook: its
`count` is `guard_answer(answer, ()).uncited_count`. The harness has no chunk
text, so every claim still in a found answer counts, and a refusal counts as
zero. `stats()` is the process total since `reset_stats()`.

## Safety preamble

`POST /chat` runs `apply_safety_preamble` (`safety.py`) on the guarded
payload, before schema validation. Procedure answers start with `SAFETY_NOTE`.
That constant is the only copy of the wording; the owner reviews it there.
The answer contract is unchanged: the note is part of `text`.

The detection rule lives on `is_procedure_answer` in `safety.py`. Refusals
never receive the note. Eval cases are in
`eval/fixtures/safety_preamble.json`.

## LLM adapter

`LLMClient.complete(messages)` returns text plus optional token usage.
`FakeLLMClient` is the test double and the default when no API key is set.
Tests pass `text=` to force a completion. With no `text`, a prompt that
includes retrieved pages becomes citation JSON (`doc_id`, `page`, `snippet`)
built from those pages. Any other prompt returns prose with no citations.
`OpenAICompatibleClient` is the live provider (OpenAI or any host that speaks
the same `/v1/chat/completions` API).

`LlmAnswerProducer` implements `AnswerProducer`. `/chat` stays the HTTP
boundary. Provider failures (timeouts, exhausted retries, empty completions)
return HTTP 200 with `kind: error` and `reason: provider_unavailable`.
That is not a found answer. Token usage and latency are logged on logger
`sidekick.llm`. A provider failure also logs `kind` (`timeout`,
`rate_limit`, `http_status`, `transport`, or `parse`), the HTTP status when
there is one, and a redacted detail. When the body has an `error` message,
that text is part of the detail. The API key, `Authorization` header, and
response body are not logged. A completion body that is not valid
provider JSON, including empty content, is retried inside the same attempt
budget as a timeout. A model reply that is not the expected answer JSON is
logged as `kind=parse` with a fixed detail (`grounded_json`, `advice_steps`,
`citation_mismatch`, or `empty_completion`) and is not sent again. A second
full completion could run past the phone's 120 second budget.

Environment variables (see `.env.example`):

| Variable | Default | Purpose |
| --- | --- | --- |
| `SIDEKICK_LLM_API_KEY` | empty (fake client) | Secret. Read from the environment only. |
| `SIDEKICK_LLM_BASE_URL` | `https://api.openai.com/v1` | Provider base URL, including `/v1` |
| `SIDEKICK_LLM_MODEL` | `gpt-4o-mini` | Answer-provider model id. Not a pstack or poteto agent slug. |
| `SIDEKICK_LLM_TIMEOUT_SECONDS` | `30` | Per-attempt HTTP timeout |
| `SIDEKICK_LLM_MAX_RETRIES` | `2` | Retries after the first attempt on timeout, transport errors, 429, 5xx, and an unreadable completion body |

`FixtureAnswerProducer` remains for tests that need a committed contract fixture.

## Part resolver

`part_resolver.resolve_answer` sets the answer contract's optional `highlight`
from a model selection, or leaves the highlight off. This is the merged
behavior from
[issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32). It only
highlights a confirmed bay-map region. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86)
and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33) rework
that path so a photo with no trace can still carry a precise outline. Do not
change the schema in the meantime.

The model must return `{"part_id": "<id>"}` or `{"part_id": null}`. The id
has to be one of `BayMapView.part_ids()`. `as_bay_map_view` builds that view
from [`contracts/bay_map.schema.json`](contracts/bay_map.schema.json). The view
carries part id, photo id, angle id, pixel area, and whether the region is
confirmed. Polygons, image size, names, aliases, license, and source stay on
the bay map. See [`docs/design/part-resolver.md`](../docs/design/part-resolver.md).

Null, or an output that does not name exactly one listed id, leaves the
answer text alone and sets no highlight. An id outside the closed list, or a
listed part with no confirmed region of area greater than zero, also sets no
highlight and appends `This part is not mapped yet.`

The highlight photo is the confirmed region with the largest `area_px`.
Equal areas break ties by `bay_photo_id`, then `angle_id`.

`LlmAnswerProducer` asks for a part id only when it is constructed with a
non-empty `BayMapView`. The default producer has no bay map, so `/chat` does
not highlight until a map is supplied. A failed selection call leaves the
answer without a highlight.

## Demo mode

Optional playground for chat-to-highlight UX before the owner's bay photos
exist. Catalog: [`data/demo/`](data/demo/). Attribution:
[`data/demo/ATTRIBUTION.md`](data/demo/ATTRIBUTION.md). The Hilux photo is
CC BY-SA 3.0 (share-alike). Polygons and `demo_state` are scripted, not
measured. Same `SIDEKICK_LLM_*` config as the normal path. No keys in git.

Send `demo: {"photo_id": "<id>"}` on `POST /chat`. The producer still calls
the model (with the confirmed LJ78 / 2JZ-GE swap as context; VVT-i is TBD).
The part is resolved from the **user's question**, constrained to that
photo's part list — not from the reply wording. The highlight follows that
part's `demo_state`, and the answer text agrees with that state:

| State | Wire |
| --- | --- |
| outline | `highlight` with `display: outline`, `geometry.polygons`, `demo: true` |
| confirm | same, `display: confirm` (softer "Is this it?" in the app) |
| not found, or a part not on that photo | no `highlight`; text points at a placeholder manual diagram |

Omit `demo` and the normal path is unchanged. Old `{bay_photo_id, part_id}`
highlights still validate. `GET /demo/photos`, `GET /demo/photos/{id}/image`,
`GET /demo/attribution`, and `POST /demo/feedback` (`yes` / `not_this`) are
demo-only. Proofs: `python3 render_demo_proofs.py`.

## Highlight renderer

`highlight.render_highlight(photo, polygon, style)` returns a new RGB image.
`style` is a `HighlightStyle`: `outline`, `saturate`, `circle`, or `dim`.
Widths, colors, and factors live on one `HighlightConfig`.

The polygon is `(x, y)` pixels of the photo, origin top left. Callers pass
the points. The product highlight is that precise outline, never a bounding
box. The bay map schema (#26) still owns how traced regions are stored.
`part_resolver.BayMapView` carries photo and part ids. Pass the polygon into
`render_highlight` directly.

Golden images live in `tests/fixtures/highlight/`. Tests compare them with
`GOLDEN_PIXEL_TOLERANCE` (max per-channel absolute difference). Those tests
draw a synthetic photo, so they stay deterministic without the prototype bay
photo files. A 4000×3000 render of each style is asserted to finish in under
one second.
