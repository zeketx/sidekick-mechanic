"""Default highlight treatment, and a stand-in that can draw it.

Issue #29 (the Python highlight renderer) is not merged. ``apply_highlight``
is the local function this bakeoff needed: photo, polygon, style, image.
It is not that renderer. No golden-image suite, no 12 MP timing claim.
Issue #26 (bay map schema) is not merged either. Callers pass a polygon.
This module does not define photos, parts, or licenses.

Widths are phone pixels on a 390x260 scene. Ink colors are highlight chrome,
not wire colors. The five scenes are synthetic. The licensed manifest has
one bay photo, which is not enough for the five-photo comparison and is not
copied here.
"""

from __future__ import annotations

import colorsys
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from PIL import Image, ImageDraw

PHONE_SIZE = (390, 260)
SCENE_IDS = ("dark", "bright", "mid", "clutter", "small")
_DEFAULT_PATH = Path(__file__).resolve().parent / "data" / "highlight_style.json"


class HighlightStyleError(ValueError):
    """A style config is missing a field or is outside the bakeoff bounds."""


@dataclass(frozen=True)
class HighlightStyle:
    """Outline, saturate, dim, and an optional circle."""

    name: str
    outline_rgba: tuple[int, int, int, int]
    outline_width_px: int
    saturate: float
    dim: float
    circle_enabled: bool
    circle_rgba: tuple[int, int, int, int]
    circle_width_px: int
    circle_pad_px: int

    def to_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "outline_rgba": list(self.outline_rgba),
            "outline_width_px": self.outline_width_px,
            "saturate": self.saturate,
            "dim": self.dim,
            "circle_enabled": self.circle_enabled,
            "circle_rgba": list(self.circle_rgba),
            "circle_width_px": self.circle_width_px,
            "circle_pad_px": self.circle_pad_px,
        }


@dataclass(frozen=True)
class Scene:
    scene_id: str
    image: Image.Image
    polygon: tuple[tuple[int, int], ...]


def default_highlight_style() -> HighlightStyle:
    """The bakeoff winner, loaded from ``data/highlight_style.json``."""
    return load_style(_DEFAULT_PATH)


def load_style(path: Path) -> HighlightStyle:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise HighlightStyleError(f"missing style: {path}") from exc
    except json.JSONDecodeError as exc:
        raise HighlightStyleError(f"style is not JSON: {path}") from exc
    if not isinstance(payload, dict):
        raise HighlightStyleError("style must be a JSON object")
    return style_from_json(payload)


def style_from_json(payload: dict[str, Any]) -> HighlightStyle:
    expected = {
        "name",
        "outline_rgba",
        "outline_width_px",
        "saturate",
        "dim",
        "circle_enabled",
        "circle_rgba",
        "circle_width_px",
        "circle_pad_px",
    }
    if set(payload) != expected:
        missing = sorted(expected - set(payload))
        extra = sorted(set(payload) - expected)
        raise HighlightStyleError(f"style keys mismatch missing={missing} extra={extra}")
    name = payload["name"]
    if not isinstance(name, str) or not name or any(char.isspace() for char in name):
        raise HighlightStyleError("name must be a non-empty string without spaces")
    style = HighlightStyle(
        name=name,
        outline_rgba=_rgba(payload["outline_rgba"], "outline_rgba"),
        outline_width_px=_int_in(payload["outline_width_px"], "outline_width_px", 0, 12),
        saturate=_float_in(payload["saturate"], "saturate", 1.0, 3.0),
        dim=_float_in(payload["dim"], "dim", 0.2, 1.0),
        circle_enabled=_bool(payload["circle_enabled"], "circle_enabled"),
        circle_rgba=_rgba(payload["circle_rgba"], "circle_rgba"),
        circle_width_px=_int_in(payload["circle_width_px"], "circle_width_px", 0, 8),
        circle_pad_px=_int_in(payload["circle_pad_px"], "circle_pad_px", 0, 24),
    )
    visible = (
        style.outline_width_px > 0
        or style.saturate > 1.0
        or style.dim < 1.0
        or (style.circle_enabled and style.circle_width_px > 0)
    )
    if not visible:
        raise HighlightStyleError("style does not change the photo")
    return style


