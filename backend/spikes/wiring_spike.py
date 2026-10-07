from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

import pypdf
import pytesseract
from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader
from pypdf.errors import PyPdfError

FONT_PATH = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
_FONT_CANDIDATES = (
    FONT_PATH,
    Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    Path("/Library/Fonts/Arial.ttf"),
)
RASTER_DPI = 150
_FONT_SIZE = 36

_REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = _REPO_ROOT / "backend" / "eval" / "results" / "wiring-spike.json"


class WiringSpikeError(Exception):
    pass


@dataclass(frozen=True)
class SamplePage:
    page: int
    sample_id: str
    kind: str
    pdf: bytes
    tokens: tuple[str, ...]
    rows: tuple[tuple[str, ...], ...]


@dataclass(frozen=True)
class MethodScore:
    text: str
    tokens_found: tuple[str, ...]
    tokens_missing: tuple[str, ...]
    rows_intact: int
    row_count: int
    usable_as_lookup: bool
    unanchored_text: bool


@dataclass(frozen=True)
class PageScore:
    page: int
    sample_id: str
    kind: str
    tokens: tuple[str, ...]
    rows: tuple[tuple[str, ...], ...]
    text_extraction: MethodScore
    ocr: MethodScore


def run() -> dict[str, object]:
    _require_tools()
    pages = [_score(sample) for sample in build_samples()]
    return {
        "fixture_policy": "Tokens are FAKE-* placeholders. They are not vehicle facts.",
        "real_manual": {
            "doc_id": "lj78-wiring",
            "accuracy": "TBD",
            "reason": (
                "The PDF is not in the repo. docs/MANUALS.md records an "
                "AES-encrypted copy, and backend/ingest.py refuses encrypted PDFs."
            ),
        },
        "tools": _tool_versions(),
        "pages": [_page_payload(page) for page in pages],
    }


