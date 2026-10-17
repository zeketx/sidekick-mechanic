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
    _is_heading_line,
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
    "You answer yes or no about manual pages. "
    "The question is the owner's problem. Each snippet is the opening of one page. "
    "Answer yes when that page's own job is the fault, the part that has the fault, "
    "or a part whose name says it stops that fault. "
    "It may leave out how fast or where, and it does not have to repeat every word. "
    "A part in the same assembly as the fault is yes even when the fault word is missing. "
    "Answer no when the page is a different job that only shares a word, "
    "such as a sensor, a fluid level, or an alignment. "
    "Answer no when the page is a different problem and this fault or part "
    "is only mentioned as a cause, a symptom, or an aside. "
    "A different system is no. "
    'Reply with one JSON object {"pages": [{"id": number, "answer": "yes" or "no"}]} '
    "and no other text. One entry for every page, using the given id."
)
# One short call for the pages lexical checks cannot decide. The answer
# call still uses the client's own timeout. This cap keeps the extra
# call inside the phone's retry budget.
JUDGE_TIMEOUT_S = 8.0
_SPEC_HEADING = re.compile(
    r"\b(?:torque:|service data|service specifications)\b",
    re.IGNORECASE,
)
_CAUSE_RE = re.compile(
    r"\b(?:caused by|possible causes?|due to|because of|abnormal)\b",
    re.IGNORECASE,
)
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+|\n+")
# A generic procedure title is not a different fault.
_SUBJECT_BOILERPLATE = frozenset(
    {
        "check",
        "data",
        "fake",
        "heading",
        "inspection",
        "page",
        "procedure",
        "service",
        "spec",
        "vehicle",
    }
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
    # One call for the pages a lexical check cannot decide. Order stays
    # the search order. At most three yes pages are shown.
    window = eligible[:RELATED_JUDGE_LIMIT]
    flags = judge_pages(
        client,
        question,
        [item["snippet"] for item in window],
        keep_on_error=False,
    )
    kept: list[dict[str, Any]] = []
    for item, flag in zip(window, flags):
        if not flag:
            continue
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
    if _mentioned_only_as_another_faults_cause(fault, assembly, snippet):
        return False
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


def judge_pages(
    client: LLMClient,
    question: str,
    snippets: Sequence[str],
    *,
    keep_on_error: bool,
) -> list[bool]:
    """Yes or no for each snippet. Lexical decisions do not call the model.

    Pages that only share a word, and pages that mention the part only as
    a cause of a different fault, are no. A page whose heading or spec
    block names the part is yes. The rest go out together in one call.
    ``keep_on_error`` is for an answer: a judge timeout must not hide the
    manual. Related chips pass false and show nothing when the call fails.
    """

    if not snippets:
        return []
    decisions = [_lexical_support(question, snippet) for snippet in snippets]
    unsure = [index for index, decision in enumerate(decisions) if decision == "unsure"]
    judged: list[bool] = []
    if unsure:
        try:
            judged = _batch_judge(
                client, question, [snippets[index] for index in unsure]
            )
        except LLMError:
            judged = [keep_on_error] * len(unsure)
    flags: list[bool] = []
    cursor = 0
    for decision in decisions:
        if decision == "yes":
            flags.append(True)
        elif decision == "no":
            flags.append(False)
        else:
            flags.append(judged[cursor])
            cursor += 1
    return flags


def _lexical_support(question: str, snippet: str) -> str:
    claims = tuple(
        term
        for term in _focus_terms(question)
        if term.casefold() not in _CONDITION_TERMS
    )
    if not claims:
        return "yes"
    fault = claims[-1]
    assembly = claims[:-1]
    if not _snippet_is_related(snippet, fault, assembly):
        return "no"
    if _focus_in_text(claims, _subject_text(snippet)):
        return "yes"
    if _SPEC_HEADING.search(snippet):
        return "yes"
    return "unsure"


def _mentioned_only_as_another_faults_cause(
    fault: str,
    assembly: Sequence[str],
    snippet: str,
) -> bool:
    """The page's job is a different fault, and this part is only a cause.

    A heading that names the part is the page's own job. A generic
    procedure title is not a different fault.
    """

    terms = (fault, *assembly)
    if _focus_in_text(terms, _subject_text(snippet)):
        return False
    if not _names_a_different_job(snippet, terms):
        return False
    sentences = [
        part.strip() for part in _SENTENCE_SPLIT.split(snippet) if part.strip()
    ]
    hits = [sentence for sentence in sentences if _focus_in_text(terms, sentence)]
    if not hits:
        return False
    return all(_CAUSE_RE.search(sentence) for sentence in hits)


def _names_a_different_job(snippet: str, terms: Sequence[str]) -> bool:
    subject = _opening_subject(snippet)
    if _focus_in_text(terms, subject):
        return False
    words = [
        token
        for token in content_terms(subject)
        if token.casefold() not in _SUBJECT_BOILERPLATE
    ]
    return len(words) >= 1


def _subject_text(snippet: str) -> str:
    headings = [
        line.strip()
        for line in snippet.splitlines()
        if _is_heading_line(line.strip()) or line.strip().startswith("FAKE-HEADING")
    ]
    return " ".join([*headings, _opening_subject(snippet)])


def _opening_subject(snippet: str) -> str:
    stripped = snippet.strip()
    if not stripped:
        return ""
    line = stripped.splitlines()[0].strip()
    parts = _SENTENCE_SPLIT.split(line, maxsplit=1)
    return parts[0][:180]


def _focus_in_text(terms: Sequence[str], text: str) -> bool:
    return any(_term_in_snippet(term, text) for term in terms)


def _batch_judge(
    client: LLMClient, question: str, snippets: Sequence[str]
) -> list[bool]:
    result = _complete_bounded(client, _relevance_turns(question, snippets))
    parsed = _parse_batch(result.text, len(snippets))
    if parsed is None:
        raise LLMError("relevance judge returned no pages")
    return parsed


def _complete_bounded(client: LLMClient, messages: list[ChatTurn]) -> Any:
    import inspect

    params = inspect.signature(client.complete).parameters
    kwargs: dict[str, Any] = {}
    if "timeout_s" in params:
        kwargs["timeout_s"] = JUDGE_TIMEOUT_S
    if "attempts" in params:
        kwargs["attempts"] = 1
    return client.complete(messages, **kwargs)


def _relevance_turns(question: str, snippets: Sequence[str]) -> list[ChatTurn]:
    payload = json.dumps(
        {
            "question": question,
            "pages": [
                {"id": index, "snippet": snippet}
                for index, snippet in enumerate(snippets)
            ],
        },
        ensure_ascii=False,
    )
    return [
        ChatTurn(role="system", content=_RELEVANCE_INSTRUCTIONS),
        ChatTurn(role="user", content=RELEVANCE_HEADER + payload),
    ]


def _parse_batch(raw: str, count: int) -> list[bool] | None:
    try:
        payload = json.loads(_unwrap_markdown_fence(raw.strip()))
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    pages = payload.get("pages")
    if not isinstance(pages, list):
        return None
    by_id: dict[int, bool] = {}
    for item in pages:
        if not isinstance(item, dict):
            continue
        page_id = item.get("id")
        answer = item.get("answer")
        if isinstance(page_id, bool) or not isinstance(page_id, int):
            continue
        if not isinstance(answer, str):
            continue
        by_id[page_id] = _parse_yes_no(answer)
    if not by_id:
        return None
    # Models sometimes number the first page 1. Shift only when every id
    # matches that scheme, so a missing page stays a no.
    one_based = {index + 1 for index in range(count)}
    if 0 not in by_id and set(by_id) == one_based:
        by_id = {index - 1: flag for index, flag in by_id.items()}
    return [by_id.get(index, False) for index in range(count)]


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
