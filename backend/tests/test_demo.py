"""Demo-mode catalog, resolver states, and scripted /chat requests."""

from __future__ import annotations

from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import Conversation, DemoRequest, Message
from contract import validate_answer
from demo import (
    DEMO_DIAGRAM_POINTER,
    DEMO_LABEL,
    apply_demo_resolution,
    bay_map_view_for_photo,
    catalog_public,
    has_photo,
    load_catalog,
    log_demo_feedback,
    resolve_demo_answer,
)
from llm import ChatTurn, LLMError, LLMResult
from part_resolver import Resolution, ResolutionKind
from producer import LlmAnswerProducer, SYSTEM_PROMPT

HRYMX = "hrymx-2jz-ge-25308847029"
HILUX = "commons-hilux-2jz"


def _answer(text: str = "Check the throttle body on the demo photo.") -> dict[str, Any]:
    return {
        "kind": "answer",
        "text": text,
        "citations": [
            {
                "doc_id": "FAKE-DOC",
                "page": 999,
                "snippet": "FAKE-SNIPPET",
            }
        ],
    }


def _selection(part_id: str | None) -> str:
    if part_id is None:
        return '{"part_id": null}'
    return f'{{"part_id": "{part_id}"}}'


class _ScriptedLLM:
    def __init__(self, results: list[LLMResult | Exception]) -> None:
        self._results = list(results)
        self.calls: list[list[ChatTurn]] = []

    def complete(self, messages: list[ChatTurn]) -> LLMResult:
        self.calls.append(list(messages))
        item = self._results.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def _result(text: str) -> LLMResult:
    return LLMResult(text=text, model="fake", usage=None)


def test_catalog_loads_four_photos_and_attribution() -> None:
    catalog = load_catalog()
    ids = catalog.photo_ids()
    assert ids == (
        "hrymx-2jz-ge-25308847029",
        "commons-hilux-2jz",
        "commons-supra-n5abh",
        "flickr-robmarson-6763892857",
    )
    hilux = catalog.photo(HILUX)
    assert hilux is not None
    assert hilux.share_alike is True
    assert "CC BY-SA 3.0" in hilux.attribution
    assert hilux.image_path.is_file()
    public = catalog_public()
    assert public["demo"] is True
    assert public["label"] == DEMO_LABEL
    assert public["photos"][1]["share_alike"] is True
    assert has_photo(HRYMX) is True
    assert has_photo("missing-photo") is False


def test_closed_list_is_only_that_photo() -> None:
    hrymx = bay_map_view_for_photo(HRYMX)
    hilux = bay_map_view_for_photo(HILUX)
    assert hrymx.part_ids() == ("throttle-body", "intake-plenum", "coil-packs")
    assert "fuse-relay-box" not in hrymx.part_ids()
    assert "fuse-relay-box" in hilux.part_ids()
    assert "throttle-body" not in hilux.part_ids()


def test_outline_state_returns_demo_geometry() -> None:
    payload = resolve_demo_answer(_answer(), _selection("throttle-body"), HRYMX)
    validate_answer(payload)
    highlight = payload["highlight"]
    assert highlight["bay_photo_id"] == HRYMX
    assert highlight["part_id"] == "throttle-body"
    assert highlight["display"] == "outline"
    assert highlight["demo"] is True
    assert len(highlight["geometry"]["polygons"]) == 1
    assert len(highlight["geometry"]["polygons"][0]["points"]) >= 3
    assert highlight["geometry"]["polygons"][0]["points"][0] == {
        "x": 0.75586,
        "y": 0.46413,
    }
    assert DEMO_DIAGRAM_POINTER not in payload["text"]
    assert payload["citations"][0]["page"] == 999


def test_confirm_state_returns_softer_display() -> None:
    payload = resolve_demo_answer(
        _answer("The intake plenum is the large chamber."),
        _selection("intake-plenum"),
        HRYMX,
    )
    validate_answer(payload)
    assert payload["highlight"]["display"] == "confirm"
    assert payload["highlight"]["demo"] is True
    assert payload["highlight"]["part_id"] == "intake-plenum"
    assert payload["highlight"]["geometry"]["polygons"][0]["points"][0]["x"] == 0.53125


