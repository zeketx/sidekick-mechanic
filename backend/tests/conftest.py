"""Test-wide guards: no outbound HTTP, no live API key."""

from __future__ import annotations

import httpx
import pytest


@pytest.fixture(autouse=True)
def clear_llm_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("SIDEKICK_LLM_API_KEY", raising=False)


@pytest.fixture(autouse=True)
def block_outbound_http(monkeypatch: pytest.MonkeyPatch) -> None:
    def blocked(self: httpx.HTTPTransport, request: httpx.Request) -> httpx.Response:
        raise AssertionError(
            f"outbound HTTP is disabled in tests: {request.method} {request.url}"
        )

    monkeypatch.setattr(httpx.HTTPTransport, "handle_request", blocked)
