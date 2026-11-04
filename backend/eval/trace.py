"""Per-question eval trace. One JSON file, no second scoring pipeline."""

from __future__ import annotations

import json
import re
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from eval.golden import EVAL_DIR
from eval.runner import RetrievedHit
from eval.value_match import guard_decision, is_refusal, value_is_labeled, value_match_for

TRACE_DIR = EVAL_DIR / "traces"
_LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")


class TraceError(ValueError):
    """The trace label or document cannot be written."""


def trace_path(label: str, directory: Path = TRACE_DIR) -> Path:
    if _LABEL.fullmatch(label) is None:
        raise TraceError(f"trace label is not a file stem: {label}")
    return directory / f"{label}.json"


def question_trace(
    question_id: str,
    answer: Mapping[str, Any],
    retrieval: Sequence[RetrievedHit] | None,
    *,
    value: str | None,
    unit: str | None,
) -> dict[str, Any]:
    labeled = value_is_labeled(value, unit)
    return {
        "id": question_id,
        "cited_pages": _cited_pages(answer),
        "top5": None if retrieval is None else _top5(retrieval),
        "guard": guard_decision(answer),
        "value_labeled": labeled,
        "value_match": value_match_for(answer, value=value, unit=unit),
        "refused": is_refusal(answer),
    }


def trace_document(
    *,
    label: str,
    golden_path: str,
    runner: str,
    questions: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "label": label,
        "golden_path": golden_path,
        "runner": runner,
        "questions": list(questions),
    }


def write_trace(path: Path, document: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(document, indent=2, sort_keys=True, ensure_ascii=True)
    path.write_text(text + "\n", encoding="utf-8")


def _cited_pages(answer: Mapping[str, Any]) -> list[dict[str, Any]]:
    if answer.get("kind") != "answer":
        return []
    citations = answer.get("citations")
    if not isinstance(citations, list):
        return []
    pages: list[dict[str, Any]] = []
    for citation in citations:
        if not isinstance(citation, Mapping):
            continue
        doc_id = citation.get("doc_id")
        page = citation.get("page")
        if not isinstance(doc_id, str) or not isinstance(page, int) or isinstance(page, bool):
            continue
        pages.append({"doc_id": doc_id, "page": page})
    return pages


def _top5(retrieval: Sequence[RetrievedHit]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for hit in list(retrieval)[:5]:
        score = None if hit.score is None else round(float(hit.score), 6)
        rows.append({"doc_id": hit.doc_id, "page": hit.page, "score": score})
    return rows
