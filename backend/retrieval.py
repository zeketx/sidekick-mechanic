"""Lexical retrieval over ingest chunks. SQLite FTS5; see docs/design/retrieval-index.md."""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

DEFAULT_K = 5
RELATED_CANDIDATE_K = 40
CHUNKS_FILENAME = "chunks.jsonl"
INDEX_FILENAME = "index.sqlite"
_CANDIDATE_K = 40
# The strict AND pool hides a page that lacks one colloquial term once any
# other page already contains every term. The broad pool is what rerank may see.
_BROAD_CANDIDATE_K = 80
_LABEL_BM25_WEIGHT = 8.0
_TEXT_BM25_WEIGHT = 1.0

_REPO_BACKEND = Path(__file__).resolve().parent
_DEFAULT_CHUNKS = _REPO_BACKEND / ".ingest" / CHUNKS_FILENAME
_DEFAULT_INDEX = _REPO_BACKEND / ".ingest" / INDEX_FILENAME
_TOKEN = re.compile(r"[A-Za-z0-9]+")
_WS = re.compile(r"\s+")
_COMPONENT_NO = re.compile(r"\b[A-Z][A-Z0-9][A-Z0-9 /.&'-]{1,} NO\.\s*\d+\b")
_SCHEMA_SQL = """
CREATE VIRTUAL TABLE chunks USING fts5(
    doc_id UNINDEXED,
    page UNINDEXED,
    labels,
    text,
    tokenize = 'porter unicode61'
);
"""
_STOPWORDS = frozenset(
    """
    a an the and or of on in at to for from with without by as into over
    after before about up down out off than then so if than
    what whats which where when how why who whom
    do does did doing done
    is are was were be been being
    should would could can will
    i my me we our you your it its this that these those
    go goes going get gets got take takes taking
    have has had having
    a s t d ll ve re
    much many any some
    please tell show give
    start starts starting
    hold holds holding
    system systems
    read reads reading
    feed feeds
    actually really working works job jobs
    scanner scanners shows shown mean means
    see seen new
    """.split()
)
_VEHICLE_QUERY_TOKENS = frozenset(
    {"2jz", "ge", "jz", "is300", "lexus", "lj78", "toyota"}
)
_SPEC_QUERY = re.compile(
    r"\b(?:torque|resistance|pressure|temperature|clearance|capacity|gap)\b",
    re.IGNORECASE,
)
# Shop wording to the heading the manual actually prints. Not page ids.
_SHOP_EXPANSIONS: dict[str, tuple[str, ...]] = {
    "tight": ("torque",),
    "tighter": ("torque",),
    "tightness": ("torque",),
    "tighten": ("torque",),
    "tightening": ("torque",),
    "ohm": ("resistance",),
    "ohms": ("resistance",),
}
_OIL_QUANTITY = re.compile(r"\bhow much\b", re.IGNORECASE)
_OIL_WORD = re.compile(r"\boil\b", re.IGNORECASE)
_TORQUE_SPEC = re.compile(r"\bTorque:")
_EQUIPMENT_TORQUE = re.compile(r"Torque wrench", re.IGNORECASE)


class RetrievalError(Exception):
    """Index build or query failed."""


@dataclass(frozen=True)
class Chunk:
    doc_id: str
    page: int
    text: str

    def __post_init__(self) -> None:
        if not self.doc_id.strip():
            raise RetrievalError("chunk doc_id is empty")
        if self.page < 1:
            raise RetrievalError(f"chunk page must be >= 1, got {self.page}")
        if not self.text.strip():
            raise RetrievalError(
                f"chunk text is empty for {self.doc_id} page {self.page}"
            )


@dataclass(frozen=True)
class RetrievedChunk:
    doc_id: str
    page: int
    text: str
    score: float
    rank: int


class Retriever(Protocol):
    def search(self, query: str, k: int = DEFAULT_K) -> tuple[RetrievedChunk, ...]:
        """Return at most k chunks, best first. Each hit has doc_id and page."""


