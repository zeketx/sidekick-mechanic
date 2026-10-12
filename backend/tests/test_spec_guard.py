from __future__ import annotations

import logging
from typing import Any

import pytest

from contract import load_answer_fixture, validate_answer
from spec_guard import (
    GuardStats,
    SpecGuardUncitedCounter,
    guard_answer,
    reset_stats,
    stats,
)

pytestmark = pytest.mark.usefixtures("_reset_guard_stats")


@pytest.fixture
def _reset_guard_stats() -> Any:
    reset_stats()
    yield
    reset_stats()


def _found(text: str) -> dict[str, Any]:
    return {"kind": "answer", "text": text, "citations": []}


def _refusal(surfaces: tuple[str, ...]) -> dict[str, str]:
    named = ", ".join(surfaces)
    return {
        "kind": "refusal",
        "text": f"Not found in the cited manual text: {named}.",
        "reason": "not_found_in_manual",
    }


@pytest.mark.parametrize(
    ("answer_text", "chunks", "uncited"),
    [
        ("Torque is 999 Nm.", ("FAKE-CHUNK: no torque is listed.",), ("999 Nm",)),
        ("Torque is 999 Nm.", ("FAKE-CHUNK: torque is 999.4 Nm.",), ("999 Nm",)),
        ("Torque is 999.0 Nm.", ("FAKE-CHUNK: torque is 999 Nm.",), ("999.0 Nm",)),
        ("Torque is 999 Nm.", ("FAKE-CHUNK: torque is 999 N·m.",), ()),
        ("Torque is 999 Nm.", ("FAKE-CHUNK: torque is 999   Nm.",), ()),
        ("Check pin 999.", ("FAKE-CHUNK: see pin 999.",), ()),
        ("Check pin 999.", ("FAKE-CHUNK: no pin is listed.",), ("pin 999",)),
        (
            "Check connector FAKE-C9.",
            ("FAKE-CHUNK: no connector is listed.",),
            ("connector FAKE-C9",),
        ),
        (
            "Check connector FAKE-C9.",
            ("FAKE-CHUNK: connector fake-c9 is shown.",),
            (),
        ),
        (
            "Check pin 999.",
            ("FAKE-CHUNK: connector 999 is shown.",),
            ("pin 999",),
        ),
        ("Torque is 999 Nm.", ("FAKE-CHUNK: torque is 1999 Nm.",), ("999 Nm",)),
        ("Torque is 999 Nm.", ("FAKE 999", "FAKE Nm"), ("999 Nm",)),
        (
            "Torque is 999 Nm.",
            ("FAKE-CHUNK: nothing", "FAKE-CHUNK: torque is 999 Nm."),
            (),
        ),
        (
            "Torque is 999 Nm. Check pin 999.",
            ("FAKE-CHUNK: torque is 999 Nm.",),
            ("pin 999",),
        ),
        ("See step 3 in the FAKE manual.", (), ()),
        ("Use 999 a bit of FAKE tape.", (), ()),
        ("FAKE current is 999 A.", (), ("999 A",)),
        (
            "Torque is 999-1000 Nm.",
            ("FAKE-CHUNK: torque is 1000 Nm.",),
            ("999-1000 Nm",),
        ),
        ("Torque is -999 Nm.", ("FAKE-CHUNK: torque is 999 Nm.",), ("-999 Nm",)),
        (
            "FAKE clearance is 9/9 mm.",
            ("FAKE-CHUNK: clearance is 9 mm.",),
            ("9/9 mm",),
        ),
        (
            "Torque is 9.99e2 Nm.",
            ("FAKE-CHUNK: torque is 999 Nm.",),
            ("9.99e2 Nm",),
        ),
        ("Torque is 9.99e2 Nm.", ("FAKE-CHUNK: torque is 9.99E2 Nm.",), ()),
        (
            "Torque is 9.99e+2 Nm.",
            ("FAKE-CHUNK: torque is 9.99e2 Nm.",),
            ("9.99e+2 Nm",),
        ),
        (
            "Pressure is 999,5 kPa.",
            ("FAKE-CHUNK: pressure is 999.5 kPa.",),
            ("999,5 kPa",),
        ),
        ("Pressure is 9,999 kPa.", ("FAKE-CHUNK: pressure is 9999 kPa.",), ()),
        ("Pressure is 9 999 kPa.", ("FAKE-CHUNK: pressure is 9999 kPa.",), ()),
        (
            "Torque is 999\u20131000 Nm.",
            ("FAKE-CHUNK: torque is 1000 Nm.",),
            ("999-1000 Nm",),
        ),
        ("Length is 999 mm.", ("FAKE-CHUNK: length is 999 m.",), ("999 mm",)),
        (
            "Resistance is 999 MΩ.",
            ("FAKE-CHUNK: resistance is 999 mΩ.",),
            ("999 megohm",),
        ),
        ("Check terminal FAKE-T9.", ("FAKE-CHUNK: terminal FAKE-T9.",), ()),
        (
            "Check pins 999 and 998.",
            ("FAKE-CHUNK: pin 999 and pin 998.",),
            (),
        ),
        (
            "Check pins 999 and 998.",
            ("FAKE-CHUNK: pin 999.",),
            ("pin 998",),
        ),
    ],
)
def test_claims_match_only_the_same_normalized_value(
    answer_text: str,
    chunks: tuple[str, ...],
    uncited: tuple[str, ...],
) -> None:
    answer = _found(answer_text)
    result = guard_answer(answer, chunks)

    assert result.uncited == uncited
    assert result.uncited_count == len(uncited)
    if uncited:
        assert result.answer == _refusal(uncited)
        validate_answer(result.answer)
        assert answer == _found(answer_text)
    else:
        assert result.answer == answer
        assert result.answer["kind"] == "answer"


