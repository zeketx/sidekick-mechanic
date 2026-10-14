"""Demo-mode catalog, resolver states, and scripted /chat requests."""

from __future__ import annotations

import json
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import create_app
from chat_models import Conversation, DemoRequest, Message
from contract import validate_answer
from demo import (
    DEMO_DEFAULT_PHOTO_ID,
    DEMO_DIAGRAM_POINTER,
    DEMO_DIM_FACTOR,
    DEMO_LABEL,
    DEMO_SYSTEM_PROMPT,
    apply_demo_resolution,
    bay_map_view_for_photo,
    catalog_public,
    confirm_highlight_config,
    has_photo,
    load_catalog,
    log_demo_feedback,
    match_part_from_question,
    resolve_demo_answer,
)
from general_advice import ADVICE_HONESTY
from llm import ChatTurn, LLMResult
from safety import SAFETY_NOTE
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


class _Page:
    def __init__(self, doc_id: str, page: int, text: str) -> None:
        self.doc_id = doc_id
        self.page = page
        self.text = text


class _Pages:
    def search(self, query: str, k: int = 5) -> tuple[_Page, ...]:
        del query, k
        return (
            _Page("FAKE-DOC", 999, "FAKE-CHUNK: throttle body has no part location."),
        )


def test_confirm_dim_is_in_the_visible_band() -> None:
    config = confirm_highlight_config()
    assert config.dim_factor == DEMO_DIM_FACTOR
    assert 0.35 <= config.dim_factor <= 0.45
    assert config.outline_width_px == 4
    assert config.saturation_factor == 2.0


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
    assert public["default_photo_id"] == DEMO_DEFAULT_PHOTO_ID
    assert public["photos"][1]["share_alike"] is True
    assert public["photos"][1]["short_name"] == "Hilux"
    assert public["photos"][0]["short_name"] == "2JZ-GE prototype"
    assert public["photos"][2]["short_name"] == "Supra (2JZ-GTE)"
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
    assert payload["text"] == "Check the throttle body on the demo photo."
    assert "1990 Toyota" not in payload["text"]
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
    assert payload["text"] == "The intake plenum is the large chamber."
    assert "1990 Toyota" not in payload["text"]


def test_not_found_state_omits_highlight_and_points_at_diagram() -> None:
    original = _answer("Coil packs sit on the valve cover.")
    payload = resolve_demo_answer(original, _selection("coil-packs"), HRYMX)
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"].startswith("coil packs — not visible in this photo.")
    assert payload["text"].endswith(DEMO_DIAGRAM_POINTER)
    assert original["text"] not in payload["text"]


def test_part_absent_from_photo_is_not_found() -> None:
    payload = resolve_demo_answer(
        _answer("Where is the fuse box?"),
        _selection("fuse-relay-box"),
        HRYMX,
    )
    validate_answer(payload)
    assert "highlight" not in payload
    assert "not visible in this photo" in payload["text"]
    assert payload["text"].endswith(DEMO_DIAGRAM_POINTER)


def test_null_selection_leaves_text_and_omits_highlight() -> None:
    original = _answer()
    payload = resolve_demo_answer(original, _selection(None), HRYMX)
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"] == original["text"]
    assert DEMO_DIAGRAM_POINTER not in payload["text"]


def test_refusal_keeps_its_text_and_gains_the_outline() -> None:
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
    assert payload["kind"] == "refusal"
    assert payload["text"] == "Not found in the manual."
    assert payload["reason"] == "not_found_in_manual"
    assert "citations" not in payload
    assert payload["highlight"]["part_id"] == "throttle-body"
    assert payload["highlight"]["demo"] is True
    assert "1990 Toyota" not in payload["text"]


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
    ("question", "part_id", "display"),
    [
        ("where's the throttle body?", "throttle-body", "outline"),
        ("where is the throttle body", "throttle-body", "outline"),
        ("show me the intake plenum", "intake-plenum", "confirm"),
    ],
)
def test_scripted_chat_resolves_plain_question_not_reply(
    question: str,
    part_id: str,
    display: str,
) -> None:
    model_text = "I do not know the make or model of this engine."
    fake = _ScriptedLLM([_result(model_text)])
    client = _demo_client(LlmAnswerProducer(fake))
    response = client.post("/chat", json=_demo_body(question))
    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["highlight"]["display"] == display
    assert payload["highlight"]["part_id"] == part_id
    assert payload["highlight"]["demo"] is True
    assert payload["highlight"]["geometry"]["polygons"]
    assert payload["text"] == model_text
    assert "1990 Toyota" not in payload["text"]
    assert len(fake.calls) == 1
    assert fake.calls[0][0].content == DEMO_SYSTEM_PROMPT


