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


def _write_manifest(directory: Path, rows: list[tuple[str, str]]) -> Path:
    lines = [
        "# Test inventory",
        "",
        "| ID | Title | Edition | Page count | SHA-256 |",
        "| --- | --- | --- | --- | --- |",
    ]
    for doc_id, sha256 in rows:
        lines.append(f"| {doc_id} | Fake test manual | TBD | TBD | {sha256} |")
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
