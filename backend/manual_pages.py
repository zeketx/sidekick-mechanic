"""Render one cited manual page as a PNG.

Real documents are rasterized from ``manuals/<id>.pdf`` with pdftoppm
(1-based viewer page numbers, same as ingest). ``FAKE-DOC*`` ids get a
generated stand-in. PDFs are never written into the repo.
"""

from __future__ import annotations

import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from go_deeper import FAKE_DOC_PREFIX, FAKE_PAGE_TEXT, is_fake_doc_id
from manifest import ManifestError, load_manifest

_REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANUALS_DIR = _REPO_ROOT / "manuals"
DEFAULT_MANIFEST_PATH = _REPO_ROOT / "docs" / "MANUALS.md"
DEFAULT_CACHE_DIR = Path(__file__).resolve().parent / ".ingest" / "pages"
RASTER_DPI = 150
_SAFE_DOC_ID = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_FONT_PATH = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")


class ManualPageError(Exception):
    """The page image cannot be produced."""

    def __init__(self, message: str, *, status_code: int) -> None:
        super().__init__(message)
        self.status_code = status_code


def is_safe_doc_id(doc_id: str) -> bool:
    """Document ids become one path component. ``.`` and ``..`` would escape."""
    if doc_id in {".", ".."}:
        return False
    return bool(_SAFE_DOC_ID.fullmatch(doc_id))


def is_servable_doc_id(
    doc_id: str,
    *,
    manifest_path: Path | None = None,
) -> bool:
    """Fixture IDs and ``ingest`` rows only. Blocked and unknown IDs are not served."""
    if not is_safe_doc_id(doc_id):
        return False
    if is_fake_doc_id(doc_id):
        return True
    path = manifest_path if manifest_path is not None else DEFAULT_MANIFEST_PATH
    try:
        documents = load_manifest(path)
    except ManifestError:
        return False
    return any(doc.id == doc_id and doc.status == "ingest" for doc in documents)


def page_png(
    doc_id: str,
    page: int,
    *,
    manuals_dir: Path | None = None,
    cache_dir: Path | None = None,
    manifest_path: Path | None = None,
) -> bytes:
    """Return PNG bytes for one 1-based page."""
    if not is_servable_doc_id(doc_id, manifest_path=manifest_path):
        raise ManualPageError("This manual page is not available.", status_code=404)
    if not isinstance(page, int) or isinstance(page, bool) or page < 1:
        raise ManualPageError("This manual page is not available.", status_code=404)
    if is_fake_doc_id(doc_id):
        return fake_page_png(doc_id, page)

    manuals = manuals_dir if manuals_dir is not None else DEFAULT_MANUALS_DIR
    cache = cache_dir if cache_dir is not None else DEFAULT_CACHE_DIR
    cached = _cached_png(cache, doc_id, page)
    if cached is not None:
        return cached
    pdf_path = manuals / f"{doc_id}.pdf"
    if not pdf_path.is_file():
        raise ManualPageError("This manual page is not available.", status_code=404)
    png = _rasterize(pdf_path, page)
    _store_cache(cache, doc_id, page, png)
    return png


def fake_page_png(doc_id: str, page: int) -> bytes:
    """Striped stand-in with FAKE labels. Not a real manual page."""
    width, height = 400, 560
    image = Image.new("RGB", (width, height), (0xF2, 0xF2, 0xF2))
    draw = ImageDraw.Draw(image)
    stripe = 0xD8
    for top in range(8, height - 8, 16):
        draw.rectangle((8, top, width - 9, min(top + 7, height - 9)), fill=(stripe, stripe, stripe))
    draw.rectangle((0, 0, width - 1, height - 1), outline=(0x2C, 0x2C, 0x2C), width=6)
    font = _font(22)
    small = _font(14)
    lines = [
        doc_id,
        f"p. {page}",
        "FAKE-PAGE",
        FAKE_PAGE_TEXT if doc_id.startswith(FAKE_DOC_PREFIX) else "FAKE-PAGE",
    ]
    y = 28
    for index, line in enumerate(lines):
        draw.text((24, y), line, font=font if index < 3 else small, fill=(0x2C, 0x2C, 0x2C))
        y += 36 if index < 3 else 18
    return _png_bytes(image)


def is_png(data: bytes) -> bool:
    return data.startswith(_PNG_SIGNATURE)


RASTER_TIMEOUT_SECONDS = 30


def _rasterize(pdf_path: Path, page: int) -> bytes:
    with tempfile.TemporaryDirectory(prefix="sidekick-page-") as tmp:
        prefix = Path(tmp) / "page"
        try:
            completed = subprocess.run(
                [
                    "pdftoppm",
                    "-png",
                    "-r",
                    str(RASTER_DPI),
                    "-f",
                    str(page),
                    "-l",
                    str(page),
                    "-singlefile",
                    str(pdf_path),
                    str(prefix),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=RASTER_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise ManualPageError(
                "This manual page took too long to render.",
                status_code=504,
            ) from exc
        except FileNotFoundError as exc:
            raise ManualPageError(
                "This manual page is not available.",
                status_code=404,
            ) from exc
        if completed.returncode != 0:
            raise ManualPageError("This manual page is not available.", status_code=404)
        png_path = Path(str(prefix) + ".png")
        if not png_path.is_file():
            raise ManualPageError("This manual page is not available.", status_code=404)
        data = png_path.read_bytes()
        if not is_png(data):
            raise ManualPageError("The manual page image was unreadable.", status_code=500)
        return data


def _cached_png(cache_dir: Path, doc_id: str, page: int) -> bytes | None:
    path = cache_dir / doc_id / f"{page}.png"
    if not path.is_file():
        return None
    data = path.read_bytes()
    if not is_png(data):
        path.unlink(missing_ok=True)
        return None
    return data


def _store_cache(cache_dir: Path, doc_id: str, page: int, data: bytes) -> None:
    path = cache_dir / doc_id / f"{page}.png"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    except OSError:
        return


def _png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    if _FONT_PATH.is_file():
        return ImageFont.truetype(str(_FONT_PATH), size)
    return ImageFont.load_default()
