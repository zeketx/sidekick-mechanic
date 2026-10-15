"""Pluggable eval runners. The default calls in-process POST /chat."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import urlsplit

import httpx
from fastapi.testclient import TestClient

from app import create_app
from llm import FakeLLMClient
from producer import AnswerProducer, LlmAnswerProducer

_HTTP_TIMEOUT_S = 120.0


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


class HttpBackendRunner:
    """POST /chat on a running backend.

    The chat URL drops userinfo, query, and fragment so a key in the
    base URL is not sent and is not stored. Errors name the status or
    a fixed failure line. They do not include the response body.
    Retrieval stays None. The answer contract has no hit list, and
    citations are not hits.
    """

    name = "http_backend"

    def __init__(
        self,
        base_url: str,
        *,
        client: httpx.Client | None = None,
        timeout_s: float = _HTTP_TIMEOUT_S,
    ) -> None:
        self._chat_url = _chat_url(base_url)
        self._client = client or httpx.Client(
            timeout=timeout_s,
            trust_env=False,
            follow_redirects=False,
        )
        self._owns_client = client is None

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def run(self, question: str) -> RunnerOutput:
        started = time.perf_counter()
        try:
            response = self._client.post(
                self._chat_url,
                json={"messages": [{"role": "user", "text": question}]},
            )
        except httpx.HTTPError:
            raise RunnerError("POST /chat failed") from None
        latency_ms = (time.perf_counter() - started) * 1000
        if response.status_code != 200:
            raise RunnerError(f"POST /chat returned {response.status_code}")
        try:
            payload = response.json()
        except ValueError:
            raise RunnerError("POST /chat returned a non-object body") from None
        if not isinstance(payload, dict):
            raise RunnerError("POST /chat returned a non-object body")
        return RunnerOutput(answer=payload, latency_ms=latency_ms, retrieval=None)


def _chat_url(base_url: str) -> str:
    parsed = urlsplit(base_url.strip())
    host = parsed.hostname
    if parsed.scheme not in {"http", "https"} or not host:
        raise RunnerError("backend URL must be http or https")
    if ":" in host:
        host = f"[{host}]"
    port = f":{parsed.port}" if parsed.port else ""
    path = parsed.path.rstrip("/").removesuffix("/chat")
    return f"{parsed.scheme}://{host}{port}{path}/chat"