def build_samples() -> tuple[SamplePage, ...]:
    rows = (("FAKE-ROW-1A", "FAKE-ROW-1B"), ("FAKE-ROW-2A", "FAKE-ROW-2B"))
    pairs = (("FAKE-PAIR-L1", "FAKE-PAIR-R1"), ("FAKE-PAIR-L2", "FAKE-PAIR-R2"))
    scans = (("FAKE-SCAN-1", "FAKE-SCAN-2"),)
    verts = (("FAKE-VERT-1", "FAKE-VERT-2"),)
    diagrams = (("FAKE-DIAGRAM-1", "FAKE-DIAGRAM-2"), ("FAKE-CAPTION",))
    return (
        SamplePage(
            1,
            "text-layer-rows",
            "text-layer",
            _text_pdf(
                "BT /F1 24 Tf 40 320 Td (FAKE-ROW-1A) Tj 300 0 Td (FAKE-ROW-1B) Tj "
                "-300 -80 Td (FAKE-ROW-2A) Tj 300 0 Td (FAKE-ROW-2B) Tj ET"
            ),
            _flat(rows),
            rows,
        ),
        SamplePage(
            2,
            "image-only",
            "image-only",
            _image_pdf(
                _labeled_image((("FAKE-SCAN-1", 40, 80), ("FAKE-SCAN-2", 460, 80)))
            ),
            _flat(scans),
            scans,
        ),
        SamplePage(
            3,
            "scrambled-order",
            "text-layer-column-major",
            _text_pdf(
                "BT /F1 24 Tf 40 320 Td (FAKE-PAIR-L1) Tj 0 -80 Td (FAKE-PAIR-L2) Tj "
                "300 80 Td (FAKE-PAIR-R1) Tj 0 -80 Td (FAKE-PAIR-R2) Tj ET"
            ),
            _flat(pairs),
            pairs,
        ),
        SamplePage(
            4,
            "vertical-image",
            "image-only-vertical",
            _image_pdf(_vertical_image(("FAKE-VERT-1", "FAKE-VERT-2"))),
            _flat(verts),
            verts,
        ),
        SamplePage(
            5,
            "mixed-caption",
            "image-plus-caption",
            _image_pdf(
                _labeled_image(
                    (("FAKE-DIAGRAM-1", 40, 120), ("FAKE-DIAGRAM-2", 460, 120))
                ),
                extra_ops="BT /F1 18 Tf 40 30 Td (FAKE-CAPTION) Tj ET",
            ),
            _flat(diagrams),
            diagrams,
        ),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Score synthetic wiring pages with text extraction and OCR."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args(argv)
    try:
        report = run()
    except WiringSpikeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    _write_json(args.output, report)
    print(f"wrote {args.output}")
    return 0


def _score(sample: SamplePage) -> PageScore:
    extracted = _extract_text(sample.pdf)
    recognized = _ocr_pdf(sample.pdf)
    return PageScore(
        page=sample.page,
        sample_id=sample.sample_id,
        kind=sample.kind,
        tokens=sample.tokens,
        rows=sample.rows,
        text_extraction=_method_score(extracted, sample),
        ocr=_method_score(recognized, sample),
    )


def _method_score(text: str, sample: SamplePage) -> MethodScore:
    found = tuple(token for token in sample.tokens if token in text)
    missing = tuple(token for token in sample.tokens if token not in text)
    intact = sum(1 for row in sample.rows if _row_intact(text, row, sample.tokens))
    return MethodScore(
        text=text,
        tokens_found=found,
        tokens_missing=missing,
        rows_intact=intact,
        row_count=len(sample.rows),
        usable_as_lookup=not missing and intact == len(sample.rows),
        unanchored_text=bool(text.strip()) and not found,
    )


def _row_intact(text: str, row: tuple[str, ...], tokens: tuple[str, ...]) -> bool:
    if any(token not in text for token in row):
        return False
    if len(row) < 2:
        return True
    start = min(text.index(token) for token in row)
    end = max(text.index(token) + len(token) for token in row)
    span = text[start:end]
    return all(other not in span for other in tokens if other not in row)


def _extract_text(pdf: bytes) -> str:
    try:
        raw = PdfReader(BytesIO(pdf)).pages[0].extract_text()
    except (OSError, PyPdfError, ValueError) as exc:
        raise WiringSpikeError(f"text extraction failed: {exc}") from exc
    return (raw or "").strip()


def _ocr_pdf(pdf: bytes) -> str:
    with tempfile.TemporaryDirectory(prefix="wiring-spike-") as tmp:
        directory = Path(tmp)
        pdf_path = directory / "page.pdf"
        pdf_path.write_bytes(pdf)
        prefix = directory / "page"
        completed = subprocess.run(
            ["pdftoppm", "-png", "-r", str(RASTER_DPI), str(pdf_path), str(prefix)],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise WiringSpikeError(completed.stderr.strip() or "pdftoppm failed")
        image_path = Path(str(prefix) + "-1.png")
        if not image_path.is_file():
            raise WiringSpikeError(f"pdftoppm wrote no page image for {pdf_path.name}")
        return pytesseract.image_to_string(Image.open(image_path)).strip()


def _labeled_image(labels: tuple[tuple[str, int, int], ...]) -> Image.Image:
    image = Image.new("RGB", (900, 400), "white")
    draw = ImageDraw.Draw(image)
    font = _font()
    for text, x, y in labels:
        draw.text((x, y), text, font=font, fill=0)
    return image


def _vertical_image(labels: tuple[str, ...]) -> Image.Image:
    image = Image.new("RGB", (900, 500), "white")
    font = _font()
    x = 80
    for text in labels:
        piece = Image.new("RGB", (420, 48), "white")
        ImageDraw.Draw(piece).text((4, 4), text, font=font, fill=0)
        image.paste(piece.rotate(90, expand=True), (x, 30))
        x += 180
    return image


def resolved_font_path() -> Path | None:
    for path in _FONT_CANDIDATES:
        if path.is_file():
            return path
    return None


def _font() -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = resolved_font_path()
    if path is not None:
        return ImageFont.truetype(str(path), _FONT_SIZE)
    return ImageFont.load_default()


def _image_pdf(image: Image.Image, extra_ops: str = "") -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=95)
    jpeg = buffer.getvalue()
    width, height = image.size
    image_obj = (
        f"<< /Type /XObject /Subtype /Image /Width {width} /Height {height} "
        f"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode "
        f"/Length {len(jpeg)} >>\nstream\n".encode()
        + jpeg
        + b"\nendstream"
    )
    ops = f"q {width} 0 0 {height} 0 0 cm /Im0 Do Q\n{extra_ops}"
    return _pack_pdf(ops, width, height, image_obj)


def _text_pdf(ops: str, width: int = 900, height: int = 400) -> bytes:
    return _pack_pdf(ops, width, height, image_obj=None)


def _pack_pdf(ops: str, width: int, height: int, image_obj: bytes | None) -> bytes:
    stream = ops.encode("ascii")
    content = (
        f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream"
    )
    if image_obj is None:
        resources = "<< /Font << /F1 4 0 R >> >>"
        objs: dict[int, bytes] = {
            1: b"<< /Type /Catalog /Pages 2 0 R >>",
            2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            3: (
                f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] "
                f"/Resources {resources} /Contents 5 0 R >>"
            ).encode(),
            4: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            5: content,
        }
    else:
        resources = "<< /XObject << /Im0 5 0 R >> /Font << /F1 6 0 R >> >>"
        objs = {
            1: b"<< /Type /Catalog /Pages 2 0 R >>",
            2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            3: (
                f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] "
                f"/Resources {resources} /Contents 4 0 R >>"
            ).encode(),
            4: content,
            5: image_obj,
            6: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        }
    return _serialize_pdf(objs)


