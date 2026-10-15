"""FastAPI app: POST /chat returns a contract-valid answer.

The spec guard runs on the producer payload, or on the page answer when the
newest user turn names a manual page. A page answer is guarded against that
page's server text only. Procedure answers then receive the safety note from
safety.py. The note is not scanned. Refusals do not receive it.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, PlainTextResponse, Response
from jsonschema.exceptions import ValidationError
from pydantic import BaseModel, ConfigDict, Field

from chat_models import Conversation, PageRef
from contract import validate_answer
from demo import (
    ATTRIBUTION_PATH,
    catalog_public,
    has_photo,
    log_demo_feedback,
    photo_file,
)
from go_deeper import GoDeeperError, cited_page_text, go_deeper
from llm import LLMClient, build_llm_client, build_vision_client
from manual_pages import ManualPageError, is_servable_doc_id, page_png
from page_chat import answer_about_page
from producer import (
    AnswerProducer,
    CitedChunkSource,
    LlmAnswerProducer,
    default_producer,
    format_searched_pages,
)
from safety import apply_safety_preamble
from spec_guard import guard_answer


class DemoFeedback(BaseModel):
    model_config = ConfigDict(extra="forbid")

    photo_id: str = Field(min_length=1)
    part_id: str = Field(min_length=1)
    action: Literal["yes", "not_this"]


def create_app(
    producer: AnswerProducer | None = None,
    *,
    manuals_dir: Path | None = None,
    chunks_path: Path | None = None,
    page_cache_dir: Path | None = None,
    go_deeper_client: LLMClient | None = None,
    manifest_path: Path | None = None,
    page_client: LLMClient | None = None,
    vision_client: LLMClient | None = None,
) -> FastAPI:
    answer_producer = producer if producer is not None else default_producer()
    page_llm = page_client if page_client is not None else build_llm_client()
    vision = vision_client if vision_client is not None else build_vision_client()
    application = FastAPI(
        title="Sidekick Mechanic",
        summary=(
            "Chat endpoint. The spec guard checks the producer answer, then "
            "procedure answers get the safety note. Cited pages are PNGs from "
            "local manuals, with a Go deeper block grounded in that page."
        ),
    )
    application.state.manuals_dir = manuals_dir
    application.state.chunks_path = chunks_path
    application.state.page_cache_dir = page_cache_dir
    application.state.go_deeper_client = go_deeper_client
    application.state.manifest_path = manifest_path

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

    @application.get("/manuals/{doc_id}/pages/{page}.png")
    def get_manual_page_png(doc_id: str, page: int) -> Response:
        try:
            png = page_png(
                doc_id,
                page,
                manuals_dir=application.state.manuals_dir,
                cache_dir=application.state.page_cache_dir,
                manifest_path=application.state.manifest_path,
            )
        except ManualPageError as exc:
            raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
        return Response(content=png, media_type="image/png")

    @application.get("/manuals/{doc_id}/pages/{page}/go-deeper")
    def get_manual_page_go_deeper(
        doc_id: str, page: int, snippet: str | None = None
    ) -> dict[str, Any]:
        try:
            return go_deeper(
                doc_id,
                page,
                snippet=snippet,
                chunks_path=application.state.chunks_path,
                manuals_dir=application.state.manuals_dir,
                client=application.state.go_deeper_client,
                manifest_path=application.state.manifest_path,
            )
        except GoDeeperError as exc:
            raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc

    @application.post("/demo/feedback")
    def post_demo_feedback(body: DemoFeedback) -> dict[str, Any]:
        if not has_photo(body.photo_id):
            raise HTTPException(status_code=422, detail="unknown demo photo")
        return log_demo_feedback(
            photo_id=body.photo_id,
            part_id=body.part_id,
            action=body.action,
        )

    def page_image_or_none(doc_id: str, page: int) -> bytes | None:
        try:
            return page_png(
                doc_id,
                page,
                manuals_dir=application.state.manuals_dir,
                cache_dir=application.state.page_cache_dir,
                manifest_path=application.state.manifest_path,
            )
        except ManualPageError:
            return None

    def answer_page_turn(
        conversation: Conversation, page: PageRef
    ) -> tuple[dict[str, Any], tuple[str, ...]]:
        if not is_servable_doc_id(
            page.doc_id, manifest_path=application.state.manifest_path
        ):
            raise HTTPException(status_code=422, detail="unknown manual page")
        # Loaded once. The prompt and the guard see the same string.
        page_text = cited_page_text(
            page.doc_id,
            page.page,
            chunks_path=application.state.chunks_path,
            manuals_dir=application.state.manuals_dir,
        )
        payload = answer_about_page(
            conversation,
            page,
            page_text,
            llm=page_llm,
            vision=vision,
            page_image=lambda: page_image_or_none(page.doc_id, page.page),
        )
        evidence = (page_text,) if page_text and page_text.strip() else ()
        return payload, evidence

    @application.post("/chat")
    def post_chat(
        conversation: Conversation, request: Request, response: Response
    ) -> dict[str, Any]:
        if conversation.demo is not None and not has_photo(conversation.demo.photo_id):
            raise HTTPException(status_code=422, detail="unknown demo photo")
        page = conversation.page
        if page is not None:
            payload, chunk_texts = answer_page_turn(conversation, page)
        else:
            payload = answer_producer.produce(conversation)
            # No CitedChunkSource means nothing was retrieved, so any spec is uncited.
            if isinstance(answer_producer, CitedChunkSource):
                chunk_texts = answer_producer.cited_chunk_texts(conversation, payload)
            else:
                chunk_texts = ()
        guarded = guard_answer(payload, chunk_texts)
        # After the guard so the safety note is never scanned for specs.
        noted = apply_safety_preamble(guarded.answer)
        if request.headers.get("x-sidekick-eval") == "retrieval":
            pages = _debug_searched_pages(answer_producer, conversation, page)
            if pages is not None:
                response.headers["X-Sidekick-Retrieval"] = format_searched_pages(pages)
        try:
            return validate_answer(noted)
        except ValidationError as exc:
            raise HTTPException(
                status_code=500,
                detail="answer failed contract validation",
            ) from exc

    return application


def _debug_searched_pages(
    producer: AnswerProducer,
    conversation: Conversation,
    page: PageRef | None,
) -> tuple[tuple[str, int], ...] | None:
    if page is not None or not isinstance(producer, LlmAnswerProducer):
        return None
    return producer.searched_pages(conversation)


app = create_app()
