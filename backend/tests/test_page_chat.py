from __future__ import annotations

import base64
import json
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from contract import validate_answer
from go_deeper import FAKE_PAGE_TEXT
from llm import FakeLLMClient, LLMError
from page_chat import PAGE_EXPLAIN_INSTRUCTIONS, PAGE_TEXT_HEADER
from plug_check import MATCH_WITH_WRITING_TEXT, UNSURE_LEAD
from producer import UNAVAILABLE_ANSWER, FixtureAnswerProducer

PAGE = {"doc_id": "FAKE-DOC", "page": 999}
FAKE_JPEG = b"\xff\xd8\xffFAKE-PHOTO"
PHOTO = {"media_type": "image/jpeg", "data": base64.b64encode(FAKE_JPEG).decode("ascii")}


class ExplodingProducer:
    def produce(self, conversation: Any) -> dict[str, Any]:
        raise AssertionError("a page turn must not reach the general producer")


def _client(
    *,
    page_client: FakeLLMClient | None = None,
    vision_client: FakeLLMClient | None = None,
    producer: Any = None,
) -> TestClient:
    return TestClient(
        create_app(
            producer=producer or ExplodingProducer(),
            page_client=page_client or FakeLLMClient(text="FAKE-REPLY about this page."),
            vision_client=vision_client,
        )
    )


def _page_turn(text: str = "Explain this page simply", **extra: Any) -> dict[str, Any]:
    return {"messages": [{"role": "user", "text": text, "page": PAGE, **extra}]}


def _look(**overrides: Any) -> dict[str, Any]:
    look: dict[str, Any] = {
        "shape": "rectangular",
        "pin_count": 2,
        "color": "black",
        "label": "FAKE-PAGE",
    }
    look.update(overrides)
    return look


@pytest.mark.parametrize("field", ["text", "page_text"])
def test_client_page_text_is_rejected(field: str) -> None:
    body = _page_turn()
    body["messages"][0]["page"] = {**PAGE, field: "Tighten it to 999 Nm."}

    response = _client().post("/chat", json=body)

    assert response.status_code == 422


def test_page_reply_with_an_uncited_spec_is_refused() -> None:
    assert "999 Nm" not in FAKE_PAGE_TEXT
    client = _client(page_client=FakeLLMClient(text="Tighten it to 999 Nm."))

    response = client.post("/chat", json=_page_turn("What torque?"))

    assert response.status_code == 200
    assert response.json() == {
        "kind": "refusal",
        "text": "Not found in the cited manual text: 999 Nm.",
        "reason": "not_found_in_manual",
    }


def test_page_answer_is_schema_valid_cites_the_page_and_has_no_highlight() -> None:
    page_client = FakeLLMClient(text="FAKE-REPLY about this page.")

    response = _client(page_client=page_client).post("/chat", json=_page_turn())

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["kind"] == "answer"
    assert payload["text"] == "FAKE-REPLY about this page."
    assert payload["citations"] == [
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": " ".join(FAKE_PAGE_TEXT.split())}
    ]
    system = page_client.calls[0][0]
    assert system.role == "system"
    assert system.content == f"{PAGE_EXPLAIN_INSTRUCTIONS}\n\n{PAGE_TEXT_HEADER}{FAKE_PAGE_TEXT}"
    assert [(turn.role, turn.content) for turn in page_client.calls[0][1:]] == [
        ("user", "Explain this page simply"),
    ]


def test_page_explain_mentions_garage_notes_and_still_cites_the_page() -> None:
    page_client = FakeLLMClient(text="FAKE-REPLY about this page.")
    body = _page_turn()
    body["garage"] = {
        "notes": [{"name": "Wiring harness", "note": "already replaced"}],
    }

    response = _client(page_client=page_client).post("/chat", json=body)

    assert response.status_code == 200
    payload = response.json()
    assert payload["kind"] == "answer"
    assert payload["citations"] == [
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": " ".join(FAKE_PAGE_TEXT.split())}
    ]
    system = page_client.calls[0][0].content
    assert "already replaced" in system
    assert "not a manual page" in system
    page_text = system.split(PAGE_TEXT_HEADER, 1)[1]
    assert page_text == FAKE_PAGE_TEXT
    assert "already replaced" not in page_text


