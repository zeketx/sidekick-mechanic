from __future__ import annotations

import argparse
import enum
import json
import os
import re
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType

from eval.golden import GoldenQuestion, GoldenSetError, load_golden
from manifest import ManifestError, load_manifest

PROVISIONAL_PART_IDS: frozenset[str] = frozenset(
    {
        "alternator",
        "brake-master-cylinder",
        "camshaft-position-sensor",
        "ect-sensor",
        "ignition-coil",
        "maf-meter",
        "oil-control-valve",
        "power-steering-pump",
        "radiator-cap",
        "starter-relay",
        "thermostat",
        "throttle-body",
        "timing-belt-cover",
    }
)

_QUESTION_TARGET = 50
TOTAL_MIN = _QUESTION_TARGET - 5
TOTAL_MAX = _QUESTION_TARGET + 5
ANSWERABLE_MIN = 10
UNANSWERABLE_SPEC_MIN = 10
PART_ID_MIN = 10

_BACKEND_DIR = Path(__file__).resolve().parents[1]
_REPO_ROOT = _BACKEND_DIR.parent
_DEFAULT_MANIFEST = _REPO_ROOT / "docs" / "MANUALS.md"
_DEFAULT_CHUNKS = _BACKEND_DIR / ".ingest" / "chunks.jsonl"
_DEFAULT_GOLDEN = Path(__file__).resolve().parent / "golden.jsonl"

_WORD_RE = re.compile(r"[a-z0-9]+")
_FAKE_SPEC_RE = re.compile(r"(?<![A-Za-z0-9])FAKE-SPEC(?![A-Za-z0-9-])")
_PIN_NUMBER_RE = re.compile(r"\b(?:pin|terminal)\s+\d+\b", re.IGNORECASE)
_LONG_DIGIT_RE = re.compile(r"(?<![A-Za-z0-9])\d{5,}(?![A-Za-z0-9])")
_PART_NUMBER_RE = re.compile(r"(?<![A-Za-z0-9])\d+-\d+(?![A-Za-z0-9])")

_UNIT_WORDS = (
    "N\u00b7m",
    "Nm",
    "N-m",
    "ft-lb",
    "ohms",
    "ohm",
    "degrees",
    "degree",
    "rpm",
    "mm",
    "volts",
    "volt",
    "psi",
    "kPa",
    "miles",
    "mile",
    "km",
    "liters",
    "liter",
    "quarts",
    "quart",
)
_NUMBER_UNIT_RE = re.compile(
    r"(?<![A-Za-z0-9])(?:\d{1,3}(?:,\d{3})+|\d+)\s*"
    r"(?:" + "|".join(re.escape(unit) for unit in _UNIT_WORDS) + r")\b",
    re.IGNORECASE,
)
_CELSIUS_RE = re.compile(
    r"(?<![A-Za-z0-9])(?:\d{1,3}(?:,\d{3})+|\d+)\s+C\b",
    re.IGNORECASE,
)

_SPEC_WORDS = frozenset(
    {
        "torque",
        "torques",
        "resistance",
        "clearance",
        "capacity",
        "pressure",
        "gap",
        "voltage",
        "pinout",
        "pin",
        "pins",
        "terminal",
        "terminals",
        "connector",
        "advance",
        "boost",
        "fluid",
        "grade",
        "ohm",
        "ohms",
        "length",
    }
)
_SPEC_PHRASES = frozenset(
    {
        ("wire", "color"),
        ("how", "much"),
        ("how", "many"),
        ("how", "tight"),
        ("ignition", "timing"),
    }
)
_COLORS = frozenset(
    {
        "red",
        "blue",
        "black",
        "green",
        "white",
        "yellow",
        "brown",
        "orange",
        "pink",
        "violet",
        "purple",
        "gray",
        "grey",
    }
)
_STOP = frozenset(
    {
        "what",
        "whats",
        "which",
        "when",
        "where",
        "how",
        "does",
        "do",
        "did",
        "should",
        "can",
        "could",
        "would",
        "will",
        "just",
        "only",
        "also",
        "the",
        "and",
        "for",
        "with",
        "this",
        "that",
        "from",
        "into",
        "your",
        "have",
        "has",
        "had",
        "are",
        "was",
        "were",
        "been",
        "being",
        "its",
        "they",
        "them",
        "then",
        "than",
        "there",
        "their",
        "about",
        "after",
        "before",
        "between",
        "while",
        "during",
        "under",
        "over",
        "engine",
        "manual",
        "page",
        "spec",
        "specification",
        "stock",
        "truck",
        "mean",
        "means",
        "really",
        "actually",
        "need",
        "needs",
        "take",
        "takes",
        "read",
        "reads",
        "using",
        "used",
        "make",
        "makes",
        "much",
        "many",
        "seen",
        "show",
        "shows",
        "going",
        "goes",
        "air",
        "but",
        "not",
        "you",
        "out",
        "all",
        "any",
        "per",
        "via",
        "one",
        "two",
    }
)