@pytest.mark.parametrize(
    ("answer_text", "chunk"),
    [
        ("Torque is 999 Nm.", "FAKE-CHUNK: torque is 999 newton meters."),
        ("Torque is 999 N-m.", "FAKE-CHUNK: torque is 999 Nm."),
        ("Torque is 999 ft-lb.", "FAKE-CHUNK: torque is 999 ft lb."),
        ("Torque is 999 ft·lbf.", "FAKE-CHUNK: torque is 999 ft-lbf."),
        ("Torque is 999 ft·lbf.", "FAKE-CHUNK: torque is 999 ft·lb."),
        ("Torque is 999 kgf·cm.", "FAKE-CHUNK: torque is 999 kgf·cm."),
        ("Voltage is 999 volts.", "FAKE-CHUNK: voltage is 999 V."),
        ("Resistance is 999 ohms.", "FAKE-CHUNK: resistance is 999 Ω."),
        ("Resistance is 999 kΩ.", "FAKE-CHUNK: resistance is 999 kohm."),
        ("Pressure is 999 kPa.", "FAKE-CHUNK: pressure is 999 kpa."),
        ("Speed is 999 rpm.", "FAKE-CHUNK: speed is 999 r/min."),
        ("Temperature is 999 deg C.", "FAKE-CHUNK: temperature is 999 °C."),
        ("FAKE ratio is 999%.", "FAKE-CHUNK: ratio is 999 %."),
        ("FAKE current is 999 amps.", "FAKE-CHUNK: current is 999 A."),
    ],
)
def test_equivalent_spellings_pass(answer_text: str, chunk: str) -> None:
    result = guard_answer(_found(answer_text), (chunk,))

    assert result.uncited == ()
    assert result.answer["kind"] == "answer"
    assert result.answer["text"] == answer_text


def test_foot_pound_torque_is_not_a_length_in_feet() -> None:
    refused = guard_answer(
        _found("FAKE-SPEC torque is 999 ft·lbf."),
        ("FAKE-CHUNK: the length is 999 feet.",),
    )
    assert refused.uncited == ("999 ft·lbf",)
    assert refused.answer == _refusal(("999 ft·lbf",))

    other_way = guard_answer(
        _found("FAKE-SPEC length is 999 feet."),
        ("FAKE-CHUNK: torque is 999 ft-lbf.",),
    )
    assert other_way.uncited == ("999 feet",)

    hyphen = guard_answer(
        _found("FAKE-SPEC torque is 999 ft-lbf."),
        ("FAKE-CHUNK: the length is 999 ft.",),
    )
    assert hyphen.uncited == ("999 ft-lbf",)


def test_kgf_cm_is_torque_not_length_or_kgf_m() -> None:
    missing = guard_answer(
        _found("FAKE-SPEC torque is 999 kgf·cm."),
        ("FAKE-CHUNK: nothing listed.",),
    )
    assert missing.uncited == ("999 kgf·cm",)

    length = guard_answer(
        _found("FAKE-SPEC torque is 999 kgf·cm."),
        ("FAKE-CHUNK: the length is 999 cm.",),
    )
    assert length.uncited == ("999 kgf·cm",)

    kilogram_meters = guard_answer(
        _found("FAKE-SPEC torque is 999 kgf·cm."),
        ("FAKE-CHUNK: torque is 999 kgf·m.",),
    )
    assert kilogram_meters.uncited == ("999 kgf·cm",)

    squared = guard_answer(
        _found("FAKE-SPEC pressure is 999 kgf·cm^2."),
        ("FAKE-CHUNK: torque is 999 kgf·cm.",),
    )
    assert squared.uncited == ("999 kgf·cm^2",)

    torque_against_pressure = guard_answer(
        _found("FAKE-SPEC torque is 999 kgf·cm."),
        ("FAKE-CHUNK: pressure is 999 kgf·cm^2.",),
    )
    assert torque_against_pressure.uncited == ("999 kgf·cm",)


