"""Real-PDF retrieval eval. Skips when manuals/ PDFs are not on disk.

Expected pages were read from pdftotext of the local manuals. The fixture
stores only question text and page numbers, not spec values.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from retrieval import Fts5Index, RetrievalError

EVAL_DIR = Path(__file__).resolve().parent
FIXTURE_PATH = EVAL_DIR / "fixtures" / "retrieval-real.jsonl"
_BACKEND = EVAL_DIR.parent
_REPO_ROOT = _BACKEND.parent
_DEFAULT_MANUALS = _REPO_ROOT / "manuals"
_DEFAULT_INDEX = _BACKEND / ".ingest" / "index.sqlite"
_ENGINE_WIRING_DOC = "is300-engine-wiring"
_REQUIRED_PDFS = ("2jz-ge-rm.pdf", "is300-engine-wiring.pdf")
SKIP_MESSAGE = "skip: manuals/ PDFs are not present"


@dataclass(frozen=True)
class RetrievalCase:
    id: str
    corpus: str
    question: str
    expected: tuple[tuple[str, int], ...]


@dataclass(frozen=True)
class CaseScore:
    id: str
    corpus: str
    question: str
    expected: tuple[tuple[str, int], ...]
    hits: tuple[tuple[str, int], ...]
    rank: int | None

    @property
    def hit_at_1(self) -> bool:
        return self.rank == 1

    @property
    def hit_at_3(self) -> bool:
        return self.rank is not None and self.rank <= 3


@dataclass(frozen=True)
class RetrievalSummary:
    skipped: bool
    reason: str | None
    cases: tuple[CaseScore, ...]

    @property
    def n(self) -> int:
        return len(self.cases)

    @property
    def hit_at_1(self) -> float | None:
        if not self.cases:
            return None
        return sum(1 for case in self.cases if case.hit_at_1) / self.n

    @property
    def hit_at_3(self) -> float | None:
        if not self.cases:
            return None
        return sum(1 for case in self.cases if case.hit_at_3) / self.n


def manuals_present(manuals_dir: Path = _DEFAULT_MANUALS) -> bool:
    return all((manuals_dir / name).is_file() for name in _REQUIRED_PDFS)


def load_cases(path: Path = FIXTURE_PATH) -> tuple[RetrievalCase, ...]:
    rows: list[RetrievalCase] = []
    for line_number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw.strip():
            continue
        payload = json.loads(raw)
        rows.append(_case_from_payload(payload, line_number))
    return tuple(rows)


def score_hits(
    expected: tuple[tuple[str, int], ...],
    hits: tuple[tuple[str, int], ...],
) -> int | None:
    wanted = set(expected)
    for rank, hit in enumerate(hits, start=1):
        if hit in wanted:
            return rank
    return None


def run_retrieval_eval(
    *,
    manuals_dir: Path = _DEFAULT_MANUALS,
    index_path: Path = _DEFAULT_INDEX,
    fixture_path: Path = FIXTURE_PATH,
    k: int = 5,
) -> RetrievalSummary:
    if not manuals_present(manuals_dir):
        return RetrievalSummary(skipped=True, reason=SKIP_MESSAGE, cases=())
    if not index_path.is_file():
        return RetrievalSummary(
            skipped=True,
            reason="skip: FTS index is not present (python3 retrieval.py build)",
            cases=(),
        )
    cases = load_cases(fixture_path)
    try:
        index = Fts5Index.open(index_path)
    except RetrievalError as exc:
        return RetrievalSummary(
            skipped=True,
            reason=f"skip: {exc}",
            cases=(),
        )
    try:
        scored = tuple(_score_case(index, case, k=k) for case in cases)
    finally:
        index.close()
    return RetrievalSummary(skipped=False, reason=None, cases=scored)


def render_summary(summary: RetrievalSummary) -> str:
    if summary.skipped:
        return f"{summary.reason}\n"
    lines = [
        f"n={summary.n} hit@1={_rate(summary.hit_at_1)} hit@3={_rate(summary.hit_at_3)}",
    ]
    for case in summary.cases:
        mark = "Y" if case.hit_at_1 else ("~" if case.hit_at_3 else "N")
        lines.append(
            f"{mark} {case.corpus} {case.id} rank={case.rank} hits={list(case.hits[:3])}"
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Score real-PDF retrieval hit@1 and hit@3. Skips without PDFs."
    )
    parser.add_argument("--manuals-dir", type=Path, default=_DEFAULT_MANUALS)
    parser.add_argument("--index", type=Path, default=_DEFAULT_INDEX)
    parser.add_argument("--fixture", type=Path, default=FIXTURE_PATH)
    parser.add_argument("--k", type=int, default=5)
    args = parser.parse_args(argv)
    summary = run_retrieval_eval(
        manuals_dir=args.manuals_dir,
        index_path=args.index,
        fixture_path=args.fixture,
        k=args.k,
    )
    sys.stdout.write(render_summary(summary))
    return 0


def _score_case(index: Fts5Index, case: RetrievalCase, *, k: int) -> CaseScore:
    doc_id = _ENGINE_WIRING_DOC if case.corpus == "engine-wiring" else None
    retrieved = index.search(case.question, k=k, doc_id=doc_id)
    hits = tuple((hit.doc_id, hit.page) for hit in retrieved)
    return CaseScore(
        id=case.id,
        corpus=case.corpus,
        question=case.question,
        expected=case.expected,
        hits=hits,
        rank=score_hits(case.expected, hits),
    )


def _case_from_payload(payload: Any, line_number: int) -> RetrievalCase:
    if not isinstance(payload, dict):
        raise ValueError(f"fixture line {line_number} is not an object")
    expected_raw = payload.get("expected")
    if not isinstance(expected_raw, list) or not expected_raw:
        raise ValueError(f"fixture line {line_number} needs expected pages")
    expected: list[tuple[str, int]] = []
    for item in expected_raw:
        if not isinstance(item, dict):
            raise ValueError(f"fixture line {line_number} has a bad expected row")
        doc_id = item.get("doc_id")
        page = item.get("page")
        if not isinstance(doc_id, str) or not isinstance(page, int) or page < 1:
            raise ValueError(f"fixture line {line_number} has a bad expected row")
        expected.append((doc_id, page))
    corpus = payload.get("corpus")
    question = payload.get("question")
    case_id = payload.get("id")
    if corpus not in {"engine", "engine-wiring"}:
        raise ValueError(f"fixture line {line_number} has a bad corpus")
    if not isinstance(question, str) or not question.strip():
        raise ValueError(f"fixture line {line_number} has a bad question")
    if not isinstance(case_id, str) or not case_id.strip():
        raise ValueError(f"fixture line {line_number} has a bad id")
    return RetrievalCase(
        id=case_id,
        corpus=corpus,
        question=question,
        expected=tuple(expected),
    )


def _rate(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:.3f}"


if __name__ == "__main__":
    raise SystemExit(main())
