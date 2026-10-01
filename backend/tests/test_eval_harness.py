"""Harness, golden-file, and metrics-doc tests. Pages are fake."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from eval.golden import SAMPLE_PATH, GoldenSetError, load_golden
from eval.harness import run_harness
from eval.report import (
    ResultsError,
    latest_results_path,
    render_job_summary,
    render_metrics_markdown,
    write_metrics_document,
)
from eval.runner import InProcessChatRunner, RetrievedHit, RunnerError, RunnerOutput
from llm import DEFAULT_FAKE_TEXT

FAKE_DATE = "2026-10-01"


def test_sample_set_is_fake_and_has_a_smaller_ci_subset() -> None:
    questions = load_golden(SAMPLE_PATH)
    ci_questions = load_golden(SAMPLE_PATH, ci_only=True)

    assert len(questions) >= 2
    assert 0 < len(ci_questions) < len(questions)
    assert any(question.answerable for question in questions)
    assert any(not question.answerable for question in questions)
    assert any(question.part_id is not None for question in questions)
    for question in questions:
        assert question.id.startswith("fake-")
        assert question.part_id is None or question.part_id.startswith("fake-")
        for page in question.expected:
            assert page.doc_id.startswith("FAKE-")
            assert page.page == 999


def test_load_golden_rejects_answerable_row_without_pages(tmp_path: Path) -> None:
    path = tmp_path / "bad.jsonl"
    path.write_text(
        json.dumps(
            {
                "id": "fake-empty",
                "question": "Where is FAKE-PART?",
                "answerable": True,
                "expected": [],
            }
        )
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GoldenSetError, match="should be non-empty"):
        load_golden(path)


def test_load_golden_rejects_duplicate_ids(tmp_path: Path) -> None:
    row = {
        "id": "fake-dup",
        "question": "Where is FAKE-PART?",
        "answerable": False,
        "expected": [],
    }
    path = tmp_path / "dup.jsonl"
    path.write_text(json.dumps(row) + "\n" + json.dumps(row) + "\n", encoding="utf-8")

    with pytest.raises(GoldenSetError, match="duplicate id"):
        load_golden(path)


def test_inprocess_runner_uses_fake_llm_and_no_retrieval() -> None:
    output = InProcessChatRunner().run("Where is FAKE-PART-INTAKE?")

    assert output.retrieval is None
    assert output.latency_ms >= 0
    assert output.answer == {
        "kind": "answer",
        "text": DEFAULT_FAKE_TEXT,
        "citations": [],
    }


def test_harness_sample_does_not_invent_recall(tmp_path: Path) -> None:
    payload = run_harness(SAMPLE_PATH, output_dir=tmp_path, date=FAKE_DATE)
    written = json.loads((tmp_path / f"{FAKE_DATE}.json").read_text(encoding="utf-8"))

    assert payload["metrics"]["recall_at_5"] is None
    assert payload["uncited_number_counter"] == "local"
    assert payload["runner"] == "inprocess_chat_fake_llm"
    assert payload["subset"] == "full"
    assert payload["case_count"] == 4
    assert written["metrics"]["recall_at_5"] is None
    assert written["metrics"]["citation_accuracy"] == 0.0
    assert written["metrics"]["refusal_correctness"] == 0.0
    assert written["metrics"]["uncited_number_count"] == 0
    assert written["metrics"]["latency_p50_ms"] >= 0
    assert written["metrics"]["latency_p95_ms"] >= written["metrics"]["latency_p50_ms"]
    assert all(case["retrieval_available"] is False for case in written["cases"])


def test_harness_ci_subset_is_smaller(tmp_path: Path) -> None:
    payload = run_harness(SAMPLE_PATH, output_dir=tmp_path, ci_only=True, date=FAKE_DATE)

    assert payload["subset"] == "ci"
    assert payload["case_count"] == 3
    assert {case["id"] for case in payload["cases"]} == {
        "fake-answerable-intake",
        "fake-answerable-pages",
        "fake-unanswerable-pinout",
    }


def test_scripted_runner_scores_retrieval_without_reading_citations(tmp_path: Path) -> None:
    path = _write_golden(
        tmp_path,
        [
            {
                "id": "fake-hit",
                "question": "Where is FAKE-PART?",
                "answerable": True,
                "expected": [{"doc_id": "FAKE-DOC-2JZ", "page": 999}],
                "part_id": "fake-part-intake",
            },
            {
                "id": "fake-refuse",
                "question": "What is FAKE-CONNECTOR?",
                "answerable": False,
                "expected": [],
            },
        ],
    )

    class Scripted:
        name = "scripted"

        def run(self, question: str) -> RunnerOutput:
            if question.startswith("Where"):
                return RunnerOutput(
                    answer={
                        "kind": "answer",
                        "text": "See the fixture page.",
                        "citations": [
                            {
                                "doc_id": "FAKE-DOC-2JZ",
                                "page": 999,
                                "snippet": "FAKE-SNIPPET",
                            }
                        ],
                    },
                    latency_ms=10,
                    retrieval=(RetrievedHit("FAKE-DOC-2JZ", 999),),
                )
            return RunnerOutput(
                answer={
                    "kind": "refusal",
                    "text": "Not found in the fixture.",
                    "reason": "not_found_in_manual",
                },
                latency_ms=30,
                retrieval=(),
            )

    payload = run_harness(path, runner=Scripted(), output_dir=tmp_path, date=FAKE_DATE)

    assert payload["runner"] == "scripted"
    assert payload["metrics"]["recall_at_5"] == 1.0
    assert payload["metrics"]["citation_accuracy"] == 1.0
    assert payload["metrics"]["refusal_correctness"] == 1.0
    assert payload["cases"][0]["part_id"] == "fake-part-intake"
    assert payload["cases"][1]["recall_at_5"] is None
    assert payload["cases"][1]["retrieval_available"] is True


def test_citations_do_not_count_as_retrieval(tmp_path: Path) -> None:
    path = _write_golden(
        tmp_path,
        [
            {
                "id": "fake-cited",
                "question": "Where is FAKE-PART?",
                "answerable": True,
                "expected": [{"doc_id": "FAKE-DOC-2JZ", "page": 999}],
            }
        ],
    )

    class CitingOnly:
        def run(self, question: str) -> RunnerOutput:
            del question
            return RunnerOutput(
                answer={
                    "kind": "answer",
                    "text": "See the fixture page.",
                    "citations": [
                        {
                            "doc_id": "FAKE-DOC-2JZ",
                            "page": 999,
                            "snippet": "FAKE-SNIPPET",
                        }
                    ],
                },
                latency_ms=4,
                retrieval=None,
            )

    payload = run_harness(path, runner=CitingOnly(), output_dir=tmp_path, date=FAKE_DATE)

    assert payload["metrics"]["recall_at_5"] is None
    assert payload["metrics"]["citation_accuracy"] == 1.0


def test_custom_counter_name_is_recorded(tmp_path: Path) -> None:
    class Guard:
        name = "spec_guard"

        def count(self, answer: dict[str, Any]) -> int:
            del answer
            return 2

    payload = run_harness(
        SAMPLE_PATH,
        output_dir=tmp_path,
        ci_only=True,
        date=FAKE_DATE,
        uncited_counter=Guard(),
    )

    assert payload["uncited_number_counter"] == "spec_guard"
    assert payload["metrics"]["uncited_number_count"] == 6


def test_invalid_runner_answer_fails(tmp_path: Path) -> None:
    path = _write_golden(
        tmp_path,
        [
            {
                "id": "fake-bad",
                "question": "Where is FAKE-PART?",
                "answerable": False,
                "expected": [],
            }
        ],
    )

    class Broken:
        def run(self, question: str) -> RunnerOutput:
            del question
            return RunnerOutput(
                answer={"kind": "answer", "text": "", "citations": []},
                latency_ms=1,
            )

    with pytest.raises(RunnerError, match="failed the contract"):
        run_harness(path, runner=Broken(), output_dir=tmp_path, date=FAKE_DATE)


def test_metrics_markdown_uses_results_and_tbd_targets(tmp_path: Path) -> None:
    results = tmp_path / "2026-10-01.json"
    results.write_text(
        json.dumps(
            {
                "generated_at": "2026-10-01T12:00:00+00:00",
                "date": "2026-10-01",
                "runner": "inprocess_chat_fake_llm",
                "subset": "full",
                "case_count": 1,
                "uncited_number_counter": "local",
                "metrics": {
                    "recall_at_5": None,
                    "citation_accuracy": 0.0,
                    "refusal_correctness": 1.0,
                    "uncited_number_count": 3,
                    "latency_p50_ms": 1.5,
                    "latency_p95_ms": 2.25,
                },
            }
        ),
        encoding="utf-8",
    )
    destination = tmp_path / "METRICS.md"

    write_metrics_document(results, destination)
    text = destination.read_text(encoding="utf-8")

    assert "| Metric | Target | Current value | Date |" in text
    assert "| recall@5 | TBD | not available | 2026-10-01 |" in text
    assert "| citation accuracy | TBD | 0.0000 | 2026-10-01 |" in text
    assert "| refusal correctness | TBD | 1.0000 | 2026-10-01 |" in text
    assert "| uncited-number count | TBD | 3 | 2026-10-01 |" in text
    assert "| latency p50 (ms) | TBD | 1.500 | 2026-10-01 |" in text
    assert "| latency p95 (ms) | TBD | 2.250 | 2026-10-01 |" in text
    assert "Do not edit this file by hand." in text
    assert "null" in text.lower() or "Null" in text


def test_job_summary_shows_not_available_for_null_recall(tmp_path: Path) -> None:
    payload = run_harness(SAMPLE_PATH, output_dir=tmp_path, ci_only=True, date=FAKE_DATE)

    summary = render_job_summary(payload)

    assert "| recall@5 | not available |" in summary
    assert "ci subset" in summary


def test_latest_results_follow_generated_at(tmp_path: Path) -> None:
    older = tmp_path / "2026-10-02.json"
    newer = tmp_path / "2026-09-01.json"
    older.write_text(
        json.dumps(_metrics_payload("2026-10-02T00:00:00+00:00")),
        encoding="utf-8",
    )
    newer.write_text(
        json.dumps(_metrics_payload("2026-10-03T00:00:00+00:00")),
        encoding="utf-8",
    )

    assert latest_results_path(tmp_path) == newer


def test_metrics_render_rejects_a_file_without_metrics(tmp_path: Path) -> None:
    path = tmp_path / "empty.json"
    path.write_text("{}", encoding="utf-8")

    with pytest.raises(ResultsError, match="missing metrics"):
        render_metrics_markdown_from(path)


def test_ci_flag_rejects_a_set_with_no_ci_rows(tmp_path: Path) -> None:
    path = _write_golden(
        tmp_path,
        [
            {
                "id": "fake-full-only",
                "question": "Where is FAKE-PART?",
                "answerable": False,
                "expected": [],
                "ci": False,
            }
        ],
    )

    with pytest.raises(GoldenSetError, match="no ci rows"):
        load_golden(path, ci_only=True)


def _write_golden(tmp_path: Path, rows: list[dict[str, Any]]) -> Path:
    path = tmp_path / "golden.jsonl"
    path.write_text(
        "".join(json.dumps(row) + "\n" for row in rows),
        encoding="utf-8",
    )
    return path


def _metrics_payload(generated_at: str) -> dict[str, Any]:
    return {
        "generated_at": generated_at,
        "metrics": {
            "recall_at_5": None,
            "citation_accuracy": 0,
            "refusal_correctness": 0,
            "uncited_number_count": 0,
            "latency_p50_ms": 0,
            "latency_p95_ms": 0,
        },
    }


def render_metrics_markdown_from(path: Path) -> str:
    from eval.report import load_results

    return render_metrics_markdown(load_results(path), source=path)
