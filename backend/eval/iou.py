"""Convex-polygon IoU in the bay map's normalized plane.

The highlight renderer draws these rings (scaled by the photo's pixel
size). IoU is continuous intersection over union, so the photo's pixel
size does not change it. Rings are convex and do not repeat the first
point. A clockwise ring is reversed before clipping.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

Point = tuple[float, float]
Polygon = tuple[Point, ...]

# Shared edges and collinear corners sit on this side of zero.
_EPS = 1e-12


class IouError(ValueError):
    """The ring is not a convex polygon this IoU can score."""


def polygon_iou(
    left: Sequence[Sequence[float]],
    right: Sequence[Sequence[float]],
) -> float:
    """Intersection over union of two convex rings. Disjoint rings score 0."""

    subject = _ring(left)
    clip = _ring(right)
    return _iou(_area(subject), _area(clip), _intersection_area(subject, clip))


def region_iou(
    left: Sequence[Sequence[Sequence[float]]],
    right: Sequence[Sequence[Sequence[float]]],
) -> float:
    """IoU of two unions of convex rings.

    Rings on one side must not overlap in their interiors. A shared edge
    is allowed. Overlap would make the summed areas larger than the union.
    """

    rendered = _rings(left)
    labeled = _rings(right)
    _require_disjoint(rendered)
    _require_disjoint(labeled)
    intersection = sum(
        _intersection_area(subject, clip) for subject in rendered for clip in labeled
    )
    return _iou(
        sum(_area(polygon) for polygon in rendered),
        sum(_area(polygon) for polygon in labeled),
        intersection,
    )


def _rings(polygons: Sequence[Sequence[Sequence[float]]]) -> tuple[Polygon, ...]:
    if len(polygons) < 1:
        raise IouError("region needs at least one polygon")
    return tuple(_ring(polygon) for polygon in polygons)


def _ring(points: Sequence[Sequence[float]]) -> Polygon:
    parsed: list[Point] = []
    for index, point in enumerate(points):
        if (
            isinstance(point, (str, bytes))
            or not isinstance(point, Sequence)
            or len(point) != 2
        ):
            raise IouError(f"point {index} must be an (x, y) pair")
        x, y = point
        if (
            isinstance(x, bool)
            or isinstance(y, bool)
            or not isinstance(x, (int, float))
            or not isinstance(y, (int, float))
            or not math.isfinite(float(x))
            or not math.isfinite(float(y))
        ):
            raise IouError(f"point {index} coordinates must be finite numbers")
        parsed.append((float(x), float(y)))
    if len(parsed) >= 2 and _same_point(parsed[0], parsed[-1]):
        parsed.pop()
    if len(parsed) < 3:
        raise IouError("polygon needs at least 3 points")
    if not _is_convex(parsed):
        raise IouError("polygon must be convex")
    if _signed_area(parsed) < 0:
        parsed.reverse()
    if _area(parsed) <= _EPS:
        raise IouError("polygon area must be positive")
    return tuple(parsed)


def _require_disjoint(polygons: Sequence[Polygon]) -> None:
    for index, polygon in enumerate(polygons):
        for other in polygons[index + 1 :]:
            if _intersection_area(polygon, other) > _EPS:
                raise IouError("polygons in one region overlap")


def _iou(left_area: float, right_area: float, intersection: float) -> float:
    union = left_area + right_area - intersection
    if union <= _EPS:
        return 0.0
    ratio = intersection / union
    if ratio < 0.0:
        return 0.0
    if ratio > 1.0:
        return 1.0
    return ratio


def _intersection_area(subject: Polygon, clip: Polygon) -> float:
    """Sutherland–Hodgman. ``clip`` is convex and counter-clockwise."""

    output = list(subject)
    for index, start in enumerate(clip):
        if not output:
            return 0.0
        end = clip[(index + 1) % len(clip)]
        incoming = output
        output = []
        previous = incoming[-1]
        for current in incoming:
            current_inside = _left_of(current, start, end)
            previous_inside = _left_of(previous, start, end)
            if current_inside:
                if not previous_inside:
                    output.append(_segment_hit(previous, current, start, end))
                output.append(current)
            elif previous_inside:
                output.append(_segment_hit(previous, current, start, end))
            previous = current
    if len(output) < 3:
        return 0.0
    area = _area(output)
    if area <= _EPS:
        return 0.0
    return area


def _left_of(point: Point, start: Point, end: Point) -> bool:
    # Inside a counter-clockwise clip is to the left of each directed edge.
    cross = (end[0] - start[0]) * (point[1] - start[1]) - (end[1] - start[1]) * (
        point[0] - start[0]
    )
    return cross >= -_EPS


def _segment_hit(p1: Point, p2: Point, start: Point, end: Point) -> Point:
    edge = (p2[0] - p1[0], p2[1] - p1[1])
    bound = (end[0] - start[0], end[1] - start[1])
    denom = edge[0] * bound[1] - edge[1] * bound[0]
    if abs(denom) <= _EPS:
        return p2
    offset = (start[0] - p1[0], start[1] - p1[1])
    t = (offset[0] * bound[1] - offset[1] * bound[0]) / denom
    return (p1[0] + t * edge[0], p1[1] + t * edge[1])


def _is_convex(points: Sequence[Point]) -> bool:
    signs: list[float] = []
    count = len(points)
    for index, start in enumerate(points):
        middle = points[(index + 1) % count]
        end = points[(index + 2) % count]
        cross = (middle[0] - start[0]) * (end[1] - middle[1]) - (
            middle[1] - start[1]
        ) * (end[0] - middle[0])
        if abs(cross) <= _EPS:
            continue
        signs.append(cross)
    if not signs:
        return False
    return all(value > 0 for value in signs) or all(value < 0 for value in signs)


def _signed_area(points: Sequence[Point]) -> float:
    total = 0.0
    for index, point in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        total += point[0] * nxt[1] - nxt[0] * point[1]
    return total / 2


def _area(points: Sequence[Point]) -> float:
    return abs(_signed_area(points))


def _same_point(left: Point, right: Point) -> bool:
    return abs(left[0] - right[0]) <= _EPS and abs(left[1] - right[1]) <= _EPS
