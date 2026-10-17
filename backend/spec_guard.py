"""Post-generation spec guard.

Blocks numbers-with-units and pin, connector, and terminal references that
are not present in cited chunk text. Citation snippets on the answer are
not evidence. Normalization rules and the eval counter live in
``docs/design/spec-guard.md``.
"""

from __future__ import annotations

import html
import logging
import re
import threading
import unicodedata
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from contract import validate_answer

logger = logging.getLogger("sidekick.spec_guard")

# Longer forms come first. A shorter form must not win when a space follows
# it ("999 degrees celsius", "999 mm Hg", "999 ft-lb").
_UNIT_PATTERNS: tuple[tuple[str, str], ...] = (
    ("celsius", r"degrees?\s+celsius|°\s*c|deg(?:rees?)?\s+c"),
    ("fahrenheit", r"degrees?\s+fahrenheit|°\s*f|deg(?:rees?)?\s+f"),
    ("mmhg", r"mm\s*hg"),
    ("kgfcm2", r"kgf?\s*(?:[·⋅•.\-]\s*|/\s*)?cm\s*(?:\^?\s*2|²)"),
    ("kgfcm", r"kgf\s*(?:[·⋅•\-]\s*|\.(?!\s))?\s*cm(?!\s*(?:\^|\d))"),
    ("nm", r"newton[\s-]+met(?:er|re)s?|n\s*[·⋅•.\-]?\s*m"),
    ("kgfm", r"kgf\s*[·⋅•.\-]?\s*m|kg\s*[·⋅•.\-]?\s*m"),
    (
        "ftlbf",
        r"foot[\s-]+pounds?|ft[\s-]+pounds?|"
        r"ft\s*(?:[·⋅•\-]\s*|\.(?!\s))?\s*lb(?:f|s)?|"
        r"lb(?:f|s)?\s*(?:[·⋅•\-]\s*|\.(?!\s))?\s*ft",
    ),
    (
        "inlbf",
        r"inch[\s-]+pounds?|in[\s-]+pounds?|"
        r"in\s*(?:[·⋅•\-]\s*|\.(?!\s))?\s*lb(?:f|s)?",
    ),
    ("kohm", r"kilo[\s-]?ohms?|kohms?|k\s*ohms?"),
    ("megohm", r"meg[\s-]?ohms?"),
    ("milliohm", r"milli[\s-]?ohms?"),
    ("ohm", r"ohms?"),
    ("mv", r"millivolts?|mv"),
    ("kv", r"kilovolts?|kv"),
    ("kpa", r"kpa"),
    ("mpa", r"mpa"),
    ("psi", r"psi"),
    ("rpm", r"r\s*/\s*min|rpm"),
    ("mm", r"mm"),
    ("cm", r"cm"),
    ("um", r"microns?|um"),
    ("ml", r"millilit(?:er|re)s?|ml"),
    ("ma", r"milliamps?(?:eres?)?|ma"),
    ("pa", r"pa"),
    ("bar", r"bar"),
    # "in." / inch, not the word "in" ("step 3 in the manual").
    ("in", r"inches|inch|in\."),
    ("ft", r"feet|ft(?!\s*[·⋅•.\-]?\s*(?:lb|pound))"),
    ("l", r"lit(?:er|re)s?|l"),
    # Capital A only. Lowercase "a" is ordinary prose ("999 a bit").
    ("a", r"amps?|amperes?|(?-i:A)"),
    ("v", r"volts?|v"),
    ("deg", r"degrees?|deg|°"),
    ("m", r"m"),
    ("%", r"%"),
)

_NUMBER_BODY = (
    r"\d+(?:\.\d+)?-\d+(?:\.\d+)?"
    r"|-\d+(?:\.\d+)?"
    r"|\d+/\d+"
    r"|\d+(?:\.\d+)?[eE][+-]?\d+"
    r"|\d+,\d{1,2}"
    r"|\d+(?:\.\d+)?"
)

_MEASURE_RE = re.compile(
    r"(?<![A-Za-z0-9.])("
    + _NUMBER_BODY
    + r")\s*("
    + "|".join(f"(?:{pattern})" for _, pattern in _UNIT_PATTERNS)
    + r")(?![A-Za-z0-9])",
    re.IGNORECASE,
)

