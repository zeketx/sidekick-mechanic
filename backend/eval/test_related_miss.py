from __future__ import annotations

import json

from chat_models import Conversation, GarageContext, GarageFactContext, Message
from general_advice import advise_on_miss, truck_prompt_line
from llm import FakeLLMClient

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


def test_fan_later_than_the_shown_prefix_is_not_related() -> None:
    late = (
        "FAKE-HEADING: AUTOMATIC TRANSMISSION FAKE-AT-OIL-COOLER union nuts. "
        + ("FAKE-PAD " * 40)
        + "fan"
    )
    payload, _fake = _ask(_MISSES[0]["question"], (_Hit("FAKE-DOC", 999, late),))
    assert payload["related"] == []
    assert payload["steps"] == [_STEP]
