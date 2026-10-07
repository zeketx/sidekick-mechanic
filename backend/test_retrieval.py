from __future__ import annotations

import json
from pathlib import Path

import pytest

from ingest import Chunk as IngestChunk, render_chunks
from retrieval import (
    DEFAULT_K,
    Chunk,
    Fts5Index,
    RetrievalError,
    build_index,
    load_chunks_jsonl,
    main,
)


def _write_chunks(path: Path, rows: list[dict[str, object]]) -> Path:
    lines = [
        json.dumps(row, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        for row in rows
    ]
    path.write_text("".join(line + "\n" for line in lines), encoding="utf-8")
    return path


def _generated_chunks() -> list[dict[str, object]]:
    return [
        {
            "doc_id": "FAKE-DOC-2JZ",
            "page": 999,
            "text": "starter motor inspection procedure FAKE-SPEC",
        },
        {
            "doc_id": "FAKE-DOC-2JZ",
            "page": 1000,
            "text": "coolant drain and fill sequence FAKE-SPEC",
        },
        {
            "doc_id": "FAKE-DOC-WIRING",
            "page": 999,
            "text": "starter relay connector FAKE-PIN",
        },
    ]


def _build(tmp_path: Path) -> Path:
    chunks = _write_chunks(tmp_path / "chunks.jsonl", _generated_chunks())
    index_path = tmp_path / "index.sqlite"
    build_index(load_chunks_jsonl(chunks), index_path)
    return index_path


def test_top_k_returns_chunks_with_doc_id_and_page(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        hits = index.search("starter motor", k=DEFAULT_K)

    assert [(hit.doc_id, hit.page, hit.rank) for hit in hits] == [
        ("FAKE-DOC-2JZ", 999, 1),
        ("FAKE-DOC-WIRING", 999, 2),
    ]
    assert hits[0].text == "starter motor inspection procedure FAKE-SPEC"
    assert hits[1].text == "starter relay connector FAKE-PIN"
    assert hits[0].score > hits[1].score


def test_k_one_returns_the_best_page_only(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        hits = index.search("starter motor", k=1)

    assert [(hit.doc_id, hit.page) for hit in hits] == [("FAKE-DOC-2JZ", 999)]


def test_search_can_limit_to_one_doc_id(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        hits = index.search("starter", doc_id="FAKE-DOC-WIRING")

    assert [(hit.doc_id, hit.page) for hit in hits] == [("FAKE-DOC-WIRING", 999)]


def test_unmatched_query_returns_empty_tuple(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        hits = index.search("not-a-manual-term-zzzz")

    assert hits == ()


def test_operator_noise_in_query_does_not_raise(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        hits = index.search('NEAR "starter"')

    assert {(hit.doc_id, hit.page) for hit in hits} == {
        ("FAKE-DOC-2JZ", 999),
        ("FAKE-DOC-WIRING", 999),
    }


def test_punctuation_only_query_returns_empty(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        hits = index.search("??? !!!")

    assert hits == ()


def test_k_below_one_is_rejected(tmp_path: Path) -> None:
    with Fts5Index.open(_build(tmp_path)) as index:
        with pytest.raises(RetrievalError, match="k must be >= 1"):
            index.search("starter", k=0)


def test_loads_ingest_jsonl_shape(tmp_path: Path) -> None:
    path = tmp_path / "chunks.jsonl"
    path.write_text(
        render_chunks(
            (
                IngestChunk(
                    doc_id="FAKE-DOC-2JZ",
                    page=999,
                    text="FAKE-SPEC starter motor",
                ),
            )
        ),
        encoding="utf-8",
    )

    assert load_chunks_jsonl(path) == (
        Chunk(doc_id="FAKE-DOC-2JZ", page=999, text="FAKE-SPEC starter motor"),
    )


def test_rebuild_is_idempotent_for_search_results(tmp_path: Path) -> None:
    chunks = _write_chunks(tmp_path / "chunks.jsonl", _generated_chunks())
    index_path = tmp_path / "index.sqlite"
    argv = ["build", "--chunks", str(chunks), "--index", str(index_path)]

    assert main(argv) == 0
    with Fts5Index.open(index_path) as index:
        first = [(hit.doc_id, hit.page) for hit in index.search("coolant")]
    index_path.write_bytes(b"not-sqlite")
    assert main(argv) == 0
    with Fts5Index.open(index_path) as index:
        second = [(hit.doc_id, hit.page) for hit in index.search("coolant")]

    assert first == second == [("FAKE-DOC-2JZ", 1000)]


def test_cli_query_prints_doc_id_and_page(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    index_path = _build(tmp_path)

    assert main(["query", "coolant drain", "--index", str(index_path), "--k", "5"]) == 0
    payload = json.loads(capsys.readouterr().out.splitlines()[0])
    assert payload["doc_id"] == "FAKE-DOC-2JZ"
    assert payload["page"] == 1000
    assert payload["rank"] == 1
    assert payload["text"] == "coolant drain and fill sequence FAKE-SPEC"


def test_rejects_page_zero_in_jsonl(tmp_path: Path) -> None:
    path = _write_chunks(
        tmp_path / "chunks.jsonl",
        [{"doc_id": "FAKE-DOC-2JZ", "page": 0, "text": "FAKE-SPEC"}],
    )

    with pytest.raises(RetrievalError, match="page must be >= 1"):
        load_chunks_jsonl(path)


def test_rejects_duplicate_doc_id_and_page(tmp_path: Path) -> None:
    path = _write_chunks(
        tmp_path / "chunks.jsonl",
        [
            {"doc_id": "FAKE-DOC-2JZ", "page": 999, "text": "FAKE-SPEC-A"},
            {"doc_id": "FAKE-DOC-2JZ", "page": 999, "text": "FAKE-SPEC-B"},
        ],
    )

    with pytest.raises(RetrievalError, match="duplicate chunk"):
        load_chunks_jsonl(path)


def test_missing_chunks_file_fails_build(tmp_path: Path) -> None:
    missing = tmp_path / "missing.jsonl"
    index_path = tmp_path / "index.sqlite"

    assert main(["build", "--chunks", str(missing), "--index", str(index_path)]) == 1
    assert not index_path.exists()
