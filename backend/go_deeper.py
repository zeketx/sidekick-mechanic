"""Plain-English Go deeper block for one cited page.

Copy is grounded only in that page's text. Spec-guard rules match chat
answers. Wiring pages that have no prose omit test/tools instead of
guessing pinouts.
"""

from __future__ import annotations

import json
import re
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from llm import GO_DEEPER_HEADER, ChatTurn, LLMClient, LLMError, build_llm_client
from spec_guard import guard_answer

_REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CHUNKS_PATH = Path(__file__).resolve().parent / ".ingest" / "chunks.jsonl"
FAKE_DOC_PREFIX = "FAKE-DOC"
FAKE_FUSE_DOC = "FAKE-DOC-2JZ"
FAKE_FUSE_PAGE = 999
WIRING_DOC_IDS = frozenset({"is300-engine-wiring", "lj78-wiring"})
_SENTENCE_RE = re.compile(r"(?<=[.!?])\s+")
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
EXCERPT_LIMIT = 300

FAKE_PAGE_TEXT = (
    "FAKE-PAGE: The fuse/relay box is the plastic box that holds the fuses "
    "and relays for this engine bay. Look at the box. Check that the cover "
    "is on and nothing looks burned. Open the cover and look. You need a "
    "flashlight. No guessed numbers. Value FAKE-SPEC is not a real torque."
)

FAKE_FUSE_GO_DEEPER: dict[str, str] = {
    "how_it_works": (
        "The fuse/relay box is the plastic box that holds the fuses and "
        "relays for this engine bay."
    ),
    "what_to_test": (
        "Look at the box. Check that the cover is on and nothing looks burned."
    ),
    "how_to_test": "Open the cover and look.",
    "tools": "You need a flashlight.",
}

DIAGRAM_HOW_IT_WORKS = (
    "This page is a wiring diagram. Read the labels on the page. "
    "I am not guessing pinouts or wire colors."
)

_GO_DEEPER_INSTRUCTIONS = (
    "Reply with one JSON object and no other text. "
    "Keys: how_it_works, what_to_test, how_to_test, tools. "
    "Each value is a short everyday-English string, or empty if the page "
    "does not support that section. Do not invent torque, pinouts, wire "
    "colors, part numbers, or firing order. Use only the cited page."
)


class GoDeeperError(Exception):
    """The Go deeper block cannot be built."""

    def __init__(self, message: str, *, status_code: int) -> None:
        super().__init__(message)
        self.status_code = status_code


def is_fake_doc_id(doc_id: str) -> bool:
    return doc_id.startswith(FAKE_DOC_PREFIX)


def strip_control_chars(text: str) -> str:
    """Drop C0 controls except newline and tab."""
    return _CONTROL_RE.sub("", text)


def excerpt_around_snippet(
    page_text: str, snippet: str | None, *, limit: int = EXCERPT_LIMIT
) -> str | None:
    """1–3 sentences around the cited snippet. None when the snippet is missing."""
    page = " ".join(strip_control_chars(page_text).split())
    needle = " ".join(strip_control_chars(snippet or "").split())
    if not page or not needle:
        return None
    if needle.lower() not in page.lower():
        return None
    sentences = [piece.strip() for piece in _SENTENCE_RE.split(page) if piece.strip()]
    hit = next(
        (
            index
            for index, sentence in enumerate(sentences)
            if needle.lower() in sentence.lower()
        ),
        None,
    )
    if hit is None:
        start = page.lower().find(needle.lower())
        return _cap_excerpt(page[start:], limit)
    matched = sentences[hit]
    if len(matched) > limit:
        start = matched.lower().find(needle.lower())
        return _cap_excerpt(matched[max(start, 0):], limit)
    pieces = [matched]
    index = hit + 1
    while index < len(sentences) and len(pieces) < 3:
        candidate = " ".join([*pieces, sentences[index]])
        if len(candidate) > limit:
            break
        pieces.append(sentences[index])
        index += 1
    return _cap_excerpt(" ".join(pieces), limit)


