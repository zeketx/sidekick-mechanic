from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import httpx
import pytest

from chat_models import Conversation, Message
from contract import validate_answer
from llm import (
    DEFAULT_BASE_URL,
    DEFAULT_FAKE_TEXT,
    DEFAULT_MAX_RETRIES,
    DEFAULT_MODEL,
    DEFAULT_TIMEOUT_SECONDS,
    DEFAULT_VISION_BASE_URL,
    GO_DEEPER_HEADER,
    ChatTurn,
    FakeLLMClient,
    ImageInput,
    LLMError,
    LLMSettings,
    OpenAICompatibleClient,
    TokenUsage,
    build_llm_client,
    build_vision_client,
    load_llm_settings,
)
from producer import LlmAnswerProducer, SYSTEM_PROMPT, UNAVAILABLE_ANSWER, default_producer

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_DIR.parent


def _conversation(text: str = "Why is it hard to start?") -> Conversation:
    return Conversation(messages=[Message(role="user", text=text)])


def _settings(
    *,
    api_key: str | None = "fake-test-key",
    base_url: str = "https://example.test/v1",
    model: str = "fake-gpt-test",
    timeout_seconds: float = 1.0,
    max_retries: int = 2,
) -> LLMSettings:
    return LLMSettings(
        api_key=api_key,
        base_url=base_url,
        model=model,
        timeout_seconds=timeout_seconds,
        max_retries=max_retries,
    )


def _openai_body(text: str) -> dict[str, Any]:
    return {
        "id": "chatcmpl-fake",
        "model": "fake-gpt-test",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
    }


def _openai_client(
    handler: Any,
    *,
    settings: LLMSettings | None = None,
    sleep: Any = None,
) -> OpenAICompatibleClient:
    http = httpx.Client(transport=httpx.MockTransport(handler))
    return OpenAICompatibleClient(
        settings or _settings(),
        http_client=http,
        sleep=sleep or (lambda _: None),
    )


def test_fake_client_returns_canned_text() -> None:
    fake = FakeLLMClient()
    result = fake.complete([ChatTurn(role="user", content="Why is it hard to start?")])

    assert result.text == DEFAULT_FAKE_TEXT
    assert result.model == "fake"
    assert result.usage == TokenUsage(prompt_tokens=1, completion_tokens=1, total_tokens=2)
    assert fake.calls == [[ChatTurn(role="user", content="Why is it hard to start?")]]


def test_fake_client_restates_one_cited_page_for_go_deeper() -> None:
    fake = FakeLLMClient()
    page = (
        GO_DEEPER_HEADER
        + '{"text":"Lead-in. FAKE-CHUNK: look at the cover. After that.",'
        + '"snippet":"FAKE-CHUNK: look at the cover."}'
    )
    result = fake.complete([ChatTurn(role="user", content=page)])
    payload = json.loads(result.text)
    assert payload["how_it_works"]
    assert "FAKE-CHUNK: look at the cover." in payload["how_it_works"]
    assert len(payload["how_it_works"]) <= 300


def test_fake_client_hides_go_deeper_without_snippet_match() -> None:
    fake = FakeLLMClient()
    page = GO_DEEPER_HEADER + '{"text":"FAKE-CHUNK: look at the cover."}'
    result = fake.complete([ChatTurn(role="user", content=page)])
    payload = json.loads(result.text)
    assert payload == {}


def test_producer_wraps_fake_text_as_contract_answer() -> None:
    fake = FakeLLMClient()
    payload = LlmAnswerProducer(fake).produce(_conversation())

    validate_answer(payload)
    assert payload == {
        "kind": "answer",
        "text": DEFAULT_FAKE_TEXT,
        "citations": [],
    }
    assert fake.calls[0][0] == ChatTurn(role="system", content=SYSTEM_PROMPT)
    assert fake.calls[0][1] == ChatTurn(role="user", content="Why is it hard to start?")
    assert "Do not invent torque" in SYSTEM_PROMPT
    assert "N·m" not in SYSTEM_PROMPT


