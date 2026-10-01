"""FastAPI app: POST /chat returns a contract-valid answer.

Procedure answers start with the safety note from safety.py. Refusals do not.
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException
from jsonschema.exceptions import ValidationError

from chat_models import Conversation
from contract import validate_answer
from producer import AnswerProducer, FixtureAnswerProducer
from safety import apply_safety_preamble


def create_app(producer: AnswerProducer | None = None) -> FastAPI:
    answer_producer = producer or FixtureAnswerProducer()
    application = FastAPI(
        title="Sidekick Mechanic",
        summary="Chat skeleton. Answers are fixture-backed until the LLM adapter lands.",
    )

    @application.post("/chat")
    def post_chat(conversation: Conversation) -> dict[str, Any]:
        # On the HTTP boundary so every producer, including a later LLM
        # adapter, gets the same note.
        payload = apply_safety_preamble(answer_producer.produce(conversation))
        try:
            return validate_answer(payload)
        except ValidationError as exc:
            raise HTTPException(
                status_code=500,
                detail="answer failed contract validation",
            ) from exc

    return application


app = create_app()
