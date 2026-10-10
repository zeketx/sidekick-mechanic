from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pypdf import PdfWriter

from app import create_app
from go_deeper import (
    EXCERPT_LIMIT,
    FAKE_FUSE_GO_DEEPER,
    FAKE_PAGE_TEXT,
    excerpt_around_snippet,
    strip_control_chars,
)
from manual_pages import (
    RASTER_TIMEOUT_SECONDS,
    ManualPageError,
    _rasterize,
    is_png,
    is_safe_doc_id,
    is_servable_doc_id,
    page_png,
)

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _client(
    tmp_path: Path,
    *,
    chunks: str | None = None,
    go_deeper_client: object | None = None,
    manifest_path: Path | None = None,
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
            manifest_path=manifest_path,
        )
    )


def _write_manifest(directory: Path, rows: list[tuple[str, str, str]]) -> Path:
    path = directory / "MANUALS.md"
    lines = [
        "# Test inventory",
        "",
        "| ID | Title | Edition | Page count | SHA-256 | Status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for doc_id, digest, status in rows:
        lines.append(
            f"| {doc_id} | Fake test manual | TBD | TBD | {digest} | {status} |"
        )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


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


def test_only_ingest_and_fake_docs_are_servable() -> None:
    assert is_servable_doc_id("FAKE-DOC-2JZ")
    assert is_servable_doc_id("2jz-ge-rm")
    assert is_servable_doc_id("is300-engine-wiring")
    assert not is_servable_doc_id("lj78-wiring")
    assert not is_servable_doc_id("not-a-manual")
    assert not is_servable_doc_id("..")
    assert not is_servable_doc_id("FAKE/DOC")


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


def test_blocked_and_unknown_docs_are_404_even_when_the_pdf_exists(
    tmp_path: Path,
) -> None:
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    _blank_pdf(manuals / "lj78-wiring.pdf")
    _blank_pdf(manuals / "not-a-manual.pdf")
    cache = tmp_path / "pages"
    (cache / "lj78-wiring").mkdir(parents=True)
    (cache / "lj78-wiring" / "1.png").write_bytes(page_png("FAKE-DOC-2JZ", 999))
    client = TestClient(
        create_app(
            manuals_dir=manuals,
            page_cache_dir=cache,
            chunks_path=tmp_path / "missing.jsonl",
        )
    )

    assert client.get("/manuals/lj78-wiring/pages/1.png").status_code == 404
    assert client.get("/manuals/lj78-wiring/pages/1/go-deeper").status_code == 404
    assert client.get("/manuals/not-a-manual/pages/1.png").status_code == 404
    assert client.get("/manuals/not-a-manual/pages/1/go-deeper").status_code == 404
    assert client.get("/manuals/../pages/1.png").status_code == 404


def test_non_ingest_status_is_404(tmp_path: Path) -> None:
    digest = "a" * 64
    manifest = _write_manifest(
        tmp_path,
        [
            ("fixture-blocked", digest, "blocked"),
            ("fixture-ok", digest, "ingest"),
        ],
    )
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    _blank_pdf(manuals / "fixture-blocked.pdf")
    _blank_pdf(manuals / "fixture-ok.pdf")
    client = TestClient(
        create_app(
            manuals_dir=manuals,
            page_cache_dir=tmp_path / "pages",
            chunks_path=tmp_path / "missing.jsonl",
            manifest_path=manifest,
        )
    )
    assert client.get("/manuals/fixture-blocked/pages/1.png").status_code == 404
    assert client.get("/manuals/fixture-blocked/pages/1/go-deeper").status_code == 404
    if shutil.which("pdftoppm") is None:
        assert client.get("/manuals/fixture-ok/pages/1.png").status_code == 404
    else:
        assert client.get("/manuals/fixture-ok/pages/1.png").status_code == 200


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


def test_strip_control_chars_keeps_newline_and_tab() -> None:
    raw = "FAKE-SPEC:\x01 not-a-torque\n\tmore\x7f"
    assert strip_control_chars(raw) == "FAKE-SPEC: not-a-torque\n\tmore"
    assert "\x01" not in strip_control_chars(raw)


def test_excerpt_around_snippet_caps_length_on_word_boundary() -> None:
    snippet = "FAKE-SPEC: not a torque"
    page = "FAKE-ID\x01 " + ("junk " * 40) + ". " + snippet + " " + ("extra " * 80)
    excerpt = excerpt_around_snippet(page, snippet, limit=80)
    assert excerpt is not None
    assert "FAKE-SPEC: not a torque" in excerpt
    assert "\x01" not in excerpt
    assert "FAKE-ID" not in excerpt
    assert len(excerpt) <= 81
    assert excerpt.endswith("…")
    assert not excerpt[:-1].endswith(" ")


def test_excerpt_hides_when_snippet_does_not_match() -> None:
    assert excerpt_around_snippet("inspect the cover.", "spark plug torque") is None
    assert excerpt_around_snippet("inspect the cover.", None) is None
    assert excerpt_around_snippet("inspect the cover.", "  ") is None


def test_go_deeper_from_chunks_does_not_invent_specs(tmp_path: Path) -> None:
    chunk = (
        '{"doc_id":"2jz-ge-rm","page":12,"text":"FAKE-CHUNK: inspect the fixture cover. '
        'Use a flashlight. Value FAKE-SPEC."}\n'
    )
    client = _client(tmp_path, chunks=chunk)
    response = client.get(
        "/manuals/2jz-ge-rm/pages/12/go-deeper",
        params={"snippet": "inspect the fixture cover"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["doc_id"] == "2jz-ge-rm"
    assert payload["page"] == 12
    assert payload["how_it_works"]
    assert "inspect the fixture cover" in payload["how_it_works"]
    assert len(payload["how_it_works"]) <= EXCERPT_LIMIT
    assert "999 Nm" not in payload["how_it_works"]
    assert "pin 999" not in payload["how_it_works"].lower()
    joined = " ".join(str(payload.get(key) or "") for key in payload)
    assert "999 Nm" not in joined


def test_go_deeper_fallback_excerpts_around_snippet(tmp_path: Path) -> None:
    chunk = (
        '{"doc_id":"2jz-ge-rm","page":985,"text":"FAKE-ID\\u0001 FAKE-OTHER ohmmeter junk. '
        'FAKE-SPEC: not a torque. Then the fixture line follows."}\n'
    )
    payload = _client(tmp_path, chunks=chunk).get(
        "/manuals/2jz-ge-rm/pages/985/go-deeper",
        params={"snippet": "FAKE-SPEC: not a torque"},
    ).json()
    how = payload["how_it_works"]
    assert "FAKE-SPEC: not a torque" in how
    assert "\x01" not in how
    assert "FAKE-ID" not in how
    assert len(how) <= EXCERPT_LIMIT


def test_go_deeper_hides_how_it_works_without_snippet_match(tmp_path: Path) -> None:
    chunk = '{"doc_id":"2jz-ge-rm","page":12,"text":"FAKE-CHUNK: inspect the cover."}\n'
    payload = _client(tmp_path, chunks=chunk).get(
        "/manuals/2jz-ge-rm/pages/12/go-deeper"
    ).json()
    assert not payload.get("how_it_works")


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


def test_pdftoppm_timeout_is_not_a_hung_request(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    pdf = tmp_path / "FAKE-DOC.pdf"
    pdf.write_bytes(b"%PDF-1.4 FAKE")

    def expire(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        del args
        assert kwargs.get("timeout") == RASTER_TIMEOUT_SECONDS
        raise subprocess.TimeoutExpired(cmd="pdftoppm", timeout=RASTER_TIMEOUT_SECONDS)

    monkeypatch.setattr("manual_pages.subprocess.run", expire)
    with pytest.raises(ManualPageError) as raised:
        _rasterize(pdf, 1)
    assert raised.value.status_code == 504
    assert "too long" in str(raised.value)
