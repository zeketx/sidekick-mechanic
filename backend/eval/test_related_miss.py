from __future__ import annotations

import json
from pathlib import Path

from chat_models import Conversation, GarageContext, GarageFactContext, Message
from eval.related_miss_score import cases
from general_advice import advise_on_miss, related_search_text, truck_prompt_line
from llm import FakeLLMClient
from producer import LlmAnswerProducer, _IndexRetriever
from retrieval import DEFAULT_K, Chunk, Fts5Index, build_index

_STEP = "FAKE-STEP: check the fixture relay."
_OFF_TOPIC = (
    "FAKE-HEADING: AUTOMATIC TRANSMISSION FAKE-AT-OIL-COOLER union nuts. "
    "Do not spend time turning them. Check the union before you look again."
)

_MISSES = (
    {
        "question": "My automatic fan is not turning on at start time",
        "on_doc": "FAKE-DOC-FAN",
        "on_text": "FAKE-HEADING: COOLING FAN FAKE-FAN-RELAY wiring.",
    },
    {
        "question": "Why does the fixture motor stumble?",
        "on_doc": "FAKE-DOC-MOTOR",
        "on_text": "FAKE-HEADING: the fixture motor can stumble on the bench.",
    },
    {
        "question": "The radiator is leaking coolant onto the driveway",
        "on_doc": "FAKE-DOC-RADIATOR",
        "on_text": "FAKE-HEADING: radiator leaking coolant at the driveway.",
    },
)


class _Hit:
    def __init__(self, doc_id: str, page: int, text: str) -> None:
        self.doc_id = doc_id
        self.page = page
        self.text = text


def _ask(question: str, hits: tuple[_Hit, ...], *, garage: GarageContext | None = None):
    fake = FakeLLMClient(text=json.dumps({"steps": [_STEP]}))
    payload = advise_on_miss(
        fake,
        Conversation(
            messages=[Message(role="user", text=question)],
            garage=garage,
        ),
        hits,
    )
    assert payload is not None
    return payload, fake


def test_three_misses_drop_the_off_topic_page_and_keep_the_model_step() -> None:
    for case in _MISSES:
        payload, _fake = _ask(case["question"], (_Hit("FAKE-DOC", 999, _OFF_TOPIC),))
        assert payload["related"] == []
        assert payload["steps"] == [_STEP]
        assert payload["garage"] == {"source": "none"}


def test_three_misses_keep_only_the_page_that_shares_a_focus_term() -> None:
    for case in _MISSES:
        payload, _fake = _ask(
            case["question"],
            (
                _Hit("FAKE-DOC", 999, _OFF_TOPIC),
                _Hit(case["on_doc"], 999, case["on_text"]),
            ),
        )
        assert payload["related"] == [
            {"doc_id": case["on_doc"], "page": 999, "snippet": case["on_text"]}
        ]
        assert payload["steps"] == [_STEP]


def test_garage_summary_names_the_vehicle_and_an_empty_garage_does_not() -> None:
    garage = GarageContext(
        facts=[
            GarageFactContext(label="Chassis", value="FAKE-TRUCK"),
            GarageFactContext(label="Engine", value="FAKE-ENGINE"),
        ]
    )
    question = _MISSES[0]["question"]
    with_garage, fake = _ask(question, (), garage=garage)
    without, bare = _ask(question, ())

    summary = "The garage summary names this vehicle: FAKE-TRUCK, engine FAKE-ENGINE."
    assert (
        truck_prompt_line(
            Conversation(messages=[Message(role="user", text=question)], garage=garage)
        )
        == summary
    )
    assert summary in fake.calls[0][0].content
    assert "FAKE-TRUCK" in fake.calls[0][0].content
    assert with_garage["steps"] == [_STEP]
    assert with_garage["garage"] == {
        "source": "garage",
        "truck": "FAKE-TRUCK",
        "engine": "FAKE-ENGINE",
    }
    assert "FAKE-TRUCK" not in bare.calls[0][0].content
    assert "Land Cruiser" not in bare.calls[0][0].content
    assert "do not name a vehicle" in bare.calls[0][0].content
    assert without["steps"] == [_STEP]
    assert without["garage"] == {"source": "none"}


