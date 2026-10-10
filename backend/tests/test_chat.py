from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import Conversation, Message
from contract import load_answer_fixture, validate_answer
from llm import DEFAULT_FAKE_TEXT, FakeLLMClient, LLMError
from producer import (
    UNAVAILABLE_ANSWER,
    AnswerProducer,
    FixtureAnswerProducer,
    LlmAnswerProducer,
)
from safety import SAFETY_NOTE

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


def test_chat_missing_index_refuses_without_calling_the_model(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    missing = tmp_path / "missing.sqlite"
    monkeypatch.setattr("producer._index_path", lambda: missing)
    response = _client().post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["kind"] == "refusal"
    assert payload["reason"] == "not_found_in_manual"
    assert DEFAULT_FAKE_TEXT not in payload["text"]


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


def test_chat_refuses_uncited_spec_even_when_snippet_contains_it() -> None:
    class SnippetOnlyProducer:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            del conversation
            return {
                "kind": "answer",
                "text": "Torque is 999 Nm.",
                "citations": [
                    {
                        "doc_id": "FAKE-DOC",
                        "page": 999,
                        "snippet": "Torque is 999 Nm.",
                    }
                ],
            }

    response = TestClient(create_app(producer=SnippetOnlyProducer())).post(
        "/chat", json=HAPPY_BODY
    )

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload == {
        "kind": "refusal",
        "text": "Not found in the cited manual text: 999 Nm.",
        "reason": "not_found_in_manual",
    }


def test_chat_allows_spec_when_producer_supplies_the_chunk() -> None:
    answer = {
        "kind": "answer",
        "text": "Torque is 999 Nm.",
        "citations": [
            {
                "doc_id": "FAKE-DOC",
                "page": 999,
                "snippet": "FAKE-SNIPPET",
            }
        ],
    }

    class ChunkProducer:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            del conversation
            return answer

        def cited_chunk_texts(
            self, conversation: Conversation, answer: dict[str, Any]
        ) -> tuple[str, ...]:
            del conversation, answer
            return ("FAKE-CHUNK: torque is 999 N·m.",)

    response = TestClient(create_app(producer=ChunkProducer())).post(
        "/chat", json=HAPPY_BODY
    )

    assert response.status_code == 200
    assert response.json() == answer


def test_chat_refuses_uncited_spec_before_safety_note() -> None:
    class ProcedureWithSpec:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            del conversation
            return {
                "kind": "answer",
                "text": "1. Tighten the FAKE bolt to 999 Nm.",
                "citations": [],
            }

    response = TestClient(create_app(producer=ProcedureWithSpec())).post(
        "/chat", json=HAPPY_BODY
    )

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["kind"] == "refusal"
    assert payload["text"] == "Not found in the cited manual text: 999 Nm."
    assert SAFETY_NOTE not in payload["text"]


def test_chat_does_not_scan_the_safety_note(monkeypatch: pytest.MonkeyPatch) -> None:
    patched = SAFETY_NOTE + " Fixture note voltage 999 V."
    monkeypatch.setattr("safety.SAFETY_NOTE", patched)

    class Procedure:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            del conversation
            return {
                "kind": "answer",
                "text": "1. Leave the FAKE bay.",
                "citations": [],
            }

    response = TestClient(create_app(producer=Procedure())).post(
        "/chat", json=HAPPY_BODY
    )

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["kind"] == "answer"
    assert payload["text"] == f"{patched}\n\n1. Leave the FAKE bay."
    assert "999 V" in payload["text"]
