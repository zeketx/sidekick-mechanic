"""Metric math for one eval run.

Recall@5 is null unless the runner supplies retrieval hits. Citation overlap
is not retrieval. The local uncited-number counter is a stand-in for the
spec guard: pass an ``UncitedNumberCounter`` to replace it.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any, Protocol

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
    "uncited-number count": (
        "Count of numeric tokens in answer text that do not appear in a "
        "citation snippet, summed across the run. The local counter does "
        "not understand units or pinouts. An UncitedNumberCounter replaces it."
    ),
    "latency p50 (ms)": (
        "50th percentile of per-question runner time in milliseconds. "
        "Linear index (n - 1) * 0.50."
    ),
    "latency p95 (ms)": (
        "95th percentile of per-question runner time in milliseconds. "
        "Linear index (n - 1) * 0.95."
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
    uncited_number_count: int


@dataclass(frozen=True)
class Metrics:
    recall_at_5: float | None
    citation_accuracy: float | None
    refusal_correctness: float | None
    uncited_number_count: int
    latency_p50_ms: float | None
    latency_p95_ms: float | None


class LocalUncitedNumberCounter:
    """Count digit tokens in answer text missing from citation snippets.

    ``name`` is recorded on the results file so a later guard can identify
    itself. This counter does not know units or connector names.
    """

    name = "local"

    def count(self, answer: Mapping[str, Any]) -> int:
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
        citation_accurate=citation_is_accurate(expected, answer) if answerable else None,
        refusal_correct=is_correct_refusal(answer) if not answerable else None,
        uncited_number_count=count_uncited_numbers(answer, counter),
    )


def aggregate_metrics(cases: Sequence[CaseScore]) -> Metrics:
    recalls = [case.recall_at_5 for case in cases if case.recall_at_5 is not None]
    citations = [
        case.citation_accurate for case in cases if case.citation_accurate is not None
    ]
    refusals = [case.refusal_correct for case in cases if case.refusal_correct is not None]
    latencies = [case.latency_ms for case in cases]
    return Metrics(
        recall_at_5=_mean(recalls),
        citation_accuracy=_mean([1.0 if hit else 0.0 for hit in citations]),
        refusal_correctness=_mean([1.0 if hit else 0.0 for hit in refusals]),
        uncited_number_count=sum(case.uncited_number_count for case in cases),
        latency_p50_ms=percentile(latencies, 50),
        latency_p95_ms=percentile(latencies, 95),
    )


def _mean(values: Sequence[float] | None) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


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
