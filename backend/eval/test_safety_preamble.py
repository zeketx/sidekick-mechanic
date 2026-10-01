"""Eval fixture: procedure answers start with the safety note."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import Conversation, Message
from contract import validate_answer
from llm import FakeLLMClient
from producer import LlmAnswerProducer
from safety import SAFETY_NOTE, is_procedure_answer

FIXTURE_PATH = Path(__file__).resolve().parent / "fixtures" / "safety_preamble.json"
CHAT_BODY = {
    "messages": [
        {"role": "user", "text": "How do I do the fixture job?"},
    ]
}
REQUIRED_CASE_IDS = {
    "numbered_steps",
    "step_labels",
    "prose",
    "refusal_with_numbered_lines",
}


class _StaticProducer:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        del conversation
        return self.payload


def _cases() -> list[dict[str, Any]]:
    payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    cases = payload["cases"]
    assert isinstance(cases, list)
    return cases


def _post(answer: dict[str, Any]) -> dict[str, Any]:
    response = TestClient(create_app(producer=_StaticProducer(answer))).post(
        "/chat",
        json=CHAT_BODY,
    )
    assert response.status_code == 200
    body = response.json()
    assert isinstance(body, dict)
    validate_answer(body)
    return body


def test_safety_preamble_fixture_covers_required_cases() -> None:
    assert {case["id"] for case in _cases()} == REQUIRED_CASE_IDS


def test_safety_note_names_generic_hazards_only() -> None:
    lowered = SAFETY_NOTE.casefold()
    assert "engine cool" in lowered
    assert "disconnect the battery" in lowered
    assert "when the step calls for it" in lowered
    assert "stands" in lowered
    assert not any(character.isdigit() for character in SAFETY_NOTE)


@pytest.mark.parametrize("case", _cases(), ids=lambda case: case["id"])
def test_chat_applies_safety_preamble_from_eval_fixture(case: dict[str, Any]) -> None:
    answer = case["answer"]
    untouched = json.loads(json.dumps(answer))
    assert is_procedure_answer(answer) is case["expect_preamble"]

    body = _post(answer)

    assert answer == untouched
    expected = dict(answer)
    if case["expect_preamble"]:
        expected["text"] = f"{SAFETY_NOTE}\n\n{answer['text']}"
        assert body["text"].startswith(SAFETY_NOTE)
    else:
        assert SAFETY_NOTE not in body["text"]
    assert body == expected


def test_llm_procedure_gets_note_only_at_http_boundary() -> None:
    steps = "1. Let the fixture engine cool.\n2) Support the fixture vehicle on stands."
    conversation = Conversation(
        messages=[Message(role="user", text="How do I do the fixture job?")]
    )
    raw = LlmAnswerProducer(FakeLLMClient(text=steps)).produce(conversation)

    assert raw == {"kind": "answer", "text": steps, "citations": []}
    assert SAFETY_NOTE not in raw["text"]

    response = TestClient(
        create_app(producer=LlmAnswerProducer(FakeLLMClient(text=steps)))
    ).post("/chat", json=CHAT_BODY)

    assert response.status_code == 200
    body = response.json()
    validate_answer(body)
    assert body == {
        "kind": "answer",
        "text": f"{SAFETY_NOTE}\n\n{steps}",
        "citations": [],
    }


def test_chat_does_not_repeat_safety_note() -> None:
    case = next(item for item in _cases() if item["id"] == "numbered_steps")
    once = _post(case["answer"])
    twice = _post(once)

    assert twice == once
    assert once["text"].count(SAFETY_NOTE) == 1
