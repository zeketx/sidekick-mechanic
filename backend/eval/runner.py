"""Pluggable eval runners. The default calls in-process POST /chat."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Protocol

from fastapi.testclient import TestClient

from app import create_app
from llm import FakeLLMClient
from producer import AnswerProducer, LlmAnswerProducer


class RunnerError(RuntimeError):
    """The runner could not produce a contract answer."""


@dataclass(frozen=True)
class RetrievedHit:
    doc_id: str
    page: int


@dataclass(frozen=True)
class RunnerOutput:
    answer: dict[str, Any]
    latency_ms: float
    retrieval: tuple[RetrievedHit, ...] | None = None


class EvalRunner(Protocol):
    def run(self, question: str) -> RunnerOutput:
        """Score one question. ``retrieval`` is None when this runner has no store."""


class InProcessChatRunner:
    """POST /chat inside this process.

    Uses ``FakeLLMClient`` so a configured API key cannot turn eval into a
    live call. Retrieval stays None: the chat payload has no hit list, and
    citations must not be read as one.
    """

    name = "inprocess_chat_fake_llm"

    def __init__(self, producer: AnswerProducer | None = None) -> None:
        if producer is None:
            producer = LlmAnswerProducer(FakeLLMClient())
        self._client = TestClient(create_app(producer=producer))

    def run(self, question: str) -> RunnerOutput:
        started = time.perf_counter()
        response = self._client.post(
            "/chat",
            json={"messages": [{"role": "user", "text": question}]},
        )
        latency_ms = (time.perf_counter() - started) * 1000
        if response.status_code != 200:
            raise RunnerError(
                f"POST /chat returned {response.status_code} for question {question!r}"
            )
        payload = response.json()
        if not isinstance(payload, dict):
            raise RunnerError("POST /chat returned a non-object body")
        return RunnerOutput(answer=payload, latency_ms=latency_ms, retrieval=None)
