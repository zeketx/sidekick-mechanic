---
name: verify-backend
description: "Drive the Sidekick Mechanic FastAPI backend on Linux. Launch POST /chat, check the answer contract, FAKE fixtures, refusals, the spec guard, and citations, then run swift test and make eval. Use when proving backend, contract, or eval behavior."
---

# Verify the Sidekick Mechanic backend

Prove `POST /chat` by launching the real FastAPI app and saving the response. Also run `swift test` in `app/SidekickCore` and `make eval`. This skill runs on Linux. The iPhone UI is `verify-ios`, and that one is owner-only.

The product server is still `uvicorn app:app` from `backend/README.md`. Verification starts the same `create_app` function through the helper below. It does not add a route.

## Launch

From the repository root, install dependencies once for the interpreter you will use:

```bash
python3 -m pip install -r backend/requirements.txt
```

Start one isolated server and leave it up:

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fake
```

Fixture and spec-guard cases:

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name plain.json
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name refusal.json
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name with_citations.json
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name with_highlight.json
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case uncited-spec
python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case cited-spec
```

Ready means `GET /openapi.json` returns 200 and the title is `Sidekick Mechanic`. The process listens on `127.0.0.1` and an ephemeral port, not port 8000. The helper drops `SIDEKICK_LLM_API_KEY` from the server environment, so the fake case uses `FakeLLMClient` and does not call the network.

The helper refuses to launch when its recorded pid is still alive. Two verification servers at once would share the state file. Stop the one you started before launching another. Do not drive a `uvicorn` the user started themselves.

`run` launches, checks, drives, and stops each case itself:

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py run
```

## Doctor

Read-only. Run this before every drive, and again after a drive fails.

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py doctor
```

Exit 0 only when all of these are true:

- The recorded pid is alive and its command line contains `serve.py`.
- That pid owns the listening socket.
- `SIDEKICK_LLM_API_KEY` is unset in that process.
- `GET /openapi.json` is 200, the title is `Sidekick Mechanic`, and `POST /chat` is present.

Doctor writes `.cursor/skills/verify-backend/evidence/latest/doctor-<case>.json`. It does not send a chat.

## Drive

Send the README question to the server you launched. The body is always:

```json
{"messages":[{"role":"user","text":"Why is it hard to start?"}]}
```

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fake
python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fixture
python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive uncited-spec
python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive cited-spec
```

`drive fixture` uses the fixture name from the active launch. `drive fake` also posts `{"messages":[]}` and requires HTTP 422.

What each case must return:

- `fake` — HTTP 200, schema-valid general advice. There is no index and no garage, so the reply is `kind` `general_advice`, the honesty line `Not in your manual. Here's what usually causes this.`, one step that starts with `FAKE-STEP` and does not name a truck, `garage.source` `none`, and `related` `[]`.
- `plain.json` — the committed fixture, unchanged.
- `refusal.json` — `kind` `refusal`, `reason` `not_found_in_manual`.
- `with_citations.json` — citation `doc_id` `FAKE-DOC-2JZ`, `page` `999`.
- `with_highlight.json` — `bay_photo_id` `fake-bay-photo-front`, `part_id` `fake-part-intake`.
- `uncited-spec` — HTTP 200 refusal `Not found in the cited manual text: 999 Nm.` The producer puts `999 Nm` in the answer and in the citation snippet. The snippet is not evidence, so the guard refuses.
- `cited-spec` — HTTP 200 answer `Torque is 999 Nm.` with citation `FAKE-DOC` page `999`. The chunk text is `FAKE-CHUNK: torque is 999 N·m.`

Every HTTP 200 body must validate against `backend/contracts/answer.schema.json`.

Linux proofs that are not HTTP:

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py swift-test
python3 .cursor/skills/verify-backend/scripts/verify_backend.py eval
```

`swift-test` runs `swift test` in `app/SidekickCore`. `swift` must be on `PATH`. Exit 0 and the transcript must contain `Test Suite 'All tests' passed`.

`eval` runs `make eval PYTHON=<this interpreter>`. That is the repo target. It rewrites `docs/METRICS.md` and `backend/eval/results/<date>.json`. The helper copies the new results file into the evidence directory, then restores the previous bytes of those tracked files. A verify run must not change product metrics. Stdout must name `recall@5`, `citation accuracy`, `refusal correctness`, `uncited-number count`, `latency p50 (ms)`, and `latency p95 (ms)`.

`run` performs every drive above, then `swift-test`, then `eval`.

## Evidence

Proof goes to `.cursor/skills/verify-backend/evidence/latest/`. Each chat file has `feature_id`, `entry_point` (`POST /chat`), the request, the status, and the response. Schema-valid answers set `schema_valid` to true.

| File | What it proves |
| --- | --- |
| `chat-fake.json` | Default fake-LLM answer |
| `chat-invalid.json` | HTTP 422 for an empty message list |
| `chat-plain.json` | `plain.json` through `/chat` |
| `chat-refusal.json` | Refusal fixture |
| `chat-citations.json` | Citation fixture, `FAKE-DOC-2JZ` page 999 |
| `chat-highlight.json` | Highlight fixture |
| `chat-uncited-spec.json` | Spec guard refusal |
| `chat-cited-spec.json` | Spec guard allows a claim present in the chunk |
| `swift-test.txt` | `swift test` transcript |
| `eval-stdout.txt` | `make eval` summary |
| `eval-results.json` | Copy of the results file `make eval` wrote |

Capture the request and the response, not only a pass line. Do not point this skill at a live LLM. The fake client is the production path when no API key is set. The fixture and spec-guard producers are passed into `create_app` because that is the existing seam. They are not extra HTTP routes.

## Cleanup

```bash
python3 .cursor/skills/verify-backend/scripts/verify_backend.py cleanup
```

Cleanup sends `SIGTERM`, then `SIGKILL`, to the process group recorded in `.cursor/skills/verify-backend/run/state.json`. It deletes that state file. It does not delete `evidence/`. After `run`, the evidence files listed above must still be on disk, and the state file must be gone.

`run` replaces `evidence/latest` at the start of a new run. That is a new proof, not cleanup.

## Helpers

Both scripts are executable.

- `python3 .cursor/skills/verify-backend/scripts/verify_backend.py run`
- `python3 .cursor/skills/verify-backend/scripts/serve.py --host 127.0.0.1 --port <port>`

Call `verify_backend.py`. It starts `serve.py`. Do not start `serve.py` by hand unless you are debugging a launch failure. The server log is `evidence/latest/server-<case>.log`.

## Maintenance

When chat behavior changes, run `/maintain-verification-skill` and correct this skill from a live `run`, not from memory.