def _serialize_pdf(objs: dict[int, bytes]) -> bytes:
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
        (
            f"trailer << /Size {max_id + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"
        ).encode("ascii")
    )
    return bytes(out)


def _flat(rows: tuple[tuple[str, ...], ...]) -> tuple[str, ...]:
    return tuple(token for row in rows for token in row)


def missing_tools() -> str | None:
    """Skip only when raster/OCR tools are missing. Fonts fall back on macOS."""
    missing: list[str] = []
    if shutil.which("pdftoppm") is None:
        missing.append("pdftoppm")
    if shutil.which("tesseract") is None:
        missing.append("tesseract")
    try:
        import pytesseract as _pytesseract
    except ImportError:
        missing.append("pytesseract")
    else:
        del _pytesseract
    if not missing:
        return None
    return (
        "missing " + ", ".join(missing)
        + " (apt install poppler-utils tesseract-ocr; pip install pytesseract)"
    )


def _require_tools() -> None:
    reason = missing_tools()
    if reason is not None:
        raise WiringSpikeError(reason)


def _tool_versions() -> dict[str, str]:
    return {
        "tesseract": _command_version(["tesseract", "--version"]),
        "poppler": _command_version(["pdftotext", "-v"]),
        "pypdf": pypdf.__version__,
        "pdftoppm_dpi": str(RASTER_DPI),
    }


def _command_version(command: list[str]) -> str:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    text = (completed.stdout or completed.stderr).strip().splitlines()
    return text[0] if text else "unknown"


def _page_payload(page: PageScore) -> dict[str, object]:
    return {
        "page": page.page,
        "sample_id": page.sample_id,
        "kind": page.kind,
        "tokens": list(page.tokens),
        "rows": [list(row) for row in page.rows],
        "text_extraction": _method_payload(page.text_extraction),
        "ocr": _method_payload(page.ocr),
    }


def _method_payload(score: MethodScore) -> dict[str, object]:
    return {
        "text": score.text,
        "tokens_found": list(score.tokens_found),
        "tokens_missing": list(score.tokens_missing),
        "rows_intact": score.rows_intact,
        "row_count": score.row_count,
        "usable_as_lookup": score.usable_as_lookup,
        "unanchored_text": score.unanchored_text,
    }


def _write_json(path: Path, report: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


if __name__ == "__main__":
    sys.exit(main())
