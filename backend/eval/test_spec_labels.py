"""Expected-value labels on golden spec rows stay inside the quoted page text."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from eval.golden import (
    GOLDEN_PATH,
    ExpectedPage,
    GoldenQuestion,
    GoldenSetError,
    SpecLabel,
    load_golden,
)
from eval.spec_labels import is_spec_value_question, quote_contains_value_and_unit

_LABEL_KEYS = frozenset(
    {
        "expected_value",
        "unit",
        "source_page",
        "source_quote",
        "label_status",
        "label_note",
    }
)


def test_spec_value_rows_are_labeled_and_other_rows_are_not() -> None:
    questions = load_golden(GOLDEN_PATH)
    raw_rows = [
        json.loads(line)
        for line in GOLDEN_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    raw_by_id = {row["id"]: row for row in raw_rows}

    assert len(raw_by_id) == len(questions)
    for question in questions:
        raw = raw_by_id[question.id]
        if is_spec_value_question(question.question):
            assert question.spec_label is not None, question.id
            assert raw["label_status"] in ("ok", "needs_review")
        else:
            assert question.spec_label is None, question.id
            assert _LABEL_KEYS.isdisjoint(raw), question.id


def test_needs_review_rows_leave_the_value_empty() -> None:
    for question in load_golden(GOLDEN_PATH):
        label = question.spec_label
        if label is None or label.label_status != "needs_review":
            continue
        assert label.expected_value == "", question.id
        assert label.label_note, question.id
        if label.source_page is None:
            continue
        pages = {page.page for page in question.expected}
        assert label.source_page in pages, question.id


def _ok_label_problem(question: GoldenQuestion) -> str | None:
    label = question.spec_label
    if label is None or label.label_status != "ok":
        return None
    pages = {page.page for page in question.expected}
    if label.source_page not in pages:
        return "source_page"
    if not quote_contains_value_and_unit(
        label.expected_value, label.unit, label.source_quote
    ):
        return "quote"
    return None


def test_ok_rows_quote_the_value_and_unit() -> None:
    for question in load_golden(GOLDEN_PATH):
        assert _ok_label_problem(question) is None, question.id


def _labeled_ok(*, source_quote: str, source_page: int) -> GoldenQuestion:
    return GoldenQuestion(
        id="fake-torque",
        question="What torque is this FAKE-SPEC fastener?",
        answerable=True,
        expected=(ExpectedPage("FAKE-DOC", 999),),
        part_id=None,
        ci=False,
        spec_label=SpecLabel(
            expected_value="999",
            unit="FAKEUNIT",
            source_quote=source_quote,
            label_status="ok",
            source_page=source_page,
        ),
    )


def test_ok_label_check_rejects_a_quote_that_lacks_the_value() -> None:
    missing = _labeled_ok(source_quote="torque 998 FAKEUNIT", source_page=999)
    wrong_page = _labeled_ok(source_quote="torque 999 FAKEUNIT", source_page=998)

    held = _labeled_ok(source_quote="torque 999 FAKEUNIT", source_page=999)

    assert _ok_label_problem(missing) == "quote"
    assert _ok_label_problem(wrong_page) == "source_page"
    assert _ok_label_problem(held) is None


def test_quote_match_allows_commas_and_trailing_zeros_only() -> None:
    assert quote_contains_value_and_unit("999", "FAKEUNIT", "torque 999 FAKEUNIT")
    assert quote_contains_value_and_unit("999", "FAKEUNIT", "torque 999.0 FAKEUNIT")
    assert quote_contains_value_and_unit("999.0", "FAKEUNIT", "torque 999 FAKEUNIT")
    assert quote_contains_value_and_unit("1120", "FAKEUNIT", "torque 1,120 FAKEUNIT")
    assert quote_contains_value_and_unit("1,120", "FAKEUNIT", "torque 1120 FAKEUNIT")
    assert quote_contains_value_and_unit("1.50", "FAKEUNIT", "gap 1.5 FAKEUNIT")
    assert quote_contains_value_and_unit("10", "FAKEUNIT", "gap 10.00 FAKEUNIT")
    assert quote_contains_value_and_unit("999", "N·m", "torque 999 N·m")

    assert not quote_contains_value_and_unit("999", "FAKEUNIT", "torque 998 FAKEUNIT")
    assert not quote_contains_value_and_unit("18", "FAKEUNIT", "torque 180 FAKEUNIT")
    assert not quote_contains_value_and_unit("12", "FAKEUNIT", "torque 1,120 FAKEUNIT")
    assert not quote_contains_value_and_unit("999", "FAKEUNIT", "torque 999 FAKE-UNIT")
    assert not quote_contains_value_and_unit("999", "N·m", "torque 999 Nm")
    assert not quote_contains_value_and_unit("18-20", "FAKEUNIT", "torque 18 FAKEUNIT")
    assert not quote_contains_value_and_unit("", "FAKEUNIT", "torque 999 FAKEUNIT")


def test_needs_review_rejects_a_filled_in_value(tmp_path: Path) -> None:
    row = {
        "id": "fake-torque",
        "question": "What torque is this FAKE-SPEC fastener?",
        "answerable": False,
        "expected": [],
        "expected_value": "999",
        "unit": "FAKEUNIT",
        "source_quote": "FAKE-SPEC 999 FAKEUNIT",
        "label_status": "needs_review",
        "label_note": "The page text is scrambled.",
    }
    path = tmp_path / "golden.jsonl"
    path.write_text(json.dumps(row) + "\n", encoding="utf-8")

    with pytest.raises(GoldenSetError):
        load_golden(path)
