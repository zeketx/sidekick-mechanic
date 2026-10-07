from __future__ import annotations

import json
from pathlib import Path

import pytest

from eval.retrieval_real import (
    SKIP_MESSAGE,
    load_cases,
    manuals_present,
    run_retrieval_eval,
    score_hits,
)
from retrieval import build_index, load_chunks_jsonl


def test_fixture_has_engine_and_wiring_rows() -> None:
    cases = load_cases()
    engine = [case for case in cases if case.corpus == "engine"]
    wiring = [case for case in cases if case.corpus == "engine-wiring"]

    assert 8 <= len(engine) <= 10
    assert 4 <= len(wiring) <= 6
    assert all(case.expected for case in cases)


def test_score_hits_is_one_based() -> None:
    expected = (("2jz-ge-rm", 985),)
    hits = (("2jz-ge-rm", 3), ("2jz-ge-rm", 985), ("2jz-ge-rm", 77))

    assert score_hits(expected, hits) == 2
    assert score_hits(expected, hits[:1]) is None
    assert score_hits(expected, (("2jz-ge-rm", 985),)) == 1


def test_skips_when_manuals_are_absent(tmp_path: Path) -> None:
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    summary = run_retrieval_eval(
        manuals_dir=manuals,
        index_path=tmp_path / "missing.sqlite",
        fixture_path=_write_fixture(tmp_path),
    )

    assert summary.skipped is True
    assert summary.reason == SKIP_MESSAGE
    assert summary.cases == ()
    assert manuals_present(manuals) is False


@pytest.mark.skipif(not manuals_present(), reason=SKIP_MESSAGE)
def test_real_pdf_hit_rates_when_manuals_present() -> None:
    summary = run_retrieval_eval()
    if summary.skipped:
        pytest.skip(summary.reason or SKIP_MESSAGE)
    assert summary.n >= 12
    assert summary.hit_at_1 is not None and summary.hit_at_1 >= 0.75
    assert summary.hit_at_3 == 1.0


def test_eval_scores_a_local_index(tmp_path: Path) -> None:
    manuals = tmp_path / "manuals"
    manuals.mkdir()
    (manuals / "2jz-ge-rm.pdf").write_bytes(b"%PDF-FAKE")
    (manuals / "is300-engine-wiring.pdf").write_bytes(b"%PDF-FAKE")
    chunks = tmp_path / "chunks.jsonl"
    chunks.write_text(
        json.dumps(
            {
                "doc_id": "2jz-ge-rm",
                "page": 999,
                "text": "reinstall the spark plugs. Torque: 18 FAKE-SPEC",
            },
            separators=(",", ":"),
        )
        + "\n"
        + json.dumps(
            {
                "doc_id": "2jz-ge-rm",
                "page": 3,
                "text": "2JZ-GE identification FAKE-SPEC",
            },
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    index_path = tmp_path / "index.sqlite"
    build_index(load_chunks_jsonl(chunks), index_path)
    fixture = _write_fixture(tmp_path)

    summary = run_retrieval_eval(
        manuals_dir=manuals,
        index_path=index_path,
        fixture_path=fixture,
    )

    assert summary.skipped is False
    assert summary.n == 1
    assert summary.hit_at_1 == 1.0
    assert summary.hit_at_3 == 1.0
    assert summary.cases[0].hits[0] == ("2jz-ge-rm", 999)


def _write_fixture(tmp_path: Path) -> Path:
    path = tmp_path / "retrieval-real.jsonl"
    path.write_text(
        json.dumps(
            {
                "id": "spark-plug-torque",
                "corpus": "engine",
                "question": "What's the spark plug torque on the 2JZ-GE?",
                "expected": [{"doc_id": "2jz-ge-rm", "page": 999}],
            },
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    return path
