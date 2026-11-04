"""Recompute value_match from a saved trace and the current golden labels.

No model call. The trace must already hold each answer's text and refusal flag.
"""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from eval.golden import GoldenQuestion, load_golden, resolve_golden_path
from eval.metrics import _mean
from eval.trace import TraceError
from eval.value_match import is_scored_label, value_match_for


def rescore(trace_file: Path, golden_path: Path | None = None) -> dict[str, Any]:
    document = _load_trace(trace_file)
    questions = load_golden(resolve_golden_path(golden_path))
    by_id = {question.id: question for question in questions}
    rows = document["questions"]
    if not isinstance(rows, list):
        raise TraceError(f"{trace_file} questions is not a list")
    matches: list[bool] = []
    excluded = 0
    refused = 0
    for row in rows:
        if not isinstance(row, Mapping) or not isinstance(row.get("id"), str):
            excluded += 1
            continue
        question = by_id.get(row["id"])
        if question is None or not _scoreable(question):
            excluded += 1
            continue
        answer = _answer_from_trace(row)
        matched = value_match_for(
            answer,
            value=question.expected_value,
            unit=question.unit,
            label_status=question.label_status,
        )
        if matched is None:
            excluded += 1
            continue
        matches.append(matched)
        if answer.get("kind") == "refusal":
            refused += 1
    rate = _mean([1.0 if hit else 0.0 for hit in matches])
    golden = resolve_golden_path(golden_path)
    return {
        "subset": "full",
        "golden_path": golden.as_posix(),
        "runner": "rescore",
        "case_count": len(rows) if isinstance(rows, Sequence) else 0,
        "metrics": {
            "recall_at_5": None,
            "citation_accuracy": None,
            "value_match": None if rate is None else round(rate, 6),
            "value_match_excluded": excluded,
            "refused_count": refused,
            "refusal_correctness": None,
            "gap_coverage": None,
            "uncited_number_count": 0,
            "latency_p50_ms": None,
            "latency_p95_ms": None,
            "correct_part_rate": None,
            "region_iou": None,
            "unmapped_highlight_count": 0,
        },
    }


def _scoreable(question: GoldenQuestion) -> bool:
    return is_scored_label(question.expected_value, question.label_status)


def _answer_from_trace(row: Mapping[str, Any]) -> dict[str, Any]:
    text = row.get("answer_text")
    if not isinstance(text, str):
        text = ""
    if row.get("refused") is True:
        return {
            "kind": "refusal",
            "text": text,
            "reason": "not_found_in_manual",
        }
    return {"kind": "answer", "text": text, "citations": []}


def _load_trace(path: Path) -> Mapping[str, Any]:
    if not path.is_file():
        raise TraceError(f"trace file not found: {path}")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise TraceError(f"{path} is not JSON") from exc
    if not isinstance(document, dict) or "questions" not in document:
        raise TraceError(f"{path} has no questions")
    return document
