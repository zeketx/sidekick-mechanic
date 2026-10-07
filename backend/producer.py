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

from chat_models import Conversation
from contract import load_answer_fixture, validate_answer
from demo import DEMO_SYSTEM_PROMPT, resolve_demo_answer
from llm import (
    RETRIEVED_PAGES_HEADER,
    ChatTurn,
    LLMClient,
    LLMError,
    TokenUsage,
    build_llm_client,
)
from manifest import ManifestError, load_manifest
from part_resolver import BayMapView, complete_selection, resolve_answer
from retrieval import (
    DEFAULT_K,
    INDEX_FILENAME,
    Fts5Index,
    RetrievalError,
    RetrievedChunk,
    Retriever,
)

DEFAULT_FIXTURE = "plain.json"
LOGGER = logging.getLogger("sidekick.llm")
_SNIPPET_LIMIT = 280

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
    "snippet must be an exact case-sensitive copy of a contiguous span of the "
    "decoded page text, not JSON escape sequences. "
    "Do not add an ellipsis, quotes, or other characters. "
    f"The server shortens a snippet longer than {_SNIPPET_LIMIT} characters. "
    "Use only a doc_id and page from the retrieved pages. "
    "If those pages do not support an answer, set citations to an empty array. "
    "text may be empty only in that case."
)

UNAVAILABLE_ANSWER: dict[str, Any] = {
    "kind": "answer",
    "text": "The mechanic is unavailable right now. Try again in a moment.",
    "citations": [],
}

NOT_FOUND_REFUSAL: dict[str, Any] = {
    "kind": "refusal",
    "text": "Not found in the manual. I do not have a cited page for this.",
    "reason": "not_found_in_manual",
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
validate_answer(NOT_FOUND_REFUSAL)
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

    def cited_chunk_texts(self, conversation: Conversation) -> Sequence[str]:
        """Chunk texts retrieved for this conversation, one string per chunk."""


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

        query = _last_user_text(conversation)
        if _chassis_wiring_blocked(query):
            return dict(WIRING_NOT_INGESTED_REFUSAL)
        try:
            hits = retriever.search(query)
        except _IndexMissing:
            return self._ungrounded(conversation)
        except (RetrievalError, sqlite3.Error):
            return dict(UNAVAILABLE_ANSWER)
        if _is_engine_wiring(query):
            hits = tuple(
                hit for hit in hits if hit.doc_id == _ENGINE_WIRING_DOC_ID
            )
        if not hits:
            return _refusal_for_miss(query)

        text = self._complete(
            _chat_messages(conversation, _grounded_system_prompt(hits, conversation))
        )
        if text is None:
            return dict(UNAVAILABLE_ANSWER)
        parsed = _parse_grounded_completion(text)
        if parsed is None:
            return dict(UNAVAILABLE_ANSWER)
        if parsed.citation_count == 0:
            return dict(NOT_FOUND_REFUSAL)
        citations = _filter_citations(parsed.citations, hits)
        if not citations:
            return dict(UNAVAILABLE_ANSWER)
        return self._with_part_highlight(
            {"kind": "answer", "text": parsed.text, "citations": citations},
            conversation,
        )

    def cited_chunk_texts(self, conversation: Conversation) -> tuple[str, ...]:
        retriever = self._retriever
        if retriever is None:
            return ()
        query = _last_user_text(conversation)
        if _chassis_wiring_blocked(query):
            return ()
        try:
            hits = retriever.search(query)
        except (_IndexMissing, RetrievalError, sqlite3.Error):
            return ()
        if _is_engine_wiring(query):
            hits = tuple(
                hit for hit in hits if hit.doc_id == _ENGINE_WIRING_DOC_ID
            )
        return tuple(hit.text for hit in hits)

    def _ungrounded(self, conversation: Conversation) -> dict[str, Any]:
        system = (
            DEMO_SYSTEM_PROMPT if conversation.demo is not None else SYSTEM_PROMPT
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
        except LLMError:
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
            return None
        return text

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
        bay_map = self._bay_map
        if bay_map is None or not bay_map.parts:
            return payload
        try:
            selection_text = complete_selection(
                self._client,
                answer_text=payload["text"],
                bay_map=bay_map,
            )
        except LLMError:
            LOGGER.warning("part selection failed; answer has no highlight")
            return payload
        return resolve_answer(payload, selection_text, bay_map)


class _IndexRetriever:
    """Opens the index for one search. A missing file is not an empty hit list."""

    def __init__(self, index_path: Path | None = None) -> None:
        self._index_path = index_path

    def search(self, query: str, k: int = DEFAULT_K) -> tuple[RetrievedChunk, ...]:
        path = self._index_path if self._index_path is not None else _index_path()
        if not path.is_file():
            raise _IndexMissing(str(path))
        index = Fts5Index.open(path)
        try:
            return index.search(query, k)
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


def _refusal_for_miss(query: str) -> dict[str, Any]:
    if _is_engine_wiring(query):
        return dict(NOT_FOUND_REFUSAL)
    if _WIRING_QUERY.search(query) and _wiring_manual_blocked():
        return dict(WIRING_NOT_INGESTED_REFUSAL)
    return dict(NOT_FOUND_REFUSAL)


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
    return (
        f"{preamble}\n\n{_GROUNDED_INSTRUCTIONS}\n\n"
        f"{RETRIEVED_PAGES_HEADER}{rendered}"
    )


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
        if page_text is None or snippet not in page_text:
            continue
        stored = _cap_snippet(snippet)
        if not stored.strip():
            continue
        identity = (doc_id, page, stored)
        if identity in seen:
            continue
        seen.add(identity)
        kept.append({"doc_id": doc_id, "page": page, "snippet": stored})
    return kept


def _cap_snippet(snippet: str) -> str:
    if len(snippet) <= _SNIPPET_LIMIT:
        return snippet
    window = snippet[:_SNIPPET_LIMIT]
    last_space = _last_whitespace_index(window)
    if last_space is None:
        return window
    trimmed = window[:last_space].rstrip()
    if not trimmed:
        return window
    return trimmed


def _last_whitespace_index(window: str) -> int | None:
    for index in range(len(window) - 1, -1, -1):
        if window[index].isspace():
            return index
    return None


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
