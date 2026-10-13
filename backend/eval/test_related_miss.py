from __future__ import annotations

import json

from chat_models import Conversation, Message
from general_advice import advise_on_miss
from llm import FakeLLMClient

_QUESTION = "My automatic fan is not turning on at start time"
_FAN_CHECK = (
    "On this 1990 Toyota Land Cruiser LJ78 with a 2JZ-GE swap, "
    "look at the engine cooling fan before you take anything apart."
)
_OFF_TOPIC = (
    "FAKE-HEADING: AUTOMATIC TRANSMISSION FAKE-AT-OIL-COOLER union nuts."
)
_ON_TOPIC = "FAKE-HEADING: COOLING FAN FAKE-FAN-RELAY wiring."
_FAN_CITATION = {
    "doc_id": "FAKE-DOC-FAN",
    "page": 999,
    "snippet": _ON_TOPIC,
}


class _Hit:
    def __init__(self, doc_id: str, page: int, text: str) -> None:
        self.doc_id = doc_id
        self.page = page
        self.text = text


def _conversation() -> Conversation:
    return Conversation(messages=[Message(role="user", text=_QUESTION)])


def test_off_topic_page_is_not_related() -> None:
    fake = FakeLLMClient(
        text=json.dumps({"steps": ["FAKE-STEP: check the fixture relay."]})
    )
    payload = advise_on_miss(
        fake,
        _conversation(),
        (_Hit("FAKE-DOC", 999, _OFF_TOPIC),),
    )

    assert payload is not None
    assert payload["related"] == []
    assert payload["steps"][0] == _FAN_CHECK
    assert payload["garage"] == {"source": "none"}


def test_mixed_hits_keep_only_the_fan_page() -> None:
    fake = FakeLLMClient(
        text=json.dumps({"steps": ["FAKE-STEP: check the fixture relay."]})
    )
    payload = advise_on_miss(
        fake,
        _conversation(),
        (
            _Hit("FAKE-DOC", 999, _OFF_TOPIC),
            _Hit("FAKE-DOC-FAN", 999, _ON_TOPIC),
        ),
    )

    assert payload is not None
    assert payload["related"] == [_FAN_CITATION]
    assert payload["steps"][0] == _FAN_CHECK
    assert payload["garage"] == {"source": "none"}


def test_first_check_is_stable_across_model_strings() -> None:
    first = advise_on_miss(
        FakeLLMClient(
            text=json.dumps({"steps": ["FAKE-STEP: check the fixture relay."]})
        ),
        _conversation(),
        (_Hit("FAKE-DOC", 999, _OFF_TOPIC),),
    )
    second = advise_on_miss(
        FakeLLMClient(
            text=json.dumps({"steps": ["FAKE-STEP: inspect the fixture fuse."]})
        ),
        _conversation(),
        (_Hit("FAKE-DOC", 999, _OFF_TOPIC),),
    )

    assert first is not None
    assert second is not None
    assert first["steps"][0] == second["steps"][0] == _FAN_CHECK