class Fts5Index:
    """SQLite FTS5 retriever. `search` is the seam #20 and #24 should call."""

    def __init__(self, connection: sqlite3.Connection) -> None:
        self._connection = connection

    @classmethod
    def open(cls, index_path: Path) -> Fts5Index:
        if not index_path.is_file():
            raise RetrievalError(f"index not found: {index_path}")
        connection = sqlite3.connect(index_path)
        connection.row_factory = sqlite3.Row
        try:
            _require_fts5_schema(connection)
        except RetrievalError:
            connection.close()
            raise
        return cls(connection)

    def search(
        self,
        query: str,
        k: int = DEFAULT_K,
        *,
        doc_id: str | None = None,
        match_any: bool = False,
    ) -> tuple[RetrievedChunk, ...]:
        if k < 1:
            raise RetrievalError(f"k must be >= 1, got {k}")
        terms = content_terms(query)
        if not terms:
            return ()
        # Related search stays on the owner's words. Shop headings are not
        # fault words, and they must not fill the related-page judge window.
        extras = () if match_any else expansion_terms(query)
        and_match = _fts_and_query(terms)
        or_match = _fts_or_query(terms)
        # Related pages ask for any fault word. AND would hide a pad page
        # once some other page already contains every fault word.
        if match_any:
            rows = _match_rows(
                self._connection, or_match, k=_CANDIDATE_K, doc_id=doc_id
            )
        else:
            strict = _match_rows(
                self._connection, and_match, k=_CANDIDATE_K, doc_id=doc_id
            )
            broad = _match_rows(
                self._connection, or_match, k=_BROAD_CANDIDATE_K, doc_id=doc_id
            )
            if not strict:
                # Nothing contains every term. Do not add shop headings here.
                # An empty AND plus "torque" would fill the pool with tables.
                rows = broad
            else:
                extra_rows = (
                    _match_rows(
                        self._connection,
                        _fts_or_query((*terms, *extras)),
                        k=_BROAD_CANDIDATE_K,
                        doc_id=doc_id,
                    )
                    if extras
                    else []
                )
                strict_keys = {
                    (str(row["doc_id"]), int(row["page"])) for row in strict
                }
                rows = [
                    row
                    for row in _merge_candidate_rows(strict, broad, extra_rows)
                    if _keep_candidate(
                        query,
                        terms,
                        row,
                        strict_keys=strict_keys,
                        extras=extras,
                    )
                ]
        if not rows:
            return ()
        ranked = _rerank(
            self._connection, query, terms, rows, doc_id=doc_id, extras=extras
        )
        return tuple(
            RetrievedChunk(
                doc_id=row["doc_id"],
                page=int(row["page"]),
                text=row["text"],
                score=score,
                rank=index,
            )
            for index, (score, row) in enumerate(ranked[:k], start=1)
        )

    def close(self) -> None:
        self._connection.close()

    def __enter__(self) -> Fts5Index:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def load_chunks_jsonl(path: Path) -> tuple[Chunk, ...]:
    if not path.is_file():
        raise RetrievalError(f"chunks not found: {path}")
    chunks: list[Chunk] = []
    seen: set[tuple[str, int]] = set()
    for line_number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw.strip():
            continue
        chunk = _chunk_from_json(raw, line_number)
        key = (chunk.doc_id, chunk.page)
        if key in seen:
            raise RetrievalError(f"duplicate chunk {chunk.doc_id} page {chunk.page}")
        seen.add(key)
        chunks.append(chunk)
    return tuple(chunks)


def build_index(chunks: tuple[Chunk, ...], index_path: Path) -> None:
    index_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = index_path.with_name(index_path.name + ".tmp")
    if tmp.exists():
        tmp.unlink()
    try:
        _write_sqlite(chunks, tmp)
        tmp.replace(index_path)
    finally:
        if tmp.exists():
            tmp.unlink()


def extract_labels(text: str) -> str:
    """Headings and component labels for a boosted FTS column."""

    labels: list[str] = []
    seen: set[str] = set()

    def add(value: str) -> None:
        cleaned = _WS.sub(" ", value).strip(" -")
        if len(cleaned) < 4:
            return
        key = cleaned.lower()
        if key in seen:
            return
        seen.add(key)
        labels.append(cleaned)

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("-") and len(stripped) > 8:
            add(stripped)
        elif _is_heading_line(stripped):
            add(stripped)
    for match in _COMPONENT_NO.findall(text):
        add(match)
    return " ".join(labels)


SNIPPET_LIMIT = 280


def cap_snippet(snippet: str) -> str:
    if len(snippet) <= SNIPPET_LIMIT:
        return snippet
    window = snippet[:SNIPPET_LIMIT]
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