def test_not_found_state_omits_highlight_and_points_at_diagram() -> None:
    original = _answer("Coil packs sit on the valve cover.")
    payload = resolve_demo_answer(original, _selection("coil-packs"), HRYMX)
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"] == f"{original['text']} {DEMO_DIAGRAM_POINTER}"


def test_part_absent_from_photo_is_not_found() -> None:
    payload = resolve_demo_answer(
        _answer("Where is the fuse box?"),
        _selection("fuse-relay-box"),
        HRYMX,
    )
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"].endswith(DEMO_DIAGRAM_POINTER)


def test_null_selection_leaves_text_and_omits_highlight() -> None:
    original = _answer()
    payload = resolve_demo_answer(original, _selection(None), HRYMX)
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"] == original["text"]
    assert DEMO_DIAGRAM_POINTER not in payload["text"]


def test_refusal_never_gains_demo_highlight() -> None:
    refusal = {
        "kind": "refusal",
        "text": "Not found in the manual.",
        "reason": "not_found_in_manual",
        "highlight": {
            "bay_photo_id": HRYMX,
            "part_id": "throttle-body",
        },
    }
    payload = apply_demo_resolution(
        refusal,
        Resolution(
            kind=ResolutionKind.HIGHLIGHT,
            part_id="throttle-body",
            bay_photo_id=HRYMX,
            angle_id="demo",
        ),
        HRYMX,
    )
    validate_answer(payload)
    assert payload == {
        "kind": "refusal",
        "text": "Not found in the manual.",
        "reason": "not_found_in_manual",
    }


def test_multi_ring_confirm_keeps_both_polygons() -> None:
    payload = resolve_demo_answer(
        _answer("Radiator cap and upper hose."),
        _selection("radiator-cap-upper-hose"),
        "commons-supra-n5abh",
    )
    validate_answer(payload)
    assert payload["highlight"]["display"] == "confirm"
    assert len(payload["highlight"]["geometry"]["polygons"]) == 2


def test_invalid_demo_display_fails_schema() -> None:
    payload = resolve_demo_answer(_answer(), _selection("throttle-body"), HRYMX)
    payload["highlight"]["display"] = "not_found"
    with pytest.raises(Exception, match="not_found|enum|display"):
        validate_answer(payload)


def test_legacy_highlight_fixture_still_validates() -> None:
    validate_answer(
        {
            "kind": "answer",
            "text": "Look at the fake intake area on the fixture bay photo.",
            "citations": [
                {
                    "doc_id": "FAKE-DOC-2JZ",
                    "page": 999,
                    "snippet": "FAKE-SNIPPET: check the mapped fixture part.",
                }
            ],
            "highlight": {
                "bay_photo_id": "fake-bay-photo-front",
                "part_id": "fake-part-intake",
            },
        }
    )