def apply_highlight(
    image: Image.Image,
    polygon: Sequence[tuple[int, int]],
    style: HighlightStyle,
) -> Image.Image:
    """Return a new RGB image with the part treated by ``style``."""
    if image.mode != "RGB":
        raise HighlightStyleError("image must be RGB")
    if image.size != PHONE_SIZE:
        raise HighlightStyleError(f"image must be {PHONE_SIZE[0]}x{PHONE_SIZE[1]}")
    points = tuple((int(x), int(y)) for x, y in polygon)
    if len(points) < 3:
        raise HighlightStyleError("polygon needs at least 3 points")
    _require_inside(image.size, points)

    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    composed = Image.composite(
        _saturate_image(image, style.saturate),
        _dim_image(image, style.dim),
        mask,
    ).convert("RGBA")

    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    if style.outline_width_px > 0:
        # Pillow's line leaves a gap where the polyline closes. A disk at
        # each vertex fills that joint without changing the style config.
        draw.line(
            points + (points[0],),
            fill=style.outline_rgba,
            width=style.outline_width_px,
            joint="curve",
        )
        radius = style.outline_width_px / 2
        for x, y in points:
            draw.ellipse(
                (x - radius, y - radius, x + radius, y + radius),
                fill=style.outline_rgba,
            )
    if style.circle_enabled and style.circle_width_px > 0:
        draw.ellipse(
            _circle_box(points, style.circle_pad_px),
            outline=style.circle_rgba,
            width=style.circle_width_px,
        )
    return Image.alpha_composite(composed, overlay).convert("RGB")


def bakeoff_scenes() -> tuple[Scene, ...]:
    """Five synthetic phone scenes. Not a real engine bay."""
    return (_dark(), _bright(), _mid(), _clutter(), _small())


def _rgba(value: object, label: str) -> tuple[int, int, int, int]:
    if not isinstance(value, list) or len(value) != 4:
        raise HighlightStyleError(f"{label} must be [r, g, b, a]")
    red, green, blue, alpha = (_int_in(item, label, 0, 255) for item in value)
    return (red, green, blue, alpha)


def _int_in(value: object, label: str, low: int, high: int) -> int:
    if type(value) is not int:
        raise HighlightStyleError(f"{label} must be an int")
    if value < low or value > high:
        raise HighlightStyleError(f"{label} must be in {low}..{high}")
    return value