def _cap_excerpt(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    trimmed = text[:limit].rsplit(" ", 1)[0].rstrip(".,;: ")
    if not trimmed:
        trimmed = text[:limit]
    return trimmed + "…"


def go_deeper(
    doc_id: str,
    page: int,
    *,
    snippet: str | None = None,
    chunks_path: Path | None = None,
    manuals_dir: Path | None = None,
    client: LLMClient | None = None,
    manifest_path: Path | None = None,
) -> dict[str, Any]:
    """Return a Go deeper payload grounded in one page."""
    from manual_pages import is_servable_doc_id

    if not is_servable_doc_id(doc_id, manifest_path=manifest_path):
        raise GoDeeperError("This manual page is not available.", status_code=404)
    if not isinstance(page, int) or isinstance(page, bool) or page < 1:
        raise GoDeeperError("This manual page is not available.", status_code=404)

    page_text = cited_page_text(
        doc_id, page, chunks_path=chunks_path, manuals_dir=manuals_dir
    )
    if page_text is None and not is_fake_doc_id(doc_id):
        raise GoDeeperError("This manual page is not available.", status_code=404)

    text = strip_control_chars(page_text or "")
    sections = _sections_for_page(
        doc_id, page, text, snippet=snippet, client=client
    )
    guarded = _guard_sections(sections, text, snippet=snippet)
    return {
        "doc_id": doc_id,
        "page": page,
        **guarded,
    }


def cited_page_text(
    doc_id: str,
    page: int,
    *,
    chunks_path: Path | None = None,
    manuals_dir: Path | None = None,
) -> str | None:
    if is_fake_doc_id(doc_id):
        return strip_control_chars(FAKE_PAGE_TEXT)
    path = chunks_path if chunks_path is not None else DEFAULT_CHUNKS_PATH
    from_chunks = _text_from_chunks(path, doc_id, page)
    if from_chunks is not None:
        return strip_control_chars(from_chunks)
    extracted = _text_from_pdf(doc_id, page, manuals_dir)
    if extracted is None:
        return None
    return strip_control_chars(extracted)


def _sections_for_page(
    doc_id: str,
    page: int,
    page_text: str,
    *,
    snippet: str | None,
    client: LLMClient | None,
) -> dict[str, str]:
    if doc_id == FAKE_FUSE_DOC and page == FAKE_FUSE_PAGE:
        return dict(FAKE_FUSE_GO_DEEPER)
    if is_fake_doc_id(doc_id):
        return {
            "how_it_works": (
                "This is a fixture page, not a real manual. "
                "It does not give a real procedure."
            ),
        }
    if doc_id in WIRING_DOC_IDS or not page_text.strip():
        return {"how_it_works": DIAGRAM_HOW_IT_WORKS}
    generated = _llm_sections(page_text, snippet=snippet, client=client)
    if generated is not None:
        return generated
    excerpt = excerpt_around_snippet(page_text, snippet)
    if excerpt:
        return {"how_it_works": excerpt}
    return {}


def _llm_sections(
    page_text: str, *, snippet: str | None, client: LLMClient | None
) -> dict[str, str] | None:
    llm = client if client is not None else build_llm_client()
    payload: dict[str, str] = {"text": page_text}
    if snippet and snippet.strip():
        payload["snippet"] = snippet.strip()
    page_json = json.dumps(payload, ensure_ascii=False)
    prompt = f"{GO_DEEPER_HEADER}{page_json}"
    try:
        result = llm.complete(
            [
                ChatTurn(role="system", content=_GO_DEEPER_INSTRUCTIONS),
                ChatTurn(role="user", content=prompt),
            ]
        )
    except LLMError:
        return None
    parsed = _parse_sections(result.text)
    if parsed is None:
        return None
    return parsed


def _parse_sections(raw: str) -> dict[str, str] | None:
    text = raw.strip()
    if not text:
        return None
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    sections: dict[str, str] = {}
    for key in ("how_it_works", "what_to_test", "how_to_test", "tools"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            sections[key] = value.strip()
    return sections or None


def _guard_sections(
    sections: Mapping[str, str], page_text: str, *, snippet: str | None
) -> dict[str, str]:
    chunks = (page_text,) if page_text.strip() else ()
    kept: dict[str, str] = {}
    for key, value in sections.items():
        probe = {"kind": "answer", "text": value, "citations": []}
        result = guard_answer(probe, chunks)
        if result.uncited:
            continue
        kept[key] = value
    if "how_it_works" in kept:
        return kept
    if not page_text.strip():
        fallback = DIAGRAM_HOW_IT_WORKS
        probe = {"kind": "answer", "text": fallback, "citations": []}
        result = guard_answer(probe, ())
        if not result.uncited:
            kept["how_it_works"] = fallback
        return kept
    fallback = excerpt_around_snippet(page_text, snippet)
    if not fallback:
        return kept
    probe = {"kind": "answer", "text": fallback, "citations": []}
    result = guard_answer(probe, chunks)
    if not result.uncited:
        kept["how_it_works"] = fallback
    return kept


def _text_from_chunks(path: Path, doc_id: str, page: int) -> str | None:
    if not path.is_file():
        return None
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not isinstance(row, dict):
            continue
        if row.get("doc_id") == doc_id and row.get("page") == page:
            text = row.get("text")
            if isinstance(text, str) and text.strip():
                return text
    return None


def _text_from_pdf(doc_id: str, page: int, manuals_dir: Path | None) -> str | None:
    from pypdf import PdfReader
    from pypdf.errors import PyPdfError

    from ingest import _normalize_page_text
    from manual_pages import DEFAULT_MANUALS_DIR

    manuals = manuals_dir if manuals_dir is not None else DEFAULT_MANUALS_DIR
    pdf_path = manuals / f"{doc_id}.pdf"
    if not pdf_path.is_file():
        return None
    try:
        reader = PdfReader(pdf_path)
    except (OSError, PyPdfError):
        return None
    if page > len(reader.pages):
        return None
    # Empty extract is still a real page (wiring diagrams often have no text layer).
    return _normalize_page_text(reader.pages[page - 1].extract_text()) or ""