# A digit-bearing id, or one letter. Stops "pin 999 and pin 998" from
# treating the second "pin" as an id and swallowing it.
_PIN_ID = (
    r"(?:(?:[A-Za-z0-9]+-)*[A-Za-z]*\d[A-Za-z0-9]*"
    r"|[A-Za-z](?![A-Za-z0-9]))"
)
_PIN_RE = re.compile(
    rf"\b(pins?|connectors?|terminals?)\s+({_PIN_ID}(?:\s*(?:,|&|\band\b)\s+{_PIN_ID})*)",
    re.IGNORECASE,
)
# Advice steps only. A hash or colon is not the space `_PIN_RE` requires,
# so "pin #4" and "terminal: A" would otherwise reach the card.
_ADVICE_PIN_RE = re.compile(
    rf"\b(pins?|connectors?|terminals?)\s*[#:]\s*"
    rf"({_PIN_ID}(?:\s*(?:,|&|\band\b)\s*[#:]?\s*{_PIN_ID})*)",
    re.IGNORECASE,
)
# A mark between the number and the unit. "12.7. Nm" is not "12.7 Nm".
_ADVICE_MEASURE_RE = re.compile(
    r"(?<![A-Za-z0-9.])("
    + _NUMBER_BODY
    + r")\s*[#:.]+\s*("
    + "|".join(f"(?:{pattern})" for _, pattern in _UNIT_PATTERNS)
    + r")(?![A-Za-z0-9])",
    re.IGNORECASE,
)
_ID_SPLIT_RE = re.compile(r"\s*(?:,|&|\band\b)\s*", re.IGNORECASE)
_INVISIBLE_RE = re.compile("[\u200b\u200c\u200d\u2060\ufeff]")

_checks = 0
_failures = 0
_uncited_claims = 0
_stats_lock = threading.Lock()


@dataclass(frozen=True)
class GuardStats:
    """Process totals since the last ``reset_stats`` call.

    ``uncited_claims`` is the sum of ``GuardResult.uncited_count``.
    The eval harness should prefer the per-answer field; this snapshot is
    the same total for one process.
    """

    checks: int
    failures: int
    uncited_claims: int


@dataclass(frozen=True)
class GuardResult:
    """One guard decision.

    ``answer`` is the input payload, or a ``not_found_in_manual`` refusal
    when a claim is missing. ``uncited`` names those claims in answer order
    after normalization. It is empty when the payload is allowed through,
    including when the input was already a refusal.

    Sum ``uncited_count`` for the eval uncited-number count.
    """

    answer: dict[str, Any]
    uncited: tuple[str, ...]

    @property
    def uncited_count(self) -> int:
        return len(self.uncited)


@dataclass(frozen=True)
class _Claim:
    start: int
    surface: str
    canonical: str


def guard_answer(
    answer: Mapping[str, Any],
    cited_chunk_texts: Iterable[str],
) -> GuardResult:
    """Return ``answer`` or a refusal naming claims missing from the chunks.

    ``cited_chunk_texts`` is retrieved page text. Citation snippets inside
    ``answer`` are ignored. A payload that is already a refusal is returned
    with the same fields. ``general_advice`` steps are scanned one at a time,
    including a hash or colon on a pin id and a mark between a number and
    its unit. Hit text is not evidence for that kind. Found answers keep
    the spaced patterns only.
    """
    global _checks, _failures, _uncited_claims
    if not isinstance(answer, Mapping):
        raise TypeError("answer must be a mapping")
    texts = _require_chunk_texts(cited_chunk_texts)
    payload = dict(answer)
    kind = payload.get("kind")
    # A refusal names the missing claim. Scanning it would refuse again.
    if kind == "general_advice":
        return _guard_steps(payload)
    if kind != "answer" or not isinstance(payload.get("text"), str):
        return GuardResult(answer=payload, uncited=())

    known = _canonical_claims(texts)
    blocked = tuple(
        claim.surface
        for claim in _unique_claims(payload["text"])
        if claim.canonical not in known
    )
    with _stats_lock:
        _checks += 1
        if blocked:
            _failures += 1
            _uncited_claims += len(blocked)
    if not blocked:
        return GuardResult(answer=payload, uncited=())

    logger.warning(
        "spec guard blocked %d uncited claim(s): %s",
        len(blocked),
        ", ".join(blocked),
    )
    refusal = {
        "kind": "refusal",
        "text": "Not found in the cited manual text: " + ", ".join(blocked) + ".",
        "reason": "not_found_in_manual",
    }
    validate_answer(refusal)
    return GuardResult(answer=refusal, uncited=blocked)


