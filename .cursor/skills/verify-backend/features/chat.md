# Chat

Chat is the `POST /chat` request the iPhone app sends. The response is a found answer, general advice, or a `not_found_in_manual` refusal, validated against `backend/contracts/answer.schema.json`.

## Sub-features

- `chat-contract` returns the fake-LLM answer when no API key is set.
- `chat-invalid` rejects an empty message list with HTTP 422.
- `chat-plain-fixture` returns `plain.json` unchanged.
- `chat-refusal` returns `refusal.json`.
- `chat-citations` returns `with_citations.json`, including `FAKE-DOC-2JZ` page 999.
- `chat-highlight` returns `with_highlight.json` for `fake-part-intake`.
- `chat-spec-guard-blocks` refuses `999 Nm` when the only copy of that claim is a citation snippet.
- `chat-spec-guard-allows` returns `Torque is 999 Nm.` when the cited chunk contains the claim.

## How to get to it (user POV)

- In the app, type a problem and tap Send. The app posts `{ "messages": [{ "role": "user", "text": "..." }] }` to `{SIDEKICK_BACKEND_URL}/chat`. When the Garage has facts, notes, or open to-dos, the same request also sends a compact `garage` object. Verification still posts messages only.
- From a shell, post the same body to the verification server the helper prints. The question used here is `Why is it hard to start?`

## Driving it with verify-backend

Preconditions:

- `python3 -m pip install -r backend/requirements.txt` has been run for this interpreter.
- For one case, launch that case and require `python3 .cursor/skills/verify-backend/scripts/verify_backend.py doctor` to exit 0.
- For every sub-feature in one shot, use `run` instead of launching by hand.

- **Contract.** Launch the fake server. Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fake`, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py doctor`, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fake`. HTTP 200. With no index, `kind` is `general_advice`. The honesty line is `Not in your manual. Here's what usually causes this.` The only step starts with `FAKE-STEP`. `garage.source` is `none`. `related` is `[]`. `schema_valid` is true in `evidence/latest/chat-fake.json`.
- **Invalid body.** The same `drive fake` command posts `{"messages":[]}`. HTTP 422 and the body has `detail`. Proof is `evidence/latest/chat-invalid.json`.
- **Plain fixture.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name plain.json`, doctor, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fixture`. The response equals `backend/contracts/fixtures/plain.json`.
- **Refusal.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name refusal.json`, doctor, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fixture`. `kind` is `refusal` and `reason` is `not_found_in_manual`.
- **Citations.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name with_citations.json`, doctor, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fixture`. The first citation is `doc_id` `FAKE-DOC-2JZ` and `page` `999`.
- **Highlight fixture.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case fixture --name with_highlight.json`, doctor, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive fixture`. `highlight.part_id` is `fake-part-intake`.
- **Spec guard blocks.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case uncited-spec`, doctor, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive uncited-spec`. The response is `{"kind":"refusal","text":"Not found in the cited manual text: 999 Nm.","reason":"not_found_in_manual"}`.
- **Spec guard allows.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py launch --case cited-spec`, doctor, then `python3 .cursor/skills/verify-backend/scripts/verify_backend.py drive cited-spec`. `kind` is `answer`, `text` is `Torque is 999 Nm.`, and the citation is `FAKE-DOC` page `999`.
- **All of the above.** Run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py run`. Then run `python3 .cursor/skills/verify-backend/scripts/verify_backend.py cleanup` only if a launch is still recorded. `run` already cleans up.

## Gotchas

- Retrieval is not wired into `/chat`. The fake path has empty citations. That is not a citation success.
- Citation snippets are not spec-guard evidence. `uncited-spec` puts `999 Nm` in the snippet and must still be refused.
- `999 Nm`, `FAKE-DOC`, `FAKE-DOC-2JZ`, and page `999` are fixtures. Do not replace them with a real torque, part number, or manual page.
- The fixture producer ignores the question text. Changing the question does not change `plain.json`.
- Do not point this skill at port 8000 unless `doctor` shows the recorded pid owns it.
- `make eval` rewrites metrics files. Use the helper so those tracked bytes are restored. Latency numbers in the evidence copy are allowed to move.
- Stop the server you started before launching a second case. The state file is one lock.
