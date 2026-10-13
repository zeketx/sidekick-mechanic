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
        _Hit("FAKE-DOC", 999, "FAKE-SNIPPET from the hit."),
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
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SNIPPET from the hit."}
    ]
    assert "MODEL-PICKED" not in json.dumps(payload)
    assert "notes" not in payload["garage"]
    system = fake.calls[0][0].content
    assert ADVICE_STEPS_HEADER in system
    assert RETRIEVED_PAGES_HEADER not in system
    assert page not in system
    assert "FAKE-SNIPPET from the hit." not in system
    assert "FAKE-NOTE already replaced" in system
    assert "FAKE-TODO check the spare" in system
    assert "Garage notes are not a manual page." in system


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


def test_writer_failure_is_none() -> None:
    fake = FakeLLMClient(text="not json")
    assert advise_on_miss(fake, _conversation(), ()) is None
    assert (
        advise_on_miss(FakeLLMClient(text='{"steps": ["   "]}'), _conversation(), ())
        is None
    )
