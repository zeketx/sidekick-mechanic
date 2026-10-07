from __future__ import annotations

import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pypdf import PdfWriter

from app import create_app
from go_deeper import FAKE_FUSE_GO_DEEPER, FAKE_PAGE_TEXT
from manual_pages import is_png, is_safe_doc_id, page_png

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _client(
    tmp_path: Path,
    *,
    chunks: str | None = None,
    go_deeper_client: object | None = None,
) -> TestClient:
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    cache = tmp_path / "pages"
    chunks_path = tmp_path / "chunks.jsonl"
    if chunks is not None:
        chunks_path.write_text(chunks, encoding="utf-8")
    return TestClient(
        create_app(
            manuals_dir=manuals,
            chunks_path=chunks_path,
            page_cache_dir=cache,
            go_deeper_client=go_deeper_client,  # type: ignore[arg-type]
        )
    )


def _blank_pdf(path: Path, pages: int = 1) -> None:
    writer = PdfWriter()
    for _ in range(pages):
        writer.add_blank_page(width=200, height=200)
    with path.open("wb") as handle:
        writer.write(handle)


def test_unsafe_document_ids_are_rejected() -> None:
    assert is_safe_doc_id("FAKE-DOC-2JZ")
    assert is_safe_doc_id("2jz-ge-rm")
    assert not is_safe_doc_id("..")
    assert not is_safe_doc_id(".")
    assert not is_safe_doc_id("FAKE/DOC")
    assert not is_safe_doc_id("FAKE\\DOC")


def test_fake_doc_page_png_is_obviously_fake(tmp_path: Path) -> None:
    client = _client(tmp_path)
    response = client.get("/manuals/FAKE-DOC-2JZ/pages/999.png")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("image/png")
    assert response.content.startswith(PNG_SIGNATURE)
    assert is_png(response.content)
    png = page_png("FAKE-DOC-2JZ", 999)
    assert png == response.content
    assert len(png) > 200


def test_missing_and_unsafe_pages_are_404(tmp_path: Path) -> None:
    client = _client(tmp_path)
    assert client.get("/manuals/2jz-ge-rm/pages/1.png").status_code == 404
    assert client.get("/manuals/../pages/1.png").status_code == 404
    assert client.get("/manuals/FAKE-DOC-2JZ/pages/0.png").status_code == 404


def test_synthetic_pdf_rasterizes_when_pdftoppm_exists(tmp_path: Path) -> None:
    if shutil.which("pdftoppm") is None:
        pytest.skip("pdftoppm is not installed")
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    _blank_pdf(manuals / "2jz-ge-rm.pdf", pages=2)
    cache = tmp_path / "pages"
    client = TestClient(
        create_app(manuals_dir=manuals, page_cache_dir=cache, chunks_path=tmp_path / "missing.jsonl")
    )

    first = client.get("/manuals/2jz-ge-rm/pages/1.png")
    assert first.status_code == 200
    assert first.content.startswith(PNG_SIGNATURE)
    cached = cache / "2jz-ge-rm" / "1.png"
    assert cached.is_file()
    assert cached.read_bytes() == first.content

    second = client.get("/manuals/2jz-ge-rm/pages/1.png")
    assert second.content == first.content
    missing = client.get("/manuals/2jz-ge-rm/pages/9.png")
    assert missing.status_code == 404


def test_real_owner_pdfs_are_skipped_when_absent() -> None:
    repo_pdf = Path(__file__).resolve().parents[2] / "manuals" / "2jz-ge-rm.pdf"
    if not repo_pdf.is_file():
        pytest.skip("owner PDF manuals/2jz-ge-rm.pdf is not in this environment")
    if shutil.which("pdftoppm") is None:
        pytest.skip("pdftoppm is not installed")
    png = page_png("2jz-ge-rm", 1)
    assert png.startswith(PNG_SIGNATURE)