def test_scored_cases_keep_on_topic_pages_in_input_order() -> None:
    for case in cases():
        hits = tuple(_Hit(page.doc_id, page.page, page.text) for page in case.pages)
        payload, _fake = _ask(case.question, hits)
        assert payload["related"] == [
            {"doc_id": page.doc_id, "page": page.page, "snippet": page.text}
            for page in case.pages
            if page.on_topic
        ]
        assert payload["steps"] == [_STEP]


def _condition_index(tmp_path: Path) -> Path:
    low_speed = " at low speed."
    pages = (
        ("FAKE-WIPER", "FAKE-HEADING: wiper motor runs" + low_speed),
        ("FAKE-PUMP", "FAKE-HEADING: fuel pump circuit" + low_speed),
        ("FAKE-FAN", "FAKE-HEADING: condenser fan" + low_speed),
        ("FAKE-ABS-FRONT", "FAKE-HEADING: front speed sensor" + low_speed),
        ("FAKE-ABS-REAR", "FAKE-HEADING: rear speed sensor" + low_speed),
        ("FAKE-TROUBLE", "FAKE-HEADING: brake troubleshooting squeal."),
        ("FAKE-SHIM", "FAKE-HEADING: anti-squeal shim."),
        ("FAKE-PAD", "FAKE-HEADING: front brake pad."),
        (
            "FAKE-SHAKE",
            "FAKE-HEADING: the truck shakes when a wheel is out of balance.",
        ),
        ("FAKE-AT-SPEED", "FAKE-HEADING: vehicle speed sensor circuit."),
        ("FAKE-BRAKE-SPEED", "FAKE-HEADING: brake speed sensor."),
    )
    chunks = []
    for doc_id, text in pages:
        body = text
        if "low speed" in text or doc_id.endswith("SPEED"):
            body = " ".join([text] * 6)
        chunks.append(Chunk(doc_id=doc_id, page=999, text=body))
    index_path = tmp_path / "index.sqlite"
    build_index(tuple(chunks), index_path)
    return index_path


def _miss(question: str, index_path: Path) -> dict:
    fake = FakeLLMClient(
        script=(
            json.dumps({"text": "", "citations": []}),
            json.dumps({"steps": [_STEP]}),
        )
    )
    payload = LlmAnswerProducer(fake, retriever=_IndexRetriever(index_path)).produce(
        Conversation(messages=[Message(role="user", text=question)])
    )
    assert payload is not None
    assert payload["kind"] == "general_advice"
    return payload


def test_related_search_prefers_the_fault_over_low_speed(tmp_path: Path) -> None:
    index_path = _condition_index(tmp_path)
    question = "Brakes squeal at low speed"
    assert related_search_text(question) == "Brakes squeal"

    with Fts5Index.open(index_path) as index:
        top = {hit.doc_id for hit in index.search(question, k=DEFAULT_K)}
    assert "FAKE-SHIM" not in top
    assert "FAKE-PAD" not in top
    assert "FAKE-ABS-FRONT" in top

    related = {item["doc_id"] for item in _miss(question, index_path)["related"]}
    assert related >= {"FAKE-TROUBLE", "FAKE-SHIM", "FAKE-PAD"}
    assert related.isdisjoint(
        {
            "FAKE-WIPER",
            "FAKE-PUMP",
            "FAKE-FAN",
            "FAKE-ABS-FRONT",
            "FAKE-ABS-REAR",
            "FAKE-AT-SPEED",
            "FAKE-BRAKE-SPEED",
        }
    )


def test_shake_related_search_drops_speed_sensors(tmp_path: Path) -> None:
    index_path = _condition_index(tmp_path)
    question = "My truck shakes at highway speed"
    assert related_search_text(question) == "truck shakes"

    related = {item["doc_id"] for item in _miss(question, index_path)["related"]}
    assert "FAKE-SHAKE" in related
    assert related.isdisjoint(
        {"FAKE-AT-SPEED", "FAKE-BRAKE-SPEED", "FAKE-ABS-FRONT", "FAKE-ABS-REAR"}
    )


def test_fan_later_than_the_shown_prefix_is_not_related() -> None:
    late = (
        "FAKE-HEADING: AUTOMATIC TRANSMISSION FAKE-AT-OIL-COOLER union nuts. "
        + ("FAKE-PAD " * 40)
        + "fan"
    )
    payload, _fake = _ask(_MISSES[0]["question"], (_Hit("FAKE-DOC", 999, late),))
    assert payload["related"] == []
    assert payload["steps"] == [_STEP]