def _guard_steps(payload: dict[str, Any]) -> GuardResult:
    global _checks, _failures, _uncited_claims
    steps = payload.get("steps")
    blocked = _claims_in_steps(steps if isinstance(steps, list) else ())
    with _stats_lock:
        _checks += 1
        if blocked:
            _failures += 1
            _uncited_claims += len(blocked)
    if not blocked:
        return GuardResult(answer=payload, uncited=())
    logger.warning(
        "spec guard blocked %d uncited claim(s): %s",
        len(blocked),
        ", ".join(blocked),
    )
    refusal = {
        "kind": "refusal",
        "text": "Not found in the cited manual text: " + ", ".join(blocked) + ".",
        "reason": "not_found_in_manual",
    }
    validate_answer(refusal)
    return GuardResult(answer=refusal, uncited=blocked)


def _claims_in_steps(steps: Sequence[object]) -> tuple[str, ...]:
    # Joining steps would invent a claim across the boundary ("999" then "Nm").
    seen: set[str] = set()
    surfaces: list[str] = []
    for step in steps:
        if not isinstance(step, str):
            continue
        for claim in (*_unique_claims(step), *_advice_only_claims(step)):
            if claim.canonical in seen:
                continue
            seen.add(claim.canonical)
            surfaces.append(claim.surface)
    return tuple(surfaces)


class SpecGuardUncitedCounter:
    """Harness hook. ``name`` is ``spec_guard``.

    ``count`` is how many claims ``guard_answer`` would block. The harness
    has no retrieved chunk text, and citation snippets are not evidence, so
    the chunk list is empty. A refusal counts as zero.
    """

    name = "spec_guard"

    def count(self, answer: Mapping[str, Any]) -> int:
        return guard_answer(answer, ()).uncited_count


def stats() -> GuardStats:
    """Return a snapshot of guard counters for this process."""
    with _stats_lock:
        return GuardStats(
            checks=_checks,
            failures=_failures,
            uncited_claims=_uncited_claims,
        )


def reset_stats() -> None:
    """Zero the process counters. Tests and a fresh eval run call this."""
    global _checks, _failures, _uncited_claims
    with _stats_lock:
        _checks = 0
        _failures = 0
        _uncited_claims = 0


def _require_chunk_texts(cited_chunk_texts: Iterable[str]) -> tuple[str, ...]:
    if isinstance(cited_chunk_texts, (str, bytes)):
        raise TypeError(
            "cited_chunk_texts must be a sequence of strings, not one string"
        )
    texts = tuple(cited_chunk_texts)
    for text in texts:
        if not isinstance(text, str):
            raise TypeError("each cited chunk text must be a string")
    return texts


def _canonical_claims(texts: Iterable[str]) -> set[str]:
    found: set[str] = set()
    for text in texts:
        prepared = _prepare(text)
        for claim in _extract_prepared(prepared, range_endpoints=True):
            found.add(claim.canonical)
        for claim in _table_torque_claims(prepared):
            found.add(claim.canonical)
    return found


def supporting_page_mask(
    answer_text: str, page_texts: Sequence[str]
) -> tuple[bool, ...] | None:
    """Which pages contain a unit or pin claim the answer states.

    ``None`` when the answer states no such claim, or when no page contains
    one. The caller keeps every citation in those cases so the guard can
    still refuse a number that is not on a cited page.
    """

    wanted = {claim.canonical for claim in _unique_claims(answer_text)}
    if not wanted:
        return None
    flags = tuple(
        bool(wanted & _canonical_claims((page_text,))) for page_text in page_texts
    )
    if not any(flags):
        return None
    return flags


