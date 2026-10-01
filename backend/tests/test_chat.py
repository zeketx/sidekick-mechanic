from __future__ import annotations

from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import Conversation, Message
from contract import load_answer_fixture, validate_answer
from llm import DEFAULT_FAKE_TEXT, FakeLLMClient, LLMError
from producer import (
    AnswerProducer,
    FixtureAnswerProducer,
    LlmAnswerProducer,
    UNAVAILABLE_ANSWER,
)

HAPPY_BODY = {
    "messages": [
        {"role": "user", "text": "Why is it hard to start?"},
    ]
}


def _client(producer: AnswerProducer | None = None) -> TestClient:
    return TestClient(create_app(producer=producer))


def test_chat_happy_path_returns_schema_valid_fixture() -> None:
    response = _client(FixtureAnswerProducer()).post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload == load_answer_fixture("plain.json")
    assert payload == {
        "kind": "answer",
        "text": "This is a fixture-only reply with no manual citations.",
        "citations": [],
    }


def test_chat_default_without_api_key_uses_fake_llm() -> None:
    response = _client().post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload == {
        "kind": "answer",
        "text": DEFAULT_FAKE_TEXT,
        "citations": [],
    }


def test_chat_llm_error_returns_contract_valid_error_answer() -> None:
    producer = LlmAnswerProducer(FakeLLMClient(error=LLMError("timeout")))
    response = _client(producer).post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload == UNAVAILABLE_ANSWER


def test_chat_uses_injected_producer() -> None:
    client = _client(FixtureAnswerProducer("refusal.json"))

    response = client.post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload == load_answer_fixture("refusal.json")
    assert payload["kind"] == "refusal"
    assert payload["reason"] == "not_found_in_manual"


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"messages": []},
        {"messages": [{"role": "user", "text": ""}]},
        {"messages": [{"role": "mechanic", "text": "Why is it hard to start?"}]},
        {"conversation": {"messages": [{"role": "user", "text": "Why?"}]}},
        {"messages": [{"role": "user", "text": "Why?"}], "extra": True},
    ],
    ids=[
        "missing_messages",
        "empty_messages",
        "empty_text",
        "unknown_role",
        "wrapped_conversation",
        "extra_property",
    ],
)
def test_chat_invalid_request_rejected(body: dict[str, Any]) -> None:
    response = _client().post("/chat", json=body)

    assert response.status_code == 422


def test_chat_rejects_producer_payload_that_fails_contract() -> None:
    class BrokenProducer:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            assert conversation.messages == [
                Message(role="user", text="Why is it hard to start?")
            ]
            return {"kind": "answer", "text": "", "citations": []}

    response = TestClient(create_app(producer=BrokenProducer())).post(
        "/chat", json=HAPPY_BODY
    )

    assert response.status_code == 500
    assert response.json() == {"detail": "answer failed contract validation"}
