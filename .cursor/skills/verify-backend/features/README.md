# Backend verification map

This directory is the maintained source for verifying `POST /chat`. Read it before driving the backend, then use [chat.md](./chat.md).

Answer card and mock mode are iPhone features. Their map is [verify-ios](../../verify-ios/features/README.md).

## Baseline preconditions

- Install `backend/requirements.txt` into the interpreter that runs the helper.
- Launch with `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch`. The helper picks `127.0.0.1` and a free port.
- Leave `SIDEKICK_LLM_API_KEY` unset. The helper removes it from the server even if the parent shell has it.
- Run `doctor` and require exit 0 before a drive.
- Never drive a uvicorn process this skill did not start.

## Driving conventions

- Start from the fake case unless the recipe names another case.
- Treat every command as literal. Keep fixture file names unchanged.
- The chat body is `{"messages":[{"role":"user","text":"Why is it hard to start?"}]}`.
- `python3 .cursor/skills/verify-backend/scripts/verify_backend.py run` drives every sub-feature, then `swift test` and `make eval`.
- Restore is part of `eval`: product files `docs/METRICS.md` and `backend/eval/results/` go back to their previous bytes. The proof copy stays in `evidence/latest`.

## Proof and skip reporting

- Save the request and the response under `.cursor/skills/verify-backend/evidence/latest/`.
- A schema-valid answer is not proof by itself. The recipe names the expected `kind`, text, citations, or refusal.
- Record `feature_id` and `POST /chat` on every chat artifact.
- If `swift` is missing, record the command and the unmet precondition. Do not mark `swift-test` verified.
- Do not report a fixture case as proof of the fake-LLM path, or the reverse.

## Additional Linux proofs

These are not separate user features. `run` includes them.

- `swift-test` runs `swift test` in `app/SidekickCore`.
- `eval` runs `make eval` and checks the summary names recall@5, citation accuracy, refusal correctness, uncited-number count, and latency p50/p95.

## Feature entry contract

Each feature file starts with an H1 and one paragraph, then exactly four H2 sections: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify-backend`, and `Gotchas`.

## Features

- [Chat](./chat.md) covers the answer contract, the FAKE fixtures, refusals, citations, the highlight fixture, and the spec guard.