class RejectReason(enum.Enum):
    SPEC_IN_QUESTION = "spec_in_question"
    PART_ID_UNKNOWN = "part_id_unknown"
    UNANSWERABLE_HAS_PAGES = "unanswerable_has_pages"
    DOC_NOT_INGEST = "doc_not_ingest"
    PAGE_OUT_OF_RANGE = "page_out_of_range"
    PAGE_NOT_IN_CORPUS = "page_not_in_corpus"
    TOPIC_NOT_IN_TEXT = "topic_not_in_text"
    SPEC_SHAPE_MISSING = "spec_shape_missing"


@dataclass(frozen=True)
class Inventory:
    """Ingest manuals only. page_counts are the manifest integers.

    Blocked rows are absent. A citation to one fails DOC_NOT_INGEST.
    """

    ingest_ids: frozenset[str]
    page_counts: Mapping[str, int]


@dataclass(frozen=True)
class LoadedCorpus:
    """Non-empty ingest page text, keyed by (doc_id, page).

    pages is a read-only map. Missing keys are empty extracts or pages
    the chunk file never wrote. None is not a legal value here.
    """

    inventory: Inventory
    pages: Mapping[tuple[str, int], str]


@dataclass(frozen=True)
class RowRejection:
    question_id: str
    reason: RejectReason


@dataclass(frozen=True)
class QuotaVerdict:
    total: int
    answerable: int
    unanswerable_spec: int
    part_rows: int
    ok: bool
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class ScreenResult:
    kept: tuple[GoldenQuestion, ...]
    rejected: tuple[RowRejection, ...]
    quotas: QuotaVerdict


@dataclass(frozen=True)
class GateResult:
    kept: tuple[GoldenQuestion, ...]
    rejected: tuple[RowRejection, ...]
    quotas: QuotaVerdict


class GateError(Exception):
    """Manifest, chunk file, or write refusal.

    Row-level rejects live on GateResult. result is None for a bad file.
    """

    def __init__(self, message: str, result: GateResult | None = None) -> None:
        super().__init__(message)
        self.result = result


class CorpusMissing(GateError):
    pass


def load_inventory(manifest_path: Path) -> Inventory:
    try:
        documents = load_manifest(manifest_path)
    except ManifestError as exc:
        raise GateError(str(exc)) from exc
    ingest_ids: set[str] = set()
    page_counts: dict[str, int] = {}
    for document in documents:
        if document.status != "ingest":
            continue
        try:
            count = int(document.page_count)
        except (TypeError, ValueError) as exc:
            raise GateError(
                f"non-integer page count for ingest document {document.id}"
            ) from exc
        ingest_ids.add(document.id)
        page_counts[document.id] = count
    return Inventory(
        ingest_ids=frozenset(ingest_ids),
        page_counts=MappingProxyType(page_counts),
    )


def load_corpus(chunks_path: Path, inventory: Inventory) -> LoadedCorpus:
    if not chunks_path.is_file():
        raise CorpusMissing(f"{chunks_path} is not on disk. Page text was not checked.")
    pages: dict[tuple[str, int], str] = {}
    text = chunks_path.read_text(encoding="utf-8")
    for line_number, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip():
            continue
        doc_id, page, page_text = _chunk_fields(raw, line_number)
        if not page_text.strip():
            continue
        if doc_id not in inventory.ingest_ids:
            continue
        key = (doc_id, page)
        if key in pages:
            raise GateError(f"duplicate page {doc_id} {page}")
        pages[key] = page_text
    return LoadedCorpus(inventory=inventory, pages=MappingProxyType(pages))


