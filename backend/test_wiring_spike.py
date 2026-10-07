from __future__ import annotations

import json
from pathlib import Path

import pytest

from eval.report import latest_results_path
from spikes.wiring_spike import main, missing_tools, run

_RESULTS = Path(__file__).resolve().parent / "eval" / "results" / "wiring-spike.json"


def _skip_if_tools_missing() -> None:
    reason = missing_tools()
    if reason is not None:
        pytest.skip(reason)


def _page(report: dict[str, object], sample_id: str) -> dict[str, object]:
    pages = report["pages"]
    assert isinstance(pages, list)
    match = [page for page in pages if page["sample_id"] == sample_id]
    assert len(match) == 1
    return match[0]


def test_five_synthetic_pages_score_text_and_ocr() -> None:
    _skip_if_tools_missing()
    report = run()
    assert report["real_manual"]["accuracy"] == "TBD"
    assert report["real_manual"]["doc_id"] == "lj78-wiring"

    pages = report["pages"]
    assert [page["sample_id"] for page in pages] == [
        "text-layer-rows",
        "image-only",
        "scrambled-order",
        "vertical-image",
        "mixed-caption",
    ]

    rows = _page(report, "text-layer-rows")
    assert rows["text_extraction"]["text"] == (
        "FAKE-ROW-1A FAKE-ROW-1B\nFAKE-ROW-2A FAKE-ROW-2B"
    )
    assert rows["text_extraction"]["usable_as_lookup"] is True
    assert rows["text_extraction"]["rows_intact"] == 2
    assert rows["ocr"]["text"] == ("FAKE-ROW-1A FAKE-ROW-1B\n\nFAKE-ROW-2A FAKE-ROW-2B")
    assert rows["ocr"]["usable_as_lookup"] is True

    image = _page(report, "image-only")
    assert image["text_extraction"]["text"] == ""
    assert image["text_extraction"]["tokens_missing"] == ["FAKE-SCAN-1", "FAKE-SCAN-2"]
    assert image["text_extraction"]["usable_as_lookup"] is False
    assert image["ocr"]["text"] == "FAKE-SCAN-1 FAKE-SCAN-2"
    assert image["ocr"]["usable_as_lookup"] is True

    scrambled = _page(report, "scrambled-order")
    assert scrambled["text_extraction"]["text"] == (
        "FAKE-PAIR-L1\nFAKE-PAIR-L2\nFAKE-PAIR-R1\nFAKE-PAIR-R2"
    )
    assert scrambled["text_extraction"]["tokens_missing"] == []
    assert scrambled["text_extraction"]["rows_intact"] == 0
    assert scrambled["text_extraction"]["usable_as_lookup"] is False
    assert scrambled["ocr"]["text"] == (
        "FAKE-PAIR-L1 FAKE-PAIR-R1\n\nFAKE-PAIR-L2 FAKE-PAIR-R2"
    )
    assert scrambled["ocr"]["rows_intact"] == 2
    assert scrambled["ocr"]["usable_as_lookup"] is True

    vertical = _page(report, "vertical-image")
    assert vertical["text_extraction"]["text"] == ""
    assert vertical["text_extraction"]["tokens_missing"] == [
        "FAKE-VERT-1",
        "FAKE-VERT-2",
    ]
    assert vertical["ocr"]["text"] == "CLdsaN AVA\n\nTLdsaANsV4"
    assert vertical["ocr"]["tokens_found"] == []
    assert vertical["ocr"]["unanchored_text"] is True
    assert vertical["ocr"]["usable_as_lookup"] is False
    assert "FAKE-VERT-1" not in vertical["ocr"]["text"]
    assert "FAKE-VERT-2" not in vertical["ocr"]["text"]

    mixed = _page(report, "mixed-caption")
    assert mixed["text_extraction"]["text"] == "FAKE-CAPTION"
    assert mixed["text_extraction"]["tokens_missing"] == [
        "FAKE-DIAGRAM-1",
        "FAKE-DIAGRAM-2",
    ]
    assert mixed["text_extraction"]["rows_intact"] == 1
    assert mixed["text_extraction"]["usable_as_lookup"] is False
    assert mixed["ocr"]["text"] == "FAKE-DIAGRAM-1 FAKE-DIAGRAM-2\n\nFAKE-CAPTION"
    assert mixed["ocr"]["usable_as_lookup"] is True


def test_cli_rewrites_the_committed_report(tmp_path: Path) -> None:
    _skip_if_tools_missing()
    output = tmp_path / "wiring-spike.json"
    assert main(["--output", str(output)]) == 0
    fresh = json.loads(output.read_text(encoding="utf-8"))
    committed = json.loads(_RESULTS.read_text(encoding="utf-8"))
    assert fresh["pages"] == committed["pages"]
    assert fresh["real_manual"] == committed["real_manual"]
    assert committed["pages"][4]["sample_id"] == "mixed-caption"
    assert committed["pages"][4]["text_extraction"]["text"] == "FAKE-CAPTION"


def test_missing_tools_names_the_font(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr("spikes.wiring_spike.FONT_PATH", tmp_path / "DejaVuSans.ttf")
    reason = missing_tools()
    assert reason is not None
    assert "DejaVuSans.ttf" in reason


def test_spike_json_is_not_the_harness_latest_result() -> None:
    latest = latest_results_path(_RESULTS.parent)
    assert latest.name == "2026-10-01.json"
    assert latest.name != "wiring-spike.json"