def quoted_span(snippet: str, page_text: str) -> str | None:
    """The page's own slice when the snippet quotes it.

    Whitespace may collapse and case may differ. The match may not start or
    end in the middle of a token, and punctuation has to match. "1.8" is not
    a quote of "1. 8" or "180".
    """

    if not snippet.strip() or not page_text.strip():
        return None
    collapsed, mapping = _collapse_with_map(page_text)
    needle, _needle_map = _collapse_with_map(snippet)
    if not collapsed or not needle:
        return None
    hay = collapsed.casefold()
    key = needle.casefold()
    start = 0
    while True:
        found = hay.find(key, start)
        if found < 0:
            return None
        end = found + len(key)
        before_ok = found == 0 or not hay[found - 1].isalnum()
        after_ok = end == len(hay) or not hay[end].isalnum()
        if before_ok and after_ok and len(key) == len(needle):
            page_start = mapping[found]
            page_end = mapping[end - 1] + 1
            return page_text[page_start:page_end]
        start = found + 1


def grounding_span(snippet: str, page_text: str) -> str:
    """A span of the page we can show for this citation.

    A real quote is returned as the page's own characters. Otherwise the
    sentence that shares the quote's words, then a heading, then a line
    with no digit. The opening of the page is not used when that opening
    is a different measurement.
    """

    quoted = quoted_span(snippet, page_text)
    if quoted:
        return quoted
    overlap = _best_overlap_sentence(snippet, page_text)
    if overlap:
        return overlap
    labels = [line.strip() for line in extract_labels(page_text).splitlines()]
    if labels:
        return labels[0]
    for line in page_text.splitlines():
        stripped = line.strip()
        if stripped and not re.search(r"\d", stripped):
            return stripped
    words = [token for token in _TOKEN.findall(page_text) if not token.isdigit()]
    return " ".join(words[:12])


def snippet_matches_page(snippet: str, page_text: str) -> bool:
    """True when snippet quotes a contiguous span of the page text."""

    return quoted_span(snippet, page_text) is not None


def _collapse_with_map(text: str) -> tuple[str, list[int]]:
    chars: list[str] = []
    mapping: list[int] = []
    index = 0
    length = len(text)
    while index < length:
        if text[index].isspace():
            if chars and chars[-1] != " ":
                chars.append(" ")
                mapping.append(index)
            while index < length and text[index].isspace():
                index += 1
            continue
        folded = text[index].casefold()
        if len(folded) != 1:
            chars.append(text[index])
            mapping.append(index)
        else:
            chars.append(text[index])
            mapping.append(index)
        index += 1
    while chars and chars[0] == " ":
        chars.pop(0)
        mapping.pop(0)
    while chars and chars[-1] == " ":
        chars.pop()
        mapping.pop()
    return "".join(chars), mapping


def _best_overlap_sentence(snippet: str, page_text: str) -> str | None:
    wanted = {
        token.lower()
        for token in _TOKEN.findall(snippet)
        if len(token) > 2 and token.lower() not in _STOPWORDS
    }
    if not wanted:
        return None
    best = ""
    best_score = 0
    for sentence in re.split(r"\n+|(?<=[.!?])\s+", page_text):
        cleaned = sentence.strip()
        if not cleaned:
            continue
        tokens = {token.lower() for token in _TOKEN.findall(cleaned)}
        score = len(wanted & tokens)
        if score > best_score:
            best_score = score
            best = cleaned
    if best_score >= 2 or (len(wanted) == 1 and best_score == 1):
        return best
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build or query the SQLite FTS5 retrieval index."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="Write index.sqlite from chunks.jsonl")
    build.add_argument("--chunks", type=Path, default=_DEFAULT_CHUNKS)
    build.add_argument("--index", type=Path, default=_DEFAULT_INDEX)

    query = sub.add_parser("query", help="Print top-k chunks as JSON lines")
    query.add_argument("text")
    query.add_argument("--index", type=Path, default=_DEFAULT_INDEX)
    query.add_argument("--k", type=int, default=DEFAULT_K)

    args = parser.parse_args(argv)
    try:
        if args.command == "build":
            chunks = load_chunks_jsonl(args.chunks)
            build_index(chunks, args.index)
            print(f"indexed {len(chunks)} chunk(s) -> {args.index}")
            return 0
        with Fts5Index.open(args.index) as index:
            hits = index.search(args.text, k=args.k)
        for hit in hits:
            print(_json_line(_hit_payload(hit)))
        return 0
    except RetrievalError as exc:
        print(str(exc), file=sys.stderr)
        return 1


