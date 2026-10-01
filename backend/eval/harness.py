"""Run a golden set and write eval/results/<date>.json."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema.exceptions import ValidationError

from contract import validate_answer
from eval.golden import (
    RESULTS_DIR,
    GoldenQuestion,
    load_golden,
    resolve_golden_path,
)
from eval.metrics import (
    METRIC_DEFINITIONS,
    CaseScore,
    Metrics,
    UncitedNumberCounter,
    aggregate_metrics,
    counter_name,
    score_case,
)
from eval.runner import EvalRunner, InProcessChatRunner, RetrievedHit, RunnerError

SCHEMA_VERSION = 1


def run_harness(
    golden_path: Path | None = None,
    *,
    runner: EvalRunner | None = None,
    output_dir: Path = RESULTS_DIR,
    ci_only: bool = False,
    date: str | None = None,
    uncited_counter: UncitedNumberCounter | None = None,
) -> dict[str, Any]:
    path = resolve_golden_path(golden_path)
    questions = load_golden(path, ci_only=ci_only)
    chosen = runner if runner is not None else InProcessChatRunner()
    scores = [
        _score_question(question, chosen, uncited_counter) for question in questions
    ]
    metrics = aggregate_metrics(scores)
    payload = _payload(
        golden_path=path,
        runner_name=_runner_name(chosen),
        ci_only=ci_only,
        date=date or _utc_date(),
        scores=scores,
        metrics=metrics,
        counter_label=counter_name(uncited_counter),
    )
    _write_results(output_dir, payload)
    return payload


def _score_question(
    question: GoldenQuestion,
    runner: EvalRunner,
    counter: UncitedNumberCounter | None,
) -> CaseScore:
    output = runner.run(question.question)
    try:
        validate_answer(output.answer)
    except ValidationError as exc:
        raise RunnerError(
            f"{question.id} answer failed the contract: {exc.message}"
        ) from exc
    return score_case(
        question_id=question.id,
        answerable=question.answerable,
        expected=question.expected_pairs(),
        part_id=question.part_id,
        answer=output.answer,
        latency_ms=output.latency_ms,
        retrieval=_retrieval_pairs(output.retrieval),
        counter=counter,
    )


def _retrieval_pairs(
    retrieval: tuple[RetrievedHit, ...] | None,
) -> tuple[tuple[str, int], ...] | None:
    if retrieval is None:
        return None
    pairs: list[tuple[str, int]] = []
    for hit in retrieval:
        if not isinstance(hit.doc_id, str) or not hit.doc_id:
            raise RunnerError("retrieval hit is missing doc_id")
        if not isinstance(hit.page, int) or isinstance(hit.page, bool) or hit.page < 1:
            raise RunnerError("retrieval hit page must be an integer >= 1")
        pairs.append((hit.doc_id, hit.page))
    return tuple(pairs)


def _payload(
    *,
    golden_path: Path,
    runner_name: str,
    ci_only: bool,
    date: str,
    scores: list[CaseScore],
    metrics: Metrics,
    counter_label: str,
) -> dict[str, Any]:
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": generated_at,
        "date": date,
        "golden_path": _display_path(golden_path),
        "subset": "ci" if ci_only else "full",
        "runner": runner_name,
        "uncited_number_counter": counter_label,
        "case_count": len(scores),
        "definitions": METRIC_DEFINITIONS,
        "metrics": {
            "recall_at_5": _round_rate(metrics.recall_at_5),
            "citation_accuracy": _round_rate(metrics.citation_accuracy),
            "refusal_correctness": _round_rate(metrics.refusal_correctness),
            "uncited_number_count": metrics.uncited_number_count,
            "latency_p50_ms": _round_latency(metrics.latency_p50_ms),
            "latency_p95_ms": _round_latency(metrics.latency_p95_ms),
        },
        "cases": [_case_dict(score) for score in scores],
    }


def _case_dict(score: CaseScore) -> dict[str, Any]:
    body: dict[str, Any] = {
        "id": score.id,
        "answerable": score.answerable,
        "latency_ms": _round_latency(score.latency_ms),
        "answer_kind": score.answer_kind,
        "retrieval_available": score.retrieval_available,
        "recall_at_5": _round_rate(score.recall_at_5),
        "citation_accurate": score.citation_accurate,
        "refusal_correct": score.refusal_correct,
        "uncited_number_count": score.uncited_number_count,
    }
    if score.part_id is not None:
        body["part_id"] = score.part_id
    return body


def _write_results(output_dir: Path, payload: dict[str, Any]) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    destination = output_dir / f"{payload['date']}.json"
    text = json.dumps(payload, indent=2, allow_nan=False, ensure_ascii=True)
    destination.write_text(text + "\n", encoding="utf-8")
    return destination


def _runner_name(runner: EvalRunner) -> str:
    name = getattr(runner, "name", None)
    if isinstance(name, str) and name:
        return name
    return type(runner).__name__


def _display_path(path: Path) -> str:
    backend = EVAL_BACKEND_ROOT
    resolved = path.resolve()
    try:
        return resolved.relative_to(backend).as_posix()
    except ValueError:
        return resolved.as_posix()


def _utc_date() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def _round_rate(value: float | None) -> float | None:
    if value is None:
        return None
    return round(value, 6)


def _round_latency(value: float | None) -> float | None:
    if value is None:
        return None
    return round(value, 3)


EVAL_BACKEND_ROOT = Path(__file__).resolve().parent.parent
