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
from llm import ChatTurn, LLMClient, LLMError
from retrieval import cap_snippet, content_terms, snippet_matches_page, term_in_text
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
    }
)


class _Page(Protocol):
    doc_id: str
    page: int
    text: str


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
    except LLMError:
        return None
    steps = parse_steps(result.text)
    if steps is None:
        return None
    payload = {
        "kind": "general_advice",
        "honesty": ADVICE_HONESTY,
        "safety": SAFETY_NOTE,
        "steps": steps,
        "garage": garage_basis(conversation),
        "related": related_citations(question, hits),
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


def related_citations(question: str, hits: Sequence[_Page]) -> list[dict[str, Any]]:
    focus = _focus_terms(question)
    if not focus:
        return []
    kept: list[dict[str, Any]] = []
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
        # The chip shows this prefix. A focus term later in the page still
        # leaves an off-topic heading on the card.
        if not any(term_in_text(term, snippet) for term in focus):
            continue
        seen.add(key)
        kept.append({"doc_id": doc_id, "page": page, "snippet": snippet})
    return kept


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
