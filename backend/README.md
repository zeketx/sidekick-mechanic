# Backend

Python 3.11+ and FastAPI. This is the RAG service for Sidekick Mechanic.

`POST /chat` accepts a conversation and returns a payload that validates against
[`contracts/answer.schema.json`](contracts/answer.schema.json). Answers come from
`LlmAnswerProducer`, which calls an `LLMClient`. Retrieval (#19) is a SQLite FTS5
index over ingest chunks, but it is not wired into `/chat` yet, so replies have
empty citations and must not be treated as a real procedure.

Design: [`docs/design/retrieval-index.md`](../docs/design/retrieval-index.md).

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

With no `SIDEKICK_LLM_API_KEY`, the default producer uses `FakeLLMClient` (no
network). Copy [`.env.example`](.env.example) to `.env` (gitignored), set a key,
and load it into the shell before starting uvicorn:

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
prints top-k JSON lines with `doc_id`, `page`, `rank`, `score`, and `text`. Tests
use generated `FAKE-*` chunks, not real manuals.

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

The sample set is fake (`FAKE-*` document ids, page 999) so the harness and CI
have rows before the real golden set exists. Do not put real manual pages in
the sample. The golden-set issue owns `eval/golden.jsonl`.

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

The default treatment is [`data/highlight_style.json`](data/highlight_style.json): an 8 px fuchsia outline and a saturation boost inside the part. `highlight_style.default_highlight_style` loads it. `apply_highlight` draws that config on a 390×260 image. Issue #29 has not merged, so this function is the local stand-in, not the golden-image renderer. The comparison is [docs/design/highlight-style-bakeoff.md](../docs/design/highlight-style-bakeoff.md). Tests draw five synthetic scenes, not the licensed photo and not the owner's truck.

## Stack

| Piece | Choice |
| --- | --- |
| Language | Python 3.11+ |
| HTTP | FastAPI |
| Server | uvicorn |
| Answer contract | `jsonschema` against `contracts/answer.schema.json` |
| LLM | OpenAI-compatible `POST /chat/completions` over `httpx`, behind `LLMClient` |
| Tests | pytest + FastAPI `TestClient` |
| Retrieval | SQLite FTS5 (stdlib `sqlite3`), see `retrieval.py` |

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

The response is an answer or a refusal as defined by the shared contract. The
app must not invent vehicle facts; fixture citations use `page: 999` and
`FAKE-*` values.

## Spec guard

`spec_guard.guard_answer(answer, cited_chunk_texts)` runs on the producer
payload before the safety note is applied, so the note is never scanned.
It extracts numbers with units and pin, connector, and terminal references.
Each one must appear in a cited chunk. Otherwise the payload is replaced
with a `not_found_in_manual` refusal that names the missing claims.
Normalization is specified in
[`docs/design/spec-guard.md`](../docs/design/spec-guard.md).

Citation snippets are not evidence. `POST /chat` passes chunk text from
`CitedChunkSource.cited_chunk_texts` when the producer implements it, and
passes no chunks otherwise. With no chunks, any spec in the answer is refused.
`LlmAnswerProducer` does not implement that protocol yet, because retrieval
is not wired into `/chat`.

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
`OpenAICompatibleClient` is the live provider (OpenAI or any host that speaks
the same `/v1/chat/completions` API).

`LlmAnswerProducer` implements `AnswerProducer`. `/chat` stays the HTTP
boundary. Provider failures (timeouts, exhausted retries, empty completions)
return HTTP 200 with a contract-valid error answer (`kind: answer`, empty
citations). Token usage and latency are logged on logger `sidekick.llm`.

Environment variables (see `.env.example`):

| Variable | Default | Purpose |
| --- | --- | --- |
| `SIDEKICK_LLM_API_KEY` | empty (fake client) | Secret. Read from the environment only. |
| `SIDEKICK_LLM_BASE_URL` | `https://api.openai.com/v1` | Provider base URL, including `/v1` |
| `SIDEKICK_LLM_MODEL` | `gpt-4o-mini` | Model id |
| `SIDEKICK_LLM_TIMEOUT_SECONDS` | `30` | Per-attempt HTTP timeout |
| `SIDEKICK_LLM_MAX_RETRIES` | `2` | Retries after the first attempt on timeout, transport errors, 429, and 5xx |

`FixtureAnswerProducer` remains for tests that need a committed contract fixture.

## Part resolver

`part_resolver.resolve_answer` sets the answer contract's optional `highlight`
from a model selection, or leaves the highlight off.

The model must return `{"part_id": "<id>"}` or `{"part_id": null}`. The id
has to be one of `BayMapView.part_ids()`. That view is a local stand-in for
the bay map schema (#26), which is not merged. It carries part id, photo id,
angle id, pixel area, and whether the region is confirmed. Polygons, image
size, names, aliases, license, and source stay in #26. See
[`docs/design/part-resolver.md`](../docs/design/part-resolver.md).

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