def _unique_claims(text: str) -> tuple[_Claim, ...]:
    seen: set[str] = set()
    ordered: list[_Claim] = []
    for claim in _extract(text):
        if claim.canonical in seen:
            continue
        seen.add(claim.canonical)
        ordered.append(claim)
    return tuple(ordered)


def _advice_only_claims(text: str) -> tuple[_Claim, ...]:
    """Specs the shared extractor skips. Called from advice steps only.

    ``3. A clip`` stays prose: a sentence period before a one-letter unit
    is not a measurement. ``12.7. Nm`` and ``3. mm`` are.
    """
    prepared = _prepare(text)
    found: list[_Claim] = []
    for match in _ADVICE_MEASURE_RE.finditer(prepared):
        if not _advice_measure_separator(match):
            continue
        number = _canonical_number(match.group(1))
        unit = _canonical_unit(match.group(2))
        found.append(
            _Claim(
                start=match.start(),
                surface=match.group(0).strip(),
                canonical=f"{number} {unit}",
            )
        )
    for match in _ADVICE_PIN_RE.finditer(prepared):
        kind = _pin_kind(match.group(1))
        for token in _ID_SPLIT_RE.split(match.group(2)):
            cleaned = token.lstrip("#:").strip()
            pin_id = _pin_token(cleaned)
            if pin_id is None:
                continue
            found.append(
                _Claim(
                    start=match.start(),
                    surface=f"{kind} {cleaned}",
                    canonical=f"{kind} {pin_id}",
                )
            )
    found.sort(key=lambda claim: claim.start)
    return tuple(found)


def _advice_measure_separator(match: re.Match[str]) -> bool:
    between = match.group(0)[
        match.end(1) - match.start() : match.start(2) - match.start()
    ]
    if re.fullmatch(r"\s*[#:]+\s*", between):
        return True
    if not re.fullmatch(r"\s*\.+\s*", between):
        return False
    number = match.group(1)
    unit = match.group(2)
    return "." in number or len(unit) >= 2


def _extract(text: str) -> tuple[_Claim, ...]:
    return _extract_prepared(_prepare(text), range_endpoints=False)


def _extract_prepared(prepared: str, *, range_endpoints: bool) -> tuple[_Claim, ...]:
    found: list[_Claim] = []
    for match in _MEASURE_RE.finditer(prepared):
        number = _canonical_number(match.group(1))
        unit = _canonical_unit(match.group(2))
        found.append(
            _Claim(
                start=match.start(),
                surface=match.group(0).strip(),
                canonical=f"{number} {unit}",
            )
        )
        if range_endpoints:
            found.extend(_range_endpoint_claims(match.start(), number, unit))
    for match in _PIN_RE.finditer(prepared):
        kind = _pin_kind(match.group(1))
        for token in _ID_SPLIT_RE.split(match.group(2)):
            pin_id = _pin_token(token)
            if pin_id is None:
                continue
            found.append(
                _Claim(
                    start=match.start(),
                    surface=f"{kind} {token}",
                    canonical=f"{kind} {pin_id}",
                )
            )
    found.sort(key=lambda claim: claim.start)
    return tuple(found)


def _prepare(text: str) -> str:
    # Decode entities before NFKC so "999&nbsp;Nm" and "999&#8203;Nm" cannot hide.
    prepared = html.unescape(text)
    prepared = unicodedata.normalize("NFKC", prepared)
    prepared = _INVISIBLE_RE.sub("", prepared)
    prepared = (
        prepared.replace("\u2212", "-")
        .replace("\u2010", "-")
        .replace("\u2011", "-")
        .replace("\u2012", "-")
        .replace("\u2013", "-")
        .replace("\u2014", "-")
        .replace("\u00ad", "-")
        .replace("\u30fb", "·")
        .replace("*", "")
        .replace("`", "")
        .replace("_", "")
        .replace("μm", "um")
    )
    prepared = _rewrite_ohm_symbols(prepared)
    prepared = _normalize_numeric_spacing(prepared)
    return re.sub(r"\s+", " ", prepared).strip()


