"""General advice when the manual has no page. Fixtures only. No vehicle specs."""

from __future__ import annotations

import json
import logging

import pytest

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
    JUDGE_TIMEOUT_S,
    RELEVANCE_HEADER,
    advise_on_miss,
    judge_pages,
    parse_steps,
)
from llm import RETRIEVED_PAGES_HEADER, ChatTurn, FakeLLMClient, LLMError, LLMResult
from safety import SAFETY_NOTE

_STEP = "FAKE-STEP: check the fixture connection before the fixture motor."
_HIT_SNIPPET = "FAKE-SNIPPET: the fixture motor can stumble."


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


_UNSURE_PAGE = (
    "FAKE-HEADING: inspection procedure.\nThe fixture motor can stumble."
)


def test_relevance_true_keeps_the_page_and_a_bad_check_shows_none() -> None:
    class _Writer:
        def __init__(self, second: str | Exception) -> None:
            self.second = second
            self.calls: list[list[ChatTurn]] = []

        def complete(self, messages: list[ChatTurn]) -> LLMResult:
            self.calls.append(list(messages))
            if len(self.calls) == 1:
                return LLMResult(
                    text=json.dumps({"steps": [_STEP]}),
                    model="fake",
                    usage=None,
                )
            if isinstance(self.second, Exception):
                raise self.second
            return LLMResult(text=self.second, model="fake", usage=None)

    hits = (_Hit("FAKE-DOC", 999, _UNSURE_PAGE),)
    yes = json.dumps({"pages": [{"id": 0, "answer": "yes"}]})
    writer = _Writer(yes)
    kept = advise_on_miss(writer, _conversation(), hits)
    assert kept is not None
    assert kept["related"] == [
        {"doc_id": "FAKE-DOC", "page": 999, "snippet": _UNSURE_PAGE}
    ]
    assert kept["steps"] == [_STEP]
    assert len(writer.calls) == 2
    instructions = writer.calls[1][0].content
    assert "only mentioned as a cause" in instructions
    assert "same assembly" in instructions
    assert "yes or no" in instructions

    for second in (
        "not json",
        "yes no",
        "1",
        LLMError("relevance failed"),
    ):
        payload = advise_on_miss(_Writer(second), _conversation(), hits)
        assert payload is not None
        assert payload["related"] == []
        assert payload["steps"] == [_STEP]


def _ranked_hits(count: int) -> tuple[_Hit, ...]:
    return tuple(
        _Hit(
            f"FAKE-DOC-{index}",
            999,
            "FAKE-HEADING: inspection procedure.\n"
            f"The fixture motor can stumble. FAKE-DOC-{index} ranked page.",
        )
        for index in range(count)
    )


class _YesPages:
    def __init__(self, yes_ids: set[str]) -> None:
        self.yes_ids = yes_ids
        self.calls: list[list[ChatTurn]] = []

    def complete(self, messages: list[ChatTurn]) -> LLMResult:
        self.calls.append(list(messages))
        if len(self.calls) == 1:
            return LLMResult(
                text=json.dumps({"steps": [_STEP]}),
                model="fake",
                usage=None,
            )
        raw = messages[-1].content.split(RELEVANCE_HEADER, 1)[1]
        payload = json.loads(raw)
        pages = [
            {
                "id": item["id"],
                "answer": (
                    "yes" if any(doc_id in item["snippet"] for doc_id in self.yes_ids) else "no"
                ),
            }
            for item in payload["pages"]
        ]
        return LLMResult(
            text=json.dumps({"pages": pages}), model="fake", usage=None
        )


def test_related_keep_stops_at_three_best_first() -> None:
    hits = _ranked_hits(10)
    writer = _YesPages({hit.doc_id for hit in hits})
    payload = advise_on_miss(writer, _conversation(), hits)
    assert payload is not None
    assert [item["doc_id"] for item in payload["related"]] == [
        "FAKE-DOC-0",
        "FAKE-DOC-1",
        "FAKE-DOC-2",
    ]
    judged = "\n".join(turn.content for call in writer.calls for turn in call)
    assert "FAKE-DOC-7" in judged
    assert "FAKE-DOC-8" not in judged
    assert "FAKE-DOC-9" not in judged
    assert len(writer.calls) == 2


def test_related_keep_shows_one_yes_inside_the_window() -> None:
    hits = _ranked_hits(10)
    writer = _YesPages({"FAKE-DOC-4", "FAKE-DOC-9"})
    payload = advise_on_miss(writer, _conversation(), hits)
    assert payload is not None
    assert [item["doc_id"] for item in payload["related"]] == ["FAKE-DOC-4"]
    judged = "\n".join(turn.content for call in writer.calls for turn in call)
    assert "FAKE-DOC-9" not in judged


def test_writer_failure_is_none() -> None:
    fake = FakeLLMClient(text="not json")
    assert advise_on_miss(fake, _conversation(), ()) is None
    assert (
        advise_on_miss(FakeLLMClient(text='{"steps": ["   "]}'), _conversation(), ())
        is None
    )


def test_writer_failure_logs_parse_rejection(
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.WARNING, logger="sidekick.llm")

    assert advise_on_miss(FakeLLMClient(text="not json"), _conversation(), ()) is None

    assert "kind=parse" in caplog.text
    assert "detail=advice_steps" in caplog.text
    assert "not json" not in caplog.text


def test_a_heading_skips_the_model_and_a_cause_aside_is_no() -> None:
    class _Boom:
        def complete(self, messages: list[ChatTurn]) -> LLMResult:
            raise AssertionError(messages)

    flags = judge_pages(
        _Boom(),
        "The radiator fan is not spinning",
        (
            "FAKE-HEADING: radiator fan does not spin.",
            (
                "DTC P9999 FAKE engine overcooling.\n"
                "Possible cause: abnormal radiator fan operation."
            ),
        ),
        keep_on_error=True,
    )

    assert flags == [True, False]


def test_one_based_batch_ids_and_a_failed_judge() -> None:
    class _Client:
        def __init__(self, text: str | Exception) -> None:
            self.text = text
            self.kwargs: dict[str, object] = {}

        def complete(
            self,
            messages: list[ChatTurn],
            *,
            timeout_s: float | None = None,
            attempts: int | None = None,
        ) -> LLMResult:
            self.kwargs = {"timeout_s": timeout_s, "attempts": attempts}
            if isinstance(self.text, Exception):
                raise self.text
            return LLMResult(text=self.text, model="fake", usage=None)

    unsure = (
        "FAKE-HEADING: inspection procedure.\nThe radiator fan relay is open.",
        "FAKE-HEADING: inspection procedure.\nThe radiator fan relay is closed.",
    )
    client = _Client(
        json.dumps(
            {
                "pages": [
                    {"id": 1, "answer": "yes"},
                    {"id": 2, "answer": "no"},
                ]
            }
        )
    )
    flags = judge_pages(
        client,
        "The radiator fan is not spinning",
        unsure,
        keep_on_error=False,
    )

    assert flags == [True, False]
    assert client.kwargs == {"timeout_s": JUDGE_TIMEOUT_S, "attempts": 1}
    assert judge_pages(
        _Client(LLMError("timeout")),
        "The radiator fan is not spinning",
        unsure,
        keep_on_error=True,
    ) == [True, True]
    assert judge_pages(
        _Client(LLMError("timeout")),
        "The radiator fan is not spinning",
        unsure,
        keep_on_error=False,
    ) == [False, False]
