"""FastAPI app: POST /chat returns a contract-valid answer.

The spec guard runs on the producer payload. Procedure answers then receive
the safety note from safety.py. The note is not scanned. Refusals do not
receive it.
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException
from jsonschema.exceptions import ValidationError

from chat_models import Conversation
from contract import validate_answer
from producer import AnswerProducer, CitedChunkSource, default_producer
from safety import apply_safety_preamble
from spec_guard import guard_answer


def create_app(producer: AnswerProducer | None = None) -> FastAPI:
    answer_producer = producer if producer is not None else default_producer()
    application = FastAPI(
        title="Sidekick Mechanic",
        summary=(
            "Chat endpoint. The spec guard checks the producer answer, then "
            "procedure answers get the safety note."
        ),
    )

    @application.post("/chat")
    def post_chat(conversation: Conversation) -> dict[str, Any]:
        payload = answer_producer.produce(conversation)
        # No CitedChunkSource means nothing was retrieved, so any spec is uncited.
        if isinstance(answer_producer, CitedChunkSource):
            chunk_texts = answer_producer.cited_chunk_texts(conversation)
        else:
            chunk_texts = ()
        guarded = guard_answer(payload, chunk_texts)
        # After the guard so the safety note is never scanned for specs.
        noted = apply_safety_preamble(guarded.answer)
        try:
            return validate_answer(noted)
        except ValidationError as exc:
            raise HTTPException(
                status_code=500,
                detail="answer failed contract validation",
            ) from exc

    return application


app = create_app()
