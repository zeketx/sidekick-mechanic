"""Cloud LLM client behind a small interface. No network in the fake."""

from __future__ import annotations

import base64
import json
import logging
import os
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from typing import Any, Literal, Protocol

import httpx

ChatRole = Literal["system", "user", "assistant"]

DEFAULT_BASE_URL = "https://api.openai.com/v1"
DEFAULT_VISION_BASE_URL = "https://openrouter.ai/api/v1"
DEFAULT_MODEL = "gpt-4o-mini"
DEFAULT_TIMEOUT_SECONDS = 30.0
DEFAULT_MAX_RETRIES = 2
DEFAULT_FAKE_TEXT = (
    "This is a fake LLM reply with no manual citations. No vehicle specs in this reply."
)
FAKE_GROUNDED_TEXT = (
    "The retrieved pages are cited below. This stand-in does not add manual facts."
)
RETRIEVED_PAGES_HEADER = "Retrieved pages:\n"
GO_DEEPER_HEADER = "Go deeper for one cited page:\n"
RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 504})

logger = logging.getLogger("sidekick.vision")


class LLMError(Exception):
    """Provider failed. Callers map this to a contract-valid error answer."""


@dataclass(frozen=True)
class ImageInput:
    media_type: Literal["image/jpeg", "image/png"]
    data: bytes = field(repr=False)


@dataclass(frozen=True)
class ChatTurn:
    role: ChatRole
    content: str
    images: tuple[ImageInput, ...] = ()


@dataclass(frozen=True)
class TokenUsage:
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


@dataclass(frozen=True)
class LLMResult:
    text: str
    model: str
    usage: TokenUsage | None


@dataclass(frozen=True)
class LLMSettings:
    api_key: str | None
    base_url: str
    model: str
    timeout_seconds: float
    max_retries: int


class LLMClient(Protocol):
    def complete(self, messages: list[ChatTurn]) -> LLMResult:
        """Return model text. Raise LLMError after timeouts/retries are exhausted."""


FAKE_USAGE = TokenUsage(prompt_tokens=1, completion_tokens=1, total_tokens=2)


class FakeLLMClient:
    """In-process stub. Used in tests and when no API key is configured.

    ``text`` forces one completion. With ``text`` omitted, a go-deeper prompt
    restates that one page, a grounded chat prompt becomes citation JSON
    from the retrieved pages, and any other prompt returns
    ``DEFAULT_FAKE_TEXT``.
    """

    def __init__(
        self,
        text: str | None = None,
        usage: TokenUsage | None = FAKE_USAGE,
        error: Exception | None = None,
    ) -> None:
        self.text = text
        self.usage = usage
        self.error = error
        self.calls: list[list[ChatTurn]] = []

    def complete(self, messages: list[ChatTurn]) -> LLMResult:
        self.calls.append(list(messages))
        if self.error is not None:
            raise self.error
        text = self.text if self.text is not None else _fake_completion_text(messages)
        return LLMResult(text=text, model="fake", usage=self.usage)


class OpenAICompatibleClient:
    """POST /chat/completions. Works with OpenAI and other compatible hosts."""

    def __init__(
        self,
        settings: LLMSettings,
        *,
        http_client: httpx.Client | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if not settings.api_key:
            raise ValueError("OpenAICompatibleClient requires SIDEKICK_LLM_API_KEY")
        self._settings = settings
        self._http = http_client or httpx.Client(timeout=settings.timeout_seconds)
        self._sleep = sleep

    def complete(self, messages: list[ChatTurn]) -> LLMResult:
        last_error: Exception | None = None
        attempts = self._settings.max_retries + 1
        started = time.monotonic()
        for attempt in range(attempts):
            try:
                response = self._post(messages)
            except httpx.TransportError as exc:
                last_error = exc
            else:
                if response.status_code in RETRYABLE_STATUS:
                    last_error = LLMError(
                        f"provider returned HTTP {response.status_code}"
                    )
                elif response.status_code >= 400:
                    raise LLMError(f"provider returned HTTP {response.status_code}")
                else:
                    result = _parse_completion(response, fallback_model=self._settings.model)
                    _log_vision_call(messages, result, started)
                    return result
            if attempt + 1 < attempts:
                self._sleep(0.25 * (2**attempt))
        raise LLMError("provider failed after retries") from last_error

    def _post(self, messages: list[ChatTurn]) -> httpx.Response:
        url = f"{self._settings.base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self._settings.api_key}",
            "Content-Type": "application/json",
        }
        body = {
            "model": self._settings.model,
            "temperature": 0,
            "messages": [_message_body(turn) for turn in messages],
        }
        return self._http.post(url, headers=headers, json=body)


