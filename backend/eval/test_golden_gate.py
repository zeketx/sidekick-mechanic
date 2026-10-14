from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from eval.golden import GOLDEN_PATH, ExpectedPage, GoldenQuestion, load_golden
from eval.golden_gate import (
    ANSWERABLE_MIN,
    PART_ID_MIN,
    TOTAL_MIN,
    UNANSWERABLE_SPEC_MIN,
    CorpusMissing,
    GateError,
    Inventory,
    LoadedCorpus,
    RejectReason,
    RowRejection,
    commit_golden,
    format_report,
    gate_golden,
    load_corpus,
    load_inventory,
    main,
    render_golden,
    screen_questions,
)

_MANIFEST = Path(__file__).resolve().parents[2] / "docs" / "MANUALS.md"
_THERMOSTAT = (
    "At what temperature should the thermostat start to open, "
    "and how much lift should it have?"
)
_PINOUT = "What is the pinout of the Lexus donor ECU in this LJ78?"
_TIMING_BELT = (
    "Why do I have to set the crank before pulling the cam pulleys "
    "on the timing belt job?"
)
_PAGE = "thermostat temperature lift FAKE-SPEC"
_FROZEN_NS = 1_000_000_000


def test_committed_golden_passes_screen() -> None:
    inventory = load_inventory(_MANIFEST)
    questions = load_golden(GOLDEN_PATH)
    screen = screen_questions(questions, inventory)
    answerable = tuple(question for question in questions if question.answerable)
    unanswerable = tuple(question for question in questions if not question.answerable)

    assert screen.rejected == (), "structural screen rejected a row"
    assert not any(
        row.reason is RejectReason.SPEC_IN_QUESTION for row in screen.rejected
    ), "structural screen stored spec"
    assert screen.quotas.ok, "structural screen quotas failed"
    assert screen.quotas.reasons == (), "structural screen quota reasons"
    assert len(questions) == 50, "structural screen question count"
    assert len(answerable) == 26, "structural screen answerable count"
    assert len(unanswerable) == 24, "structural screen unanswerable count"
    assert screen.quotas.total == 50, "structural screen quota total"
    assert screen.quotas.answerable == 26, "structural screen quota answerable"
    assert screen.quotas.unanswerable_spec == 24, "structural screen unanswerable spec"
    assert screen.quotas.part_rows == 17, "structural screen part rows"
    assert sum(question.part_id is not None for question in questions) == 17, (
        "structural screen part_id count"
    )
    assert sum(question.ci for question in questions) == 10, (
        "structural screen ci count"
    )
    assert GOLDEN_PATH.read_text(encoding="utf-8") == render_golden(questions), (
        "structural screen canonical bytes"
    )
    for question in unanswerable:
        assert question.expected == (), (
            f"structural screen unanswerable {question.id} has pages"
        )
    for question in answerable:
        assert question.expected, f"structural screen {question.id} has no pages"
        for page in question.expected:
            assert page.doc_id == "2jz-ge-rm", (
                f"structural screen {question.id} doc id {page.doc_id}"
            )
            assert page.doc_id in inventory.ingest_ids, (
                f"structural screen {question.id} is not an ingest doc"
            )


def test_gate_keeps_page_whose_text_names_the_subject_and_a_spec_shape() -> None:
    question = _answerable("thermostat-opening")
    result = gate_golden((question,), _corpus())

    assert result.kept == (question,)
    assert result.rejected == ()


def test_gate_rejects_page_that_does_not_name_the_subject() -> None:
    question = _answerable("thermostat-opening")
    result = gate_golden(
        (question,),
        _corpus({("FAKE-DOC", 999): "unrelated brake pedal"}),
    )

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.TOPIC_NOT_IN_TEXT),
    )


def test_gate_rejects_spec_question_when_page_has_no_spec_shape() -> None:
    question = _answerable("thermostat-opening")
    result = gate_golden(
        (question,),
        _corpus({("FAKE-DOC", 999): "thermostat temperature lift procedure"}),
    )

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.SPEC_SHAPE_MISSING),
    )


def test_gate_rejects_non_ingest_doc() -> None:
    question = _answerable(
        "thermostat-opening",
        expected=(ExpectedPage("lj78-wiring", 999),),
    )
    result = gate_golden((question,), _corpus())

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.DOC_NOT_INGEST),
    )


def test_gate_rejects_page_outside_manifest_count() -> None:
    question = _answerable(
        "thermostat-opening",
        expected=(ExpectedPage("FAKE-DOC", 1000),),
    )
    result = gate_golden((question,), _corpus())

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.PAGE_OUT_OF_RANGE),
    )


def test_gate_rejects_missing_chunk() -> None:
    question = _answerable("thermostat-opening")
    result = gate_golden((question,), _corpus({}))

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.PAGE_NOT_IN_CORPUS),
    )


