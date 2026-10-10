#!/usr/bin/env python3
"""Verification server for POST /chat.

This is not the product entrypoint. `uvicorn app:app` stays the documented
server. The script builds the same FastAPI app through `create_app` so the
spec guard, safety note, and answer schema still run.

`SIDEKICK_VERIFY_CASE` selects the producer:

- `fake` — `create_app()` with no API key, so the product default is FakeLLMClient
- `fixture` — `FixtureAnswerProducer` named by `SIDEKICK_VERIFY_FIXTURE`
- `uncited-spec` — an answer that states "999 Nm" with only a citation snippet
- `cited-spec` — the same answer plus a cited chunk the guard can accept

The spec-guard producers live here because retrieval is not wired into
`/chat`, and FakeLLMClient never emits a spec. Snippets are not evidence.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

BACKEND = Path(__file__).resolve().parents[4] / "backend"
sys.path.insert(0, str(BACKEND))

from chat_models import Conversation
from producer import CitedChunkSource, FixtureAnswerProducer

from app import create_app

ALLOWED_FIXTURES = frozenset(
    {
        "plain.json",
        "refusal.json",
        "with_citations.json",
        "with_highlight.json",
    }
)

# Same fake claim the backend tests use. Not a vehicle spec.
_UNCITED_SPEC_ANSWER: dict[str, Any] = {
    "kind": "answer",
    "text": "Torque is 999 Nm.",
    "citations": [
        {
            "doc_id": "FAKE-DOC",
            "page": 999,
            "snippet": "Torque is 999 Nm.",
        }
    ],
}


class UncitedSpecProducer:
    def produce(self, conversation: Conversation) -> dict[str, Any]:
        del conversation
        return {
            "kind": "answer",
            "text": _UNCITED_SPEC_ANSWER["text"],
            "citations": [dict(item) for item in _UNCITED_SPEC_ANSWER["citations"]],
        }


class CitedSpecProducer:
    """CitedChunkSource so /chat passes chunk text into the spec guard."""

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        del conversation
        return {
            "kind": "answer",
            "text": _UNCITED_SPEC_ANSWER["text"],
            "citations": [
                {
                    "doc_id": "FAKE-DOC",
                    "page": 999,
                    "snippet": "FAKE-SNIPPET",
                }
            ],
        }

    def cited_chunk_texts(
        self, conversation: Conversation, answer: object
    ) -> tuple[str, ...]:
        del conversation, answer
        # U+00B7 in N·m matches the chunk in backend/tests/test_chat.py.
        return ("FAKE-CHUNK: torque is 999 N·m.",)


def build_app() -> Any:
    case = os.environ.get("SIDEKICK_VERIFY_CASE", "fake")
    if case == "fake":
        return create_app()
    if case == "fixture":
        name = os.environ.get("SIDEKICK_VERIFY_FIXTURE", "")
        if name not in ALLOWED_FIXTURES:
            raise SystemExit(
                f"SIDEKICK_VERIFY_FIXTURE must be one of {sorted(ALLOWED_FIXTURES)}"
            )
        return create_app(producer=FixtureAnswerProducer(name))
    if case == "uncited-spec":
        return create_app(producer=UncitedSpecProducer())
    if case == "cited-spec":
        producer = CitedSpecProducer()
        if not isinstance(producer, CitedChunkSource):
            raise SystemExit("cited-spec producer is not a CitedChunkSource")
        return create_app(producer=producer)
    raise SystemExit(f"unknown SIDEKICK_VERIFY_CASE {case!r}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Launch the verification /chat server."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    import uvicorn

    uvicorn.run(build_app(), host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
