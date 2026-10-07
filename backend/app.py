"""FastAPI app: POST /chat returns a contract-valid answer.

The spec guard runs on the producer payload. Procedure answers then receive
the safety note from safety.py. The note is not scanned. Refusals do not
receive it.
"""

from __future__ import annotations

from typing import Any, Literal

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, PlainTextResponse
from jsonschema.exceptions import ValidationError
from pydantic import BaseModel, ConfigDict, Field

from chat_models import Conversation
from contract import validate_answer
from demo import (
    ATTRIBUTION_PATH,
    catalog_public,
    has_photo,
    log_demo_feedback,
    photo_file,
)
from producer import AnswerProducer, CitedChunkSource, default_producer
from safety import apply_safety_preamble
from spec_guard import guard_answer


class DemoFeedback(BaseModel):
    model_config = ConfigDict(extra="forbid")

    photo_id: str = Field(min_length=1)
    part_id: str = Field(min_length=1)
    action: Literal["yes", "not_this"]


def create_app(producer: AnswerProducer | None = None) -> FastAPI:
    answer_producer = producer if producer is not None else default_producer()
    application = FastAPI(
        title="Sidekick Mechanic",
        summary=(
            "Chat endpoint. The spec guard checks the producer answer, then "
            "procedure answers get the safety note."
        ),
    )

    @application.get("/demo/photos")
    def get_demo_photos() -> dict[str, Any]:
        return catalog_public()

    @application.get("/demo/photos/{photo_id}/image")
    def get_demo_photo_image(photo_id: str) -> FileResponse:
        path = photo_file(photo_id)
        if path is None:
            raise HTTPException(status_code=404, detail="unknown demo photo")
        return FileResponse(path, media_type="image/jpeg")

    @application.get("/demo/attribution")
    def get_demo_attribution() -> PlainTextResponse:
        return PlainTextResponse(
            ATTRIBUTION_PATH.read_text(encoding="utf-8"),
            media_type="text/markdown; charset=utf-8",
        )

    @application.post("/demo/feedback")
    def post_demo_feedback(body: DemoFeedback) -> dict[str, Any]:
        if not has_photo(body.photo_id):
            raise HTTPException(status_code=422, detail="unknown demo photo")
        return log_demo_feedback(
            photo_id=body.photo_id,
            part_id=body.part_id,
            action=body.action,
        )

    @application.post("/chat")
    def post_chat(conversation: Conversation) -> dict[str, Any]:
        if conversation.demo is not None and not has_photo(conversation.demo.photo_id):
            raise HTTPException(status_code=422, detail="unknown demo photo")
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
