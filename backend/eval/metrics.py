"""Metric math for one eval run.

Recall@5 is null unless the runner supplies retrieval hits. Citation overlap
is not retrieval. The local uncited-number counter is a stand-in for the
spec guard: pass an ``UncitedNumberCounter`` to replace it.
"""

from __future__ import annotations

import re
from collections.abc import Collection, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, Protocol

from general_advice import ADVICE_HONESTY

Page = tuple[str, int]

# Standalone numeric token. Does not parse units or pin names.
_NUMBER = re.compile(r"(?<!\d)(\d+(?:\.\d+)?)(?!\d)")

METRIC_DEFINITIONS: dict[str, str] = {
    "recall@5": (
        "Mean, over answerable questions that have retrieval hits, of "
        "how many expected (doc_id, page) pairs appear in the first 5 hits. "
        "Null when no question has retrieval. An empty hit list scores 0. "
        "Citations are not treated as retrieval."
    ),
    "citation accuracy": (
        "Fraction of answerable questions whose answer cites at least one "
        "page and every cited (doc_id, page) is in the expected set. "
        "A refusal or an empty citation list scores 0 for that question."
    ),
    "refusal correctness": (
        "Fraction of unanswerable questions returned as a contract refusal "
        "(kind refusal, reason not_found_in_manual)."
    ),
    "gap coverage": (
        "Fraction of unanswerable questions that returned either a contract "
        "refusal or general advice with the honesty line and at least one step."
    ),
    "uncited-number count": (
        "Sum of the active counter's count for each answer. The local "
        "counter counts digit tokens in answer text that do not appear in a "
        "citation snippet. For general advice it counts digit tokens in the "
        "steps, and related snippets do not excuse a number. It does not "
        "understand units or pinouts. The spec "
        "guard counter counts unit-numbers and pin references it would block. "
        "The results file names the counter."
    ),
    "latency p50 (ms)": (
        "50th percentile of per-question runner time in milliseconds. "
        "Linear index (n - 1) * 0.50."
    ),
    "latency p95 (ms)": (
        "95th percentile of per-question runner time in milliseconds. "
        "Linear index (n - 1) * 0.95."
    ),
    "correct-part rate": (
        "Fraction of golden questions whose part_id is a confirmed bay-map "
        "part and whose answer highlight names that same part_id. Questions "
        "with no part_id, or a part that has no confirmed region, are left "
        "out. A missing highlight scores 0."
    ),
    "region IoU": (
        "Mean intersection-over-union of each held-out hand label against "
        "the confirmed bay-map polygons the highlight renderer draws for "
        "that photo and part. A label whose pair is not confirmed is left "
        "out. Null when none resolve. Coordinates are the bay map's "
        "normalized plane, which the renderer scales to the photo. "
        "Rings must be convex. "
        "eval/hand_labels.json is used when that file exists; otherwise "
        "the synthetic fixture. This score does not depend on which "
        "golden questions ran."
    ),
    "unmapped-highlight count": (
        "Number of answer highlights whose part_id is not a confirmed "
        "bay-map part. Must be 0. python -m eval exits 1 when it is not."
    ),
}


class UncitedNumberCounter(Protocol):
    """Hook for the spec guard. ``count`` returns uncited numeric specs."""

    def count(self, answer: Mapping[str, Any]) -> int:
        """Return how many numeric specs in this answer lack support."""


@dataclass(frozen=True)
class CaseScore:
    id: str
    answerable: bool
    part_id: str | None
    latency_ms: float
    answer_kind: str
    retrieval_available: bool
    recall_at_5: float | None
    citation_accurate: bool | None
    refusal_correct: bool | None
    gap_covered: bool | None
    uncited_number_count: int
    correct_part: bool | None
    unmapped_highlight: int


@dataclass(frozen=True)
class Metrics:
    recall_at_5: float | None
    citation_accuracy: float | None
    refusal_correctness: float | None
    gap_coverage: float | None
    uncited_number_count: int
    latency_p50_ms: float | None
    latency_p95_ms: float | None
    correct_part_rate: float | None
    unmapped_highlight_count: int


