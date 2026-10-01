# Backend

Python 3.11+ and FastAPI. This is the RAG service for Sidekick Mechanic.

`POST /chat` accepts a conversation and returns a payload that validates against
[`contracts/answer.schema.json`](contracts/answer.schema.json). Answers come from
`LlmAnswerProducer`, which calls an `LLMClient`. Retrieval is not wired yet, so
replies have empty citations and must not be treated as a real procedure.

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
does not, and cited pages are not treated as hits. The uncited-number total
uses `LocalUncitedNumberCounter`. `run_harness(..., uncited_counter=...)`
accepts another `UncitedNumberCounter` for the spec guard.

## Stack

| Piece | Choice |
| --- | --- |
| Language | Python 3.11+ |
| HTTP | FastAPI |
| Server | uvicorn |
| Answer contract | `jsonschema` against `contracts/answer.schema.json` |
| LLM | OpenAI-compatible `POST /chat/completions` over `httpx`, behind `LLMClient` |
| Tests | pytest + FastAPI `TestClient` |

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