def _chunk_from_json(raw: str, line_number: int) -> Chunk:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RetrievalError(f"invalid JSONL on line {line_number}") from exc
    if not isinstance(payload, dict):
        raise RetrievalError(f"JSONL line {line_number} is not an object")
    try:
        doc_id = payload["doc_id"]
        page = payload["page"]
        text = payload["text"]
    except KeyError as exc:
        raise RetrievalError(f"JSONL line {line_number} missing {exc.args[0]}") from exc
    if not isinstance(doc_id, str) or not isinstance(text, str):
        raise RetrievalError(f"JSONL line {line_number} has the wrong types")
    if not isinstance(page, int) or isinstance(page, bool):
        raise RetrievalError(f"JSONL line {line_number} page must be an integer")
    return Chunk(doc_id=doc_id, page=page, text=text)


def _write_sqlite(chunks: tuple[Chunk, ...], path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        _require_fts5(connection)
        connection.execute("DROP TABLE IF EXISTS chunks")
        connection.execute(_SCHEMA_SQL)
        connection.executemany(
            "INSERT INTO chunks(doc_id, page, labels, text) VALUES (?, ?, ?, ?)",
            (
                (chunk.doc_id, chunk.page, extract_labels(chunk.text), chunk.text)
                for chunk in chunks
            ),
        )
        connection.commit()
    finally:
        connection.close()


def _require_fts5(connection: sqlite3.Connection) -> None:
    try:
        connection.execute("CREATE VIRTUAL TABLE _fts5_probe USING fts5(x)")
    except sqlite3.OperationalError as exc:
        raise RetrievalError("SQLite was built without FTS5") from exc
    connection.execute("DROP TABLE _fts5_probe")


def _require_fts5_schema(connection: sqlite3.Connection) -> None:
    try:
        rows = connection.execute(
            "SELECT doc_id, page, labels, text FROM chunks LIMIT 0"
        ).fetchall()
    except sqlite3.OperationalError as exc:
        raise RetrievalError("index is not an FTS5 chunks table") from exc
    del rows


def expansion_terms(query: str) -> tuple[str, ...]:
    """Manual headings implied by shop wording.

    These are extra OR terms. They are not AND requirements and they do
    not arm the heading bonus by themselves. "How much oil pressure" does
    not become a capacity query.
    """

    tokens = [token.lower() for token in _TOKEN.findall(query)]
    seen = set(tokens)
    extra: list[str] = []
    for token in tokens:
        for added in _SHOP_EXPANSIONS.get(token, ()):
            if added in seen:
                continue
            seen.add(added)
            extra.append(added)
    if (
        _OIL_QUANTITY.search(query)
        and _OIL_WORD.search(query)
        and _SPEC_QUERY.search(query) is None
        and "capacity" not in seen
    ):
        extra.append("capacity")
    return tuple(extra)


def content_terms(query: str) -> tuple[str, ...]:
    terms: list[str] = []
    seen: set[str] = set()
    for token in _TOKEN.findall(query):
        low = token.lower()
        if low in _STOPWORDS or low in _VEHICLE_QUERY_TOKENS or len(low) == 1:
            continue
        if low in seen:
            continue
        seen.add(low)
        terms.append(token)
    return tuple(terms)


def _fts_and_query(terms: tuple[str, ...]) -> str | None:
    if not terms:
        return None
    return " AND ".join(f'"{term}"' for term in terms)


def _fts_or_query(terms: tuple[str, ...]) -> str | None:
    if not terms:
        return None
    quoted = [f'"{term}"' for term in terms]
    phrases = [
        f'"{terms[index]} {terms[index + 1]}"' for index in range(len(terms) - 1)
    ]
    return " OR ".join(quoted + phrases)


def _match_rows(
    connection: sqlite3.Connection,
    match: str | None,
    *,
    k: int,
    doc_id: str | None,
) -> list[sqlite3.Row]:
    if match is None:
        return []
    # bm25 weights are positional and include UNINDEXED columns.
    # doc_id and page are columns 0 and 1, so the label and text weights
    # follow two zeros. Two weights would land on the unindexed columns.
    weights = (0.0, 0.0, _LABEL_BM25_WEIGHT, _TEXT_BM25_WEIGHT)
    if doc_id is None:
        sql = """
        SELECT doc_id, page, labels, text,
               -bm25(chunks, ?, ?, ?, ?) AS score
        FROM chunks
        WHERE chunks MATCH ?
        ORDER BY bm25(chunks, ?, ?, ?, ?)
        LIMIT ?
        """
        params: tuple[object, ...] = (
            *weights,
            match,
            *weights,
            k,
        )
    else:
        sql = """
        SELECT doc_id, page, labels, text,
               -bm25(chunks, ?, ?, ?, ?) AS score
        FROM chunks
        WHERE chunks MATCH ? AND doc_id = ?
        ORDER BY bm25(chunks, ?, ?, ?, ?)
        LIMIT ?
        """
        params = (*weights, match, doc_id, *weights, k)
    try:
        return list(connection.execute(sql, params).fetchall())
    except sqlite3.OperationalError:
        return []


def _keep_candidate(
    query: str,
    terms: tuple[str, ...],
    row: sqlite3.Row,
    *,
    strict_keys: set[tuple[str, int]],
    extras: tuple[str, ...],
) -> bool:
    """A partial page stays when it is the spec table for these part words.

    A two-word query such as "starter motor" does not keep a page that
    only says starter. A shop word such as "tight" does not keep every
    torque table, only a table that also matches the part words.
    """

    key = (str(row["doc_id"]), int(row["page"]))
    if key in strict_keys:
        return True
    if _structural_bonus(query, row["text"]) > 0:
        return True
    if _expansion_bonus(row["labels"], row["text"], terms, extras) > 0:
        return True
    if len(terms) < 4:
        return False
    hay = f"{row['labels']}\n{row['text']}".lower()
    matched = sum(1 for term in terms if term_in_text(term, hay))
    return matched >= len(terms) - 1


def _merge_candidate_rows(*groups: list[sqlite3.Row]) -> list[sqlite3.Row]:
    best: dict[tuple[str, int], sqlite3.Row] = {}
    for rows in groups:
        for row in rows:
            key = (str(row["doc_id"]), int(row["page"]))
            current = best.get(key)
            if current is None or float(row["score"]) > float(current["score"]):
                best[key] = row
    return list(best.values())


def _rerank(
    connection: sqlite3.Connection,
    query: str,
    terms: tuple[str, ...],
    rows: list[sqlite3.Row],
    *,
    doc_id: str | None,
    extras: tuple[str, ...] = (),
) -> list[tuple[float, sqlite3.Row]]:
    n_docs = _chunk_count(connection, doc_id)
    idf = {term.lower(): _idf(connection, term, n_docs, doc_id) for term in terms}
    scored: list[tuple[float, sqlite3.Row]] = []
    for row in rows:
        hay = f"{row['labels']}\n{row['text']}".lower()
        phrase_hits = _phrase_hit_count(terms, hay)
        coverage = 0.0
        for term in terms:
            if term_in_text(term, hay):
                coverage += idf[term.lower()]
        score = (
            8.0 * phrase_hits
            + 4.0 * coverage
            + _structural_bonus(query, row["text"])
            + _expansion_bonus(row["labels"], row["text"], terms, extras)
            + float(row["score"])
        )
        scored.append((score, row))
    scored.sort(key=lambda item: -item[0])
    return scored


def _chunk_count(connection: sqlite3.Connection, doc_id: str | None) -> int:
    if doc_id is None:
        row = connection.execute("SELECT count(*) FROM chunks").fetchone()
    else:
        row = connection.execute(
            "SELECT count(*) FROM chunks WHERE doc_id = ?", (doc_id,)
        ).fetchone()
    return int(row[0]) if row is not None else 0


def _idf(
    connection: sqlite3.Connection,
    term: str,
    n_docs: int,
    doc_id: str | None,
) -> float:
    match = f'"{term}"'
    try:
        if doc_id is None:
            row = connection.execute(
                "SELECT count(*) FROM chunks WHERE chunks MATCH ?", (match,)
            ).fetchone()
        else:
            row = connection.execute(
                "SELECT count(*) FROM chunks WHERE chunks MATCH ? AND doc_id = ?",
                (match, doc_id),
            ).fetchone()
    except sqlite3.OperationalError:
        return 0.0
    df = int(row[0]) if row is not None else 0
    return math.log((n_docs + 1) / (df + 1))


def _expansion_bonus(
    labels: str,
    text: str,
    terms: tuple[str, ...],
    extras: tuple[str, ...],
) -> float:
    """Heading bonus for a shop word, only when the page matches the part.

    "Tight" may surface a torque table. The table still has to share the
    part words. A brake question does not promote every torque page.
    """

    if not extras or not terms:
        return 0.0
    hay = f"{labels}\n{text}".lower()
    matched = sum(1 for term in terms if term_in_text(term, hay))
    if matched < max(1, (len(terms) + 1) // 2):
        return 0.0
    bonus = 0.0
    if "torque" in extras and _TORQUE_SPEC.search(text):
        bonus += 8.0
    if "SERVICE DATA" in text or "SERVICE SPECIFICATIONS" in text:
        bonus += 5.0
    return bonus


def _structural_bonus(query: str, text: str) -> float:
    bonus = 0.0
    if re.search(r"\btorque\b", query, re.IGNORECASE):
        if _TORQUE_SPEC.search(text):
            bonus += 8.0
        if "TORQUE SPECIFICATION" in text:
            bonus += 6.0
        if _EQUIPMENT_TORQUE.search(text) and _TORQUE_SPEC.search(text) is None:
            bonus -= 6.0
    if _SPEC_QUERY.search(query) or re.search(r"\brecommended\b", query, re.IGNORECASE):
        if "SERVICE DATA" in text or "SERVICE SPECIFICATIONS" in text:
            bonus += 5.0
    return bonus


def _phrase_hit_count(terms: tuple[str, ...], hay: str) -> int:
    count = 0
    for index in range(len(terms) - 1):
        if _phrase_in_hay(terms[index], terms[index + 1], hay):
            count += 1
    return count


def _phrase_in_hay(left: str, right: str, hay: str) -> bool:
    for first in _surface_variants(left):
        for second in _surface_variants(right):
            if f"{first} {second}".lower() in hay:
                return True
    return False


def term_in_text(term: str, hay: str) -> bool:
    tokens = {token.lower() for token in _TOKEN.findall(hay)}
    return any(variant.lower() in tokens for variant in _surface_variants(term))


def _surface_variants(term: str) -> tuple[str, ...]:
    variants = [term.lower()]
    low = term.lower()
    if len(low) <= 3:
        return (low,)
    if low.endswith("ies") and len(low) > 4:
        variants.append(low[:-3] + "y")
    elif low.endswith("es") and len(low) > 4:
        # "brakes" → "brake", not "brak". "gases" / "lenses" also keep
        # the two-letter stem ("gas", "lens").
        variants.append(low[:-1])
        if low.endswith(("sses", "xes", "zes", "ches", "shes", "ses")):
            variants.append(low[:-2])
    elif low.endswith("s") and not low.endswith("ss") and len(low) > 3:
        variants.append(low[:-1])
    if low.endswith("ing") and len(low) > 6 and len(low) - 3 >= 4:
        # "tightening" matches "tighten". "timing" is too short to strip.
        variants.append(low[:-3])
    if low.endswith("ed") and len(low) > 5:
        variants.append(low[:-2])
        variants.append(low[:-1])
    return tuple(dict.fromkeys(variants))


def _is_heading_line(line: str) -> bool:
    if line in {"SERVICE DATA", "TORQUE SPECIFICATION", "INSPECTION", "REPLACEMENT"}:
        return True
    if line.startswith("SERVICE ") and line.isupper():
        return True
    letters = [char for char in line if char.isalpha()]
    if len(letters) < 6:
        return False
    upper = sum(1 for char in letters if char.isupper())
    return upper / len(letters) >= 0.85 and " " in line


def _hit_payload(hit: RetrievedChunk) -> dict[str, object]:
    return {
        "doc_id": hit.doc_id,
        "page": hit.page,
        "rank": hit.rank,
        "score": hit.score,
        "text": hit.text,
    }


def _json_line(obj: dict[str, object]) -> str:
    return json.dumps(obj, ensure_ascii=True, sort_keys=True, separators=(",", ":"))


if __name__ == "__main__":
    sys.exit(main())
