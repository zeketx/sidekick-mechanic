"""Trace writer and value_match normalizer. Fixtures use 999, not a manual spec."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from eval.__main__ import main
from eval.golden import GOLDEN_PATH, load_golden
from eval.harness import run_harness
from eval.rescore import rescore
from eval.runner import RetrievedHit, RunnerOutput
from eval.trace import question_trace, trace_document, write_trace
from eval.value_match import answer_contains_spec, canonical_spec, guard_decision, value_match_for

FAKE_DATE = "2026-10-01"


def test_committed_golden_rows_have_no_labeled_value() -> None:
    questions = load_golden(GOLDEN_PATH)

    assert questions
    assert all(
        question.expected_value is None and question.label_status is None
        for question in questions
    )


def test_normalizer_folds_unit_spelling_and_number_shape() -> None:
    assert canonical_spec("999", "N·m") == canonical_spec("999.0", "Nm")
    assert canonical_spec("999", "N-m") == "999 nm"
    assert canonical_spec("999", "kgf·cm") == canonical_spec("999", "kgf-cm")
    assert canonical_spec("999", "ft-lbf") == canonical_spec("999", "ft·lbf")
    assert canonical_spec("1,400", "ohm") == canonical_spec("1400", "Ω")
    assert canonical_spec("999", "kPa") == "999 kpa"
    assert canonical_spec("999", "psi") == "999 psi"
    assert canonical_spec("999", "kPa") != canonical_spec("999", "psi")


def test_answer_text_matches_a_normalized_value_and_a_range_endpoint() -> None:
    assert answer_contains_spec("Torque is 999 N-m.", "999.0", "N·m")
    assert answer_contains_spec("Cold reading is 835-1400 ohms.", "1400", "Ω")
    assert answer_contains_spec("The table says 999 kgf-cm.", "999", "kgf·cm")
    assert answer_contains_spec("Use 999 ft·lbf.", "999", "ft-lbf")
    assert not answer_contains_spec("Torque is 999 Nm.", "998-999", "Nm")
    assert not answer_contains_spec("Pressure is 999 psi.", "999", "kPa")
    assert not answer_contains_spec("No number here.", "999", "Nm")


def test_refusal_misses_value_match_even_when_the_text_names_the_value() -> None:
    refusal = {
        "kind": "refusal",
        "text": "Not found in the cited manual text: 999 Nm.",
        "reason": "not_found_in_manual",
    }

    assert value_match_for(refusal, value="999", unit="Nm", label_status="ok") is False
    assert guard_decision(refusal) == {"decision": "blocked", "reason": "999 Nm"}


def test_unlabeled_question_is_excluded() -> None:
    answer = {"kind": "answer", "text": "Torque is 999 Nm.", "citations": []}

    assert value_match_for(answer, value=None, unit=None) is None
    assert guard_decision(answer) == {
        "decision": "allowed",
        "reason": "guard returned the answer",
    }


def test_trace_file_is_stable_and_records_pages_scores_and_the_guard(
    tmp_path: Path,
) -> None:
    answer = {
        "kind": "answer",
        "text": "FAKE-STEP uses 999 Nm.",
        "citations": [
            {"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SPEC"},
            {"doc_id": "FAKE-DOC", "page": 998, "snippet": "FAKE-SPEC"},
        ],
    }
    row = question_trace(
        "fake-torque",
        answer,
        (
            RetrievedHit("FAKE-DOC", 999, 1.5),
            RetrievedHit("FAKE-DOC", 998, None),
        ),
        value="999",
        unit="Nm",
        label_status="ok",
    )
    document = trace_document(
        label="before",
        golden_path="eval/fixtures/fake.jsonl",
        runner="scripted",
        questions=[row],
    )
    destination = tmp_path / "before.json"

    write_trace(destination, document)
    first = destination.read_bytes()
    write_trace(destination, document)
    written = destination.read_text(encoding="utf-8")

    assert destination.read_bytes() == first
    payload = json.loads(written)
    question = payload["questions"][0]
    assert question["cited_pages"] == [
        {"doc_id": "FAKE-DOC", "page": 999},
        {"doc_id": "FAKE-DOC", "page": 998},
    ]
    assert question["top5"] == [
        {"doc_id": "FAKE-DOC", "page": 999, "score": 1.5},
        {"doc_id": "FAKE-DOC", "page": 998, "score": None},
    ]
    assert question["guard"]["decision"] == "allowed"
    assert question["value_match"] is True
    assert question["refused"] is False
    assert list(payload) == sorted(payload)


def test_harness_writes_the_trace_and_prints_value_match(tmp_path: Path) -> None:
    golden = tmp_path / "golden.jsonl"
    golden.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "id": "fake-labeled",
                        "question": "What is FAKE-SPEC?",
                        "answerable": True,
                        "expected": [{"doc_id": "FAKE-DOC", "page": 999}],
                        "expected_value": "999",
                        "unit": "Nm",
                        "label_status": "ok",
                        "source_page": 999,
                        "source_quote": "FAKE-SPEC 999 Nm",
                    }
                ),
                json.dumps(
                    {
                        "id": "fake-unlabeled",
                        "question": "Where is FAKE-PART?",
                        "answerable": True,
                        "expected": [{"doc_id": "FAKE-DOC", "page": 999}],
                    }
                ),
                json.dumps(
                    {
                        "id": "fake-refused",
                        "question": "What is the other FAKE-SPEC?",
                        "answerable": True,
                        "expected": [{"doc_id": "FAKE-DOC", "page": 998}],
                        "expected_value": "998",
                        "unit": "Nm",
                        "label_status": "ok",
                    }
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    class Scripted:
        name = "scripted"

        def run(self, question: str) -> RunnerOutput:
            if question.startswith("What is the other"):
                return RunnerOutput(
                    answer={
                        "kind": "refusal",
                        "text": "Not found in the cited manual text: 998 Nm.",
                        "reason": "not_found_in_manual",
                    },
                    latency_ms=1,
                    retrieval=(RetrievedHit("FAKE-DOC", 998, 0.25),),
                )
            if question.startswith("What is"):
                return RunnerOutput(
                    answer={
                        "kind": "answer",
                        "text": "FAKE-STEP is 999 Nm.",
                        "citations": [
                            {"doc_id": "FAKE-DOC", "page": 999, "snippet": "FAKE-SPEC"}
                        ],
                    },
                    latency_ms=1,
                    retrieval=(RetrievedHit("FAKE-DOC", 999, 2),),
                )
            return RunnerOutput(
                answer={"kind": "answer", "text": "See FAKE-PART.", "citations": []},
                latency_ms=1,
                retrieval=None,
            )

    trace = tmp_path / "traces" / "before.json"
    payload = run_harness(
        golden,
        runner=Scripted(),
        output_dir=tmp_path,
        date=FAKE_DATE,
        trace_path=trace,
        trace_label="before",
    )
    saved = json.loads(trace.read_text(encoding="utf-8"))

    assert payload["metrics"]["value_match"] == 0.5
    assert payload["metrics"]["value_match_excluded"] == 1
    assert payload["metrics"]["refused_count"] == 1
    assert saved["label"] == "before"
    assert [row["id"] for row in saved["questions"]] == [
        "fake-labeled",
        "fake-unlabeled",
        "fake-refused",
    ]
    assert saved["questions"][0]["top5"][0]["score"] == 2
    assert saved["questions"][1]["top5"] is None
    assert saved["questions"][1]["value_match"] is None
    assert saved["questions"][2]["guard"] == {
        "decision": "blocked",
        "reason": "998 Nm",
    }
    assert saved["questions"][0]["answer_text"] == "FAKE-STEP is 999 Nm."
    assert saved["questions"][0]["refused"] is False
    assert saved["questions"][2]["answer_text"].startswith(
        "Not found in the cited manual text:"
    )
    assert saved["questions"][2]["refused"] is True
    assert saved["questions"][2]["cited_pages"] == []


def test_rescore_uses_stored_answers_and_only_ok_labels(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    golden = tmp_path / "golden.jsonl"
    golden.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "id": "fake-hit",
                        "question": "What is FAKE-SPEC?",
                        "answerable": True,
                        "expected": [{"doc_id": "FAKE-DOC", "page": 999}],
                        "expected_value": "999",
                        "unit": "Nm",
                        "label_status": "ok",
                        "source_page": 999,
                        "source_quote": "FAKE-SPEC 999 Nm",
                    }
                ),
                json.dumps(
                    {
                        "id": "fake-refused",
                        "question": "What is the other FAKE-SPEC?",
                        "answerable": True,
                        "expected": [{"doc_id": "FAKE-DOC", "page": 998}],
                        "expected_value": "998",
                        "unit": "Nm",
                        "label_status": "ok",
                    }
                ),
                json.dumps(
                    {
                        "id": "fake-review",
                        "question": "What is the review FAKE-SPEC?",
                        "answerable": True,
                        "expected": [{"doc_id": "FAKE-DOC", "page": 997}],
                        "expected_value": "997",
                        "unit": "Nm",
                        "label_status": "needs_review",
                    }
                ),
                json.dumps(
                    {
                        "id": "fake-unlabeled",
                        "question": "Where else is FAKE-PART?",
                        "answerable": False,
                        "expected": [],
                    }
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    trace = tmp_path / "before.json"
    trace.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "label": "before",
                "golden_path": "eval/golden.jsonl",
                "runner": "http_backend",
                "questions": [
                    {
                        "id": "fake-hit",
                        "answer_text": "FAKE-STEP is 999 N·m.",
                        "refused": False,
                        "cited_pages": [{"doc_id": "FAKE-DOC", "page": 999}],
                    },
                    {
                        "id": "fake-refused",
                        "answer_text": "Not found in the cited manual text: 998 Nm.",
                        "refused": True,
                    },
                    {
                        "id": "fake-review",
                        "answer_text": "FAKE-STEP is 997 Nm.",
                        "refused": False,
                    },
                    {
                        "id": "fake-unlabeled",
                        "answer_text": "See FAKE-PART.",
                        "refused": False,
                    },
                    {
                        "id": "fake-missing-text",
                        "refused": False,
                    },
                ],
            }
        ),
        encoding="utf-8",
    )

    payload = rescore(trace, golden)
    code = main(["--rescore", str(trace), "--golden", str(golden)])
    printed = capsys.readouterr().out

    assert payload["metrics"]["value_match"] == 0.5
    assert payload["metrics"]["value_match_excluded"] == 3
    assert payload["metrics"]["refused_count"] == 1
    assert payload["runner"] == "rescore"
    assert code == 0
    assert "| value_match | 0.5000 |" in printed
    assert "value_match excluded 3 questions with no labeled value. refused count 1." in printed
    assert f"Rescored {trace}" in printed