def test_broken_foot_pound_token_is_not_a_length() -> None:
    footnote = guard_answer(
        _found("FAKE-SPEC length is 999 feet."),
        ("FAKE-CHUNK: torque is 999 ft·lbf\u00b9.",),
    )
    assert footnote.uncited == ("999 feet",)

    extra_letters = guard_answer(
        _found("FAKE-SPEC length is 999 ft."),
        ("FAKE-CHUNK: torque is 999 ft·lbforce.",),
    )
    assert extra_letters.uncited == ("999 ft",)

    unicode_hyphen = guard_answer(
        _found("FAKE-SPEC length is 999 feet."),
        ("FAKE-CHUNK: torque is 999 ft\u2010lbf.",),
    )
    assert unicode_hyphen.uncited == ("999 feet",)

    hyphen_torque = guard_answer(
        _found("FAKE-SPEC torque is 999 ft·lbf."),
        ("FAKE-CHUNK: torque is 999 ft\u2010lbf.",),
    )
    assert hyphen_torque.uncited == ()

    words = guard_answer(
        _found("FAKE-SPEC torque is 999 ft·lbf."),
        ("FAKE-CHUNK: 999 ft-pounds.",),
    )
    assert words.uncited == ()


def test_sentence_period_does_not_join_a_torque_unit() -> None:
    sentence = guard_answer(
        _found("FAKE-SPEC torque is 999 ft·lbf."),
        ("FAKE-CHUNK: length is 999 ft. lbf is listed later.",),
    )
    assert sentence.uncited == ("999 ft·lbf",)

    abbreviation = guard_answer(
        _found("FAKE-SPEC torque is 999 ft·lbf."),
        ("FAKE-CHUNK: torque is 999 ft.lbf.",),
    )
    assert abbreviation.uncited == ()


def test_inch_pound_lbf_is_torque() -> None:
    missing = guard_answer(_found("FAKE-SPEC torque is 999 in·lbf."), ())
    assert missing.uncited == ("999 in·lbf",)

    same = guard_answer(
        _found("FAKE-SPEC torque is 999 in·lbf."),
        ("FAKE-CHUNK: torque is 999 in-lbf.",),
    )
    assert same.uncited == ()


@pytest.mark.parametrize(
    ("text", "uncited"),
    [
        ("999 bar", ("999 bar",)),
        ("999 psi", ("999 psi",)),
        ("999 rpm", ("999 rpm",)),
        ("999 mm", ("999 mm",)),
        ("999 ml", ("999 ml",)),
        ("999 V", ("999 V",)),
        ("999 Ω", ("999 ohm",)),
        ("999 °C", ("999 °C",)),
        ("999%", ("999%",)),
        ("pin Q", ("pin Q",)),
        ("999 kgf/cm2", ("999 kgf/cm2",)),
        ("terminal FAKE-T9", ("terminal FAKE-T9",)),
    ],
)
def test_known_forms_are_extracted(text: str, uncited: tuple[str, ...]) -> None:
    result = guard_answer(_found(f"FAKE spec {text}."), ())

    assert result.uncited == uncited
    validate_answer(result.answer)


def test_citation_snippet_is_not_evidence() -> None:
    answer = {
        "kind": "answer",
        "text": "Torque is 999 Nm.",
        "citations": [
            {
                "doc_id": "FAKE-DOC",
                "page": 999,
                "snippet": "Torque is 999 Nm.",
            }
        ],
    }

    result = guard_answer(answer, ())

    assert result.uncited == ("999 Nm",)
    assert "citations" not in result.answer
    validate_answer(result.answer)


def test_highlight_is_dropped_when_refused() -> None:
    answer = {
        "kind": "answer",
        "text": "Torque is 999 Nm.",
        "citations": [
            {
                "doc_id": "FAKE-DOC",
                "page": 999,
                "snippet": "FAKE-SNIPPET",
            }
        ],
        "highlight": {
            "bay_photo_id": "fake-bay-photo-front",
            "part_id": "fake-part-intake",
        },
    }

    result = guard_answer(answer, ())

    assert result.answer == _refusal(("999 Nm",))
    validate_answer(result.answer)
    assert answer["highlight"]["part_id"] == "fake-part-intake"


def test_fixture_refusal_passes_through_untouched() -> None:
    refusal = load_answer_fixture("refusal.json")

    result = guard_answer(refusal, ())

    assert result.answer == refusal
    assert result.uncited == ()
    assert stats() == GuardStats(0, 0, 0)


