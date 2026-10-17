"""Answer-producer seam. LLM adapter implements AnswerProducer.

The spec guard does not read citation snippets. A producer that has
retrieved page text should also implement CitedChunkSource so POST /chat
can pass those strings to spec_guard.guard_answer.
"""

from __future__ import annotations

import json
import logging
import re
import sqlite3
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

from chat_models import Conversation, garage_prompt_block
from contract import load_answer_fixture, validate_answer
from demo import DEMO_SYSTEM_PROMPT, resolve_demo_answer
from general_advice import advise_on_miss, judge_pages, related_search_text
from llm import (
    RETRIEVED_PAGES_HEADER,
    ChatTurn,
    LLMClient,
    LLMError,
    TokenUsage,
    build_llm_client,
    log_answer_rejection,
    log_llm_failure,
)
from manifest import ManifestError, load_manifest
from part_resolver import BayMapView, complete_selection, resolve_answer
from retrieval import (
    DEFAULT_K,
    INDEX_FILENAME,
    RELATED_CANDIDATE_K,
    SNIPPET_LIMIT,
    Fts5Index,
    RetrievalError,
    RetrievedChunk,
    Retriever,
    cap_snippet,
    grounding_span,
)
from spec_guard import supporting_page_mask

DEFAULT_FIXTURE = "plain.json"
LOGGER = logging.getLogger("sidekick.llm")

_GROUNDED_PREAMBLE = (
    "You are Sidekick Mechanic. Answer the owner's question. "
    "Do not invent torque values, part numbers, pinouts, wire colors, or other specs. "
    "Do not cite a manual page you were not given."
)

SYSTEM_PROMPT = _GROUNDED_PREAMBLE + " If you do not know, say so."

_GROUNDED_INSTRUCTIONS = (
    "Reply with one JSON object and no other text. "
    'The object has a string field "text" and an array field "citations". '
    'Each citation has "doc_id" (string), "page" (integer), and "snippet" (string). '
    "Retrieved pages is a JSON array. "
    "snippet must copy tokens from that page's decoded text, not JSON escape "
    "sequences. Whitespace may differ; do not invent tokens. "
    "Do not add an ellipsis, quotes, or other characters. "
    f"The server shortens a snippet longer than {SNIPPET_LIMIT} characters. "
    "Use only a doc_id and page from the retrieved pages. "
    "Cite only the retrieved pages that contain the facts you state. "
    "Do not cite a neighboring page that does not contain those facts. "
    "Do not cite every retrieved page. "
    "State a number with a unit only when that number and unit appear on a page you cite. "
    "A code definition or a procedure does not need an extra measurement. "
    "When a page gives a range, you may state either endpoint with that same unit. "
    "If those pages do not support an answer, set citations to an empty array. "
    "text may be empty only in that case."
)

UNAVAILABLE_ANSWER: dict[str, Any] = {
    "kind": "error",
    "text": "The mechanic is unavailable right now. Try again in a moment.",
    "reason": "provider_unavailable",
}

WIRING_NOT_INGESTED_REFUSAL: dict[str, Any] = {
    "kind": "refusal",
    "text": (
        "The wiring manual is not ingested yet. I do not have a cited page for this."
    ),
    "reason": "not_found_in_manual",
}

_REPO_ROOT = Path(__file__).resolve().parent.parent
_MANIFEST_PATH = _REPO_ROOT / "docs" / "MANUALS.md"
_CHASSIS_WIRING_DOC_ID = "lj78-wiring"
_ENGINE_WIRING_DOC_ID = "is300-engine-wiring"
# #118 miss path: a wiring question with no hits, while the chassis EWD is blocked.
_WIRING_QUERY = re.compile(r"\b(?:wiring|harness|pinouts?|ewd)\b", re.IGNORECASE)
_ELECTRICAL_QUERY = re.compile(
    r"\b(?:wiring|harness|pinouts?|ewd|fuses?|relays?|wires?|pins?|connectors?)\b",
    re.IGNORECASE,
)
_ENGINE_WIRING_SUBJECT = re.compile(
    r"\b(?:2jz(?:-?ge)?|is300|ecm|ecu|injectors?|ignition\s+coils?|"
    r"vvt(?:-?i)?|efi|ocv|oil\s+control\s+valve|"
    r"engine\s+(?:harness|wiring|connectors?|control))\b",
    re.IGNORECASE,
)
_CHASSIS_WIRING_SUBJECT = re.compile(
    r"\b(?:lj78|lj7[0-9]|70[\s-]?series|land\s*cruisers?|glow\s*plugs?|"
    r"(?:chassis|body)\s+(?:wiring|harness|ewd))\b",
    re.IGNORECASE,
)