class LocalUncitedNumberCounter:
    """Count digit tokens in answer text missing from citation snippets.

    General advice counts digit tokens in the steps. Related snippets do not
    excuse a number there. ``name`` is recorded on the results file so a
    later guard can identify itself. This counter does not know units or
    connector names.
    """

    name = "local"

    def count(self, answer: Mapping[str, Any]) -> int:
        if answer.get("kind") == "general_advice":
            return _digit_count(_step_text(answer))
        text = answer.get("text")
        if not isinstance(text, str):
            return 0
        snippets = _citation_snippets(answer)
        count = 0
        for match in _NUMBER.finditer(text):
            token = match.group(1)
            if any(_snippet_has_number(snippet, token) for snippet in snippets):
                continue
            count += 1
        return count


def count_uncited_numbers(
    answer: Mapping[str, Any],
    counter: UncitedNumberCounter | None = None,
) -> int:
    chosen = counter if counter is not None else LocalUncitedNumberCounter()
    count = chosen.count(answer)
    if isinstance(count, bool) or not isinstance(count, int):
        raise TypeError("uncited-number counter must return an int")
    if count < 0:
        raise ValueError("uncited-number counter returned a negative count")
    return count


def counter_name(counter: UncitedNumberCounter | None) -> str:
    if counter is None:
        return LocalUncitedNumberCounter.name
    name = getattr(counter, "name", None)
    if isinstance(name, str) and name:
        return name
    return "custom"


def recall_at_5(
    expected: Sequence[Page],
    retrieved: Sequence[Page] | None,
) -> float | None:
    """Fraction of expected pages present in the first five hits.

    ``None`` means retrieval was not run. An empty sequence means it ran
    and returned nothing.
    """
    if retrieved is None:
        return None
    expected_set = set(expected)
    if not expected_set:
        return None
    found = expected_set & set(retrieved[:5])
    return len(found) / len(expected_set)


def citation_is_accurate(expected: Sequence[Page], answer: Mapping[str, Any]) -> bool:
    if answer.get("kind") != "answer":
        return False
    citations = answer.get("citations")
    if not isinstance(citations, list) or not citations:
        return False
    expected_set = set(expected)
    for citation in citations:
        if not isinstance(citation, Mapping):
            return False
        page = (citation.get("doc_id"), citation.get("page"))
        if page not in expected_set:
            return False
    return True


def is_correct_refusal(answer: Mapping[str, Any]) -> bool:
    return (
        answer.get("kind") == "refusal"
        and answer.get("reason") == "not_found_in_manual"
    )


def gap_path_ok(answer: Mapping[str, Any]) -> bool:
    """True for a contract refusal or general advice with the honesty line and steps."""

    if is_correct_refusal(answer):
        return True
    if answer.get("kind") != "general_advice":
        return False
    if answer.get("honesty") != ADVICE_HONESTY:
        return False
    steps = answer.get("steps")
    if not isinstance(steps, list) or not steps:
        return False
    return all(isinstance(step, str) and step for step in steps)


def part_is_correct(
    expected_part_id: str | None,
    answer: Mapping[str, Any],
    mapped_part_ids: Collection[str],
) -> bool | None:
    """Whether the highlight names the question's mapped part.

    ``None`` when the question does not name a confirmed bay-map part.
    """

    if expected_part_id is None or expected_part_id not in mapped_part_ids:
        return None
    highlight = answer.get("highlight")
    if not isinstance(highlight, Mapping):
        return False
    return highlight.get("part_id") == expected_part_id


def count_unmapped_highlight(
    answer: Mapping[str, Any],
    mapped_part_ids: Collection[str],
) -> int:
    """1 when the answer highlights a part that is not confirmed on the map."""

    highlight = answer.get("highlight")
    if not isinstance(highlight, Mapping):
        return 0
    part_id = highlight.get("part_id")
    if isinstance(part_id, str) and part_id in mapped_part_ids:
        return 0
    return 1


