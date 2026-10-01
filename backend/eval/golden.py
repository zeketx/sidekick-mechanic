"""Load and validate the golden-set JSONL."""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema.exceptions import ValidationError
from jsonschema.validators import Draft202012Validator

EVAL_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = EVAL_DIR / "golden.schema.json"
SAMPLE_PATH = EVAL_DIR / "golden.sample.jsonl"
GOLDEN_PATH = EVAL_DIR / "golden.jsonl"
RESULTS_DIR = EVAL_DIR / "results"


class GoldenSetError(ValueError):
    """The golden file is missing, empty, or fails the schema."""


@dataclass(frozen=True)
class ExpectedPage:
    doc_id: str
    page: int


@dataclass(frozen=True)
class GoldenQuestion:
    id: str
    question: str
    answerable: bool
    expected: tuple[ExpectedPage, ...]
    part_id: str | None
    ci: bool

    def expected_pairs(self) -> tuple[tuple[str, int], ...]:
        return tuple((page.doc_id, page.page) for page in self.expected)


def resolve_golden_path(explicit: Path | None = None) -> Path:
    """Use an explicit path, else golden.jsonl when it exists, else the sample."""
    if explicit is not None:
        return explicit
    if GOLDEN_PATH.is_file():
        return GOLDEN_PATH
    return SAMPLE_PATH


def load_golden(path: Path, *, ci_only: bool = False) -> tuple[GoldenQuestion, ...]:
    if not path.is_file():
        raise GoldenSetError(f"golden file not found: {path}")
    questions = _parse_lines(path)
    if ci_only:
        questions = tuple(question for question in questions if question.ci)
        if not questions:
            raise GoldenSetError(f"no ci rows in {path}")
    return questions


@lru_cache(maxsize=1)
def _validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


def _parse_lines(path: Path) -> tuple[GoldenQuestion, ...]:
    questions: list[GoldenQuestion] = []
    seen: set[str] = set()
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise GoldenSetError(f"{path}:{line_number}: invalid JSON") from exc
        if not isinstance(payload, dict):
            raise GoldenSetError(f"{path}:{line_number}: row is not an object")
        try:
            _validator().validate(payload)
        except ValidationError as exc:
            raise GoldenSetError(f"{path}:{line_number}: {exc.message}") from exc
        question = _question_from_payload(payload)
        if question.id in seen:
            raise GoldenSetError(f"{path}:{line_number}: duplicate id {question.id}")
        seen.add(question.id)
        questions.append(question)
    if not questions:
        raise GoldenSetError(f"no questions in {path}")
    return tuple(questions)


def _question_from_payload(payload: dict[str, Any]) -> GoldenQuestion:
    expected = tuple(
        ExpectedPage(doc_id=item["doc_id"], page=item["page"])
        for item in payload["expected"]
    )
    part_id = payload.get("part_id")
    return GoldenQuestion(
        id=payload["id"],
        question=payload["question"],
        answerable=payload["answerable"],
        expected=expected,
        part_id=part_id if isinstance(part_id, str) else None,
        ci=payload.get("ci") is True,
    )
