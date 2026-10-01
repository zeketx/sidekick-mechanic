"""Unit tests for eval metric math. Inputs are fake pages, not manual facts."""

from __future__ import annotations

from typing import Any

import pytest

from eval.metrics import (
    aggregate_metrics,
    citation_is_accurate,
    count_uncited_numbers,
    is_correct_refusal,
    percentile,
    recall_at_5,
    score_case,
)

FAKE_PAGE = ("FAKE-DOC-2JZ", 999)
OTHER_PAGE = ("FAKE-DOC-WIRING", 999)


def test_recall_at_5_is_fraction_of_expected_pages_in_top_5() -> None:
    expected = [FAKE_PAGE, OTHER_PAGE]
    retrieved = [
        FAKE_PAGE,
        ("FAKE-OTHER", 999),
        ("FAKE-OTHER", 998),
        ("FAKE-OTHER", 997),
        ("FAKE-OTHER", 996),
        OTHER_PAGE,
    ]

    assert recall_at_5(expected, retrieved) == 0.5


def test_recall_at_5_counts_a_hit_on_the_fifth_rank() -> None:
    retrieved = [("FAKE-OTHER", 999)] * 4 + [FAKE_PAGE]

    assert recall_at_5([FAKE_PAGE], retrieved) == 1.0


def test_recall_at_5_is_zero_when_retrieval_returns_nothing() -> None:
    assert recall_at_5([FAKE_PAGE], []) == 0.0


def test_recall_at_5_is_null_when_retrieval_was_not_run() -> None:
    assert recall_at_5([FAKE_PAGE], None) is None


def test_recall_at_5_collapses_duplicate_expected_pages() -> None:
    assert recall_at_5([FAKE_PAGE, FAKE_PAGE], [FAKE_PAGE]) == 1.0


def test_recall_at_5_is_null_without_expected_pages() -> None:
    assert recall_at_5([], [FAKE_PAGE]) is None


def test_citation_is_accurate_when_every_citation_is_expected() -> None:
    answer = _answer(
        citations=[
            _citation(FAKE_PAGE),
            _citation(OTHER_PAGE),
        ]
    )

    assert citation_is_accurate([FAKE_PAGE, OTHER_PAGE], answer) is True


def test_citation_is_inaccurate_when_any_page_is_outside_expected() -> None:
    answer = _answer(citations=[_citation(FAKE_PAGE), _citation(("FAKE-OTHER", 999))])

    assert citation_is_accurate([FAKE_PAGE], answer) is False


def test_citation_is_inaccurate_with_no_citations_or_a_refusal() -> None:
    assert citation_is_accurate([FAKE_PAGE], _answer(citations=[])) is False
    assert citation_is_accurate([FAKE_PAGE], _refusal()) is False


def test_refusal_matches_only_the_contract_shape() -> None:
    assert is_correct_refusal(_refusal()) is True
    assert is_correct_refusal(_answer(text="Not found in the manual.")) is False


def test_local_counter_counts_numbers_missing_from_snippets() -> None:
    answer = _answer(
        text="Use FAKE-SPEC 12 then 12 again, not 13.",
        citations=[_citation(FAKE_PAGE, snippet="FAKE-SPEC 12")],
    )

    assert count_uncited_numbers(answer) == 1


def test_local_counter_does_not_treat_a_longer_number_as_a_citation() -> None:
    answer = _answer(
        text="FAKE value 12.",
        citations=[_citation(FAKE_PAGE, snippet="FAKE value 123")],
    )

    assert count_uncited_numbers(answer) == 1


def test_local_counter_counts_each_occurrence_and_numbers_in_refusals() -> None:
    answer = _answer(text="12Nm and 12Nm", citations=[])
    refusal = _refusal(text="Not found. FAKE 40.")

    assert count_uncited_numbers(answer) == 2
    assert count_uncited_numbers(refusal) == 1


def test_local_counter_ignores_text_without_digits() -> None:
    assert count_uncited_numbers(_answer(text="No digits here.")) == 0


def test_injected_counter_replaces_the_local_one() -> None:
    class Guard:
        name = "spec_guard"

        def count(self, answer: dict[str, Any]) -> int:
            assert answer["text"] == "12"
            return 4

    assert count_uncited_numbers({"text": "12"}, counter=Guard()) == 4


def test_percentile_uses_linear_index() -> None:
    values = [1.0, 2.0, 3.0, 4.0]

    assert percentile(values, 50) == pytest.approx(2.5)
    assert percentile(values, 95) == pytest.approx(3.85)
    assert percentile([10.0], 50) == 10.0
    assert percentile([10.0], 95) == 10.0
    assert percentile([], 50) is None


def test_aggregate_leaves_recall_null_when_no_case_has_retrieval() -> None:
    cases = [
        score_case(
            question_id="fake-answerable",
            answerable=True,
            expected=[FAKE_PAGE],
            part_id="fake-part-intake",
            answer=_answer(citations=[_citation(FAKE_PAGE)]),
            latency_ms=10,
            retrieval=None,
        ),
        score_case(
            question_id="fake-unanswerable",
            answerable=False,
            expected=[],
            part_id=None,
            answer=_answer(text="A guessed FAKE reply."),
            latency_ms=30,
            retrieval=None,
        ),
    ]

    metrics = aggregate_metrics(cases)

    assert metrics.recall_at_5 is None
    assert metrics.citation_accuracy == 1.0
    assert metrics.refusal_correctness == 0.0
    assert metrics.uncited_number_count == 0
    assert metrics.latency_p50_ms == pytest.approx(20.0)
    assert metrics.latency_p95_ms == pytest.approx(29.0)


def test_aggregate_recall_uses_only_cases_with_retrieval() -> None:
    with_hits = score_case(
        question_id="fake-retrieved",
        answerable=True,
        expected=[FAKE_PAGE, OTHER_PAGE],
        part_id=None,
        answer=_answer(),
        latency_ms=5,
        retrieval=[FAKE_PAGE],
    )
    without_hits = score_case(
        question_id="fake-no-store",
        answerable=True,
        expected=[FAKE_PAGE],
        part_id=None,
        answer=_answer(),
        latency_ms=5,
        retrieval=None,
    )

    metrics = aggregate_metrics([with_hits, without_hits])

    assert with_hits.recall_at_5 == 0.5
    assert without_hits.recall_at_5 is None
    assert metrics.recall_at_5 == 0.5


def test_score_case_rejects_negative_latency() -> None:
    with pytest.raises(ValueError, match="negative"):
        score_case(
            question_id="fake-q",
            answerable=True,
            expected=[FAKE_PAGE],
            part_id=None,
            answer=_answer(),
            latency_ms=-1,
            retrieval=None,
        )


def _answer(
    *,
    text: str = "Fixture reply with no numeric spec.",
    citations: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "kind": "answer",
        "text": text,
        "citations": [] if citations is None else citations,
    }


def _citation(
    page: tuple[str, int],
    *,
    snippet: str = "FAKE-SNIPPET",
) -> dict[str, Any]:
    return {"doc_id": page[0], "page": page[1], "snippet": snippet}


def _refusal(*, text: str = "Not found in the fixture.") -> dict[str, Any]:
    return {
        "kind": "refusal",
        "text": text,
        "reason": "not_found_in_manual",
    }
