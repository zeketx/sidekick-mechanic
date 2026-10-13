"""General advice when the manual has no page. Fixtures only. No vehicle specs."""

from __future__ import annotations

import json

from chat_models import (
    Conversation,
    GarageContext,
    GarageFactContext,
    GarageNoteContext,
    GarageTodoContext,
    Message,
)
from general_advice import (
    ADVICE_HONESTY,
    ADVICE_STEPS_HEADER,
    advise_on_miss,
    parse_steps,
)
from llm import RETRIEVED_PAGES_HEADER, FakeLLMClient
from safety import SAFETY_NOTE

_STEP = "FAKE-STEP: check the fixture connection before the fixture motor."
_HIT_SNIPPET = "FAKE-SNIPPET from the fixture motor hit."


class _Hit:
    def __init__(self, doc_id: str, page: int, text: str) -> None:
        self.doc_id = doc_id
        self.page = page
        self.text = text


def _conversation() -> Conversation:
    return Conversation(
        messages=[Message(role="user", text="Why does the fixture motor stumble?")],
        garage=GarageContext(
            facts=[
                GarageFactContext(label="Engine", value="   "),
                GarageFactContext(label="Chassis", value="FAKE-TRUCK"),
                GarageFactContext(label="Engine", value="TBD"),
                GarageFactContext(label="Chassis", value="LATER-TRUCK"),
                GarageFactContext(label="Notes", value="not a basis field"),
            ],
            notes=[
                GarageNoteContext(name="Harness", note="FAKE-NOTE already replaced")
            ],
            open_todos=[GarageTodoContext(title="FAKE-TODO check the spare")],
        ),
    )


def test_engine_tbd_round_trips_and_the_prompt_omits_page_text() -> None:
    page = "FAKE-PAGE-TEXT that must stay out of the advice prompt."
    model = json.dumps(
        {
            "steps": ["1. " + _STEP],
            "related": [{"doc_id": "MODEL-PICKED", "page": 4, "snippet": page}],
            "text": page,
        }
    )
    fake = FakeLLMClient(text=model)
    hits = (
        _Hit("FAKE-DOC", 999, _HIT_SNIPPET),
        _Hit("FAKE-DOC", 999, "FAKE-SNIPPET duplicate page."),
        _Hit("FAKE-OTHER", 999, "   "),
    )

    payload = advise_on_miss(fake, _conversation(), hits)

    assert payload is not None
    assert payload["garage"] == {
        "source": "garage",
        "truck": "FAKE-TRUCK",
        "engine": "TBD",
    }
    assert payload["honesty"] == ADVICE_HONESTY
    assert payload["safety"] == SAFETY_NOTE
    assert payload["steps"] == [_STEP]
    assert payload["related"] == [
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": _HIT_SNIPPET}
    ]
    assert "MODEL-PICKED" not in json.dumps(payload)
    assert "notes" not in payload["garage"]
    system = fake.calls[0][0].content
    assert ADVICE_STEPS_HEADER in system
    assert RETRIEVED_PAGES_HEADER not in system
    assert page not in system
    assert _HIT_SNIPPET not in system
    assert "FAKE-NOTE already replaced" in system
    assert "FAKE-TODO check the spare" in system
    assert "Garage notes are not a manual page." in system
    assert "The garage summary names this vehicle: FAKE-TRUCK, engine TBD." in system
    assert "Land Cruiser" not in system
    assert "household-appliance" in system
    assert "Demo photos" not in system


def test_parse_keeps_five_cleaned_steps_and_drops_a_long_one() -> None:
    long_step = "Y" * 501
    raw = json.dumps(
        {
            "steps": [
                "   ",
                "1. FAKE-STEP: first",
                "2) FAKE-STEP: second",
                "Step 1: FAKE-STEP: third",
                long_step,
                "FAKE-STEP: fourth",
                "FAKE-STEP: fifth",
                "FAKE-STEP: sixth",
            ],
            "citations": [{"doc_id": "IGNORED", "page": 1, "snippet": "nope"}],
        }
    )

    assert parse_steps(raw) == [
        "FAKE-STEP: first",
        "FAKE-STEP: second",
        "FAKE-STEP: third",
        "FAKE-STEP: fourth",
        "FAKE-STEP: fifth",
    ]
    assert long_step[:500] not in (parse_steps(raw) or [])


def test_parse_keeps_a_decimal_measurement() -> None:
    raw = json.dumps({"steps": ["12.7 Nm", "1. FAKE-STEP: after the measurement"]})

    assert parse_steps(raw) == ["12.7 Nm", "FAKE-STEP: after the measurement"]


def test_advice_prompt_omits_prior_assistant_text() -> None:
    conversation = Conversation(
        messages=[
            Message(role="user", text="What is the fixture torque?"),
            Message(role="assistant", text="The cited page says 999 Nm."),
            Message(role="user", text="The fixture motor still will not start."),
        ]
    )
    fake = FakeLLMClient(
        text=json.dumps({"steps": ["FAKE-STEP: check the connection."]})
    )

    assert advise_on_miss(fake, conversation, ()) is not None
    sent = "\n".join(turn.content for turn in fake.calls[0])
    assert "999 Nm" not in sent
    assert "The fixture motor still will not start." in sent


def test_writer_failure_is_none() -> None:
    fake = FakeLLMClient(text="not json")
    assert advise_on_miss(fake, _conversation(), ()) is None
    assert (
        advise_on_miss(FakeLLMClient(text='{"steps": ["   "]}'), _conversation(), ())
        is None
    )