def test_producer_llm_error_returns_unavailable_answer() -> None:
    fake = FakeLLMClient(error=LLMError("timeout"))
    payload = LlmAnswerProducer(fake).produce(_conversation())

    validate_answer(payload)
    assert payload == UNAVAILABLE_ANSWER
    assert payload["kind"] == "error"
    assert payload["reason"] == "provider_unavailable"
    assert "citations" not in payload


def test_producer_empty_completion_returns_unavailable_answer() -> None:
    payload = LlmAnswerProducer(FakeLLMClient(text="  ")).produce(_conversation())

    validate_answer(payload)
    assert payload == UNAVAILABLE_ANSWER


def test_producer_logs_token_usage_and_latency(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO, logger="sidekick.llm")
    LlmAnswerProducer(FakeLLMClient()).produce(_conversation())

    assert "ok=true" in caplog.text
    assert "model=fake" in caplog.text
    assert "prompt_tokens=1" in caplog.text
    assert "completion_tokens=1" in caplog.text
    assert "total_tokens=2" in caplog.text
    assert "latency_ms=" in caplog.text


def test_producer_logs_failure_without_usage(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.INFO, logger="sidekick.llm")
    LlmAnswerProducer(FakeLLMClient(error=LLMError("boom"))).produce(_conversation())

    assert "ok=false" in caplog.text
    assert "prompt_tokens=None" in caplog.text
    assert "latency_ms=" in caplog.text


def test_openai_client_parses_completion_and_usage() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=_openai_body("Hello from fake-gpt."))

    result = _openai_client(handler).complete(
        [ChatTurn(role="user", content="Why is it hard to start?")]
    )

    assert result.text == "Hello from fake-gpt."
    assert result.model == "fake-gpt-test"
    assert result.usage == TokenUsage(
        prompt_tokens=10, completion_tokens=5, total_tokens=15
    )
    request = seen[0]
    assert request.method == "POST"
    assert str(request.url) == "https://example.test/v1/chat/completions"
    assert request.headers["Authorization"] == "Bearer fake-test-key"
    body = json.loads(request.content)
    assert body == {
        "model": "fake-gpt-test",
        "temperature": 0,
        "messages": [{"role": "user", "content": "Why is it hard to start?"}],
    }


def test_openai_client_sends_images_as_content_parts_and_logs_lengths_only(
    caplog: pytest.LogCaptureFixture,
) -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=_openai_body("FAKE-REPLY-TEXT"))

    turn = ChatTurn(
        role="user",
        content="Describe both.",
        images=(
            ImageInput(media_type="image/png", data=b"FAKE-PNG"),
            ImageInput(media_type="image/jpeg", data=b"FAKE-JPG"),
        ),
    )
    with caplog.at_level(logging.INFO, logger="sidekick.vision"):
        _openai_client(handler).complete([turn])

    body = json.loads(seen[0].content)
    assert body["messages"] == [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "Describe both."},
                {"type": "image_url", "image_url": {"url": "data:image/png;base64,RkFLRS1QTkc="}},
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,RkFLRS1KUEc="}},
            ],
        }
    ]
    assert "image_bytes=[8, 8]" in caplog.text
    assert "reply_chars=15" in caplog.text
    assert "FAKE-PNG" not in caplog.text
    assert "RkFLRS1QTkc" not in caplog.text
    assert "FAKE-REPLY-TEXT" not in caplog.text
    assert "FAKE-PNG" not in repr(turn)


def test_build_vision_client_needs_a_key_and_a_model() -> None:
    assert build_vision_client({}) is None
    assert build_vision_client({"SIDEKICK_VISION_API_KEY": "fake-test-key"}) is None
    assert build_vision_client({"SIDEKICK_VISION_MODEL": "fake-vision-model"}) is None

    client = build_vision_client(
        {"SIDEKICK_VISION_API_KEY": "fake-test-key", "SIDEKICK_VISION_MODEL": "fake-vision-model"}
    )
    assert isinstance(client, OpenAICompatibleClient)
    try:
        assert client._settings.base_url == DEFAULT_VISION_BASE_URL
        assert client._settings.model == "fake-vision-model"
    finally:
        client._http.close()