validate_answer(UNAVAILABLE_ANSWER)
validate_answer(WIRING_NOT_INGESTED_REFUSAL)


class AnswerProducer(Protocol):
    def produce(self, conversation: Conversation) -> dict[str, Any]:
        """Return an answer payload that must match answer.schema.json."""


class _RetrievedPage(Protocol):
    doc_id: str
    page: int
    text: str


@dataclass(frozen=True)
class _GroundedCompletion:
    text: str
    citations: tuple[dict[str, Any], ...]
    citation_count: int


@runtime_checkable
class CitedChunkSource(Protocol):
    """Page text the spec guard may treat as evidence."""

    def cited_chunk_texts(
        self, conversation: Conversation, answer: Mapping[str, Any]
    ) -> Sequence[str]:
        """Page text for citations that survived on this answer."""


class FixtureAnswerProducer:
    """Returns a committed contract fixture. Does not call a model."""

    def __init__(self, fixture_name: str = DEFAULT_FIXTURE) -> None:
        self.fixture_name = fixture_name

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        del conversation
        return load_answer_fixture(self.fixture_name)


class _IndexMissing(Exception):
    """The index file is absent for this request. Not a search miss."""


class LlmAnswerProducer:
    """A bay map view is optional. The default producer has none, because the
    bay map schema is not loaded here. With a non-empty view, a second
    completion picks a part id from that closed list.
    """

    def __init__(
        self,
        client: LLMClient,
        bay_map: BayMapView | None = None,
        *,
        retriever: Retriever | None = None,
    ) -> None:
        self._client = client
        self._bay_map = bay_map
        self._retriever = retriever

    def produce(self, conversation: Conversation) -> dict[str, Any]:
        retriever = self._retriever
        if retriever is None:
            return self._ungrounded(conversation)

        query = _retrieval_query(conversation)
        if _chassis_wiring_blocked(query):
            return dict(WIRING_NOT_INGESTED_REFUSAL)
        try:
            hits = _search_hits(retriever, query)
        except _IndexMissing:
            return self._advice_or_unavailable(conversation, ())
        except (RetrievalError, sqlite3.Error):
            return dict(UNAVAILABLE_ANSWER)
        if not hits:
            if _wiring_not_ingested_miss(query):
                return dict(WIRING_NOT_INGESTED_REFUSAL)
            return self._advice_or_unavailable(conversation, ())
        # Same meaning check as a related page. A strong heading is kept
        # without a model call. A page that only shares a word, or that
        # mentions the part only as a cause of a different fault, is not
        # support, so the model never cites it.
        found = hits
        hits = _relevant_hits(self._client, query, hits)
        if not hits:
            return self._advice_or_unavailable(conversation, found)

        text = self._complete(
            _chat_messages(conversation, _grounded_system_prompt(hits, conversation))
        )
        if text is None:
            return dict(UNAVAILABLE_ANSWER)
        parsed = _parse_grounded_completion(text)
        if parsed is None:
            log_answer_rejection("grounded_json")
            return dict(UNAVAILABLE_ANSWER)
        if parsed.citation_count == 0:
            return self._advice_or_unavailable(conversation, hits)
        citations = _filter_citations(parsed.citations, hits)
        citations = _citations_that_support(parsed.text, citations, hits)
        if not citations:
            log_answer_rejection("citation_mismatch")
            return dict(UNAVAILABLE_ANSWER)
        return self._with_part_highlight(
            {"kind": "answer", "text": parsed.text, "citations": citations},
            conversation,
        )

    def cited_chunk_texts(
        self, conversation: Conversation, answer: Mapping[str, Any]
    ) -> tuple[str, ...]:
        if answer.get("kind") != "answer":
            return ()
        citations = answer.get("citations")
        if not isinstance(citations, list):
            return ()
        cited_pages = {
            (item.get("doc_id"), item.get("page"))
            for item in citations
            if isinstance(item, dict)
        }
        if not cited_pages:
            return ()
        retriever = self._retriever
        if retriever is None:
            return ()
        query = _retrieval_query(conversation)
        if _chassis_wiring_blocked(query):
            return ()
        try:
            hits = _search_hits(retriever, query)
        except (_IndexMissing, RetrievalError, sqlite3.Error):
            return ()
        return tuple(hit.text for hit in hits if (hit.doc_id, hit.page) in cited_pages)

    def searched_pages(
        self, conversation: Conversation
    ) -> tuple[tuple[str, int], ...] | None:
        """Pages this turn searched, best first. None when this producer has no index."""

        retriever = self._retriever
        if retriever is None:
            return None
        query = _retrieval_query(conversation)
        if _chassis_wiring_blocked(query):
            return ()
        try:
            hits = _search_hits(retriever, query)
        except (_IndexMissing, RetrievalError, sqlite3.Error):
            return ()
        return tuple((hit.doc_id, hit.page) for hit in hits)

    def _ungrounded(self, conversation: Conversation) -> dict[str, Any]:
        system = _with_garage(
            DEMO_SYSTEM_PROMPT if conversation.demo is not None else SYSTEM_PROMPT,
            conversation,
        )
        text = self._complete(_chat_messages(conversation, system))
        if text is None:
            return dict(UNAVAILABLE_ANSWER)
        return self._with_part_highlight(
            {"kind": "answer", "text": text, "citations": []},
            conversation,
        )

    def _complete(self, messages: list[ChatTurn]) -> str | None:
        started = time.perf_counter()
        try:
            result = self._client.complete(messages)
        except LLMError as exc:
            log_llm_failure(exc)
            _log_request(
                ok=False,
                model="unknown",
                latency_ms=_latency_ms(started),
                usage=None,
            )
            return None
        text = result.text.strip()
        _log_request(
            ok=bool(text),
            model=result.model,
            latency_ms=_latency_ms(started),
            usage=result.usage,
        )
        if not text:
            log_answer_rejection("empty_completion")
            return None
        return text

    def _advice_or_unavailable(
        self,
        conversation: Conversation,
        hits: Sequence[_RetrievedPage],
    ) -> dict[str, Any]:
        advice = advise_on_miss(
            self._client, conversation, _related_hits(self, conversation, hits)
        )
        if advice is None:
            return dict(UNAVAILABLE_ANSWER)
        return self._with_part_highlight(advice, conversation)

    def _with_part_highlight(
        self,
        payload: dict[str, Any],
        conversation: Conversation,
    ) -> dict[str, Any]:
        demo_photo_id = (
            conversation.demo.photo_id if conversation.demo is not None else None
        )
        if demo_photo_id is not None:
            return resolve_demo_answer(
                payload, _last_user_text(conversation), demo_photo_id
            )
        if payload.get("kind") != "answer":
            return payload
        bay_map = self._bay_map
        if bay_map is None or not bay_map.parts:
            return payload
        try:
            selection_text = complete_selection(
                self._client,
                answer_text=payload["text"],
                bay_map=bay_map,
            )
        except LLMError as exc:
            log_llm_failure(exc)
            LOGGER.warning("part selection failed; answer has no highlight")
            return payload
        return resolve_answer(payload, selection_text, bay_map)


