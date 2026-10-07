"""Reference highlight renderer for one bay photo.

``render_highlight(photo, polygon, style)`` returns a new RGB image.
The polygon is ``(x, y)`` photo pixels, origin at the top left.
``HighlightConfig`` holds the parameters for every style:

- ``outline`` strokes the polygon
- ``saturate`` raises color inside the polygon
- ``circle`` strokes a circle around the polygon
- ``dim`` darkens every pixel outside the polygon

Callers pass the polygon. Region storage belongs to the bay map schema
(#26). Golden tests use a synthetic image, not the prototype bay photos.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum

from PIL import Image, ImageDraw, ImageEnhance

# Max |channel| difference when a render is compared to a golden image.
# Goldens produced by this module match at 0 on Pillow 11.1.0. The slack
# is the agreement budget for a later port of the same styles.
GOLDEN_PIXEL_TOLERANCE = 2


class HighlightStyle(Enum):
    OUTLINE = "outline"
    SATURATE = "saturate"
    CIRCLE = "circle"
    DIM = "dim"


@dataclass(frozen=True, slots=True)
class HighlightConfig:
    """Parameters for outline, saturate, circle, and dim."""

    # Bakeoff winner: fuchsia outline, strong interior saturation, no dim.
    # The circle style is not part of that treatment. Its ink matches the
    # outline so a caller who asks for a circle does not get a second color.
    outline_rgb: tuple[int, int, int] = (255, 0, 255)
    outline_width_px: int = 8
    saturation_factor: float = 3.0
    circle_rgb: tuple[int, int, int] = (255, 0, 255)
    circle_width_px: int = 4
    circle_padding_px: int = 8
    dim_factor: float = 1.0

    def __post_init__(self) -> None:
        _require_rgb(self.outline_rgb, "outline_rgb")
        _require_rgb(self.circle_rgb, "circle_rgb")
        _require_px(self.outline_width_px, "outline_width_px", minimum=1)
        _require_px(self.circle_width_px, "circle_width_px", minimum=1)
        _require_px(self.circle_padding_px, "circle_padding_px", minimum=0)
        object.__setattr__(
            self,
            "saturation_factor",
            _require_factor(
                self.saturation_factor,
                "saturation_factor",
                low=0.0,
                high=None,
            ),
        )
        object.__setattr__(
            self,
            "dim_factor",
            _require_factor(self.dim_factor, "dim_factor", low=0.0, high=1.0),
        )


def render_highlight(
    photo: Image.Image,
    polygon: Sequence[Sequence[float]],
    style: HighlightStyle,
    config: HighlightConfig | None = None,
) -> Image.Image:
    """Return a new RGB image with ``style`` applied to ``polygon``."""
    rgb = _require_photo(photo)
    points = _require_polygon(polygon)
    if not isinstance(style, HighlightStyle):
        raise ValueError("style must be a HighlightStyle")
    chosen = HighlightConfig() if config is None else config
    if not isinstance(chosen, HighlightConfig):
        raise ValueError("config must be a HighlightConfig")

    if style is HighlightStyle.OUTLINE:
        return _stroke_polygon(
            rgb, points, chosen.outline_rgb, chosen.outline_width_px
        )
    if style is HighlightStyle.SATURATE:
        boosted = ImageEnhance.Color(rgb).enhance(chosen.saturation_factor)
        return _composite_inside(rgb, points, boosted)
    if style is HighlightStyle.CIRCLE:
        return _stroke_ellipse(
            rgb,
            _circle_box(points, chosen.circle_padding_px),
            chosen.circle_rgb,
            chosen.circle_width_px,
        )
    if style is HighlightStyle.DIM:
        darkened = ImageEnhance.Brightness(rgb).enhance(chosen.dim_factor)
        return _composite_outside(rgb, points, darkened)
    raise ValueError(f"unknown style: {style!r}")


def _stroke_polygon(
    photo: Image.Image,
    points: Sequence[tuple[float, float]],
    color: tuple[int, int, int],
    width: int,
) -> Image.Image:
    rendered = photo.copy()
    ImageDraw.Draw(rendered).polygon(points, outline=color, width=width)
    return rendered


def _stroke_ellipse(
    photo: Image.Image,
    box: tuple[float, float, float, float],
    color: tuple[int, int, int],
    width: int,
) -> Image.Image:
    rendered = photo.copy()
    ImageDraw.Draw(rendered).ellipse(box, outline=color, width=width)
    return rendered


def _composite_inside(
    photo: Image.Image,
    points: Sequence[tuple[float, float]],
    inside: Image.Image,
) -> Image.Image:
    return Image.composite(inside, photo, _polygon_mask(photo.size, points))


def _composite_outside(
    photo: Image.Image,
    points: Sequence[tuple[float, float]],
    outside: Image.Image,
) -> Image.Image:
    return Image.composite(photo, outside, _polygon_mask(photo.size, points))


def _polygon_mask(
    size: tuple[int, int],
    points: Sequence[tuple[float, float]],
) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def _circle_box(
    points: Sequence[tuple[float, float]],
    padding: int,
) -> tuple[float, float, float, float]:
    """Circle on the axis-aligned bounding-box center.

    Radius is half the bounding-box diagonal plus ``padding``. The vertex
    mean is the wrong center for an irregular polygon: it drifts toward
    dense edges and the ring looks oversized and off-center.
    """
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    cx = (min_x + max_x) / 2.0
    cy = (min_y + max_y) / 2.0
    radius = math.hypot((max_x - min_x) / 2.0, (max_y - min_y) / 2.0) + padding
    return (cx - radius, cy - radius, cx + radius, cy + radius)


def _require_photo(photo: Image.Image) -> Image.Image:
    if not isinstance(photo, Image.Image):
        raise ValueError("photo must be a PIL image")
    if photo.mode not in {"RGB", "RGBA"}:
        raise ValueError(f"photo mode must be RGB or RGBA, got {photo.mode}")
    if photo.width < 1 or photo.height < 1:
        raise ValueError("photo must have a positive size")
    if photo.mode == "RGBA":
        return photo.convert("RGB")
    return photo


def _require_polygon(
    polygon: Sequence[Sequence[float]],
) -> list[tuple[float, float]]:
    if isinstance(polygon, (str, bytes)) or not isinstance(polygon, Sequence):
        raise ValueError("polygon must be a sequence of points")
    if len(polygon) < 3:
        raise ValueError("polygon needs at least 3 points")
    points: list[tuple[float, float]] = []
    for index, point in enumerate(polygon):
        if (
            isinstance(point, (str, bytes))
            or not isinstance(point, Sequence)
            or len(point) != 2
        ):
            raise ValueError(f"point {index} must be an (x, y) pair")
        x, y = point
        if (
            isinstance(x, bool)
            or isinstance(y, bool)
            or not isinstance(x, (int, float))
            or not isinstance(y, (int, float))
            or not math.isfinite(x)
            or not math.isfinite(y)
        ):
            raise ValueError(f"point {index} coordinates must be finite numbers")
        points.append((float(x), float(y)))
    return points


def _require_rgb(value: object, name: str) -> None:
    if not isinstance(value, tuple) or len(value) != 3:
        raise ValueError(f"{name} must be an RGB tuple")
    for channel in value:
        if isinstance(channel, bool) or not isinstance(channel, int):
            raise ValueError(f"{name} channels must be ints from 0 to 255")
        if channel < 0 or channel > 255:
            raise ValueError(f"{name} channels must be ints from 0 to 255")


def _require_px(value: object, name: str, *, minimum: int) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f"{name} must be an int >= {minimum}")


def _require_factor(
    value: object,
    name: str,
    *,
    low: float,
    high: float | None,
) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a number")
    number = float(value)
    out_of_range = number < low or (high is not None and number > high)
    if not math.isfinite(number) or out_of_range:
        if high is None:
            raise ValueError(f"{name} must be finite and >= {low}")
        raise ValueError(f"{name} must be finite and from {low} to {high}")
    return number
