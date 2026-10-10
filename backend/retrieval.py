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
CHUNKS_FILENAME = "chunks.jsonl"
INDEX_FILENAME = "index.sqlite"
_CANDIDATE_K = 40
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
    """.split()
)
_VEHICLE_QUERY_TOKENS = frozenset(
    {"2jz", "ge", "jz", "is300", "lexus", "lj78", "toyota"}
)
_SPEC_QUERY = re.compile(
    r"\b(?:torque|resistance|pressure|temperature|clearance|capacity|gap)\b",
    re.IGNORECASE,
)
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
    ) -> tuple[RetrievedChunk, ...]:
        if k < 1:
            raise RetrievalError(f"k must be >= 1, got {k}")
        terms = _content_terms(query)
        if not terms:
            return ()
        and_match = _fts_and_query(terms)
        or_match = _fts_or_query(terms)
        rows = _match_rows(self._connection, and_match, k=_CANDIDATE_K, doc_id=doc_id)
        if not rows:
            rows = _match_rows(
                self._connection, or_match, k=_CANDIDATE_K, doc_id=doc_id
            )
        if not rows:
            return ()
        ranked = _rerank(self._connection, query, terms, rows, doc_id=doc_id)
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
            raise RetrievalError(
                f"duplicate chunk {chunk.doc_id} page {chunk.page}"
            )
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


def snippet_matches_page(snippet: str, page_text: str) -> bool:
    """True when snippet is a contiguous span of the page text.

    Whitespace may collapse. Token order may not. A rearrangement of the
    page's words is not a quote.
    """

    if not snippet.strip() or not page_text:
        return False
    if snippet in page_text:
        return True
    snip_ws = _WS.sub(" ", snippet).strip()
    page_ws = _WS.sub(" ", page_text).strip()
    return snip_ws in page_ws


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
        raise RetrievalError(
            f"JSONL line {line_number} missing {exc.args[0]}"
        ) from exc
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


def _content_terms(query: str) -> tuple[str, ...]:
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
        f'"{terms[index]} {terms[index + 1]}"'
        for index in range(len(terms) - 1)
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


def _rerank(
    connection: sqlite3.Connection,
    query: str,
    terms: tuple[str, ...],
    rows: list[sqlite3.Row],
    *,
    doc_id: str | None,
) -> list[tuple[float, sqlite3.Row]]:
    n_docs = _chunk_count(connection, doc_id)
    idf = {term.lower(): _idf(connection, term, n_docs, doc_id) for term in terms}
    phrases = [
        f"{terms[index]} {terms[index + 1]}".lower()
        for index in range(len(terms) - 1)
    ]
    scored: list[tuple[float, sqlite3.Row]] = []
    for row in rows:
        hay = f"{row['labels']}\n{row['text']}".lower()
        phrase_hits = sum(1 for phrase in phrases if phrase in hay)
        coverage = 0.0
        for term in terms:
            if _term_in_text(term, hay):
                coverage += idf[term.lower()]
        score = (
            8.0 * phrase_hits
            + 4.0 * coverage
            + _structural_bonus(query, row["text"])
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


def _term_in_text(term: str, hay: str) -> bool:
    tokens = {token.lower() for token in _TOKEN.findall(hay)}
    return any(variant.lower() in tokens for variant in _surface_variants(term))


def _surface_variants(term: str) -> tuple[str, ...]:
    variants = [term]
    low = term.lower()
    if low.endswith("ies") and len(low) > 4:
        stem = term[:-3] + ("Y" if term[-4].isupper() else "y")
        variants.append(stem)
    elif low.endswith("es") and len(low) > 4:
        variants.append(term[:-2])
    elif low.endswith("s") and not low.endswith("ss") and len(low) > 3:
        variants.append(term[:-1])
    return tuple(variants)


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