def percentile(values: Sequence[float], percent: float) -> float | None:
    """Linear percentile. Index is ``(n - 1) * (percent / 100)``."""
    if not values:
        return None
    if percent < 0 or percent > 100:
        raise ValueError("percent must be between 0 and 100")
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    index = (len(ordered) - 1) * (percent / 100)
    lower = int(index)
    upper = min(lower + 1, len(ordered) - 1)
    weight = index - lower
    return float(ordered[lower] * (1 - weight) + ordered[upper] * weight)


def score_case(
    *,
    question_id: str,
    answerable: bool,
    expected: Sequence[Page],
    part_id: str | None,
    answer: Mapping[str, Any],
    latency_ms: float,
    retrieval: Sequence[Page] | None,
    counter: UncitedNumberCounter | None = None,
    mapped_part_ids: Collection[str] = (),
) -> CaseScore:
    if latency_ms < 0:
        raise ValueError(f"{question_id} latency is negative")
    kind = answer.get("kind")
    if not isinstance(kind, str):
        raise ValueError(f"{question_id} answer is missing kind")
    recall = recall_at_5(expected, retrieval) if answerable else None
    return CaseScore(
        id=question_id,
        answerable=answerable,
        part_id=part_id,
        latency_ms=latency_ms,
        answer_kind=kind,
        retrieval_available=retrieval is not None,
        recall_at_5=recall,
        citation_accurate=citation_is_accurate(expected, answer)
        if answerable
        else None,
        refusal_correct=is_correct_refusal(answer) if not answerable else None,
        gap_covered=gap_path_ok(answer) if not answerable else None,
        uncited_number_count=count_uncited_numbers(answer, counter),
        correct_part=part_is_correct(part_id, answer, mapped_part_ids),
        unmapped_highlight=count_unmapped_highlight(answer, mapped_part_ids),
    )


def aggregate_metrics(cases: Sequence[CaseScore]) -> Metrics:
    recalls = [case.recall_at_5 for case in cases if case.recall_at_5 is not None]
    citations = [
        case.citation_accurate for case in cases if case.citation_accurate is not None
    ]
    refusals = [
        case.refusal_correct for case in cases if case.refusal_correct is not None
    ]
    gaps = [case.gap_covered for case in cases if case.gap_covered is not None]
    latencies = [case.latency_ms for case in cases]
    correct_parts = [
        case.correct_part for case in cases if case.correct_part is not None
    ]
    return Metrics(
        recall_at_5=_mean(recalls),
        citation_accuracy=_mean([1.0 if hit else 0.0 for hit in citations]),
        refusal_correctness=_mean([1.0 if hit else 0.0 for hit in refusals]),
        gap_coverage=_mean([1.0 if hit else 0.0 for hit in gaps]),
        uncited_number_count=sum(case.uncited_number_count for case in cases),
        latency_p50_ms=percentile(latencies, 50),
        latency_p95_ms=percentile(latencies, 95),
        correct_part_rate=_mean([1.0 if hit else 0.0 for hit in correct_parts]),
        unmapped_highlight_count=sum(case.unmapped_highlight for case in cases),
    )


def _mean(values: Sequence[float] | None) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def _step_text(answer: Mapping[str, Any]) -> str:
    steps = answer.get("steps")
    if not isinstance(steps, list):
        return ""
    return "\n".join(step for step in steps if isinstance(step, str))


def _digit_count(text: str) -> int:
    return sum(1 for _ in _NUMBER.finditer(text))


def _citation_snippets(answer: Mapping[str, Any]) -> list[str]:
    if answer.get("kind") != "answer":
        return []
    citations = answer.get("citations")
    if not isinstance(citations, list):
        return []
    snippets: list[str] = []
    for citation in citations:
        if isinstance(citation, Mapping) and isinstance(citation.get("snippet"), str):
            snippets.append(citation["snippet"])
    return snippets


def _snippet_has_number(snippet: str, token: str) -> bool:
    return re.search(rf"(?<!\d){re.escape(token)}(?!\d)", snippet) is not None