def test_openai_client_retries_then_succeeds() -> None:
    statuses = [503, 200]
    sleeps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        status = statuses.pop(0)
        if status == 200:
            return httpx.Response(200, json=_openai_body("recovered"))
        return httpx.Response(status, json={"error": "busy"})

    result = _openai_client(handler, sleep=sleeps.append).complete(
        [ChatTurn(role="user", content="Hi")]
    )

    assert result.text == "recovered"
    assert sleeps == [0.25]


def test_openai_client_raises_after_retries_exhausted() -> None:
    sleeps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, json={"error": "busy"})

    client = _openai_client(
        handler, settings=_settings(max_retries=2), sleep=sleeps.append
    )
    with pytest.raises(LLMError, match="provider failed after retries"):
        client.complete([ChatTurn(role="user", content="Hi")])
    assert sleeps == [0.25, 0.5]


def test_openai_client_retries_timeout_then_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("read timeout")

    client = _openai_client(handler, settings=_settings(max_retries=1))
    with pytest.raises(LLMError, match="provider failed after retries"):
        client.complete([ChatTurn(role="user", content="Hi")])


def test_invalid_provider_json_retries_then_returns_text() -> None:
    pending: list[bytes | None] = [b"not-json", None]
    sleeps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        raw = pending.pop(0)
        if raw is not None:
            return httpx.Response(200, content=raw)
        return httpx.Response(200, json=_openai_body("recovered"))

    result = _openai_client(
        handler, settings=_settings(max_retries=2), sleep=sleeps.append
    ).complete([ChatTurn(role="user", content="The radiator is leaking.")])

    assert result.text == "recovered"
    assert sleeps == [0.25]


def test_null_content_retries_then_returns_text() -> None:
    bodies: list[dict[str, Any]] = [
        {
            "choices": [
                {"index": 0, "message": {"role": "assistant", "content": None}}
            ]
        },
        _openai_body("recovered"),
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=bodies.pop(0))

    result = _openai_client(handler, settings=_settings(max_retries=1)).complete(
        [ChatTurn(role="user", content="The truck shakes on the highway.")]
    )

    assert result.text == "recovered"


def test_unreadable_provider_body_stops_at_the_retry_budget() -> None:
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, content=b"not-json")

    client = _openai_client(handler, settings=_settings(max_retries=2))
    with pytest.raises(LLMError, match="provider failed after retries") as excinfo:
        client.complete([ChatTurn(role="user", content="Hi")])

    assert calls["n"] == 3
    assert excinfo.value.kind == "parse"
    assert "fake-test-key" not in str(excinfo.value)


def test_rate_limit_logs_the_status_without_the_key(
    caplog: pytest.LogCaptureFixture,
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "busy"})

    client = _openai_client(handler, settings=_settings(max_retries=1))
    caplog.set_level(logging.WARNING, logger="sidekick.llm")
    payload = LlmAnswerProducer(client).produce(
        _conversation("The radiator is leaking.")
    )

    assert payload == UNAVAILABLE_ANSWER
    assert "kind=rate_limit" in caplog.text
    assert "status=429" in caplog.text
    assert "fake-test-key" not in caplog.text


def test_empty_completion_logs_parse_rejection(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.WARNING, logger="sidekick.llm")
    payload = LlmAnswerProducer(FakeLLMClient(text="  ")).produce(_conversation())

    assert payload == UNAVAILABLE_ANSWER
    assert "kind=parse" in caplog.text
    assert "detail=empty_completion" in caplog.text


def test_openai_client_does_not_retry_client_errors() -> None:
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(400, json={"error": "bad request"})

    client = _openai_client(handler)
    with pytest.raises(LLMError, match="HTTP 400") as excinfo:
        client.complete([ChatTurn(role="user", content="Hi")])
    assert calls["n"] == 1
    assert "fake-test-key" not in str(excinfo.value)


