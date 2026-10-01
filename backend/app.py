"""FastAPI app: POST /chat returns a contract-valid answer."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException
from jsonschema.exceptions import ValidationError

from chat_models import Conversation
from contract import validate_answer
from producer import AnswerProducer, default_producer


def create_app(producer: AnswerProducer | None = None) -> FastAPI:
    answer_producer = producer if producer is not None else default_producer()
    application = FastAPI(
        title="Sidekick Mechanic",
        summary="Chat endpoint. Uses a cloud LLM when SIDEKICK_LLM_API_KEY is set.",
    )

    @application.post("/chat")
    def post_chat(conversation: Conversation) -> dict[str, Any]:
        payload = answer_producer.produce(conversation)
        try:
            return validate_answer(payload)
        except ValidationError as exc:
            raise HTTPException(
                status_code=500,
                detail="answer failed contract validation",
            ) from exc

    return application


app = create_app()
