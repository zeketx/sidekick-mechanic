from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from ingest import (
    CHUNKS_FILENAME,
    REPORT_FILENAME,
    ingest,
    main,
    render_chunks,
    render_report,
)
from manifest import ManifestError
from retrieval import Fts5Index
from retrieval import main as retrieval_main


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def make_pdf(pages: list[str | None]) -> bytes:
    """Tiny PDF for tests. None (or empty) means a page with no text operators."""
    catalog_id, pages_id, font_id = 1, 2, 3
    next_id = 4
    page_entries: list[tuple[int, int, str | None]] = []
    for text in pages:
        page_id = next_id
        next_id += 1
        content_id = 0
        if text:
            content_id = next_id
            next_id += 1
        page_entries.append((page_id, content_id, text))

    objs: dict[int, bytes] = {
        catalog_id: b"<< /Type /Catalog /Pages 2 0 R >>",
        pages_id: (
            "<< /Type /Pages /Kids ["
            + " ".join(f"{pid} 0 R" for pid, _, _ in page_entries)
            + f"] /Count {len(pages)} >>"
        ).encode("ascii"),
        font_id: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    }
    for page_id, content_id, text in page_entries:
        contents_ref = ""
        if content_id and text:
            stream = f"BT /F1 12 Tf 24 80 Td ({_pdf_escape(text)}) Tj ET"
            stream_b = stream.encode("ascii")
            objs[content_id] = (
                f"<< /Length {len(stream_b)} >>\nstream\n".encode("ascii")
                + stream_b
                + b"\nendstream"
            )
            contents_ref = f" /Contents {content_id} 0 R"
        objs[page_id] = (
            f"<< /Type /Page /Parent {pages_id} 0 R /MediaBox [0 0 200 200] "
            f"/Resources << /Font << /F1 {font_id} 0 R >> >>{contents_ref} >>"
        ).encode("ascii")

    max_id = max(objs)
    out = bytearray(b"%PDF-1.4\n")
    offsets = [0] * (max_id + 1)
    for obj_id in range(1, max_id + 1):
        offsets[obj_id] = len(out)
        out.extend(f"{obj_id} 0 obj\n".encode("ascii"))
        out.extend(objs[obj_id])
        out.extend(b"\nendobj\n")
    xref = len(out)
    out.extend(f"xref\n0 {max_id + 1}\n".encode("ascii"))
    out.extend(b"0000000000 65535 f \n")
    for obj_id in range(1, max_id + 1):
        out.extend(f"{offsets[obj_id]:010d} 00000 n \n".encode("ascii"))
    out.extend(
        f"trailer << /Size {max_id + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode(
            "ascii"
        )
    )
    return bytes(out)