def test_openai_client_requires_api_key() -> None:
    with pytest.raises(ValueError, match="SIDEKICK_LLM_API_KEY"):
        OpenAICompatibleClient(_settings(api_key=None))


def test_load_llm_settings_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SIDEKICK_LLM_API_KEY", "fake-test-key")
    monkeypatch.setenv("SIDEKICK_LLM_BASE_URL", "https://example.test/v1")
    monkeypatch.setenv("SIDEKICK_LLM_MODEL", "fake-gpt-test")
    monkeypatch.setenv("SIDEKICK_LLM_TIMEOUT_SECONDS", "12")
    monkeypatch.setenv("SIDEKICK_LLM_MAX_RETRIES", "3")

    assert load_llm_settings() == LLMSettings(
        api_key="fake-test-key",
        base_url="https://example.test/v1",
        model="fake-gpt-test",
        timeout_seconds=12.0,
        max_retries=3,
    )


def test_load_llm_settings_defaults_without_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("SIDEKICK_LLM_BASE_URL", raising=False)
    monkeypatch.delenv("SIDEKICK_LLM_MODEL", raising=False)
    monkeypatch.delenv("SIDEKICK_LLM_TIMEOUT_SECONDS", raising=False)
    monkeypatch.delenv("SIDEKICK_LLM_MAX_RETRIES", raising=False)
    monkeypatch.setenv("SIDEKICK_LLM_API_KEY", "   ")

    settings = load_llm_settings()
    assert settings.api_key is None
    assert settings.base_url == DEFAULT_BASE_URL
    assert settings.model == DEFAULT_MODEL
    assert settings.timeout_seconds == DEFAULT_TIMEOUT_SECONDS
    assert settings.max_retries == DEFAULT_MAX_RETRIES


def test_build_llm_client_fake_without_key() -> None:
    producer = default_producer()
    assert isinstance(build_llm_client(), FakeLLMClient)
    assert isinstance(producer, LlmAnswerProducer)
    assert isinstance(producer._client, FakeLLMClient)


def test_build_llm_client_openai_with_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SIDEKICK_LLM_API_KEY", "fake-test-key")
    client = build_llm_client()
    try:
        assert isinstance(client, OpenAICompatibleClient)
        assert client._http.timeout == httpx.Timeout(DEFAULT_TIMEOUT_SECONDS)
    finally:
        client._http.close()


def test_env_example_documents_keys_without_secrets() -> None:
    text = (BACKEND_DIR / ".env.example").read_text(encoding="utf-8")
    assert "SIDEKICK_LLM_API_KEY=" in text
    assert "SIDEKICK_LLM_BASE_URL=" in text
    assert "SIDEKICK_LLM_MODEL=" in text
    assert "SIDEKICK_LLM_TIMEOUT_SECONDS=" in text
    assert "SIDEKICK_LLM_MAX_RETRIES=" in text
    assert "SIDEKICK_VISION_BASE_URL=" in text
    assert "SIDEKICK_VISION_MODEL=" in text
    for line in text.splitlines():
        if line.startswith(("SIDEKICK_LLM_API_KEY=", "SIDEKICK_VISION_API_KEY=")):
            assert line.split("=", 1)[1] == ""
    assert "SIDEKICK_VISION_API_KEY=" in text


def test_server_retry_budget_fits_in_the_phone_timeout() -> None:
    attempts = DEFAULT_MAX_RETRIES + 1
    backoff = sum(0.25 * (2**attempt) for attempt in range(DEFAULT_MAX_RETRIES))
    budget = attempts * DEFAULT_TIMEOUT_SECONDS + backoff
    assert attempts == 3
    assert backoff == 0.75
    assert budget == 90.75
    assert budget < 120


def test_env_file_is_gitignored() -> None:
    gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert ".env" in {line.strip() for line in gitignore.splitlines()}
