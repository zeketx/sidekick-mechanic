"""Load docs/MANUALS.md and verify local PDF checksums."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_MANIFEST = _REPO_ROOT / "docs" / "MANUALS.md"
_DEFAULT_MANUALS_DIR = _REPO_ROOT / "manuals"

_REQUIRED_HEADERS = ("id", "title", "edition", "page count", "sha-256", "status")
_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_SEPARATOR_RE = re.compile(r"^:?-+:?$")
_STATUSES = frozenset({"ingest", "blocked"})


class ManifestError(Exception):
    """The inventory cannot be parsed or a PDF does not match it."""


@dataclass(frozen=True)
class ManualDocument:
    id: str
    title: str
    edition: str
    page_count: str
    sha256: str
    status: str

    @property
    def filename(self) -> str:
        return f"{self.id}.pdf"


def parse_manifest(text: str) -> list[ManualDocument]:
    rows = _inventory_rows(text)
    if not rows:
        raise ManifestError("manifest has no inventory table")

    documents: list[ManualDocument] = []
    seen: set[str] = set()
    for cells in rows:
        doc = _document_from_cells(cells)
        if doc.id in seen:
            raise ManifestError(f"duplicate document ID: {doc.id}")
        seen.add(doc.id)
        documents.append(doc)
    return documents


def load_manifest(path: Path) -> list[ManualDocument]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise ManifestError(f"missing manifest: {path}") from exc
    return parse_manifest(text)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_documents(documents: list[ManualDocument], manuals_dir: Path) -> None:
    errors: list[str] = []
    for document in documents:
        try:
            _verify_one(document, manuals_dir)
        except ManifestError as exc:
            errors.append(str(exc))
    if errors:
        raise ManifestError("\n".join(errors))


def verify_inventory(manifest_path: Path, manuals_dir: Path) -> list[ManualDocument]:
    documents = load_manifest(manifest_path)
    verify_documents(documents, manuals_dir)
    return documents


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify manual PDFs against docs/MANUALS.md."
    )
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--manuals-dir", type=Path, default=_DEFAULT_MANUALS_DIR)
    args = parser.parse_args(argv)
    try:
        documents = verify_inventory(args.manifest, args.manuals_dir)
    except ManifestError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"verified {len(documents)} document(s)")
    return 0


def _verify_one(document: ManualDocument, manuals_dir: Path) -> None:
    path = manuals_dir / document.filename
    if not path.is_file():
        raise ManifestError(
            f"missing file for document '{document.id}': {path}"
        )
    if document.sha256 == "TBD":
        raise ManifestError(
            f"checksum TBD for document '{document.id}'; "
            f"hash {path} and update docs/MANUALS.md"
        )
    actual = file_sha256(path)
    if actual != document.sha256:
        raise ManifestError(
            f"checksum mismatch for document '{document.id}': "
            f"expected {document.sha256} got {actual}"
        )


def _inventory_rows(text: str) -> list[dict[str, str]]:
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        header = _cells(lines[index])
        if (
            len(header) >= len(_REQUIRED_HEADERS) - 1
            and index + 1 < len(lines)
            and _is_separator(_cells(lines[index + 1]))
        ):
            mapping = {
                name.lower(): position for position, name in enumerate(header)
            }
            if all(name in mapping for name in _REQUIRED_HEADERS):
                return _data_rows(lines[index + 2 :], mapping)
            if all(name in mapping for name in _REQUIRED_HEADERS if name != "status"):
                raise ManifestError("inventory table is missing a Status column")
        index += 1
    return []


def _data_rows(
    lines: list[str], mapping: dict[str, int]
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in lines:
        cells = _cells(line)
        if not cells:
            if rows:
                break
            continue
        if _is_separator(cells):
            continue
        row = {}
        for name, position in mapping.items():
            row[name] = cells[position] if position < len(cells) else ""
        rows.append(row)
    return rows


def _document_from_cells(cells: dict[str, str]) -> ManualDocument:
    doc_id = cells["id"].strip()
    if not _ID_RE.fullmatch(doc_id):
        raise ManifestError(f"invalid document ID: {doc_id!r}")

    title = cells["title"].strip()
    if not title:
        raise ManifestError(f"document '{doc_id}' is missing a title")

    edition = _tbd_or_value(cells["edition"])
    page_count = _tbd_or_value(cells["page count"])
    sha256 = _parse_sha256(doc_id, cells["sha-256"])
    status = _parse_status(doc_id, cells["status"])
    return ManualDocument(
        id=doc_id,
        title=title,
        edition=edition,
        page_count=page_count,
        sha256=sha256,
        status=status,
    )


def _parse_status(doc_id: str, raw: str) -> str:
    value = raw.strip()
    if value not in _STATUSES:
        raise ManifestError(f"document '{doc_id}' has an invalid status: {raw!r}")
    return value


def _parse_sha256(doc_id: str, raw: str) -> str:
    value = raw.strip()
    if value.upper() == "TBD":
        return "TBD"
    digest = value.lower()
    if not _SHA256_RE.fullmatch(digest):
        raise ManifestError(
            f"document '{doc_id}' has an invalid SHA-256: {raw!r}"
        )
    return digest


def _tbd_or_value(raw: str) -> str:
    value = raw.strip()
    if not value or value.upper() == "TBD":
        return "TBD"
    return value


def _cells(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|"):
        return []
    return [cell.strip() for cell in stripped.strip("|").split("|")]


def _is_separator(cells: list[str]) -> bool:
    return bool(cells) and all(_SEPARATOR_RE.fullmatch(cell) for cell in cells)


if __name__ == "__main__":
    sys.exit(main())
