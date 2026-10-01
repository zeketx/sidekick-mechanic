"""FastAPI app: POST /chat returns a contract-valid answer."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException
from jsonschema.exceptions import ValidationError

from chat_models import Conversation
from contract import validate_answer
from producer import AnswerProducer, CitedChunkSource, FixtureAnswerProducer
from spec_guard import guard_answer


def create_app(producer: AnswerProducer | None = None) -> FastAPI:
    answer_producer = producer or FixtureAnswerProducer()
    application = FastAPI(
        title="Sidekick Mechanic",
        summary=(
            "Chat skeleton. Answers are fixture-backed until the LLM adapter "
            "lands. The spec guard refuses uncited unit-numbers and pin references."
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
        try:
            return validate_answer(guarded.answer)
        except ValidationError as exc:
            raise HTTPException(
                status_code=500,
                detail="answer failed contract validation",
            ) from exc

    return application


app = create_app()