def test_gate_rejects_unanswerable_with_pages() -> None:
    question = _unanswerable(
        "donor-ecu-pinout",
        expected=(ExpectedPage("FAKE-DOC", 999),),
    )
    result = gate_golden((question,), _corpus())

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("donor-ecu-pinout", RejectReason.UNANSWERABLE_HAS_PAGES),
    )


def test_gate_rejects_spec_stored_in_question() -> None:
    rejected_rows = (
        _unanswerable("torque-c", question="Torque to 80 C"),
        _unanswerable("blue-wire", question="the blue wire from the donor harness"),
        _unanswerable("pin-number", question="pin 14 on the donor ECU"),
        _unanswerable("degrees", question="60 degrees before top dead center"),
        _unanswerable("comma-rpm", question="oil pressure at 3,000 rpm"),
    )
    kept_rows = (
        _unanswerable(
            "which-pin",
            question="Which pin on the LJ78 cluster is the tach signal?",
        ),
        _unanswerable(
            "wire-color",
            question="What wire color feeds the pump on this LJ78?",
        ),
        _unanswerable("p0011", question="My scanner shows P0011."),
        _unanswerable(
            "tha-e2",
            question=(
                "What resistance should circuit THA-E2 read when the air is cool?"
            ),
        ),
    )
    result = gate_golden(rejected_rows + kept_rows, _corpus())

    assert result.rejected == tuple(
        RowRejection(question.id, RejectReason.SPEC_IN_QUESTION)
        for question in rejected_rows
    )
    assert result.kept == kept_rows


def test_gate_rejects_unknown_part_id() -> None:
    question = _answerable("thermostat-opening", part_id="not-a-part")
    result = gate_golden((question,), _corpus())

    assert result.kept == ()
    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.PART_ID_UNKNOWN),
    )


def test_gate_keeps_unanswerable_spec_refusal() -> None:
    question = _unanswerable("donor-ecu-pinout")
    result = gate_golden((question,), _corpus())
    sized = tuple(
        _unanswerable(f"pinout-{index}") for index in range(UNANSWERABLE_SPEC_MIN)
    )
    sized_result = gate_golden(sized, _corpus())

    assert result.kept == (question,)
    assert result.rejected == ()
    assert sized_result.quotas.unanswerable_spec >= UNANSWERABLE_SPEC_MIN


def test_gate_rejects_whole_row_when_one_page_misses_the_subject() -> None:
    bad = _answerable(
        "thermostat-opening",
        expected=(
            ExpectedPage("FAKE-DOC", 999),
            ExpectedPage("FAKE-DOC", 998),
        ),
    )
    corpus = LoadedCorpus(
        inventory=_inventory(),
        pages={
            ("FAKE-DOC", 999): "thermostat temperature lift FAKE-SPEC",
            ("FAKE-DOC", 998): "unrelated brake pedal",
        },
    )
    dropped = gate_golden((bad,), corpus)

    assert dropped.kept == ()
    assert dropped.rejected == (
        RowRejection("thermostat-opening", RejectReason.TOPIC_NOT_IN_TEXT),
    )


def test_gate_keeps_timing_belt_procedure_without_spec_shape() -> None:
    question = _answerable(
        "timing-belt-60-btdc",
        question=_TIMING_BELT,
        part_id="timing-belt-cover",
    )
    result = gate_golden(
        (question,),
        _corpus({("FAKE-DOC", 999): "crank cam pulleys timing belt"}),
    )

    assert question.question == (
        "Why do I have to set the crank before pulling the cam pulleys "
        "on the timing belt job?"
    )
    assert result.kept == (question,)
    assert result.rejected == ()


def test_commit_writes_nothing_when_quotas_fail(tmp_path: Path) -> None:
    dest = tmp_path / "golden.jsonl"
    question = _unanswerable("donor-ecu-pinout")

    with pytest.raises(GateError) as caught:
        commit_golden(dest, (question,), _corpus())

    assert caught.value.result is not None
    assert caught.value.result.kept == (question,)
    assert caught.value.result.rejected == ()
    assert caught.value.result.quotas.ok is False
    assert not dest.exists()
    assert not dest.with_name(dest.name + ".tmp").exists()


def test_commit_is_idempotent(tmp_path: Path) -> None:
    questions = _quota_set()
    dest = tmp_path / "golden.jsonl"
    first = commit_golden(dest, questions, _corpus())
    first_bytes = dest.read_bytes()
    second = commit_golden(dest, questions, _corpus())

    assert first.rejected == ()
    assert first.quotas.ok
    assert second.kept == first.kept
    assert dest.read_bytes() == first_bytes
    assert dest.read_text(encoding="utf-8") == render_golden(questions)
    assert dest.read_text(encoding="utf-8") == render_golden(first.kept)