def _rewrite_ohm_symbols(text: str) -> str:
    # Case distinguishes mega from milli. Do this before casefold.
    rewritten = re.sub(r"M\s*Ω", "megohm", text)
    rewritten = re.sub(r"m\s*Ω", "milliohm", rewritten)
    rewritten = re.sub(r"[kK]\s*Ω", "kohm", rewritten)
    return rewritten.replace("Ω", "ohm")


# Column header on a service-spec table, then a row "999 (998, 997)".
# The same triple without this header is not a torque.
_TORQUE_HEADER_RE = re.compile(
    r"n\s*[·⋅•.\-]?\s*m.{0,80}?kgf\s*(?:[·⋅•.\-]\s*)?\s*cm.{0,80}?"
    r"ft\s*(?:[·⋅•.\-]\s*)?\s*lbf",
    re.IGNORECASE | re.DOTALL,
)
_TORQUE_TRIPLE_RE = re.compile(
    r"(?<![A-Za-z0-9.])(\d+(?:\.\d+)?)\s*\(\s*(\d+(?:\.\d+)?)\s*,\s*"
    r"(\d+(?:\.\d+)?)\s*\)"
)
_RANGE_ENDS_RE = re.compile(r"(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)")


def _range_endpoint_claims(start: int, number: str, unit: str) -> tuple[_Claim, ...]:
    """A chunk range supports either endpoint. The answer's own range does not.

    ``999 Nm`` matches a chunk that says ``998-999 Nm``. ``999-1000 Nm`` does
    not match a chunk that only says ``1000 Nm``. ``999`` does not match
    ``1999-2000``.
    """

    ends = _RANGE_ENDS_RE.fullmatch(number)
    if ends is None:
        return ()
    return tuple(
        _Claim(start=start, surface=end, canonical=f"{end} {unit}")
        for end in ends.groups()
    )


def _table_torque_claims(prepared: str) -> tuple[_Claim, ...]:
    if _TORQUE_HEADER_RE.search(prepared) is None:
        return ()
    found: list[_Claim] = []
    for match in _TORQUE_TRIPLE_RE.finditer(prepared):
        nm, kgfcm, ftlbf = match.group(1), match.group(2), match.group(3)
        start = match.start()
        found.append(_Claim(start=start, surface=nm, canonical=f"{nm} nm"))
        found.append(_Claim(start=start, surface=kgfcm, canonical=f"{kgfcm} kgfcm"))
        found.append(_Claim(start=start, surface=ftlbf, canonical=f"{ftlbf} ftlbf"))
    return tuple(found)


def _normalize_numeric_spacing(text: str) -> str:
    previous = None
    while previous != text:
        previous = text
        # Grouping commas are spelling ("9,999" == "9999"), not a new value.
        # A space after the comma is a list ("210, 15"), not a thousands group.
        text = re.sub(r"(?<=\d),(?=\d{3}(?!\d))", "", text)
        text = re.sub(r"(?<=\d)\s+(?=\d)", "", text)
    # "999. 9" is the same decimal as "999.9". A dot between digits is not a sentence.
    text = re.sub(r"(?<=\d)\s*\.\s*(?=\d)", ".", text)
    # "998 - 999" is the same range as "998-999", so both endpoints can be read.
    text = re.sub(r"(?<=\d)\s*-\s*(?=\d)", "-", text)
    return text


def _canonical_number(raw: str) -> str:
    scientific = re.fullmatch(r"(\d+(?:\.\d+)?)[eE]([+-]?\d+)", raw)
    if scientific:
        return f"{scientific.group(1)}e{scientific.group(2)}"
    return raw


def _canonical_unit(surface: str) -> str:
    for canonical, pattern in _UNIT_PATTERNS:
        if re.fullmatch(pattern, surface.strip(), flags=re.IGNORECASE):
            return canonical
    raise RuntimeError(f"unmapped unit {surface!r}")


def _pin_kind(word: str) -> str:
    folded = word.casefold()
    if folded.startswith("terminal"):
        return "terminal"
    if folded.startswith("connector"):
        return "connector"
    return "pin"


def _pin_token(token: str) -> str | None:
    if re.fullmatch(r"[A-Za-z]", token):
        return token.casefold()
    if re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", token) and any(
        char.isdigit() for char in token
    ):
        return token.casefold()
    return None