def _write_manifest(
    directory: Path,
    rows: list[tuple[str, str]],
    *,
    statuses: dict[str, str] | None = None,
) -> Path:
    chosen = statuses or {}
    lines = [
        "# Test inventory",
        "",
        "| ID | Title | Edition | Page count | SHA-256 | Status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for doc_id, sha256 in rows:
        status = chosen.get(doc_id, "ingest")
        lines.append(
            f"| {doc_id} | Fake test manual | TBD | TBD | {sha256} | {status} |"
        )
    lines.append("")
    path = directory / "MANUALS.md"
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def _write_manual(
    directory: Path, doc_id: str, pages: list[str | None]
) -> tuple[bytes, str]:
    payload = make_pdf(pages)
    (directory / f"{doc_id}.pdf").write_bytes(payload)
    return payload, _sha256(payload)


def test_chunks_carry_doc_id_pdf_page_and_text(tmp_path: Path) -> None:
    _, digest = _write_manual(
        tmp_path, "fixture-a", ["FAKE-PAGE-ONE", "FAKE-SPEC"]
    )
    manifest = _write_manifest(tmp_path, [("fixture-a", digest)])

    result = ingest(manifest, tmp_path)

    assert [(c.doc_id, c.page, c.text) for c in result.chunks] == [
        ("fixture-a", 1, "FAKE-PAGE-ONE"),
        ("fixture-a", 2, "FAKE-SPEC"),
    ]
    assert result.empty_pages == ()


def test_empty_pages_listed_in_report_not_as_chunks(tmp_path: Path) -> None:
    _, digest = _write_manual(
        tmp_path, "fixture-a", ["FAKE-PAGE-ONE", None, "FAKE-PAGE-THREE"]
    )
    manifest = _write_manifest(tmp_path, [("fixture-a", digest)])

    result = ingest(manifest, tmp_path)

    assert [(c.doc_id, c.page, c.text) for c in result.chunks] == [
        ("fixture-a", 1, "FAKE-PAGE-ONE"),
        ("fixture-a", 3, "FAKE-PAGE-THREE"),
    ]
    assert [(p.doc_id, p.page) for p in result.empty_pages] == [("fixture-a", 2)]
    assert result.documents[0].page_count == 3
    assert result.documents[0].chunk_count == 2
    assert result.documents[0].empty_page_count == 1

    report = render_report(result)
    assert '"doc_id":"fixture-a"' in report
    assert '"page":2' in report
    assert "FAKE-PAGE-ONE" not in report


def test_ignores_pdfs_not_in_the_manifest(tmp_path: Path) -> None:
    _, digest = _write_manual(tmp_path, "fixture-a", ["FAKE-PAGE-ONE"])
    _write_manual(tmp_path, "fixture-extra", ["FAKE-SHOULD-NOT-INGEST"])
    manifest = _write_manifest(tmp_path, [("fixture-a", digest)])

    result = ingest(manifest, tmp_path)

    assert [c.doc_id for c in result.chunks] == ["fixture-a"]
    assert all("FAKE-SHOULD-NOT-INGEST" not in c.text for c in result.chunks)


def test_checksum_mismatch_fails_before_chunks(tmp_path: Path) -> None:
    _write_manual(tmp_path, "fixture-a", ["FAKE-PAGE-ONE"])
    expected = _sha256(b"FAKE-OTHER-BYTES")
    manifest = _write_manifest(tmp_path, [("fixture-a", expected)])
    output_dir = tmp_path / "out"

    with pytest.raises(ManifestError, match="checksum mismatch"):
        ingest(manifest, tmp_path)

    assert (
        main(
            [
                "--manifest",
                str(manifest),
                "--manuals-dir",
                str(tmp_path),
                "--output-dir",
                str(output_dir),
            ]
        )
        == 1
    )
    assert not output_dir.exists()


def test_tbd_checksum_fails_before_chunks(tmp_path: Path) -> None:
    _write_manual(tmp_path, "fixture-a", ["FAKE-PAGE-ONE"])
    manifest = _write_manifest(tmp_path, [("fixture-a", "TBD")])

    with pytest.raises(ManifestError, match="checksum TBD"):
        ingest(manifest, tmp_path)


def test_reingest_is_byte_identical(tmp_path: Path) -> None:
    _, digest_a = _write_manual(
        tmp_path, "fixture-a", ["FAKE-PAGE-ONE", None, "FAKE-PAGE-THREE"]
    )
    _, digest_b = _write_manual(tmp_path, "fixture-b", ["FAKE-OTHER-DOC"])
    manifest = _write_manifest(
        tmp_path, [("fixture-a", digest_a), ("fixture-b", digest_b)]
    )
    first = tmp_path / "out-1"
    second = tmp_path / "out-2"
    argv_first = [
        "--manifest",
        str(manifest),
        "--manuals-dir",
        str(tmp_path),
        "--output-dir",
        str(first),
    ]

    assert main(argv_first) == 0
    chunks = (first / CHUNKS_FILENAME).read_bytes()
    report = (first / REPORT_FILENAME).read_bytes()
    (first / CHUNKS_FILENAME).write_bytes(chunks + b"GARBAGE\n")
    assert main(argv_first) == 0
    assert (first / CHUNKS_FILENAME).read_bytes() == chunks
    assert (
        main(
            [
                "--manifest",
                str(manifest),
                "--manuals-dir",
                str(tmp_path),
                "--output-dir",
                str(second),
            ]
        )
        == 0
    )
    assert (second / CHUNKS_FILENAME).read_bytes() == chunks
    assert (second / REPORT_FILENAME).read_bytes() == report
    assert chunks == render_chunks(ingest(manifest, tmp_path).chunks).encode("utf-8")
    assert b"FAKE-PAGE-ONE" in chunks
    assert b'"page":1' in chunks
    assert b'"page":3' in chunks
    assert b'"page":2' in report
    assert b'"skipped":[]' in report


def test_blocked_pdf_is_verified_then_omitted_from_fts(tmp_path: Path) -> None:
    _, digest_ingest = _write_manual(tmp_path, "2jz-ge-rm", ["FAKE-PAGE-TEXT starter"])
    blocked_path = tmp_path / "lj78-wiring.pdf"
    blocked_path.write_bytes(b"not-a-pdf FAKE-WIRING")
    digest_blocked = _sha256(blocked_path.read_bytes())
    manifest = _write_manifest(
        tmp_path,
        [("2jz-ge-rm", digest_ingest), ("lj78-wiring", digest_blocked)],
        statuses={"lj78-wiring": "blocked"},
    )
    output_dir = tmp_path / "out"

    assert (
        main(
            [
                "--manifest",
                str(manifest),
                "--manuals-dir",
                str(tmp_path),
                "--output-dir",
                str(output_dir),
            ]
        )
        == 0
    )

    chunks_path = output_dir / CHUNKS_FILENAME
    chunks = chunks_path.read_text(encoding="utf-8")
    report = (output_dir / REPORT_FILENAME).read_text(encoding="utf-8")
    assert '"doc_id":"2jz-ge-rm"' in chunks
    assert "FAKE-PAGE-TEXT starter" in chunks
    assert "lj78-wiring" not in chunks
    assert "FAKE-WIRING" not in chunks
    assert '"skipped":["lj78-wiring"]' in report

    index_path = output_dir / "index.sqlite"
    assert (
        retrieval_main(
            ["build", "--chunks", str(chunks_path), "--index", str(index_path)]
        )
        == 0
    )
    with Fts5Index.open(index_path) as index:
        hits = index.search("FAKE-PAGE-TEXT")
        assert [(hit.doc_id, hit.page, hit.text) for hit in hits] == [
            ("2jz-ge-rm", 1, "FAKE-PAGE-TEXT starter"),
        ]
        assert index.search("not-a-pdf") == ()


def test_blocked_pdf_may_be_missing(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _, digest_ingest = _write_manual(tmp_path, "2jz-ge-rm", ["FAKE-PAGE-TEXT starter"])
    digest_blocked = _sha256(b"FAKE-BLOCKED-BYTES")
    manifest = _write_manifest(
        tmp_path,
        [("2jz-ge-rm", digest_ingest), ("lj78-wiring", digest_blocked)],
        statuses={"lj78-wiring": "blocked"},
    )
    output_dir = tmp_path / "out"

    result = ingest(manifest, tmp_path)

    assert [chunk.doc_id for chunk in result.chunks] == ["2jz-ge-rm"]
    assert result.skipped == ("lj78-wiring",)
    assert result.warnings == (
        f"missing file for blocked document 'lj78-wiring': {tmp_path / 'lj78-wiring.pdf'}",
    )
    assert (
        main(
            [
                "--manifest",
                str(manifest),
                "--manuals-dir",
                str(tmp_path),
                "--output-dir",
                str(output_dir),
            ]
        )
        == 0
    )
    err = capsys.readouterr().err
    assert "warning: missing file for blocked document 'lj78-wiring'" in err
    report = (output_dir / REPORT_FILENAME).read_text(encoding="utf-8")
    assert '"skipped":["lj78-wiring"]' in report
    assert "lj78-wiring" not in (output_dir / CHUNKS_FILENAME).read_text(
        encoding="utf-8"
    )
