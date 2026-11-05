"""Which golden questions ask for a spec value, and when a quote contains it.

`ok` labels have to pass `quote_contains_value_and_unit`. Thousands
separators and zeros after a decimal point are the only number-format
differences that still match. The unit must occur character for character.
"""

from __future__ import annotations

import re

_VALUE_WORDS = frozenset(
    {
        "torque",
        "torques",
        "resistance",
        "clearance",
        "capacity",
        "pressure",
        "gap",
        "voltage",
        "advance",
        "boost",
        "length",
        "ohm",
        "ohms",
    }
)
_VALUE_PHRASES = frozenset(
    {
        ("how", "much"),
        ("how", "many"),
        ("how", "tight"),
        ("ignition", "timing"),
    }
)
_WORD_RE = re.compile(r"[a-z0-9]+")
# Comma groups first so "1,120" is one token, not "1" and "120".
_NUMBER_RE = re.compile(r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?")


def is_spec_value_question(question: str) -> bool:
    """True when the question asks for a measurable spec value.

    Pinouts, connector ids, and wire colors are not values for this label.
    """
    tokens = _WORD_RE.findall(question.casefold())
    if any(token in _VALUE_WORDS for token in tokens):
        return True
    return any(
        (tokens[index], tokens[index + 1]) in _VALUE_PHRASES
        for index in range(len(tokens) - 1)
    )


def quote_contains_value_and_unit(
    expected_value: str, unit: str, source_quote: str
) -> bool:
    """True when the quote states this value and this unit.

    The unit must occur character for character. A number matches when the
    only differences are thousands commas or zeros after the decimal point.
    """
    if not unit or unit not in source_quote:
        return False
    wanted = _canonical_number(expected_value)
    if wanted is None:
        return False
    found = _NUMBER_RE.findall(source_quote)
    return any(_canonical_number(token) == wanted for token in found)


def _canonical_number(token: str) -> str | None:
    text = token.strip().replace(",", "")
    if not re.fullmatch(r"\d+(?:\.\d+)?", text):
        return None
    if "." not in text:
        return text
    whole, frac = text.split(".", 1)
    frac = frac.rstrip("0")
    if not frac:
        return whole
    return f"{whole}.{frac}"