class _IndexRetriever:
    """Opens the index for one search. A missing file is not an empty hit list."""

    def __init__(self, index_path: Path | None = None) -> None:
        self._index_path = index_path

    def search(
        self,
        query: str,
        k: int = DEFAULT_K,
        *,
        doc_id: str | None = None,
        match_any: bool = False,
    ) -> tuple[RetrievedChunk, ...]:
        path = self._index_path if self._index_path is not None else _index_path()
        if not path.is_file():
            raise _IndexMissing(str(path))
        index = Fts5Index.open(path)
        try:
            return index.search(query, k, doc_id=doc_id, match_any=match_any)
        finally:
            index.close()


def _index_path() -> Path:
    return Path(__file__).resolve().parent / ".ingest" / INDEX_FILENAME


def default_producer() -> AnswerProducer:
    return LlmAnswerProducer(build_llm_client(), retriever=_IndexRetriever())


def _chat_messages(conversation: Conversation, system: str) -> list[ChatTurn]:
    messages = [ChatTurn(role="system", content=system)]
    messages.extend(
        ChatTurn(role=message.role, content=message.text)
        for message in conversation.messages
    )
    return messages


def _with_garage(system: str, conversation: Conversation) -> str:
    block = garage_prompt_block(conversation.garage)
    if not block:
        return system
    return f"{system}\n\n{block}"


