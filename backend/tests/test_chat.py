from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import (
    MAX_GARAGE_FIELD_CHARS,
    MAX_GARAGE_PROMPT_CHARS,
    Conversation,
    GarageContext,
    GarageFactContext,
    GarageNoteContext,
    GarageTodoContext,
    Message,
    garage_prompt_block,
)
from contract import load_answer_fixture, validate_answer
from general_advice import ADVICE_HONESTY
from llm import (
    DEFAULT_FAKE_TEXT,
    FakeLLMClient,
    LLMError,
    LLMSettings,
    OpenAICompatibleClient,
)
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

GARAGE_BODY = {
    "messages": [
        {"role": "user", "text": "Should I replace the wiring harness?"},
    ],
    "garage": {
        "facts": [{"label": "Harness", "value": "already replaced"}],
        "notes": [{"name": "Wiring harness", "note": "already replaced"}],
        "open_todos": [{"title": "Check the spare"}],
    },
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


def test_chat_missing_index_returns_general_advice(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    missing = tmp_path / "missing.sqlite"
    monkeypatch.setattr("producer._index_path", lambda: missing)
    response = _client().post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["kind"] == "general_advice"
    assert payload["honesty"] == ADVICE_HONESTY
    assert payload["steps"][0].startswith("FAKE-STEP")
    assert "Land Cruiser" not in payload["steps"][0]
    assert "text" not in payload
    assert DEFAULT_FAKE_TEXT not in payload["steps"][0]


def test_chat_llm_error_returns_contract_valid_error_answer() -> None:
    producer = LlmAnswerProducer(FakeLLMClient(error=LLMError("timeout")))
    response = _client(producer).post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload == UNAVAILABLE_ANSWER


def test_chat_timeout_logs_the_provider_kind_and_hides_the_key(
    caplog: pytest.LogCaptureFixture,
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("Bearer sk-SUPERSECRETKEY12")

    http = httpx.Client(transport=httpx.MockTransport(handler))
    llm = OpenAICompatibleClient(
        LLMSettings(
            api_key="fake-test-key",
            base_url="https://example.test/v1",
            model="fake-gpt-test",
            timeout_seconds=1.0,
            max_retries=0,
        ),
        http_client=http,
        sleep=lambda _: None,
    )
    caplog.set_level(logging.WARNING, logger="sidekick.llm")

    response = _client(LlmAnswerProducer(llm)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "The radiator is leaking."}]},
    )

    assert response.status_code == 200
    assert response.json() == UNAVAILABLE_ANSWER
    assert "kind=timeout" in caplog.text
    assert "SUPERSECRETKEY" not in caplog.text
    assert "fake-test-key" not in caplog.text
    assert "Bearer" not in caplog.text


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


def test_chat_accepts_optional_garage_context() -> None:
    captured: list[Conversation] = []

    class CaptureProducer:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            captured.append(conversation)
            return load_answer_fixture("plain.json")

    response = _client(CaptureProducer()).post("/chat", json=GARAGE_BODY)

    assert response.status_code == 200
    validate_answer(response.json())
    assert captured[0].garage == GarageContext(
        facts=[GarageFactContext(label="Harness", value="already replaced")],
        notes=[GarageNoteContext(name="Wiring harness", note="already replaced")],
        open_todos=[GarageTodoContext(title="Check the spare")],
    )


def test_chat_without_garage_context_still_works() -> None:
    captured: list[Conversation] = []

    class CaptureProducer:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            captured.append(conversation)
            return load_answer_fixture("plain.json")

    response = _client(CaptureProducer()).post("/chat", json=HAPPY_BODY)

    assert response.status_code == 200
    assert captured[0].garage is None
    assert response.json() == load_answer_fixture("plain.json")


def test_chat_empty_garage_object_is_accepted() -> None:
    captured: list[Conversation] = []

    class CaptureProducer:
        def produce(self, conversation: Conversation) -> dict[str, Any]:
            captured.append(conversation)
            return load_answer_fixture("plain.json")

    response = _client(CaptureProducer()).post(
        "/chat",
        json={
            "messages": [{"role": "user", "text": "Why is it hard to start?"}],
            "garage": {},
        },
    )

    assert response.status_code == 200
    assert captured[0].garage == GarageContext()
    assert garage_prompt_block(captured[0].garage) == ""


def test_chat_rejects_unknown_garage_field() -> None:
    response = _client().post(
        "/chat",
        json={
            "messages": [{"role": "user", "text": "Why is it hard to start?"}],
            "garage": {"facts": [], "extra": True},
        },
    )

    assert response.status_code == 422


def test_producer_includes_garage_notes_in_the_system_prompt() -> None:
    fake = FakeLLMClient()
    conversation = Conversation(
        messages=[Message(role="user", text="Should I replace the wiring harness?")],
        garage=GarageContext(
            facts=[GarageFactContext(label="Harness", value="already replaced")],
            notes=[GarageNoteContext(name="Wiring harness", note="already replaced")],
            open_todos=[GarageTodoContext(title="Check the spare")],
        ),
    )

    payload = LlmAnswerProducer(fake).produce(conversation)

    validate_answer(payload)
    system = fake.calls[0][0].content
    assert "already replaced" in system
    assert "Check the spare" in system
    assert "not a manual page" in system
    assert "Do not invent torque" in system
    assert fake.calls[0][1].content == "Should I replace the wiring harness?"


def test_garage_prompt_caps_total_length() -> None:
    notes = [
        GarageNoteContext(name=f"Part {index}", note="FAKE-NOTE " * 20)
        for index in range(16)
    ]
    block = garage_prompt_block(GarageContext(notes=notes))

    assert len(block) <= MAX_GARAGE_PROMPT_CHARS
    assert block.endswith("…")


def test_garage_prompt_trims_a_very_long_note() -> None:
    long_note = "FAKE-NOTE " + ("word " * 80)
    block = garage_prompt_block(
        GarageContext(notes=[GarageNoteContext(name="Wiring harness", note=long_note)])
    )

    assert "Wiring harness:" in block
    note_line = next(line for line in block.splitlines() if line.startswith("- Wiring"))
    detail = note_line.split(": ", 1)[1]
    assert len(detail) <= MAX_GARAGE_FIELD_CHARS
    assert detail.endswith("…")
    assert len(block) <= MAX_GARAGE_PROMPT_CHARS


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