def test_page_turn_keeps_the_conversation_history() -> None:
    page_client = FakeLLMClient(text="FAKE-REPLY about this page.")
    body = {
        "messages": [
            {"role": "user", "text": "Why is it hard to start?"},
            {"role": "assistant", "text": "FAKE-ANSWER earlier."},
            {"role": "user", "text": "What tools do I need?", "page": PAGE},
        ]
    }

    response = _client(page_client=page_client).post("/chat", json=body)

    assert response.status_code == 200
    assert [(turn.role, turn.content) for turn in page_client.calls[0][1:]] == [
        ("user", "Why is it hard to start?"),
        ("assistant", "FAKE-ANSWER earlier."),
        ("user", "What tools do I need?"),
    ]


def test_a_newer_turn_without_a_page_takes_the_general_path() -> None:
    body = {
        "messages": [
            {"role": "user", "text": "Explain this page simply", "page": PAGE},
            {"role": "assistant", "text": "FAKE-ANSWER earlier."},
            {"role": "user", "text": "Why is it hard to start?"},
        ]
    }

    response = _client(producer=FixtureAnswerProducer()).post("/chat", json=body)

    assert response.status_code == 200
    assert response.json()["text"] == "This is a fixture-only reply with no manual citations."


def test_page_provider_failure_is_the_unavailable_answer() -> None:
    client = _client(page_client=FakeLLMClient(error=LLMError("provider down")))

    response = client.post("/chat", json=_page_turn())

    assert response.json() == UNAVAILABLE_ANSWER


def test_plug_photo_turn_answers_with_the_verdict_sentence() -> None:
    vision = FakeLLMClient(text=json.dumps({"page": _look(), "photo": _look()}))

    response = _client(vision_client=vision).post(
        "/chat", json=_page_turn("Which connector is this?", photo=PHOTO)
    )

    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["text"] == MATCH_WITH_WRITING_TEXT
    assert "highlight" not in payload
    assert payload["citations"][0]["doc_id"] == "FAKE-DOC"
    images = vision.calls[0][1].images
    assert [image.media_type for image in images] == ["image/png", "image/jpeg"]
    assert images[1].data == FAKE_JPEG


def test_plug_photo_without_a_vision_key_is_unsure(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("SIDEKICK_VISION_API_KEY", raising=False)

    response = _client().post("/chat", json=_page_turn("Which connector is this?", photo=PHOTO))

    assert response.status_code == 200
    assert response.json()["text"].startswith(UNSURE_LEAD)


@pytest.mark.parametrize(
    "body",
    [
        {"messages": [{"role": "user", "text": "Which connector is this?", "photo": PHOTO}]},
        {"messages": [{"role": "assistant", "text": "FAKE-ANSWER", "page": PAGE}]},
        {
            "messages": [
                {"role": "user", "text": "Which connector is this?", "page": PAGE, "photo": PHOTO},
                {"role": "user", "text": "And now?", "page": PAGE},
            ]
        },
        {**_page_turn(), "demo": {"photo_id": "FAKE-PHOTO"}},
        _page_turn(photo={"media_type": "image/jpeg", "data": base64.b64encode(b"FAKE").decode()}),
        _page_turn(photo={"media_type": "image/png", "data": PHOTO["data"]}),
        {"messages": [{"role": "user", "text": "Hi", "page": {"doc_id": "../etc", "page": 999}}]},
        {"messages": [{"role": "user", "text": "Hi", "page": {"doc_id": "FAKE-DOC", "page": "999"}}]},
        {"messages": [{"role": "user", "text": "Hi", "page": {"doc_id": "FAKE-DOC", "page": 0}}]},
    ],
)
def test_invalid_page_and_photo_shapes_are_rejected(body: dict[str, Any]) -> None:
    assert _client().post("/chat", json=body).status_code == 422


def test_unknown_manual_is_rejected() -> None:
    body = {"messages": [{"role": "user", "text": "Hi", "page": {"doc_id": "not-a-manual", "page": 999}}]}

    response = _client().post("/chat", json=body)

    assert response.status_code == 422
    assert response.json()["detail"] == "unknown manual page"
