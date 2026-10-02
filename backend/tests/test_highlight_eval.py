"""Highlight eval: polygon IoU and the unmapped-part counter.

Polygons and part ids are synthetic. Page 999 is a fixture page.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from bay_map import BAY_MAP_FIXTURE_PATH, load_bay_map
from eval.iou import IouError, polygon_iou, region_iou
from eval.labels import (
    FIXTURE_HAND_LABELS_PATH,
    HandLabel,
    load_hand_labels,
    mean_rendered_iou,
    rendered_polygons,
    resolve_bay_map_path,
    resolve_hand_labels_path,
)
from eval.metrics import (
    aggregate_metrics,
    count_unmapped_highlight,
    part_is_correct,
    score_case,
)

FAKE_PAGE = ("FAKE-DOC-2JZ", 999)
MAPPED = frozenset({"fake-part-intake"})
UNIT = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]


def test_polygon_iou_of_the_same_square_is_one() -> None:
    clockwise = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    closed = [*UNIT, (0.0, 0.0)]

    assert polygon_iou(UNIT, UNIT) == 1.0
    assert polygon_iou(UNIT, clockwise) == 1.0
    assert polygon_iou(closed, UNIT) == 1.0


def test_polygon_iou_of_disjoint_and_touching_squares_is_zero() -> None:
    beside = [(2.0, 0.0), (3.0, 0.0), (3.0, 1.0), (2.0, 1.0)]
    touching = [(1.0, 0.0), (2.0, 0.0), (2.0, 1.0), (1.0, 1.0)]

    assert polygon_iou(UNIT, beside) == 0.0
    assert polygon_iou(UNIT, touching) == 0.0


def test_polygon_iou_of_a_contained_half_is_one_half() -> None:
    bottom = [(0.0, 0.0), (1.0, 0.0), (1.0, 0.5), (0.0, 0.5)]

    assert polygon_iou(UNIT, bottom) == 0.5


def test_polygon_iou_of_a_contained_quarter_is_one_quarter() -> None:
    outer = [(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0)]
    inner = [(0.5, 0.5), (1.5, 0.5), (1.5, 1.5), (0.5, 1.5)]

    assert polygon_iou(outer, inner) == 0.25


def test_polygon_iou_of_a_side_overlap_is_one_third() -> None:
    left = [(0.0, 0.0), (2.0, 0.0), (2.0, 2.0), (0.0, 2.0)]
    right = [(1.0, 0.0), (3.0, 0.0), (3.0, 2.0), (1.0, 2.0)]

    assert polygon_iou(left, right) == pytest.approx(1 / 3)


def test_polygon_iou_rejects_a_concave_ring() -> None:
    concave = [(0.0, 0.0), (3.0, 0.0), (1.0, 1.0), (3.0, 2.0), (0.0, 2.0)]

    with pytest.raises(IouError, match="convex"):
        polygon_iou(UNIT, concave)


def test_region_iou_sums_disjoint_rings() -> None:
    left = UNIT
    right = [(2.0, 0.0), (3.0, 0.0), (3.0, 1.0), (2.0, 1.0)]

    assert region_iou([left, right], [left]) == 0.5


def test_region_iou_rejects_overlapping_rings() -> None:
    overlap = [(0.5, 0.0), (1.5, 0.0), (1.5, 1.0), (0.5, 1.0)]

    with pytest.raises(IouError, match="overlap"):
        region_iou([UNIT, overlap], [UNIT])


def test_front_intake_region_matches_itself() -> None:
    bay_map = load_bay_map(BAY_MAP_FIXTURE_PATH.read_bytes())
    rendered = rendered_polygons(bay_map, "fake-bay-photo-front", "fake-part-intake")

    assert rendered is not None
    assert len(rendered) == 2
    assert region_iou(rendered, rendered) == 1.0


def test_fixture_hand_label_covers_half_of_the_wide_intake() -> None:
    bay_map = load_bay_map(BAY_MAP_FIXTURE_PATH.read_bytes())
    labels = load_hand_labels(FIXTURE_HAND_LABELS_PATH)

    assert [(label.part_id, label.bay_photo_id) for label in labels] == [
        ("fake-part-intake", "fake-bay-photo-wide")
    ]
    assert mean_rendered_iou(bay_map, labels) == 0.5


def test_unconfirmed_label_is_left_out_of_region_iou() -> None:
    bay_map = load_bay_map(BAY_MAP_FIXTURE_PATH.read_bytes())
    labels = (
        *load_hand_labels(FIXTURE_HAND_LABELS_PATH),
        HandLabel(
            part_id="fake-part-hidden",
            bay_photo_id="fake-bay-photo-front",
            polygons=(((0.0, 0.0), (0.5, 0.0), (0.5, 0.5)),),
        ),
    )

    hidden = rendered_polygons(bay_map, "fake-bay-photo-front", "fake-part-hidden")
    assert hidden is None
    assert mean_rendered_iou(bay_map, labels) == 0.5
    assert mean_rendered_iou(bay_map, labels[1:]) is None


def test_real_label_and_bay_map_files_replace_the_fixtures(tmp_path: Path) -> None:
    bay_path = tmp_path / "bay_map.json"
    label_path = tmp_path / "hand_labels.json"
    bay_path.write_bytes(BAY_MAP_FIXTURE_PATH.read_bytes())
    label_path.write_text(
        FIXTURE_HAND_LABELS_PATH.read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    assert resolve_bay_map_path(root=tmp_path) == bay_path
    assert resolve_hand_labels_path(root=tmp_path) == label_path
    bay_map = load_bay_map(resolve_bay_map_path(root=tmp_path).read_bytes())
    labels = load_hand_labels(resolve_hand_labels_path(root=tmp_path))

    assert mean_rendered_iou(bay_map, labels) == 0.5


def test_missing_real_files_keep_the_synthetic_fixtures(tmp_path: Path) -> None:
    assert resolve_bay_map_path(root=tmp_path) == BAY_MAP_FIXTURE_PATH
    assert resolve_hand_labels_path(root=tmp_path) == FIXTURE_HAND_LABELS_PATH


def test_unmapped_highlight_count_ignores_a_missing_or_mapped_highlight() -> None:
    mapped = _confirmed_part_ids()
    highlighted = _answer()
    highlighted["highlight"] = {
        "bay_photo_id": "fake-bay-photo-wide",
        "part_id": "fake-part-intake",
    }

    assert "fake-part-hidden" not in mapped
    assert count_unmapped_highlight(_answer(), mapped) == 0
    assert count_unmapped_highlight(_refusal(), mapped) == 0
    assert count_unmapped_highlight(highlighted, mapped) == 0


def test_unmapped_highlight_count_counts_parts_outside_the_confirmed_map() -> None:
    mapped = _confirmed_part_ids()
    missing = _answer()
    missing["highlight"] = {
        "bay_photo_id": "fake-bay-photo-wide",
        "part_id": "fake-part-missing",
    }
    hidden = _answer()
    hidden["highlight"] = {
        "bay_photo_id": "fake-bay-photo-front",
        "part_id": "fake-part-hidden",
    }

    assert count_unmapped_highlight(missing, mapped) == 1
    assert count_unmapped_highlight(hidden, mapped) == 1
    assert count_unmapped_highlight({"highlight": {}}, mapped) == 1


def test_correct_part_rate_uses_only_questions_that_name_a_mapped_part() -> None:
    hit = score_case(
        question_id="fake-hit",
        answerable=True,
        expected=[FAKE_PAGE],
        part_id="fake-part-intake",
        answer=_highlighted("fake-part-intake"),
        latency_ms=10,
        retrieval=None,
        mapped_part_ids=MAPPED,
    )
    miss = score_case(
        question_id="fake-miss",
        answerable=True,
        expected=[FAKE_PAGE],
        part_id="fake-part-intake",
        answer=_answer(),
        latency_ms=10,
        retrieval=None,
        mapped_part_ids=MAPPED,
    )
    unnamed = score_case(
        question_id="fake-pages",
        answerable=True,
        expected=[FAKE_PAGE],
        part_id=None,
        answer=_answer(),
        latency_ms=10,
        retrieval=None,
        mapped_part_ids=MAPPED,
    )
    off_map = score_case(
        question_id="fake-hidden",
        answerable=False,
        expected=[],
        part_id="fake-part-hidden",
        answer=_highlighted("fake-part-hidden"),
        latency_ms=10,
        retrieval=None,
        mapped_part_ids=MAPPED,
    )

    metrics = aggregate_metrics([hit, miss, unnamed, off_map])

    assert part_is_correct("fake-part-intake", _highlighted("fake-part-intake"), MAPPED)
    assert hit.correct_part is True
    assert miss.correct_part is False
    assert unnamed.correct_part is None
    assert off_map.correct_part is None
    assert metrics.correct_part_rate == 0.5
    assert metrics.unmapped_highlight_count == 1


def _confirmed_part_ids() -> frozenset[str]:
    bay_map = load_bay_map(BAY_MAP_FIXTURE_PATH.read_bytes())
    return frozenset(choice.part_id for choice in bay_map.highlight_choices)


def _highlighted(part_id: str) -> dict[str, Any]:
    answer = _answer()
    answer["highlight"] = {
        "bay_photo_id": "fake-bay-photo-wide",
        "part_id": part_id,
    }
    return answer


def _answer() -> dict[str, Any]:
    return {
        "kind": "answer",
        "text": "Fixture reply with no numeric spec.",
        "citations": [],
    }


def _refusal() -> dict[str, Any]:
    return {
        "kind": "refusal",
        "text": "Not found in the fixture.",
        "reason": "not_found_in_manual",
    }
