from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from manifest import ManifestError, load_manifest, verify_inventory

REPO_ROOT = Path(__file__).resolve().parent.parent
COMMITTED_MANIFEST = REPO_ROOT / "docs" / "MANUALS.md"


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _write_manifest(
    directory: Path,
    *,
    doc_id: str,
    sha256: str,
    title: str = "Fake test manual",
) -> Path:
    path = directory / "MANUALS.md"
    path.write_text(
        "\n".join(
            [
                "# Test inventory",
                "",
                "| ID | Title | Edition | Page count | SHA-256 |",
                "| --- | --- | --- | --- | --- |",
                f"| {doc_id} | {title} | TBD | TBD | {sha256} |",
                "",
            ]
        ),
        encoding="utf-8",
    )
    return path


def test_checksum_match(tmp_path: Path) -> None:
    payload = b"FAKE-MANUAL-BYTES"
    digest = _sha256(payload)
    (tmp_path / "fixture-a.pdf").write_bytes(payload)
    manifest = _write_manifest(tmp_path, doc_id="fixture-a", sha256=digest)

    documents = verify_inventory(manifest, tmp_path)

    assert [document.id for document in documents] == ["fixture-a"]
    assert documents[0].sha256 == digest
    assert documents[0].filename == "fixture-a.pdf"


def test_checksum_mismatch(tmp_path: Path) -> None:
    payload = b"FAKE-MANUAL-BYTES"
    actual = _sha256(payload)
    expected = _sha256(b"FAKE-OTHER-BYTES")
    (tmp_path / "fixture-a.pdf").write_bytes(payload)
    manifest = _write_manifest(tmp_path, doc_id="fixture-a", sha256=expected)

    with pytest.raises(ManifestError) as caught:
        verify_inventory(manifest, tmp_path)

    message = str(caught.value)
    assert "checksum mismatch for document 'fixture-a'" in message
    assert expected in message
    assert actual in message


def test_missing_file(tmp_path: Path) -> None:
    digest = _sha256(b"FAKE-MANUAL-BYTES")
    manifest = _write_manifest(tmp_path, doc_id="fixture-a", sha256=digest)

    with pytest.raises(ManifestError) as caught:
        verify_inventory(manifest, tmp_path)

    message = str(caught.value)
    assert "missing file for document 'fixture-a'" in message
    assert str(tmp_path / "fixture-a.pdf") in message


def test_committed_manifest_records_phase1_pdfs() -> None:
    documents = load_manifest(COMMITTED_MANIFEST)

    assert [document.id for document in documents] == [
        "2jz-ge-rm",
        "lj78-wiring",
    ]
    assert documents[0].title == (
        "Lexus IS300 2004 repair manual RM1054U (2JZ-GE VVTi)"
    )
    assert documents[1].title == "Toyota EWD117F Dec 1990 (LJ7x wiring)"
    assert documents[0].edition == "RM1054U"
    assert documents[1].edition == "EWD117F"
    assert documents[0].page_count == "1959"
    assert documents[1].page_count == "84"
    assert documents[0].sha256 == (
        "4464676a7fda45ada554909dc875ce12c4554f96d45c9ef400788e5e20d6008d"
    )
    assert documents[1].sha256 == (
        "eff462ba654ae488df12dbacb040771dba20d4f12eb8e5926024e8f03f632851"
    )
