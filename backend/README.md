# Backend

Python 3.11+ and FastAPI. This is the RAG service for Sidekick Mechanic.

`POST /chat` is a skeleton: it accepts a conversation and returns a payload that
validates against [`contracts/answer.schema.json`](contracts/answer.schema.json).
Answers come from a fixture-backed `AnswerProducer` until the cloud LLM adapter
(#15) and ingestion (#18) land. Do not treat the reply as a real procedure.

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

The default producer returns `contracts/fixtures/plain.json`.

## Tests

```bash
pip install -r requirements.txt
pytest
```

Linux CI (#3) runs the same `pytest` from `backend/`.

## Stack

| Piece | Choice |
| --- | --- |
| Language | Python 3.11+ |
| HTTP | FastAPI |
| Server | uvicorn |
| Answer contract | `jsonschema` against `contracts/answer.schema.json` |
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

## Answer producer seam

`AnswerProducer.produce(conversation)` returns a `dict` that must match the
answer schema. `FixtureAnswerProducer` loads a committed fixture and ignores
the prompt. #15 should implement the same protocol and keep `/chat` as the HTTP
boundary.

## Spec guard

`spec_guard.guard_answer(answer, cited_chunk_texts)` runs after generation.
It extracts numbers with units and pin, connector, and terminal references
from the answer text. Each one must appear in a cited chunk. Otherwise the
payload is replaced with a `not_found_in_manual` refusal that names the
missing claims. Normalization (whitespace, unit spelling, what must not
match) is specified in [`docs/design/spec-guard.md`](../docs/design/spec-guard.md).

Citation snippets are not evidence. `POST /chat` passes chunk text from
`CitedChunkSource.cited_chunk_texts` when the producer implements it, and
passes no chunks otherwise. With no chunks, any spec in the answer is refused.
The fixture producer does not implement that protocol. Its committed fixtures
have no unit-numbers or pin references, so the default reply is unchanged.

Failures log a warning on the `sidekick.spec_guard` logger. The eval harness
sums `GuardResult.uncited_count` for the uncited-number count. `stats()` is
the same total for the process since `reset_stats()`. Refusals that enter
the guard are not counted as failures.
