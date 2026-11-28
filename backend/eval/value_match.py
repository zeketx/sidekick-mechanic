"""Correctness proxy for a golden row that already labels a value and a unit.

Rows with no label are excluded. This module does not invent a spec.
Comparison reuses the spec guard's number and unit normalizer.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from spec_guard import _extract, _extract_prepared, _prepare

_GUARD_PREFIX = "Not found in the cited manual text:"


def is_scored_label(expected_value: str | None, label_status: str | None) -> bool:
    """True only for an ok label with a non-empty expected value.

    Missing fields, a needs_review status, and an empty value are excluded.
    """

    return (
        label_status == "ok"
        and isinstance(expected_value, str)
        and bool(expected_value.strip())
    )


def canonical_spec(value: str, unit: str) -> str | None:
    """One normalized ``number unit`` token, or None when the label is not a spec."""

    claims = _extract(f"{value} {unit}")
    if len(claims) != 1:
        return None
    return _stripped(claims[0].canonical)


def answer_contains_spec(text: str, value: str, unit: str) -> bool:
    """True when ``text`` states ``value`` in ``unit`` after normalization.

    A range in the answer covers either endpoint. A range in the label
    matches only that same range.
    """

    wanted = canonical_spec(value, unit)
    if wanted is None or not text:
        return False
    claims = _extract_prepared(_prepare(text), range_endpoints=True)
    return wanted in {_stripped(claim.canonical) for claim in claims}


def value_match_for(
    answer: Mapping[str, Any],
    *,
    value: str | None,
    unit: str | None,
    label_status: str | None = None,
) -> bool | None:
    """True, false, or None when the question is not an ok labeled value.

    A refusal is a miss even when the refusal text names the labeled value.
    A missing unit on an otherwise ok label is a miss. The number alone is
    not a spec.
    """

    if not is_scored_label(value, label_status):
        return None
    if answer.get("kind") == "refusal":
        return False
    text = answer.get("text")
    if not isinstance(text, str) or not isinstance(unit, str) or not unit.strip():
        return False
    assert value is not None
    return answer_contains_spec(text, value.strip(), unit)


def is_refusal(answer: Mapping[str, Any]) -> bool:
    return answer.get("kind") == "refusal"


def guard_decision(answer: Mapping[str, Any]) -> dict[str, str]:
    """The decision already applied to this payload.

    The spec guard replaces a blocked answer with a refusal whose text
    starts with a fixed prefix. Any other payload was not blocked.
    """

    text = answer.get("text")
    if (
        answer.get("kind") == "refusal"
        and isinstance(text, str)
        and text.startswith(_GUARD_PREFIX)
    ):
        reason = text[len(_GUARD_PREFIX) :].strip()
        if reason.endswith("."):
            reason = reason[:-1].strip()
        return {"decision": "blocked", "reason": reason or "blocked claim"}
    kind = answer.get("kind")
    if kind == "refusal":
        return {
            "decision": "allowed",
            "reason": "guard left a non-spec refusal unchanged",
        }
    if kind == "general_advice":
        return {"decision": "allowed", "reason": "guard returned general advice"}
    if kind == "answer":
        return {"decision": "allowed", "reason": "guard returned the answer"}
    return {"decision": "allowed", "reason": "guard returned the payload"}


def _stripped(canonical: str) -> str:
    number, separator, unit = canonical.partition(" ")
    if separator != " ":
        return canonical
    return f"{_strip_number(number)} {unit}"


def _strip_number(number: str) -> str:
    if "/" in number or "e" in number or "E" in number:
        return number
    if "-" in number and not number.startswith("-"):
        left, right = number.split("-", 1)
        return f"{_strip_number(left)}-{_strip_number(right)}"
    if "." not in number:
        return number
    whole, frac = number.split(".", 1)
    frac = frac.rstrip("0")
    if not frac:
        return whole or "0"
    return f"{whole}.{frac}"