def screen_questions(
    questions: Sequence[GoldenQuestion], inventory: Inventory
) -> ScreenResult:
    kept: list[GoldenQuestion] = []
    rejected: list[RowRejection] = []
    for question in questions:
        reason = _first_screen_reason(question, inventory)
        if reason is None:
            kept.append(question)
        else:
            rejected.append(RowRejection(question.id, reason))
    admitted = tuple(kept)
    return ScreenResult(
        kept=admitted,
        rejected=tuple(rejected),
        quotas=_assess_quotas(admitted),
    )


def gate_golden(
    questions: Sequence[GoldenQuestion], corpus: LoadedCorpus
) -> GateResult:
    screen = screen_questions(questions, corpus.inventory)
    kept: list[GoldenQuestion] = []
    rejected = list(screen.rejected)
    for question in screen.kept:
        reason = _first_text_reason(question, corpus)
        if reason is None:
            kept.append(question)
        else:
            rejected.append(RowRejection(question.id, reason))
    admitted = tuple(kept)
    return GateResult(
        kept=admitted,
        rejected=tuple(rejected),
        quotas=_assess_quotas(admitted),
    )


def commit_golden(
    path: Path,
    questions: Sequence[GoldenQuestion],
    corpus: LoadedCorpus,
) -> GateResult:
    result = gate_golden(questions, corpus)
    if result.rejected or not result.quotas.ok:
        raise GateError("golden gate refused the write", result)
    payload = render_golden(result.kept)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(payload, encoding="utf-8", newline="\n")
    os.replace(temporary, path)
    return result


def render_golden(questions: Sequence[GoldenQuestion]) -> str:
    if not questions:
        return ""
    lines: list[str] = []
    for question in questions:
        payload: dict[str, object] = {
            "id": question.id,
            "question": question.question,
            "answerable": question.answerable,
            "expected": [
                {"doc_id": page.doc_id, "page": page.page} for page in question.expected
            ],
        }
        if isinstance(question.part_id, str):
            payload["part_id"] = question.part_id
        if question.ci:
            payload["ci"] = True
        lines.append(json.dumps(payload, ensure_ascii=True))
    return "\n".join(lines) + "\n"


