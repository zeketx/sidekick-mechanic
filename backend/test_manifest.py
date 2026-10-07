from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from manifest import ManifestError, load_manifest, main, verify_inventory

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
    status: str = "ingest",
) -> Path:
    path = directory / "MANUALS.md"
    path.write_text(
        "\n".join(
            [
                "# Test inventory",
                "",
                "| ID | Title | Edition | Page count | SHA-256 | Status |",
                "| --- | --- | --- | --- | --- | --- |",
                f"| {doc_id} | {title} | TBD | TBD | {sha256} | {status} |",
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

    documents, warnings = verify_inventory(manifest, tmp_path)

    assert warnings == []
    assert [document.id for document in documents] == ["fixture-a"]
    assert documents[0].sha256 == digest
    assert documents[0].filename == "fixture-a.pdf"
    assert documents[0].status == "ingest"


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
        "is300-engine-wiring",
        "lj78-wiring",
    ]
    assert documents[0].title == (
        "Lexus IS300 2004 repair manual RM1054U (2JZ-GE VVTi)"
    )
    assert documents[1].title == "IS300 engine wiring (EWD451U)"
    assert documents[2].title == "Toyota EWD117F Dec 1990 (LJ7x wiring)"
    assert documents[0].edition == "RM1054U"
    assert documents[1].edition == "EWD451U"
    assert documents[2].edition == "EWD117F"
    assert documents[0].page_count == "1959"
    assert documents[1].page_count == "43"
    assert documents[2].page_count == "84"
    assert documents[0].sha256 == (
        "4464676a7fda45ada554909dc875ce12c4554f96d45c9ef400788e5e20d6008d"
    )
    assert documents[1].sha256 == (
        "80fc98b8963068f6ebb0ef0c0ca06a869f0edb6d98d7e70195d4247cae43e45d"
    )
    assert documents[2].sha256 == (
        "eff462ba654ae488df12dbacb040771dba20d4f12eb8e5926024e8f03f632851"
    )
    assert documents[0].status == "ingest"
    assert documents[1].status == "ingest"
    assert documents[2].status == "blocked"


def test_blocked_row_checksum_is_still_checked(tmp_path: Path) -> None:
    ingest_payload = b"FAKE-MANUAL-BYTES"
    blocked_payload = b"FAKE-BLOCKED-BYTES"
    (tmp_path / "fixture-a.pdf").write_bytes(ingest_payload)
    (tmp_path / "fixture-b.pdf").write_bytes(blocked_payload)
    wrong = _sha256(b"FAKE-OTHER-BYTES")
    manifest = tmp_path / "MANUALS.md"
    manifest.write_text(
        "\n".join(
            [
                "| ID | Title | Edition | Page count | SHA-256 | Status |",
                "| --- | --- | --- | --- | --- | --- |",
                f"| fixture-a | Fake test manual | TBD | TBD | {_sha256(ingest_payload)} | ingest |",
                f"| fixture-b | Fake blocked manual | TBD | TBD | {wrong} | blocked |",
                "",
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(ManifestError) as caught:
        verify_inventory(manifest, tmp_path)

    message = str(caught.value)
    assert "checksum mismatch for document 'fixture-b'" in message
    assert wrong in message
    assert _sha256(blocked_payload) in message


def test_blocked_row_verifies_when_the_hash_matches(tmp_path: Path) -> None:
    ingest_payload = b"FAKE-MANUAL-BYTES"
    blocked_payload = b"FAKE-BLOCKED-BYTES"
    (tmp_path / "fixture-a.pdf").write_bytes(ingest_payload)
    (tmp_path / "fixture-b.pdf").write_bytes(blocked_payload)
    manifest = tmp_path / "MANUALS.md"
    manifest.write_text(
        "\n".join(
            [
                "| ID | Title | Edition | Page count | SHA-256 | Status |",
                "| --- | --- | --- | --- | --- | --- |",
                f"| fixture-a | Fake test manual | TBD | TBD | {_sha256(ingest_payload)} | ingest |",
                f"| fixture-b | Fake blocked manual | TBD | TBD | {_sha256(blocked_payload)} | blocked |",
                "",
            ]
        ),
        encoding="utf-8",
    )

    documents, warnings = verify_inventory(manifest, tmp_path)

    assert warnings == []
    assert [(document.id, document.status) for document in documents] == [
        ("fixture-a", "ingest"),
        ("fixture-b", "blocked"),
    ]


def test_blocked_row_missing_file_is_a_warning(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    ingest_payload = b"FAKE-MANUAL-BYTES"
    (tmp_path / "fixture-a.pdf").write_bytes(ingest_payload)
    manifest = tmp_path / "MANUALS.md"
    manifest.write_text(
        "\n".join(
            [
                "| ID | Title | Edition | Page count | SHA-256 | Status |",
                "| --- | --- | --- | --- | --- | --- |",
                f"| fixture-a | Fake test manual | TBD | TBD | {_sha256(ingest_payload)} | ingest |",
                f"| fixture-b | Fake blocked manual | TBD | TBD | {_sha256(b'FAKE-BLOCKED-BYTES')} | blocked |",
                "",
            ]
        ),
        encoding="utf-8",
    )

    documents, warnings = verify_inventory(manifest, tmp_path)

    assert [document.id for document in documents] == ["fixture-a", "fixture-b"]
    assert warnings == [
        f"missing file for blocked document 'fixture-b': {tmp_path / 'fixture-b.pdf'}"
    ]
    assert (
        main(["--manifest", str(manifest), "--manuals-dir", str(tmp_path)]) == 0
    )
    err = capsys.readouterr().err
    assert "warning: missing file for blocked document 'fixture-b'" in err
    assert str(tmp_path / "fixture-b.pdf") in err


def test_missing_ingest_file_still_fails_when_blocked_is_also_missing(
    tmp_path: Path,
) -> None:
    digest = _sha256(b"FAKE-MANUAL-BYTES")
    manifest = tmp_path / "MANUALS.md"
    manifest.write_text(
        "\n".join(
            [
                "| ID | Title | Edition | Page count | SHA-256 | Status |",
                "| --- | --- | --- | --- | --- | --- |",
                f"| fixture-a | Fake test manual | TBD | TBD | {digest} | ingest |",
                f"| fixture-b | Fake blocked manual | TBD | TBD | {digest} | blocked |",
                "",
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(ManifestError) as caught:
        verify_inventory(manifest, tmp_path)

    message = str(caught.value)
    assert "missing file for document 'fixture-a'" in message
    assert "fixture-a.pdf" in message


def test_invalid_status_rejected(tmp_path: Path) -> None:
    manifest = _write_manifest(
        tmp_path,
        doc_id="fixture-a",
        sha256=_sha256(b"FAKE-MANUAL-BYTES"),
        status="later",
    )

    with pytest.raises(ManifestError, match="invalid status"):
        load_manifest(manifest)


def test_missing_status_column_rejected(tmp_path: Path) -> None:
    manifest = tmp_path / "MANUALS.md"
    manifest.write_text(
        "| ID | Title | Edition | Page count | SHA-256 |\n"
        "| --- | --- | --- | --- | --- |\n"
        "| fixture-a | Fake test manual | TBD | TBD | TBD |\n",
        encoding="utf-8",
    )

    with pytest.raises(ManifestError, match="Status column"):
        load_manifest(manifest)
