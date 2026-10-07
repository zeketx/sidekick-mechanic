"""Chunk verified manual PDFs into page-level records."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

from pypdf import PdfReader
from pypdf.errors import PyPdfError

from manifest import ManifestError, print_warnings, verify_inventory

_REPO_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_MANIFEST = _REPO_ROOT / "docs" / "MANUALS.md"
_DEFAULT_MANUALS_DIR = _REPO_ROOT / "manuals"
_DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / ".ingest"

CHUNKS_FILENAME = "chunks.jsonl"
REPORT_FILENAME = "report.json"


class IngestError(Exception):
    """PDF extraction failed after the inventory verified."""


@dataclass(frozen=True)
class Chunk:
    doc_id: str
    page: int
    text: str


@dataclass(frozen=True)
class EmptyPage:
    doc_id: str
    page: int


@dataclass(frozen=True)
class DocumentStats:
    doc_id: str
    page_count: int
    chunk_count: int
    empty_page_count: int
    sha256: str


@dataclass(frozen=True)
class IngestionResult:
    chunks: tuple[Chunk, ...]
    empty_pages: tuple[EmptyPage, ...]
    documents: tuple[DocumentStats, ...]
    skipped: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()


def ingest(manifest_path: Path, manuals_dir: Path) -> IngestionResult:
    documents, warnings = verify_inventory(manifest_path, manuals_dir)
    selected = tuple(document for document in documents if document.status == "ingest")
    skipped = tuple(
        document.id for document in documents if document.status == "blocked"
    )
    chunks: list[Chunk] = []
    empty_pages: list[EmptyPage] = []
    stats: list[DocumentStats] = []
    for document in selected:
        path = manuals_dir / document.filename
        doc_chunks, doc_empty, page_count = _extract_document(document.id, path)
        chunks.extend(doc_chunks)
        empty_pages.extend(doc_empty)
        stats.append(
            DocumentStats(
                doc_id=document.id,
                page_count=page_count,
                chunk_count=len(doc_chunks),
                empty_page_count=len(doc_empty),
                sha256=document.sha256,
            )
        )
    return IngestionResult(
        chunks=tuple(chunks),
        empty_pages=tuple(empty_pages),
        documents=tuple(stats),
        skipped=skipped,
        warnings=tuple(warnings),
    )


def write_ingestion(result: IngestionResult, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    _replace_text(output_dir / CHUNKS_FILENAME, render_chunks(result.chunks))
    _replace_text(output_dir / REPORT_FILENAME, render_report(result))


def render_chunks(chunks: tuple[Chunk, ...]) -> str:
    return "".join(_json_line(asdict(chunk)) + "\n" for chunk in chunks)


def render_report(result: IngestionResult) -> str:
    payload = {
        "documents": [asdict(document) for document in result.documents],
        "empty_pages": [asdict(page) for page in result.empty_pages],
        "skipped": list(result.skipped),
    }
    return _json_line(payload) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Verify manuals against docs/MANUALS.md, then write page-level "
            f"{CHUNKS_FILENAME} and an empty-page {REPORT_FILENAME}."
        )
    )
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--manuals-dir", type=Path, default=_DEFAULT_MANUALS_DIR)
    parser.add_argument("--output-dir", type=Path, default=_DEFAULT_OUTPUT_DIR)
    args = parser.parse_args(argv)
    try:
        result = ingest(args.manifest, args.manuals_dir)
        write_ingestion(result, args.output_dir)
    except (ManifestError, IngestError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print_warnings(result.warnings)
    print(
        f"ingested {len(result.documents)} document(s), "
        f"skipped {len(result.skipped)} blocked, "
        f"{len(result.chunks)} chunk(s), "
        f"{len(result.empty_pages)} empty page(s)"
    )
    return 0


def _extract_document(
    doc_id: str, path: Path
) -> tuple[list[Chunk], list[EmptyPage], int]:
    try:
        reader = PdfReader(path)
    except (OSError, PyPdfError) as exc:
        raise IngestError(
            f"cannot read PDF for document '{doc_id}': {path}"
        ) from exc
    if reader.is_encrypted:
        raise IngestError(f"encrypted PDF for document '{doc_id}': {path}")
    page_count = len(reader.pages)
    if page_count == 0:
        raise IngestError(f"no pages in document '{doc_id}': {path}")

    chunks: list[Chunk] = []
    empty_pages: list[EmptyPage] = []
    # 1-based PDF page numbers, matching a viewer; citations anchor to these.
    for index, page in enumerate(reader.pages, start=1):
        text = _normalize_page_text(page.extract_text())
        if text:
            chunks.append(Chunk(doc_id=doc_id, page=index, text=text))
        else:
            empty_pages.append(EmptyPage(doc_id=doc_id, page=index))
    return chunks, empty_pages, page_count


_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def _normalize_page_text(raw: str | None) -> str:
    if not raw:
        return ""
    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    return _CONTROL_RE.sub("", text).strip()


def _json_line(obj: dict[str, object]) -> str:
    return json.dumps(obj, ensure_ascii=True, sort_keys=True, separators=(",", ":"))


def _replace_text(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


if __name__ == "__main__":
    sys.exit(main())
