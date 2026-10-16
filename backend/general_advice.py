"""General checks when the manual does not cover the question.

The model writes steps only. Pages, the garage basis, and the honesty line
are filled in here.
"""

from __future__ import annotations

import json
import re
from collections.abc import Sequence
from typing import Any, Protocol

from chat_models import Conversation, garage_prompt_block
from contract import validate_answer
from llm import (
    ChatTurn,
    LLMClient,
    LLMError,
    log_answer_rejection,
    log_llm_failure,
)
from retrieval import (
    _surface_variants,
    cap_snippet,
    content_terms,
    snippet_matches_page,
)
from safety import SAFETY_NOTE

ADVICE_HONESTY = "Not in your manual. Here's what usually causes this."
ADVICE_STEPS_HEADER = "General checks, not a manual answer:\n"
_STEP_LIMIT = 5
_STEP_CHARS = 500
# A list marker is digits, then "." or ")", then whitespace, then a non-digit.
# "12.7 Nm" is a measurement, not a marker. Stripping it would show "7 Nm".
_LEADING_LABEL = re.compile(
    r"^(?:step\s+\d+\s*[:.)]|\d+[.)])\s+(?!\d)",
    re.IGNORECASE,
)
_INSTRUCTIONS = (
    "Reply with one JSON object and no other text. "
    'The object is {"steps": [string, ...]} only. Extra keys are ignored. '
    "Write one to five sentences. "
    "Put the cheapest and easiest check first. "
    "Use one plain sentence for that first check, in the same shape every time. "
    "When a garage summary names a vehicle, name that vehicle in the first check. "
    "When no garage summary is present, do not name a vehicle. "
    "Do not write household-appliance advice. "
    "Do not start a sentence with a step number. "
    "Do not give a torque or any other number with a unit. "
    "Do not give a pin, connector, or terminal id. "
    "Do not give a wire color or a part number. "
    "Leave TBD as TBD. "
    "Garage notes are not a manual page."
)
_RELATED_WEAK_TERMS = frozenset(
    {
        "automatic",
        "manual",
        "not",
        "no",
        "never",
        "turning",
        "turn",
        "turned",
        "turns",
        "time",
        "times",
        "working",
        "work",
        "works",
        "problem",
        "issue",
        "check",
        "checks",
        "checked",
        "checking",
        "inspect",
        "inspects",
        "inspected",
        "inspecting",
        "look",
        "looks",
        "looked",
        "looking",
        "onto",
    }
)
# How fast or where. Omitting one of these is still the same fault.
# Requiring one of them hides that fault and keeps a different part.
_CONDITION_TERMS = frozenset(
    {
        "freeway",
        "highway",
        "high",
        "idle",
        "low",
        "speed",
        "speeds",
    }
)
RELEVANCE_HEADER = "Related page check:\n"
RELATED_JUDGE_LIMIT = 8
RELATED_KEEP_LIMIT = 3
_RELEVANCE_INSTRUCTIONS = (
    "You answer yes or no about one manual page. "
    "The question is the owner's problem. The snippet is the opening of that one page. "
    "Answer yes when the page names that fault, the part that has the fault, "
    "or a part whose name says it stops that fault. "
    "It may leave out how fast or where, and it does not have to repeat every word. "
    "A part in the same assembly as the fault is yes even when the fault word is missing. "
    "Answer no when the page is a different job that only shares a word, "
    "such as a sensor, a fluid level, or an alignment. "
    "A different system is no. "
    "Reply with one word, yes or no, and no other text."
)
_YES_NO = re.compile(r"^(yes|no)\b", re.IGNORECASE)
# The keyless stand-in has no model. These name a different job than the fault.
# Procedure words such as inspection stay out, so the wearing part can still match.
_DIFFERENT_JOB = frozenset({"alignment", "fluid", "sensor", "switch"})
_DETECTOR_TAILS = frozenset({"sensor", "switch"})


class _Page(Protocol):
    doc_id: str
    page: int
    text: str


def related_search_text(question: str) -> str:
    """Query for related pages. Fault words stay. Speed and place drop out.

    An empty remainder keeps the original question, so a speed-only question
    still searches.
    """

    kept = [
        term
        for term in content_terms(question)
        if term.casefold() not in _CONDITION_TERMS
        and term.casefold() not in _RELATED_WEAK_TERMS
    ]
    if not kept:
        return question
    return " ".join(kept)


