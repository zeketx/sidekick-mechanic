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