def test_format_report_omits_page_text() -> None:
    question = _answerable("thermostat-opening")
    result = gate_golden(
        (question,),
        _corpus({("FAKE-DOC", 999): "FAKE-SPEC-SECRET unrelated brake pedal"}),
    )
    report = format_report(result)

    assert result.rejected == (
        RowRejection("thermostat-opening", RejectReason.TOPIC_NOT_IN_TEXT),
    )
    assert report == (
        "thermostat-opening topic_not_in_text\n"
        "kept 0 answerable 0 unanswerable_spec 0 part_rows 0\n"
    )
    assert "FAKE-SPEC-SECRET" not in report


def test_load_corpus_rejects_duplicate_page(tmp_path: Path) -> None:
    path = tmp_path / "chunks.jsonl"
    line = json.dumps(
        {"doc_id": "FAKE-DOC", "page": 999, "text": _PAGE},
        ensure_ascii=True,
    )
    path.write_text(line + "\n" + line + "\n", encoding="utf-8")

    with pytest.raises(GateError, match="duplicate") as caught:
        load_corpus(path, _inventory())

    assert not isinstance(caught.value, CorpusMissing)
    assert "FAKE-SPEC" not in str(caught.value)


def test_cli_missing_chunks_exits_2(tmp_path: Path) -> None:
    golden = tmp_path / "golden.jsonl"
    golden.write_text("leave-me\n", encoding="utf-8")
    before = golden.read_bytes()
    _freeze(golden)

    code = main(
        [
            "--manifest",
            str(_MANIFEST),
            "--chunks",
            str(tmp_path / "missing.jsonl"),
            "--golden",
            str(golden),
        ]
    )

    assert code == 2
    assert golden.read_bytes() == before
    assert golden.stat().st_mtime_ns == _FROZEN_NS


def test_cli_dry_run_does_not_write(tmp_path: Path) -> None:
    chunks = tmp_path / "chunks.jsonl"
    golden = tmp_path / "golden.jsonl"
    _write_chunks(chunks, doc_id="2jz-ge-rm")
    golden.write_text(
        render_golden(_quota_set(doc_id="2jz-ge-rm")),
        encoding="utf-8",
        newline="\n",
    )
    before = golden.read_bytes()
    _freeze(golden)

    code = main(
        [
            "--manifest",
            str(_MANIFEST),
            "--chunks",
            str(chunks),
            "--golden",
            str(golden),
        ]
    )

    assert code == 0
    assert golden.read_bytes() == before
    assert golden.stat().st_mtime_ns == _FROZEN_NS


def _inventory() -> Inventory:
    return Inventory(
        ingest_ids=frozenset({"FAKE-DOC"}),
        page_counts={"FAKE-DOC": 999},
    )


def _corpus(
    pages: dict[tuple[str, int], str] | None = None,
) -> LoadedCorpus:
    if pages is None:
        pages = {("FAKE-DOC", 999): _PAGE}
    return LoadedCorpus(inventory=_inventory(), pages=pages)


def _answerable(
    question_id: str,
    *,
    question: str = _THERMOSTAT,
    expected: tuple[ExpectedPage, ...] | None = None,
    part_id: str | None = "thermostat",
) -> GoldenQuestion:
    if expected is None:
        expected = (ExpectedPage("FAKE-DOC", 999),)
    return GoldenQuestion(
        id=question_id,
        question=question,
        answerable=True,
        expected=expected,
        part_id=part_id,
        ci=False,
    )


def _unanswerable(
    question_id: str,
    *,
    question: str = _PINOUT,
    expected: tuple[ExpectedPage, ...] = (),
) -> GoldenQuestion:
    return GoldenQuestion(
        id=question_id,
        question=question,
        answerable=False,
        expected=expected,
        part_id=None,
        ci=False,
    )


def _quota_set(doc_id: str = "FAKE-DOC") -> tuple[GoldenQuestion, ...]:
    answerable_count = max(ANSWERABLE_MIN, PART_ID_MIN)
    unanswerable_count = UNANSWERABLE_SPEC_MIN
    if answerable_count + unanswerable_count < TOTAL_MIN:
        unanswerable_count += TOTAL_MIN - (answerable_count + unanswerable_count)
    questions: list[GoldenQuestion] = []
    for index in range(answerable_count):
        questions.append(
            GoldenQuestion(
                id=f"answerable-{index}",
                question=_THERMOSTAT,
                answerable=True,
                expected=(ExpectedPage(doc_id, 999),),
                part_id="thermostat",
                ci=False,
            )
        )
    for index in range(unanswerable_count):
        questions.append(
            GoldenQuestion(
                id=f"unanswerable-{index}",
                question=_PINOUT,
                answerable=False,
                expected=(),
                part_id=None,
                ci=False,
            )
        )
    return tuple(questions)


def _write_chunks(path: Path, *, doc_id: str) -> None:
    line = json.dumps(
        {"doc_id": doc_id, "page": 999, "text": _PAGE},
        ensure_ascii=True,
    )
    path.write_text(line + "\n", encoding="utf-8")


def _freeze(path: Path) -> None:
    os.utime(path, ns=(_FROZEN_NS, _FROZEN_NS))