def test_refusal_that_names_a_spec_is_not_scanned() -> None:
    refusal = {
        "kind": "refusal",
        "text": "Not found in the cited manual text: 999 Nm, pin 999.",
        "reason": "not_found_in_manual",
    }

    result = guard_answer(refusal, ())

    assert result.answer == refusal
    assert result.uncited == ()
    assert stats() == GuardStats(0, 0, 0)


def test_guarding_a_refusal_again_does_not_count_another_failure() -> None:
    first = guard_answer(_found("Torque is 999 Nm."), ())

    second = guard_answer(first.answer, ())

    assert second.answer == first.answer
    assert second.uncited == ()
    assert stats() == GuardStats(checks=1, failures=1, uncited_claims=1)


def test_duplicate_normalized_claim_is_named_once() -> None:
    result = guard_answer(_found("Torque is 999 Nm, also written 999 N·m."), ())

    assert result.uncited == ("999 Nm",)
    assert stats().uncited_claims == 1


def test_zero_width_space_does_not_hide_a_claim() -> None:
    hidden = guard_answer(_found("Torque is 999\u200bNm."), ())
    shown = guard_answer(
        _found("Torque is 999\u200bNm."),
        ("FAKE-CHUNK: torque is 999 Nm.",),
    )

    assert hidden.answer["text"] == "Not found in the cited manual text: 999Nm."
    assert shown.uncited == ()
    assert shown.answer["kind"] == "answer"


def test_html_whitespace_entity_does_not_hide_a_claim() -> None:
    nbsp = guard_answer(_found("Torque is 999&nbsp;Nm."), ())
    zero_width = guard_answer(_found("Torque is 999&#8203;Nm."), ())

    assert nbsp.answer["text"] == "Not found in the cited manual text: 999 Nm."
    assert zero_width.answer["text"] == "Not found in the cited manual text: 999Nm."


def test_fullwidth_digits_match_ascii_digits() -> None:
    result = guard_answer(
        _found("Torque is ９９９ Nm."),
        ("FAKE-CHUNK: torque is 999 Nm.",),
    )

    assert result.uncited == ()
    assert result.answer["kind"] == "answer"


def test_markdown_emphasis_does_not_hide_a_claim() -> None:
    result = guard_answer(_found("Torque is 999 **Nm**."), ())

    assert result.answer["text"] == "Not found in the cited manual text: 999 Nm."


def test_failure_is_logged(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.WARNING, logger="sidekick.spec_guard")

    guard_answer(_found("Torque is 999 Nm. Check pin 999."), ())

    assert len(caplog.records) == 1
    record = caplog.records[0]
    assert record.levelname == "WARNING"
    assert record.name == "sidekick.spec_guard"
    assert record.message == "spec guard blocked 2 uncited claim(s): 999 Nm, pin 999"


def test_pass_is_not_logged(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG, logger="sidekick.spec_guard")

    guard_answer(_found("Torque is 999 Nm."), ("FAKE-CHUNK: 999 Nm",))

    assert caplog.records == []


def test_stats_count_checks_failures_and_claims() -> None:
    guard_answer(_found("No spec in this FAKE reply."), ())
    guard_answer(_found("Torque is 999 Nm."), ())
    guard_answer(_found("Torque is 999 Nm."), ("FAKE-CHUNK: torque is 999 Nm.",))

    assert stats() == GuardStats(checks=3, failures=1, uncited_claims=1)


def test_malformed_answer_is_not_rewritten() -> None:
    payload = {"kind": "answer", "citations": []}

    result = guard_answer(payload, ())

    assert result.answer == payload
    assert result.uncited == ()
    assert stats() == GuardStats(0, 0, 0)


def test_harness_counter_uses_the_guard_and_ignores_snippets() -> None:
    counter = SpecGuardUncitedCounter()
    cited_only_in_snippet = {
        "kind": "answer",
        "text": "Torque is 999 Nm.",
        "citations": [
            {
                "doc_id": "FAKE-DOC",
                "page": 999,
                "snippet": "Torque is 999 Nm.",
            }
        ],
    }
    refusal = {
        "kind": "refusal",
        "text": "Not found in the cited manual text: 999 Nm.",
        "reason": "not_found_in_manual",
    }

    assert counter.name == "spec_guard"
    assert counter.count(cited_only_in_snippet) == 1
    assert counter.count(refusal) == 0
    assert counter.count(_found("No spec in this FAKE reply.")) == 0


def test_string_of_chunks_is_rejected() -> None:
    with pytest.raises(TypeError, match="sequence of strings"):
        guard_answer(_found("Torque is 999 Nm."), "FAKE-CHUNK: 999 Nm")


def test_non_string_chunk_is_rejected() -> None:
    with pytest.raises(TypeError, match="must be a string"):
        guard_answer(_found("No spec."), (None,))  # type: ignore[arg-type]