def test_demo_feedback_logs_tap(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level("INFO", logger="sidekick.demo")
    payload = log_demo_feedback(
        photo_id=HRYMX,
        part_id="intake-plenum",
        action="not_this",
    )
    assert payload == {"ok": True, "demo": True}
    assert "demo confirm tap" in caplog.text
    assert HRYMX in caplog.text
    assert "not_this" in caplog.text


def _demo_client(producer: LlmAnswerProducer) -> TestClient:
    return TestClient(create_app(producer=producer))


def _demo_body(text: str, photo_id: str = HRYMX) -> dict[str, Any]:
    return {
        "messages": [{"role": "user", "text": text}],
        "demo": {"photo_id": photo_id},
    }


@pytest.mark.parametrize(
    ("question", "answer_text", "part_id", "display"),
    [
        (
            "where's the throttle body?",
            "The throttle body is on the intake side of this demo photo.",
            "throttle-body",
            "outline",
        ),
        (
            "show me the intake plenum",
            "The intake plenum is the large chamber on this demo photo.",
            "intake-plenum",
            "confirm",
        ),
    ],
)
def test_scripted_chat_returns_each_highlight_state(
    question: str,
    answer_text: str,
    part_id: str,
    display: str,
) -> None:
    client = _demo_client(
        LlmAnswerProducer(
            _ScriptedLLM([_result(answer_text), _result(_selection(part_id))])
        )
    )
    response = client.post("/chat", json=_demo_body(question))
    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["highlight"]["display"] == display
    assert payload["highlight"]["part_id"] == part_id
    assert payload["highlight"]["demo"] is True
    assert payload["highlight"]["geometry"]["polygons"]


def test_scripted_chat_not_found_omits_highlight() -> None:
    client = _demo_client(
        LlmAnswerProducer(
            _ScriptedLLM(
                [
                    _result("Coil packs sit on the valve cover of this engine."),
                    _result(_selection("coil-packs")),
                ]
            )
        )
    )
    response = client.post("/chat", json=_demo_body("where are the coil packs?"))
    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert "highlight" not in payload
    assert DEMO_DIAGRAM_POINTER in payload["text"]


def test_chat_without_demo_does_not_select_a_demo_part() -> None:
    fake = _ScriptedLLM([_result("FAKE reply with no specs.")])
    response = _demo_client(LlmAnswerProducer(fake)).post(
        "/chat",
        json={"messages": [{"role": "user", "text": "where's the throttle body?"}]},
    )
    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert "highlight" not in payload
    assert len(fake.calls) == 1
    assert fake.calls[0][0].content == SYSTEM_PROMPT


def test_unknown_demo_photo_is_rejected() -> None:
    response = _demo_client(
        LlmAnswerProducer(_ScriptedLLM([_result("unused")]))
    ).post("/chat", json=_demo_body("hello", photo_id="not-a-demo-photo"))
    assert response.status_code == 422
    assert response.json() == {"detail": "unknown demo photo"}


def test_demo_catalog_and_image_routes() -> None:
    client = TestClient(create_app())
    listing = client.get("/demo/photos")
    assert listing.status_code == 200
    body = listing.json()
    assert body["demo"] is True
    assert len(body["photos"]) == 4
    image = client.get(f"/demo/photos/{HRYMX}/image")
    assert image.status_code == 200
    assert image.headers["content-type"].startswith("image/jpeg")
    assert image.content[:3] == b"\xff\xd8\xff"
    missing = client.get("/demo/photos/missing-photo/image")
    assert missing.status_code == 404
    attribution = client.get("/demo/attribution")
    assert attribution.status_code == 200
    assert "CC BY-SA 3.0" in attribution.text
    assert "Miguel Sanchez 2JZ" in attribution.text


def test_demo_feedback_route(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level("INFO", logger="sidekick.demo")
    client = TestClient(create_app())
    response = client.post(
        "/demo/feedback",
        json={"photo_id": HRYMX, "part_id": "intake-plenum", "action": "yes"},
    )
    assert response.status_code == 200
    assert response.json() == {"ok": True, "demo": True}
    assert "action=yes" in caplog.text
    bad = client.post(
        "/demo/feedback",
        json={"photo_id": "missing-photo", "part_id": "intake-plenum", "action": "yes"},
    )
    assert bad.status_code == 422


def test_producer_demo_map_lists_only_photo_parts() -> None:
    scripted = _ScriptedLLM(
        [
            _result("The throttle body is on this demo photo."),
            _result(_selection("throttle-body")),
        ]
    )
    payload = LlmAnswerProducer(scripted).produce(
        Conversation(
            messages=[Message(role="user", text="where's the throttle body?")],
            demo=DemoRequest(photo_id=HRYMX),
        )
    )
    validate_answer(payload)
    assert payload["highlight"]["part_id"] == "throttle-body"
    closed = scripted.calls[1][1].content
    assert "throttle-body" in closed
    assert "fuse-relay-box" not in closed


def test_demo_selection_failure_omits_highlight(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level("WARNING")
    payload = LlmAnswerProducer(
        _ScriptedLLM(
            [
                _result("The throttle body is on this demo photo."),
                LLMError("selection timed out"),
            ]
        )
    ).produce(
        Conversation(
            messages=[Message(role="user", text="where's the throttle body?")],
            demo=DemoRequest(photo_id=HRYMX),
        )
    )
    validate_answer(payload)
    assert "highlight" not in payload
    assert DEMO_DIAGRAM_POINTER not in payload["text"]
    assert "part selection failed" in caplog.text