def _float_in(value: object, label: str, low: float, high: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise HighlightStyleError(f"{label} must be a number")
    number = float(value)
    if number < low or number > high:
        raise HighlightStyleError(f"{label} must be in {low}..{high}")
    return number


def _bool(value: object, label: str) -> bool:
    if type(value) is not bool:
        raise HighlightStyleError(f"{label} must be a bool")
    return value


def _require_inside(size: tuple[int, int], points: Sequence[tuple[int, int]]) -> None:
    width, height = size
    for x, y in points:
        if x < 0 or y < 0 or x >= width or y >= height:
            raise HighlightStyleError(f"polygon point {(x, y)} is outside the image")


def _dim_image(image: Image.Image, factor: float) -> Image.Image:
    if factor == 1.0:
        return image.copy()
    return Image.eval(image, lambda channel: int(round(channel * factor)))


def _saturate_image(image: Image.Image, factor: float) -> Image.Image:
    if factor == 1.0:
        return image.copy()
    out = image.copy()
    pixels = out.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            red, green, blue = pixels[x, y]
            hue, sat, val = colorsys.rgb_to_hsv(red / 255.0, green / 255.0, blue / 255.0)
            sat = min(1.0, sat * factor)
            rr, gg, bb = colorsys.hsv_to_rgb(hue, sat, val)
            pixels[x, y] = (
                int(round(rr * 255)),
                int(round(gg * 255)),
                int(round(bb * 255)),
            )
    return out


def _circle_box(points: Sequence[tuple[int, int]], pad: int) -> tuple[float, float, float, float]:
    cx = sum(x for x, _ in points) / len(points)
    cy = sum(y for _, y in points) / len(points)
    radius = max(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 for x, y in points) + pad
    return (cx - radius, cy - radius, cx + radius, cy + radius)


def _canvas(color: tuple[int, int, int]) -> Image.Image:
    return Image.new("RGB", PHONE_SIZE, color)


def _dark() -> Scene:
    image = _canvas((16, 18, 22))
    draw = ImageDraw.Draw(image)
    draw.rectangle((16, 24, 150, 110), fill=(28, 32, 36))
    draw.rectangle((160, 30, 370, 100), fill=(24, 28, 30))
    draw.rectangle((20, 180, 180, 240), fill=(30, 28, 26))
    draw.polygon((220, 150, 360, 150, 360, 230, 220, 230), fill=(26, 30, 28))
    polygon = ((78, 112), (168, 104), (184, 168), (120, 196), (64, 160))
    draw.polygon(polygon, fill=(34, 48, 38))
    return Scene("dark", image, polygon)


def _bright() -> Scene:
    image = _canvas((236, 234, 228))
    draw = ImageDraw.Draw(image)
    draw.rectangle((12, 16, 180, 90), fill=(214, 216, 220))
    draw.rectangle((190, 20, 374, 96), fill=(226, 220, 206))
    draw.rectangle((16, 170, 140, 246), fill=(210, 214, 208))
    draw.polygon((160, 140, 370, 150, 360, 240, 170, 230), fill=(228, 226, 218))
    polygon = ((200, 48), (312, 56), (328, 128), (236, 146), (186, 96))
    draw.polygon(polygon, fill=(208, 204, 188))
    return Scene("bright", image, polygon)


def _mid() -> Scene:
    image = _canvas((88, 92, 96))
    draw = ImageDraw.Draw(image)
    draw.rectangle((18, 20, 120, 100), fill=(120, 96, 72))
    draw.rectangle((250, 18, 370, 110), fill=(70, 86, 104))
    draw.rectangle((20, 170, 160, 244), fill=(64, 70, 66))
    draw.ellipse((280, 160, 368, 240), fill=(104, 100, 92))
    polygon = ((140, 70), (230, 60), (248, 130), (176, 168), (118, 124))
    draw.polygon(polygon, fill=(92, 108, 78))
    return Scene("mid", image, polygon)


def _clutter() -> Scene:
    image = _canvas((62, 66, 70))
    draw = ImageDraw.Draw(image)
    blobs = (
        ((24, 24), (100, 90), (96, 104, 110)),
        ((120, 30), (196, 96), (98, 106, 112)),
        ((220, 20), (300, 92), (94, 102, 108)),
        ((310, 36), (374, 100), (100, 108, 114)),
        ((30, 120), (104, 190), (92, 100, 106)),
        ((230, 130), (310, 210), (97, 105, 111)),
        ((300, 150), (376, 230), (95, 103, 109)),
        ((40, 190), (130, 248), (99, 107, 113)),
    )
    for start, end, color in blobs:
        draw.ellipse((start[0], start[1], end[0], end[1]), fill=color)
    polygon = ((132, 124), (196, 118), (214, 176), (150, 198), (112, 164))
    draw.polygon(polygon, fill=(98, 106, 112))
    return Scene("clutter", image, polygon)


def _small() -> Scene:
    image = _canvas((48, 52, 56))
    draw = ImageDraw.Draw(image)
    draw.rectangle((16, 16, 200, 120), fill=(176, 174, 166))
    draw.rectangle((210, 20, 374, 110), fill=(150, 156, 160))
    draw.rectangle((16, 140, 180, 244), fill=(70, 74, 72))
    polygon = ((292, 168), (324, 164), (332, 190), (306, 202), (284, 186))
    draw.polygon(polygon, fill=(72, 78, 70))
    return Scene("small", image, polygon)