def advise_on_miss(
    client: LLMClient,
    conversation: Conversation,
    hits: Sequence[_Page],
) -> dict[str, Any] | None:
    """Return general advice, or None when the writer did not return steps."""

    last = conversation.last_user_message
    question = last.text if last is not None else ""
    try:
        result = client.complete(_turns(conversation))
    except LLMError as exc:
        log_llm_failure(exc)
        return None
    steps = parse_steps(result.text)
    if steps is None:
        log_answer_rejection("advice_steps")
        return None
    payload = {
        "kind": "general_advice",
        "honesty": ADVICE_HONESTY,
        "safety": SAFETY_NOTE,
        "steps": steps,
        "garage": garage_basis(conversation),
        "related": related_citations(question, hits, client),
    }
    validate_answer(payload)
    return payload


def advice_system_prompt(conversation: Conversation) -> str:
    parts = [
        "You are Sidekick Mechanic. The manual does not cover this question.",
        _INSTRUCTIONS,
    ]
    summary = truck_prompt_line(conversation)
    if summary:
        parts.append(summary)
    block = garage_prompt_block(conversation.garage)
    if block:
        parts.append(block)
    parts.append(ADVICE_STEPS_HEADER)
    return "\n\n".join(parts)


def parse_steps(raw: str) -> list[str] | None:
    try:
        payload = json.loads(_unwrap_markdown_fence(raw.strip()))
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    raw_steps = payload.get("steps")
    if not isinstance(raw_steps, list):
        return None
    kept: list[str] = []
    for item in raw_steps:
        if not isinstance(item, str):
            continue
        cleaned = _LEADING_LABEL.sub("", item.strip(), count=1).strip()
        if not cleaned or len(cleaned) > _STEP_CHARS:
            continue
        kept.append(cleaned)
        if len(kept) == _STEP_LIMIT:
            break
    if not kept:
        return None
    return kept


def garage_basis(conversation: Conversation) -> dict[str, Any]:
    truck: str | None = None
    engine: str | None = None
    garage = conversation.garage
    if garage is not None:
        for fact in garage.facts:
            label = fact.label.casefold().strip()
            if not fact.value.strip():
                continue
            if label == "chassis" and truck is None:
                truck = fact.value
            elif label == "engine" and engine is None:
                engine = fact.value
    if truck is None and engine is None:
        return {"source": "none"}
    basis: dict[str, Any] = {"source": "garage"}
    if truck is not None:
        basis["truck"] = truck
    if engine is not None:
        basis["engine"] = engine
    return basis


def related_citations(
    question: str,
    hits: Sequence[_Page],
    client: LLMClient,
) -> list[dict[str, Any]]:
    if not _focus_terms(question):
        return []
    eligible: list[dict[str, Any]] = []
    seen: set[tuple[str, int]] = set()
    for hit in hits:
        doc_id = hit.doc_id
        page = hit.page
        if not isinstance(doc_id, str) or not doc_id.strip():
            continue
        if isinstance(page, bool) or not isinstance(page, int) or page < 1:
            continue
        key = (doc_id, page)
        if key in seen:
            continue
        snippet = cap_snippet(hit.text)
        if not snippet.strip() or not snippet_matches_page(snippet, hit.text):
            continue
        # The chip shows this prefix. A later sentence is not what the card shows.
        seen.add(key)
        eligible.append({"doc_id": doc_id, "page": page, "snippet": snippet})
    # Callers pass the pool best first. A long list makes the yes/no unreliable.
    kept: list[dict[str, Any]] = []
    for item in eligible[:RELATED_JUDGE_LIMIT]:
        if _page_is_related(client, question, item["snippet"]):
            kept.append(item)
        if len(kept) == RELATED_KEEP_LIMIT:
            break
    return kept


def in_process_related(question: str, snippets: Sequence[str]) -> list[bool]:
    # Keyless stand-in for the relevance completion. The fault word or the
    # part that has it is enough. How fast or where can be missing.
    # A different job that only shares a word is not related.
    claims = tuple(
        term
        for term in _focus_terms(question)
        if term.casefold() not in _CONDITION_TERMS
    )
    if not claims:
        return [False] * len(snippets)
    fault = claims[-1]
    assembly = claims[:-1]
    return [_snippet_is_related(snippet, fault, assembly) for snippet in snippets]


