"""Answer-producer seam. LLM adapter implements AnswerProducer."""

from __future__ import annotations

import logging
import time
from typing import Any, Protocol

from chat_models import Conversation
from contract import load_answer_fixture, validate_answer
from llm import (
    ChatTurn,
    LLMClient,
    LLMError,
    TokenUsage,
    build_llm_client,
)

DEFAULT_FIXTURE = "plain.json"
LOGGER = logging.getLogger("sidekick.llm")

SYSTEM_PROMPT = (
    "You are Sidekick Mechanic. Answer the owner's question. "
    "Do not invent torque values, part numbers, pinouts, wire colors, or other specs. "
    "Do not cite a manual page you were not given. "
    "If you do not know, say so."
)

UNAVAILABLE_ANSWER: dict[str, Any] = {
    "kind": "answer",
    "text": "The mechanic is unavailable right now. Try again in a moment.",
    "citations": [],
}

validate_answer(UNAVAILABLE_ANSWER)


class AnswerProducer(Protocol):
    def produce(self, conversation: Conversation) -> dict[str, Any]:
        """Return an answer payload that must match answer.schema.json."""


class FixtureAnswerProducer:
    """Returns a committed contract fixture. Does not call a model."""

    def __init__(self, fixture_name: str = DEFAULT_FIXTURE) -> None:
        self.fixture_name = fixture_name

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        del conversation
        return load_answer_fixture(self.fixture_name)


class LlmAnswerProducer:
    """Turns an LLM completion into a contract answer. Citations stay empty until retrieval."""

    def __init__(self, client: LLMClient) -> None:
        self._client = client

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        messages = [ChatTurn(role="system", content=SYSTEM_PROMPT)]
        messages.extend(
            ChatTurn(role=message.role, content=message.text)
            for message in conversation.messages
        )
        started = time.perf_counter()
        try:
            result = self._client.complete(messages)
        except LLMError:
            _log_request(
                ok=False,
                model="unknown",
                latency_ms=_latency_ms(started),
                usage=None,
            )
            return dict(UNAVAILABLE_ANSWER)
        text = result.text.strip()
        _log_request(
            ok=bool(text),
            model=result.model,
            latency_ms=_latency_ms(started),
            usage=result.usage,
        )
        if not text:
            return dict(UNAVAILABLE_ANSWER)
        # Retrieval is not wired. Emitting citations here would invent pages.
        return {"kind": "answer", "text": text, "citations": []}


def default_producer() -> AnswerProducer:
    return LlmAnswerProducer(build_llm_client())


def _latency_ms(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)


def _log_request(
    *,
    ok: bool,
    model: str,
    latency_ms: int,
    usage: TokenUsage | None,
) -> None:
    prompt = usage.prompt_tokens if usage is not None else None
    completion = usage.completion_tokens if usage is not None else None
    total = usage.total_tokens if usage is not None else None
    LOGGER.info(
        "llm request completed ok=%s model=%s latency_ms=%s prompt_tokens=%s "
        "completion_tokens=%s total_tokens=%s",
        str(ok).lower(),
        model,
        latency_ms,
        prompt,
        completion,
        total,
    )