def test_fake_go_deeper_is_canned_and_grounded(tmp_path: Path) -> None:
    client = _client(tmp_path)
    response = client.get("/manuals/FAKE-DOC-2JZ/pages/999/go-deeper")

    assert response.status_code == 200
    payload = response.json()
    assert payload["doc_id"] == "FAKE-DOC-2JZ"
    assert payload["page"] == 999
    assert payload["how_it_works"] == FAKE_FUSE_GO_DEEPER["how_it_works"]
    assert payload["what_to_test"] == FAKE_FUSE_GO_DEEPER["what_to_test"]
    assert payload["how_to_test"] == FAKE_FUSE_GO_DEEPER["how_to_test"]
    assert payload["tools"] == FAKE_FUSE_GO_DEEPER["tools"]
    for value in FAKE_FUSE_GO_DEEPER.values():
        assert value in FAKE_PAGE_TEXT


def test_go_deeper_from_chunks_does_not_invent_specs(tmp_path: Path) -> None:
    chunk = (
        '{"doc_id":"2jz-ge-rm","page":12,"text":"FAKE-CHUNK: inspect the fixture cover. '
        'Use a flashlight. Value FAKE-SPEC."}\n'
    )
    client = _client(tmp_path, chunks=chunk)
    response = client.get("/manuals/2jz-ge-rm/pages/12/go-deeper")

    assert response.status_code == 200
    payload = response.json()
    assert payload["doc_id"] == "2jz-ge-rm"
    assert payload["page"] == 12
    assert payload["how_it_works"]
    assert "999 Nm" not in payload["how_it_works"]
    assert "pin 999" not in payload["how_it_works"].lower()
    joined = " ".join(str(payload.get(key) or "") for key in payload)
    assert "999 Nm" not in joined


def test_go_deeper_drops_uncited_specs(tmp_path: Path) -> None:
    from llm import FakeLLMClient

    chunk = '{"doc_id":"2jz-ge-rm","page":12,"text":"FAKE-CHUNK: look at the cover."}\n'
    client = _client(
        tmp_path,
        chunks=chunk,
        go_deeper_client=FakeLLMClient(
            text='{"how_it_works":"Torque is 999 Nm.","what_to_test":"Look at the cover."}'
        ),
    )
    payload = client.get("/manuals/2jz-ge-rm/pages/12/go-deeper").json()
    assert payload.get("how_it_works") != "Torque is 999 Nm."
    assert "999 Nm" not in (payload.get("how_it_works") or "")
    assert payload.get("what_to_test") == "Look at the cover."


def test_wiring_page_does_not_guess_pinouts(tmp_path: Path) -> None:
    chunk = '{"doc_id":"is300-engine-wiring","page":3,"text":"FAKE-CAPTION only."}\n'
    client = _client(tmp_path, chunks=chunk)
    payload = client.get("/manuals/is300-engine-wiring/pages/3/go-deeper").json()
    how = payload["how_it_works"]
    assert "pin" not in how.lower() or "guessing pinouts" in how
    assert how.startswith("This page is a wiring diagram.")
    assert payload.get("what_to_test") is None
    assert payload.get("tools") is None


def test_blank_wiring_pdf_omits_test_and_tools(tmp_path: Path) -> None:
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    _blank_pdf(manuals / "is300-engine-wiring.pdf")
    client = TestClient(
        create_app(
            manuals_dir=manuals,
            chunks_path=tmp_path / "missing.jsonl",
            page_cache_dir=tmp_path / "pages",
        )
    )
    payload = client.get("/manuals/is300-engine-wiring/pages/1/go-deeper").json()
    assert payload["how_it_works"].startswith("This page is a wiring diagram.")
    assert payload.get("what_to_test") is None
    assert payload.get("how_to_test") is None
    assert payload.get("tools") is None


def test_go_deeper_missing_page_is_404(tmp_path: Path) -> None:
    client = _client(tmp_path)
    assert client.get("/manuals/2jz-ge-rm/pages/1/go-deeper").status_code == 404
