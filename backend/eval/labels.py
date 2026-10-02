"""Held-out hand labels for highlight region IoU.

``eval/hand_labels.json`` is the real file, once labeled photos exist.
Until that file is present, scoring uses the synthetic fixture. The same
rule selects ``eval/bay_map.json`` over the fake bay-map fixture. Part
ids in the fixture are ``fake-*``. This file stores no manual pages.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from bay_map import BAY_MAP_FIXTURE_PATH, BayMap
from eval.iou import region_iou

EVAL_DIR = Path(__file__).resolve().parent
REAL_HAND_LABELS_PATH = EVAL_DIR / "hand_labels.json"
REAL_BAY_MAP_PATH = EVAL_DIR / "bay_map.json"
FIXTURE_HAND_LABELS_PATH = EVAL_DIR / "fixtures" / "fake-hand-labels.json"


class HandLabelError(ValueError):
    """The hand-label file is missing or does not match the fixture shape."""


@dataclass(frozen=True)
class HandLabel:
    part_id: str
    bay_photo_id: str
    polygons: tuple[tuple[tuple[float, float], ...], ...]


def resolve_hand_labels_path(
    explicit: Path | None = None,
    *,
    root: Path | None = None,
) -> Path:
    """Real labels win when the file exists. Otherwise the synthetic fixture."""

    if explicit is not None:
        return explicit
    real = REAL_HAND_LABELS_PATH if root is None else root / REAL_HAND_LABELS_PATH.name
    if real.is_file():
        return real
    return FIXTURE_HAND_LABELS_PATH


def resolve_bay_map_path(
    explicit: Path | None = None,
    *,
    root: Path | None = None,
) -> Path:
    """A real bay map at ``eval/bay_map.json`` wins. Otherwise the fake fixture."""

    if explicit is not None:
        return explicit
    real = REAL_BAY_MAP_PATH if root is None else root / REAL_BAY_MAP_PATH.name
    if real.is_file():
        return real
    return BAY_MAP_FIXTURE_PATH


def load_hand_labels(path: Path) -> tuple[HandLabel, ...]:
    if not path.is_file():
        raise HandLabelError(f"hand labels not found: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise HandLabelError(f"{path} is not JSON") from exc
    if not isinstance(payload, dict):
        raise HandLabelError(f"{path} is not an object")
    if payload.get("schema_version") != 1:
        raise HandLabelError(f"{path} schema_version must be 1")
    rows = payload.get("labels")
    if not isinstance(rows, list):
        raise HandLabelError(f"{path} labels must be an array")
    if set(payload) != {"schema_version", "labels"}:
        raise HandLabelError(f"{path} has unknown keys")
    labels: list[HandLabel] = []
    seen: set[tuple[str, str]] = set()
    for index, row in enumerate(rows):
        label = _label(row, index)
        key = (label.bay_photo_id, label.part_id)
        if key in seen:
            raise HandLabelError(
                f"duplicate label for {label.bay_photo_id} {label.part_id}"
            )
        seen.add(key)
        labels.append(label)
    return tuple(labels)


def mean_rendered_iou(bay_map: BayMap, labels: Sequence[HandLabel]) -> float | None:
    """Mean IoU of each label against the confirmed region the renderer draws.

    A label whose photo and part do not resolve is left out. ``None`` means
    no label resolved to a confirmed region.
    """

    scores: list[float] = []
    for label in labels:
        rendered = rendered_polygons(bay_map, label.bay_photo_id, label.part_id)
        if rendered is None:
            continue
        scores.append(region_iou(rendered, label.polygons))
    if not scores:
        return None
    return sum(scores) / len(scores)


def rendered_polygons(
    bay_map: BayMap,
    bay_photo_id: str,
    part_id: str,
) -> tuple[tuple[tuple[float, float], ...], ...] | None:
    """Confirmed rings for this pair, in normalized bay-map coordinates.

    ``None`` when the pair is missing or unconfirmed. Those rings are the
    polygon the highlight renderer strokes, saturates, circles, or dims.
    """

    found = bay_map.resolve(bay_photo_id, part_id)
    if found is None:
        return None
    return tuple(
        tuple((point.x, point.y) for point in polygon.points)
        for polygon in found.polygons
    )


def _label(row: object, index: int) -> HandLabel:
    if not isinstance(row, dict):
        raise HandLabelError(f"label {index} is not an object")
    if set(row) != {"part_id", "bay_photo_id", "polygons"}:
        raise HandLabelError(f"label {index} has unknown keys")
    part_id = _id(row.get("part_id"), f"label {index} part_id")
    bay_photo_id = _id(row.get("bay_photo_id"), f"label {index} bay_photo_id")
    polygons = row.get("polygons")
    if not isinstance(polygons, list) or not polygons:
        raise HandLabelError(f"label {index} needs at least one polygon")
    rings = tuple(
        _polygon(polygon, index, poly_index)
        for poly_index, polygon in enumerate(polygons)
    )
    return HandLabel(part_id=part_id, bay_photo_id=bay_photo_id, polygons=rings)


def _polygon(
    polygon: object,
    label_index: int,
    poly_index: int,
) -> tuple[tuple[float, float], ...]:
    where = f"label {label_index} polygon {poly_index}"
    if not isinstance(polygon, dict) or set(polygon) != {"points"}:
        raise HandLabelError(f"{where} must be an object with points")
    points = polygon.get("points")
    if not isinstance(points, list) or len(points) < 3:
        raise HandLabelError(f"{where} needs at least 3 points")
    parsed: list[tuple[float, float]] = []
    for point_index, point in enumerate(points):
        if not isinstance(point, dict) or set(point) != {"x", "y"}:
            raise HandLabelError(f"{where} point {point_index} must be x and y")
        parsed.append(
            (
                _coordinate(point.get("x"), f"{where} point {point_index} x"),
                _coordinate(point.get("y"), f"{where} point {point_index} y"),
            )
        )
    return tuple(parsed)


def _id(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise HandLabelError(f"{label} must be a non-empty string")
    return value


def _coordinate(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise HandLabelError(f"{label} must be a number")
    return float(value)