def _message_body(turn: ChatTurn) -> dict[str, Any]:
    if not turn.images:
        return {"role": turn.role, "content": turn.content}
    parts: list[dict[str, Any]] = [{"type": "text", "text": turn.content}]
    for image in turn.images:
        encoded = base64.b64encode(image.data).decode("ascii")
        parts.append(
            {
                "type": "image_url",
                "image_url": {"url": f"data:{image.media_type};base64,{encoded}"},
            }
        )
    return {"role": turn.role, "content": parts}


def _log_vision_call(messages: list[ChatTurn], result: LLMResult, started: float) -> None:
    """Lengths only. Image bytes and reply text can show a real plug label."""
    sizes = [len(image.data) for turn in messages for image in turn.images]
    if not sizes:
        return
    logger.info(
        "vision model=%s image_bytes=%s reply_chars=%d latency_ms=%d",
        result.model,
        sizes,
        len(result.text),
        round((time.monotonic() - started) * 1000),
    )


def load_llm_settings(environ: Mapping[str, str] | None = None) -> LLMSettings:
    env = os.environ if environ is None else environ
    return LLMSettings(
        api_key=_optional_str(env.get("SIDEKICK_LLM_API_KEY")),
        base_url=_optional_str(env.get("SIDEKICK_LLM_BASE_URL")) or DEFAULT_BASE_URL,
        model=_optional_str(env.get("SIDEKICK_LLM_MODEL")) or DEFAULT_MODEL,
        timeout_seconds=_float_setting(
            env.get("SIDEKICK_LLM_TIMEOUT_SECONDS"),
            DEFAULT_TIMEOUT_SECONDS,
            name="SIDEKICK_LLM_TIMEOUT_SECONDS",
            minimum=0.001,
        ),
        max_retries=_int_setting(
            env.get("SIDEKICK_LLM_MAX_RETRIES"),
            DEFAULT_MAX_RETRIES,
            name="SIDEKICK_LLM_MAX_RETRIES",
            minimum=0,
        ),
    )


def build_llm_client(settings: LLMSettings | None = None) -> LLMClient:
    resolved = settings or load_llm_settings()
    if resolved.api_key:
        return OpenAICompatibleClient(resolved)
    return FakeLLMClient()


def build_vision_client(environ: Mapping[str, str] | None = None) -> LLMClient | None:
    """None without a key and a model, so a plug check says it cannot tell.

    The model is not chosen yet, so there is no default to fall back on.
    """
    env = os.environ if environ is None else environ
    api_key = _optional_str(env.get("SIDEKICK_VISION_API_KEY"))
    model = _optional_str(env.get("SIDEKICK_VISION_MODEL"))
    if not api_key or not model:
        return None
    settings = LLMSettings(
        api_key=api_key,
        base_url=_optional_str(env.get("SIDEKICK_VISION_BASE_URL")) or DEFAULT_VISION_BASE_URL,
        model=model,
        timeout_seconds=DEFAULT_TIMEOUT_SECONDS,
        max_retries=DEFAULT_MAX_RETRIES,
    )
    return OpenAICompatibleClient(settings)


def _optional_str(raw: str | None) -> str | None:
    text = (raw or "").strip()
    return text or None


def _float_setting(raw: str | None, default: float, *, name: str, minimum: float) -> float:
    text = (raw or "").strip()
    if not text:
        return default
    value = float(text)
    if value < minimum:
        raise ValueError(f"{name} must be >= {minimum}")
    return value


def _int_setting(raw: str | None, default: int, *, name: str, minimum: int) -> int:
    text = (raw or "").strip()
    if not text:
        return default
    value = int(text)
    if value < minimum:
        raise ValueError(f"{name} must be >= {minimum}")
    return value