def _snippet_is_related(
    snippet: str,
    fault: str,
    assembly: Sequence[str],
) -> bool:
    fault_hit = _fault_is_present(fault, snippet)
    assembly_hit = any(_term_in_snippet(term, snippet) for term in assembly)
    if not fault_hit and not assembly_hit:
        return False
    if fault_hit:
        return True
    folds = {fault.casefold(), *(term.casefold() for term in assembly)}
    tokens = _snippet_tokens(snippet)
    return not any(token in _DIFFERENT_JOB and token not in folds for token in tokens)


def _fault_is_present(fault: str, snippet: str) -> bool:
    if not _term_in_snippet(fault, snippet):
        return False
    # "knock sensor" names the detector, not the fault.
    variants = "|".join(re.escape(variant) for variant in _surface_variants(fault))
    pattern = re.compile(
        rf"\b(?:{variants})\s+(?:{'|'.join(sorted(_DETECTOR_TAILS))})\b",
        re.IGNORECASE,
    )
    return _term_in_snippet(fault, pattern.sub(" ", snippet))


def _term_in_snippet(term: str, snippet: str) -> bool:
    tokens = _snippet_tokens(snippet)
    return any(variant.casefold() in tokens for variant in _surface_variants(term))


def _snippet_tokens(snippet: str) -> set[str]:
    return {token.lower() for token in re.findall(r"[A-Za-z0-9]+", snippet)}


def _page_is_related(client: LLMClient, question: str, snippet: str) -> bool:
    try:
        result = client.complete(_relevance_turns(question, snippet))
    except LLMError:
        return False
    return _parse_yes_no(result.text)


def answer_page_is_related(client: LLMClient, question: str, snippet: str) -> bool:
    """Whether this page may support an answer. Same yes/no as a related page.

    A judge failure keeps the page. Related chips hide a page when the judge
    fails. An answer must not disappear because that check timed out.
    """

    if not _focus_terms(question):
        return True
    try:
        result = client.complete(_relevance_turns(question, snippet))
    except LLMError:
        return True
    return _parse_yes_no(result.text)


def _relevance_turns(question: str, snippet: str) -> list[ChatTurn]:
    payload = json.dumps(
        {"question": question, "snippet": snippet},
        ensure_ascii=False,
    )
    return [
        ChatTurn(role="system", content=_RELEVANCE_INSTRUCTIONS),
        ChatTurn(role="user", content=RELEVANCE_HEADER + payload),
    ]


def _parse_yes_no(raw: str) -> bool:
    text = _unwrap_markdown_fence(raw.strip()).strip().casefold()
    match = _YES_NO.match(text)
    if match is None:
        return False
    if match.group(1).casefold() == "yes" and re.search(r"\bno\b", text):
        return False
    return match.group(1).casefold() == "yes"


def truck_prompt_line(conversation: Conversation) -> str:
    """Name the vehicle from the garage summary, or return empty when it has none."""

    basis = garage_basis(conversation)
    if basis.get("source") != "garage":
        return ""
    truck = basis.get("truck")
    engine = basis.get("engine")
    if isinstance(truck, str) and isinstance(engine, str):
        named = f"{truck}, engine {engine}"
    elif isinstance(truck, str):
        named = truck
    elif isinstance(engine, str):
        named = f"engine {engine}"
    else:
        return ""
    return f"The garage summary names this vehicle: {named}."


def _focus_terms(question: str) -> tuple[str, ...]:
    return tuple(
        term
        for term in content_terms(question)
        if term.casefold() not in _RELATED_WEAK_TERMS
    )


def _turns(conversation: Conversation) -> list[ChatTurn]:
    # Prior assistant text can quote a unit the guard allowed on a cited page.
    # That page is not evidence for these steps, so the model does not see it.
    messages = [ChatTurn(role="system", content=advice_system_prompt(conversation))]
    messages.extend(
        ChatTurn(role=message.role, content=message.text)
        for message in conversation.messages
        if message.role == "user"
    )
    return messages


def _unwrap_markdown_fence(text: str) -> str:
    if "\n" not in text or not text.startswith("```") or not text.endswith("```"):
        return text
    opener, _, body = text.partition("\n")
    if opener.strip().lower() not in {"```", "```json"}:
        return text
    if not body.endswith("```"):
        return text
    return body[:-3].removesuffix("\n")