def format_searched_pages(pages: tuple[tuple[str, int], ...]) -> str:
    if not pages:
        return "-"
    return ",".join(f"{doc_id}:{page}" for doc_id, page in pages)


def parse_searched_pages(value: str) -> tuple[tuple[str, int], ...]:
    if value == "-":
        return ()
    hits: list[tuple[str, int]] = []
    for item in value.split(","):
        doc_id, separator, page_text = item.rpartition(":")
        if separator != ":" or not doc_id or not page_text.isdigit():
            raise ValueError("retrieval header is not pages")
        page = int(page_text)
        if page < 1:
            raise ValueError("retrieval header is not pages")
        hits.append((doc_id, page))
    return tuple(hits)


def _related_hits(
    producer: LlmAnswerProducer,
    conversation: Conversation,
    grounded: Sequence[_RetrievedPage],
) -> Sequence[_RetrievedPage]:
    retriever = producer._retriever
    if retriever is None:
        return grounded
    question = _retrieval_query(conversation)
    text = related_search_text(question)
    doc_id = _ENGINE_WIRING_DOC_ID if _is_engine_wiring(text) else None
    try:
        if isinstance(retriever, _IndexRetriever):
            found = retriever.search(
                text, RELATED_CANDIDATE_K, doc_id=doc_id, match_any=True
            )
        else:
            found = retriever.search(text, RELATED_CANDIDATE_K)
            if doc_id is not None:
                found = tuple(hit for hit in found if hit.doc_id == doc_id)
    except (_IndexMissing, RetrievalError, sqlite3.Error):
        return grounded
    return found if found else grounded


def _search_hits(retriever: Retriever, query: str) -> tuple[RetrievedChunk, ...]:
    if _is_engine_wiring(query):
        if isinstance(retriever, _IndexRetriever):
            return retriever.search(query, doc_id=_ENGINE_WIRING_DOC_ID)
        return tuple(
            hit
            for hit in retriever.search(query)
            if hit.doc_id == _ENGINE_WIRING_DOC_ID
        )
    return retriever.search(query)


def _wiring_not_ingested_miss(query: str) -> bool:
    if _is_engine_wiring(query):
        return False
    return _WIRING_QUERY.search(query) is not None and _wiring_manual_blocked()


def _is_engine_wiring(query: str) -> bool:
    return (
        _ENGINE_WIRING_SUBJECT.search(query) is not None
        and _ELECTRICAL_QUERY.search(query) is not None
    )


def _is_chassis_wiring(query: str) -> bool:
    if _CHASSIS_WIRING_SUBJECT.search(query) is None:
        return False
    return not _is_engine_wiring(query)


def _chassis_wiring_blocked(query: str) -> bool:
    return _is_chassis_wiring(query) and _wiring_manual_blocked()


def _wiring_manual_blocked() -> bool:
    try:
        documents = load_manifest(_MANIFEST_PATH)
    except ManifestError:
        return False
    return any(
        document.id == _CHASSIS_WIRING_DOC_ID and document.status == "blocked"
        for document in documents
    )


def _retrieval_query(conversation: Conversation) -> str:
    parts = [
        message.text.strip()
        for message in conversation.messages
        if message.role == "user" and message.text.strip()
    ]
    return " ".join(parts)


def _last_user_text(conversation: Conversation) -> str:
    for message in reversed(conversation.messages):
        if message.role == "user":
            return message.text
    return ""


def _grounded_system_prompt(
    hits: Sequence[_RetrievedPage],
    conversation: Conversation | None = None,
) -> str:
    pages = [{"doc_id": hit.doc_id, "page": hit.page, "text": hit.text} for hit in hits]
    rendered = json.dumps(pages, ensure_ascii=False)
    preamble = (
        DEMO_SYSTEM_PROMPT
        if conversation is not None and conversation.demo is not None
        else _GROUNDED_PREAMBLE
    )
    parts = [preamble]
    if conversation is not None:
        block = garage_prompt_block(conversation.garage)
        if block:
            parts.append(block)
    parts.append(_GROUNDED_INSTRUCTIONS)
    parts.append(f"{RETRIEVED_PAGES_HEADER}{rendered}")
    return "\n\n".join(parts)


