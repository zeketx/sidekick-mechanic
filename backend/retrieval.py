"""Lexical retrieval over ingest chunks. SQLite FTS5; see docs/design/retrieval-index.md."""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

DEFAULT_K = 5
CHUNKS_FILENAME = "chunks.jsonl"
INDEX_FILENAME = "index.sqlite"

_REPO_BACKEND = Path(__file__).resolve().parent
_DEFAULT_CHUNKS = _REPO_BACKEND / ".ingest" / CHUNKS_FILENAME
_DEFAULT_INDEX = _REPO_BACKEND / ".ingest" / INDEX_FILENAME
_TOKEN = re.compile(r"[A-Za-z0-9]+")
_SCHEMA_SQL = """
CREATE VIRTUAL TABLE chunks USING fts5(
    doc_id UNINDEXED,
    page UNINDEXED,
    text,
    tokenize = 'unicode61'
);
"""


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

    def search(self, query: str, k: int = DEFAULT_K) -> tuple[RetrievedChunk, ...]:
        if k < 1:
            raise RetrievalError(f"k must be >= 1, got {k}")
        match = _fts_match_query(query)
        if match is None:
            return ()
        rows = self._connection.execute(
            """
            SELECT doc_id, page, text, -bm25(chunks) AS score
            FROM chunks
            WHERE chunks MATCH ?
            ORDER BY bm25(chunks)
            LIMIT ?
            """,
            (match, k),
        ).fetchall()
        return tuple(
            RetrievedChunk(
                doc_id=row["doc_id"],
                page=int(row["page"]),
                text=row["text"],
                score=float(row["score"]),
                rank=index,
            )
            for index, row in enumerate(rows, start=1)
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
            "INSERT INTO chunks(doc_id, page, text) VALUES (?, ?, ?)",
            ((chunk.doc_id, chunk.page, chunk.text) for chunk in chunks),
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
            "SELECT doc_id, page, text FROM chunks LIMIT 0"
        ).fetchall()
    except sqlite3.OperationalError as exc:
        raise RetrievalError("index is not an FTS5 chunks table") from exc
    del rows


def _fts_match_query(query: str) -> str | None:
    tokens = _TOKEN.findall(query)
    if not tokens:
        return None
    return " OR ".join(f'"{token}"' for token in tokens)


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