def test_scripted_chat_not_found_omits_highlight() -> None:
    fake = _ScriptedLLM([_result("I do not know the make or model of this engine.")])
    client = _demo_client(LlmAnswerProducer(fake))
    response = client.post("/chat", json=_demo_body("where are the coil packs?"))
    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert "highlight" not in payload
    assert "not visible in this photo" in payload["text"]
    assert DEMO_DIAGRAM_POINTER in payload["text"]
    assert len(fake.calls) == 1


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
    response = _demo_client(LlmAnswerProducer(_ScriptedLLM([_result("unused")]))).post(
        "/chat", json=_demo_body("hello", photo_id="not-a-demo-photo")
    )
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


def test_producer_resolves_from_question_without_a_second_llm_call() -> None:
    scripted = _ScriptedLLM([_result("I do not know the make or model.")])
    payload = LlmAnswerProducer(scripted).produce(
        Conversation(
            messages=[Message(role="user", text="where's the throttle body?")],
            demo=DemoRequest(photo_id=HRYMX),
        )
    )
    validate_answer(payload)
    assert payload["highlight"]["part_id"] == "throttle-body"
    assert payload["text"] == "I do not know the make or model."
    assert "1990 Toyota" not in payload["text"]
    assert len(scripted.calls) == 1
    assert scripted.calls[0][0].content == DEMO_SYSTEM_PROMPT


def test_empty_citations_still_attach_the_demo_outline() -> None:
    step = "FAKE-STEP: check the fixture connection before the fixture motor."
    chunk = "FAKE-CHUNK: throttle body has no part location."
    fake = _ScriptedLLM(
        [
            _result('{"text":"no page","citations":[]}'),
            _result(json.dumps({"steps": [step]})),
            _result(json.dumps({"related": [True]})),
        ]
    )
    response = _demo_client(LlmAnswerProducer(fake, retriever=_Pages())).post(
        "/chat",
        json=_demo_body("where's the throttle body?"),
    )
    assert response.status_code == 200
    payload = response.json()
    validate_answer(payload)
    assert payload["kind"] == "general_advice"
    assert payload["honesty"] == ADVICE_HONESTY
    assert payload["safety"] == SAFETY_NOTE
    assert payload["steps"] == [step]
    assert "Land Cruiser" not in json.dumps(payload["steps"])
    assert payload["garage"] == {"source": "none"}
    assert payload["related"] == [
        {
            "doc_id": "FAKE-DOC",
            "page": 999,
            "snippet": chunk,
        }
    ]
    assert payload["highlight"]["part_id"] == "throttle-body"
    assert payload["highlight"]["display"] == "outline"
    assert payload["highlight"]["demo"] is True
    assert "no page" not in payload["steps"][0]
    assert "not visible in this photo" not in json.dumps(payload)
    assert len(fake.calls) == 3


def test_general_advice_not_visible_keeps_the_checks() -> None:
    step = "FAKE-STEP: look at the fixture."
    advice = {
        "kind": "general_advice",
        "honesty": ADVICE_HONESTY,
        "safety": SAFETY_NOTE,
        "steps": [step],
        "garage": {"source": "garage", "engine": "TBD"},
        "related": [{"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SNIPPET"}],
    }
    payload = resolve_demo_answer(advice, _selection("coil-packs"), HRYMX)
    validate_answer(payload)
    assert payload["honesty"] == ADVICE_HONESTY
    assert payload["steps"] == [step]
    assert payload["garage"] == {"source": "garage", "engine": "TBD"}
    assert payload["related"] == advice["related"]
    assert "highlight" not in payload
    assert "text" not in payload
    assert "not visible in this photo" not in json.dumps(payload)


def test_unmatched_question_leaves_llm_text_and_omits_highlight() -> None:
    payload = LlmAnswerProducer(
        _ScriptedLLM([_result("FAKE reply with no specs.")])
    ).produce(
        Conversation(
            messages=[Message(role="user", text="why is it hard to start?")],
            demo=DemoRequest(photo_id=HRYMX),
        )
    )
    validate_answer(payload)
    assert "highlight" not in payload
    assert payload["text"] == "FAKE reply with no specs."
    assert DEMO_DIAGRAM_POINTER not in payload["text"]


@pytest.mark.parametrize(
    ("question", "part_id"),
    [
        ("where's the throttle body?", "throttle-body"),
        ("where is the throttle body", "throttle-body"),
        ("show me the intake plenum", "intake-plenum"),
        ("where are the coil packs?", "coil-packs"),
        ("where's the fuse box?", "fuse-relay-box"),
    ],
)
def test_plain_phrasing_matches_the_photo_part(question: str, part_id: str) -> None:
    photo_id = HILUX if part_id == "fuse-relay-box" else HRYMX
    photo = load_catalog().photo(photo_id)
    assert photo is not None
    matched = match_part_from_question(question, photo)
    assert matched is not None
    assert matched.part_id == part_id


def test_fuse_box_on_hrymx_does_not_match() -> None:
    photo = load_catalog().photo(HRYMX)
    assert photo is not None
    assert match_part_from_question("where's the fuse box?", photo) is None