def _parse_grounded_completion(raw: str) -> _GroundedCompletion | None:
    try:
        payload = json.loads(_unwrap_markdown_fence(raw.strip()))
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    citations = payload.get("citations")
    if not isinstance(citations, list):
        return None
    if len(citations) == 0:
        return _GroundedCompletion(text="", citations=(), citation_count=0)
    text = payload.get("text")
    if not isinstance(text, str):
        return None
    text = text.strip()
    if not text:
        return None
    well_typed = tuple(
        citation
        for citation in (_well_typed_citation(element) for element in citations)
        if citation is not None
    )
    return _GroundedCompletion(
        text=text,
        citations=well_typed,
        citation_count=len(citations),
    )


def _well_typed_citation(element: Any) -> dict[str, Any] | None:
    if not isinstance(element, dict):
        return None
    doc_id = element.get("doc_id")
    page = element.get("page")
    snippet = element.get("snippet")
    if not isinstance(doc_id, str) or not doc_id.strip():
        return None
    if isinstance(page, bool) or not isinstance(page, int) or page < 1:
        return None
    if not isinstance(snippet, str) or not snippet.strip():
        return None
    return {"doc_id": doc_id, "page": page, "snippet": snippet}


def _unwrap_markdown_fence(text: str) -> str:
    if "\n" not in text or not text.startswith("```") or not text.endswith("```"):
        return text
    opener, _, body = text.partition("\n")
    if opener.strip().lower() not in {"```", "```json"}:
        return text
    if not body.endswith("```"):
        return text
    inner = body[:-3]
    return inner.removesuffix("\n")


_SUPPORT_CHARS = 1500


def _relevant_hits(
    client: LLMClient,
    question: str,
    hits: Sequence[_RetrievedPage],
) -> tuple[_RetrievedPage, ...]:
    usable: list[_RetrievedPage] = []
    openings: list[str] = []
    for hit in hits:
        opening = hit.text[:_SUPPORT_CHARS]
        if not opening.strip():
            continue
        usable.append(hit)
        openings.append(opening)
    flags = judge_pages(client, question, openings, keep_on_error=True)
    return tuple(hit for hit, flag in zip(usable, flags) if flag)


def _citations_that_support(
    answer_text: str,
    citations: Sequence[Mapping[str, Any]],
    hits: Sequence[_RetrievedPage],
) -> list[dict[str, Any]]:
    """Drop a cited page that contains none of the stated measurements.

    When the answer states no measurement, or no cited page contains one,
    every citation stays. The spec guard still refuses a number that is
    not on a cited page.
    """

    pages: dict[tuple[str, int], str] = {}
    for hit in hits:
        pages.setdefault((hit.doc_id, hit.page), hit.text)
    texts = [
        pages.get((citation["doc_id"], citation["page"]), "") for citation in citations
    ]
    mask = supporting_page_mask(answer_text, texts)
    if mask is None:
        return list(citations)
    return [citation for citation, keep in zip(citations, mask) if keep]


def _filter_citations(
    citations: Sequence[Mapping[str, Any]],
    hits: Sequence[_RetrievedPage],
) -> list[dict[str, Any]]:
    pages: dict[tuple[str, int], str] = {}
    for hit in hits:
        pages.setdefault((hit.doc_id, hit.page), hit.text)
    kept: list[dict[str, Any]] = []
    seen: set[tuple[str, int, str]] = set()
    for citation in citations:
        doc_id = citation["doc_id"]
        page = citation["page"]
        snippet = citation["snippet"]
        page_text = pages.get((doc_id, page))
        if page_text is None:
            continue
        # Show the page's words. A model string that only looks like a quote
        # ("1.8" for "1. 8") must not become the chip.
        stored = cap_snippet(grounding_span(snippet, page_text))
        if not stored.strip():
            continue
        identity = (doc_id, page, stored)
        if identity in seen:
            continue
        seen.add(identity)
        kept.append({"doc_id": doc_id, "page": page, "snippet": stored})
    return kept


def _latency_ms(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)


def _log_request(
    *,
    ok: bool,
    model: str,
    latency_ms: int,
    usage: TokenUsage | None,
) -> None:
    prompt = usage.prompt_tokens if usage is not None else None
    completion = usage.completion_tokens if usage is not None else None
    total = usage.total_tokens if usage is not None else None
    LOGGER.info(
        "llm request completed ok=%s model=%s latency_ms=%s prompt_tokens=%s "
        "completion_tokens=%s total_tokens=%s",
        str(ok).lower(),
        model,
        latency_ms,
        prompt,
        completion,
        total,
    )