def _parse_completion(response: httpx.Response, *, fallback_model: str) -> LLMResult:
    try:
        payload = response.json()
    except ValueError as exc:
        raise LLMError("provider returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise LLMError("provider returned a non-object body")
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise LLMError("provider returned no choices")
    first = choices[0]
    if not isinstance(first, dict):
        raise LLMError("provider returned an invalid choice")
    message = first.get("message")
    if not isinstance(message, dict):
        raise LLMError("provider returned an invalid message")
    content = message.get("content")
    if not isinstance(content, str):
        raise LLMError("provider returned empty content")
    model = payload.get("model")
    model_name = model if isinstance(model, str) and model else fallback_model
    return LLMResult(text=content, model=model_name, usage=_parse_usage(payload.get("usage")))


def _fake_completion_text(messages: list[ChatTurn]) -> str:
    go_deeper = _go_deeper_from_messages(messages)
    if go_deeper is not None:
        return json.dumps(go_deeper, ensure_ascii=False)
    citations = _citations_from_messages(messages)
    if citations is None:
        return DEFAULT_FAKE_TEXT
    if not citations:
        return json.dumps({"text": "", "citations": []})
    return json.dumps(
        {"text": FAKE_GROUNDED_TEXT, "citations": citations},
        ensure_ascii=False,
    )


def _go_deeper_from_messages(messages: list[ChatTurn]) -> dict[str, str] | None:
    """Restate the cited page. Do not add specs that are not on it."""

    for turn in messages:
        if GO_DEEPER_HEADER not in turn.content:
            continue
        raw = turn.content.split(GO_DEEPER_HEADER, 1)[1]
        try:
            page = json.loads(raw)
        except json.JSONDecodeError:
            return None
        if not isinstance(page, dict):
            return None
        text = page.get("text")
        if not isinstance(text, str) or not text.strip():
            return {
                "how_it_works": (
                    "This page is a wiring diagram. Read the labels on the page. "
                    "I am not guessing pinouts or wire colors."
                )
            }
        from go_deeper import excerpt_around_snippet

        snippet = page.get("snippet") if isinstance(page.get("snippet"), str) else None
        excerpt = excerpt_around_snippet(text, snippet)
        if excerpt is None:
            return {}
        return {"how_it_works": excerpt}
    return None


def _citations_from_messages(messages: list[ChatTurn]) -> list[dict[str, Any]] | None:
    """Copy citations from the grounded prompt.

    Hits reach this client only as retrieved-pages JSON on the system turn.
    Each snippet is that page's text so the provenance check can keep it.
    ``None`` means the prompt is not grounded.
    """

    for turn in messages:
        if turn.role != "system" or RETRIEVED_PAGES_HEADER not in turn.content:
            continue
        raw = turn.content.split(RETRIEVED_PAGES_HEADER, 1)[1]
        try:
            pages = json.loads(raw)
        except json.JSONDecodeError:
            return None
        if not isinstance(pages, list):
            return None
        return _citations_from_pages(pages)
    return None


def _citations_from_pages(pages: list[Any]) -> list[dict[str, Any]]:
    citations: list[dict[str, Any]] = []
    seen: set[tuple[str, int]] = set()
    for page in pages:
        citation = _citation_from_page(page)
        if citation is None:
            continue
        key = (citation["doc_id"], citation["page"])
        if key in seen:
            continue
        seen.add(key)
        citations.append(citation)
    return citations


def _citation_from_page(page: Any) -> dict[str, Any] | None:
    if not isinstance(page, dict):
        return None
    doc_id = page.get("doc_id")
    number = page.get("page")
    text = page.get("text")
    if not isinstance(doc_id, str) or not doc_id.strip():
        return None
    if isinstance(number, bool) or not isinstance(number, int) or number < 1:
        return None
    if not isinstance(text, str):
        return None
    snippet = text.strip()
    if not snippet or snippet not in text:
        return None
    return {"doc_id": doc_id, "page": number, "snippet": snippet}


def _parse_usage(raw: Any) -> TokenUsage | None:
    if not isinstance(raw, dict):
        return None
    try:
        prompt = int(raw["prompt_tokens"])
        completion = int(raw["completion_tokens"])
        total = int(raw["total_tokens"])
    except (KeyError, TypeError, ValueError):
        return None
    return TokenUsage(
        prompt_tokens=prompt,
        completion_tokens=completion,
        total_tokens=total,
    )