def format_report(result: GateResult) -> str:
    lines = [f"{row.question_id} {row.reason.value}" for row in result.rejected]
    quotas = result.quotas
    lines.append(
        f"kept {len(result.kept)} answerable {quotas.answerable} "
        f"unanswerable_spec {quotas.unanswerable_spec} part_rows {quotas.part_rows}"
    )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Admit golden rows whose cited page text supports them."
    )
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--chunks", type=Path, default=_DEFAULT_CHUNKS)
    parser.add_argument("--golden", type=Path, default=_DEFAULT_GOLDEN)
    parser.add_argument(
        "--write",
        action="store_true",
        help="Replace the golden file when every row is admitted.",
    )
    args = parser.parse_args(argv)
    try:
        inventory = load_inventory(args.manifest)
        corpus = load_corpus(args.chunks, inventory)
        questions = load_golden(args.golden)
    except CorpusMissing as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except (GateError, GoldenSetError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    result = gate_golden(questions, corpus)
    sys.stdout.write(format_report(result))
    if result.rejected or not result.quotas.ok:
        return 1
    if args.write:
        try:
            commit_golden(args.golden, questions, corpus)
        except GateError as exc:
            print(str(exc), file=sys.stderr)
            return 1
    return 0


def _chunk_fields(raw: str, line_number: int) -> tuple[str, int, str]:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GateError(f"invalid JSONL on line {line_number}") from exc
    if not isinstance(payload, dict):
        raise GateError(f"JSONL line {line_number} is not an object")
    try:
        doc_id = payload["doc_id"]
        page = payload["page"]
        page_text = payload["text"]
    except KeyError as exc:
        raise GateError(f"JSONL line {line_number} missing {exc.args[0]}") from exc
    if not isinstance(doc_id, str) or not isinstance(page_text, str):
        raise GateError(f"JSONL line {line_number} has the wrong types")
    if isinstance(page, bool) or not isinstance(page, int):
        raise GateError(f"JSONL line {line_number} page must be an integer")
    if page < 1:
        raise GateError(f"JSONL line {line_number} page must be >= 1")
    return doc_id, page, page_text


def _first_screen_reason(
    question: GoldenQuestion, inventory: Inventory
) -> RejectReason | None:
    if _spec_stored_in_question(question.question):
        return RejectReason.SPEC_IN_QUESTION
    if question.part_id is not None and question.part_id not in PROVISIONAL_PART_IDS:
        return RejectReason.PART_ID_UNKNOWN
    if not question.answerable and question.expected:
        return RejectReason.UNANSWERABLE_HAS_PAGES
    if not question.answerable:
        return None
    for page in question.expected:
        count = inventory.page_counts.get(page.doc_id)
        if page.doc_id not in inventory.ingest_ids or count is None:
            return RejectReason.DOC_NOT_INGEST
        if page.page < 1 or page.page > count:
            return RejectReason.PAGE_OUT_OF_RANGE
    return None


def _first_text_reason(
    question: GoldenQuestion, corpus: LoadedCorpus
) -> RejectReason | None:
    if not question.answerable:
        return None
    texts: list[str] = []
    for page in question.expected:
        key = (page.doc_id, page.page)
        page_text = corpus.pages.get(key)
        if page_text is None:
            return RejectReason.PAGE_NOT_IN_CORPUS
        texts.append(page_text)
    if not _topic_supported(question.question, texts):
        return RejectReason.TOPIC_NOT_IN_TEXT
    if _asks_for_spec(question.question) and not any(
        _has_spec_shape(text) for text in texts
    ):
        return RejectReason.SPEC_SHAPE_MISSING
    return None


def _asks_for_spec(question: str) -> bool:
    tokens = _words(question)
    if any(token in _SPEC_WORDS for token in tokens):
        return True
    return any(
        (tokens[index], tokens[index + 1]) in _SPEC_PHRASES
        for index in range(len(tokens) - 1)
    )


def _spec_stored_in_question(question: str) -> bool:
    if _has_spec_shape(question):
        return True
    if _PIN_NUMBER_RE.search(question) is not None:
        return True
    if _LONG_DIGIT_RE.search(question) is not None:
        return True
    if _PART_NUMBER_RE.search(question) is not None:
        return True
    tokens = _words(question)
    return "wire" in tokens and any(token in _COLORS for token in tokens)


def _assess_quotas(questions: Sequence[GoldenQuestion]) -> QuotaVerdict:
    total = len(questions)
    answerable = 0
    unanswerable_spec = 0
    part_rows = 0
    for question in questions:
        if question.answerable:
            answerable += 1
        elif _asks_for_spec(question.question):
            unanswerable_spec += 1
        if question.part_id is not None:
            part_rows += 1
    reasons: list[str] = []
    if total < TOTAL_MIN or total > TOTAL_MAX:
        reasons.append(f"total {total} outside {TOTAL_MIN}..{TOTAL_MAX}")
    if answerable < ANSWERABLE_MIN:
        reasons.append(f"answerable {answerable} below {ANSWERABLE_MIN}")
    if unanswerable_spec < UNANSWERABLE_SPEC_MIN:
        reasons.append(
            f"unanswerable_spec {unanswerable_spec} below {UNANSWERABLE_SPEC_MIN}"
        )
    if part_rows < PART_ID_MIN:
        reasons.append(f"part_rows {part_rows} below {PART_ID_MIN}")
    return QuotaVerdict(
        total=total,
        answerable=answerable,
        unanswerable_spec=unanswerable_spec,
        part_rows=part_rows,
        ok=not reasons,
        reasons=tuple(reasons),
    )


def _words(text: str) -> tuple[str, ...]:
    return tuple(_WORD_RE.findall(text.casefold()))


def _subject_tokens(question: str) -> frozenset[str]:
    return frozenset(
        token for token in _words(question) if len(token) >= 3 and token not in _STOP
    )


def _topic_supported(question: str, page_texts: Sequence[str]) -> bool:
    subjects = _subject_tokens(question)
    if len(subjects) < 2:
        return False
    hits = [set(_words(text)) & subjects for text in page_texts]
    if any(not page_hits for page_hits in hits):
        return False
    union: set[str] = set()
    for page_hits in hits:
        union.update(page_hits)
    return len(union) >= 2


def _has_spec_shape(text: str) -> bool:
    return (
        _FAKE_SPEC_RE.search(text) is not None
        or _NUMBER_UNIT_RE.search(text) is not None
        or _CELSIUS_RE.search(text) is not None
    )


if __name__ == "__main__":
    sys.exit(main())
