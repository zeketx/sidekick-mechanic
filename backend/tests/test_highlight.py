"""Golden-image tests for the highlight renderer.

The photo is synthetic. Polygons are plain pixel coordinates. No bay-map
ids, part numbers, or manual pages.
"""

from __future__ import annotations

import time
from pathlib import Path

import pytest
from PIL import Image, ImageDraw

from highlight import (
    GOLDEN_PIXEL_TOLERANCE,
    HighlightConfig,
    HighlightStyle,
    render_highlight,
)

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "highlight"
POLYGON = ((30, 20), (90, 20), (90, 60), (30, 60))
INSIDE = (60, 40)
OUTSIDE = (0, 0)
OUTLINE_PIXEL = (60, 20)
CIRCLE_PIXEL = (104, 40)
SOURCE_INSIDE = (160, 90, 70)
SOURCE_OUTSIDE = (40, 50, 60)
FUCHSIA = (255, 0, 255)


def synthetic_photo() -> Image.Image:
    photo = Image.new("RGB", (120, 80), SOURCE_OUTSIDE)
    draw = ImageDraw.Draw(photo)
    draw.rectangle((60, 0, 119, 79), fill=(70, 110, 90))
    draw.rectangle((36, 26, 84, 54), fill=SOURCE_INSIDE)
    return photo


def max_channel_delta(actual: Image.Image, expected: Image.Image) -> int:
    if actual.mode != expected.mode or actual.size != expected.size:
        raise AssertionError(
            f"{actual.mode} {actual.size} vs {expected.mode} {expected.size}"
        )
    pairs = zip(actual.tobytes(), expected.tobytes(), strict=True)
    return max(abs(left - right) for left, right in pairs)


def write_goldens() -> None:
    """Rewrite the committed goldens from ``synthetic_photo`` and the default config."""
    photo = synthetic_photo()
    FIXTURES.mkdir(parents=True, exist_ok=True)
    for style in HighlightStyle:
        rendered = render_highlight(photo, POLYGON, style)
        rendered.save(FIXTURES / f"{style.value}.png")


def test_default_config_is_the_bakeoff_winner() -> None:
    config = HighlightConfig()
    assert config.outline_rgb == FUCHSIA
    assert config.outline_width_px == 8
    assert config.saturation_factor == 3.0
    assert config.dim_factor == 1.0
    assert config.circle_rgb == FUCHSIA
    assert config.circle_width_px == 4
    assert config.circle_padding_px == 8


def test_pixel_tolerance_rejects_a_three_level_change() -> None:
    base = Image.new("RGB", (2, 2), (10, 20, 30))
    shifted = base.copy()
    shifted.putpixel((1, 1), (10, 20, 33))
    assert max_channel_delta(base, shifted) == 3
    assert GOLDEN_PIXEL_TOLERANCE == 2
    assert max_channel_delta(base, shifted) > GOLDEN_PIXEL_TOLERANCE


@pytest.mark.parametrize("style", list(HighlightStyle))
def test_style_matches_golden_within_pixel_tolerance(style: HighlightStyle) -> None:
    actual = render_highlight(synthetic_photo(), POLYGON, style)
    with Image.open(FIXTURES / f"{style.value}.png") as expected:
        delta = max_channel_delta(actual, expected)
    assert delta <= GOLDEN_PIXEL_TOLERANCE


def test_outline_strokes_the_boundary_and_leaves_the_interior() -> None:
    photo = synthetic_photo()
    rendered = render_highlight(photo, POLYGON, HighlightStyle.OUTLINE)
    assert rendered.mode == "RGB"
    assert rendered.size == photo.size
    assert rendered.getpixel(OUTLINE_PIXEL) == FUCHSIA
    assert rendered.getpixel(INSIDE) == SOURCE_INSIDE
    assert rendered.getpixel(OUTSIDE) == SOURCE_OUTSIDE


def test_saturate_boosts_inside_and_leaves_outside() -> None:
    rendered = render_highlight(synthetic_photo(), POLYGON, HighlightStyle.SATURATE)
    assert rendered.getpixel(INSIDE) == (255, 52, 0)
    assert rendered.getpixel(OUTSIDE) == SOURCE_OUTSIDE


def test_circle_marks_the_ring_and_leaves_center_and_corner() -> None:
    rendered = render_highlight(synthetic_photo(), POLYGON, HighlightStyle.CIRCLE)
    assert rendered.getpixel(CIRCLE_PIXEL) == FUCHSIA
    assert rendered.getpixel(INSIDE) == SOURCE_INSIDE
    assert rendered.getpixel(OUTSIDE) == SOURCE_OUTSIDE


def test_dim_default_leaves_the_photo_and_a_lower_factor_darkens() -> None:
    photo = synthetic_photo()
    rendered = render_highlight(photo, POLYGON, HighlightStyle.DIM)
    assert rendered.getpixel(OUTSIDE) == SOURCE_OUTSIDE
    assert rendered.getpixel(INSIDE) == SOURCE_INSIDE
    dimmed = render_highlight(
        photo, POLYGON, HighlightStyle.DIM, HighlightConfig(dim_factor=0.4)
    )
    assert dimmed.getpixel(OUTSIDE) == (16, 20, 24)
    assert dimmed.getpixel(INSIDE) == SOURCE_INSIDE


def test_config_supplies_colors_and_factors() -> None:
    photo = synthetic_photo()
    outlined = render_highlight(
        photo,
        POLYGON,
        HighlightStyle.OUTLINE,
        HighlightConfig(outline_rgb=(1, 2, 3)),
    )
    circled = render_highlight(
        photo,
        POLYGON,
        HighlightStyle.CIRCLE,
        HighlightConfig(circle_rgb=(9, 8, 7)),
    )
    dimmed = render_highlight(
        photo,
        POLYGON,
        HighlightStyle.DIM,
        HighlightConfig(dim_factor=0.0),
    )
    gray = render_highlight(
        photo,
        POLYGON,
        HighlightStyle.SATURATE,
        HighlightConfig(saturation_factor=0.0),
    )
    assert outlined.getpixel(OUTLINE_PIXEL) == (1, 2, 3)
    assert circled.getpixel(CIRCLE_PIXEL) == (9, 8, 7)
    assert dimmed.getpixel(OUTSIDE) == (0, 0, 0)
    assert dimmed.getpixel(INSIDE) == SOURCE_INSIDE
    inside = gray.getpixel(INSIDE)
    assert inside[0] == inside[1] == inside[2]
    assert gray.getpixel(OUTSIDE) == SOURCE_OUTSIDE


def test_identity_factors_match_the_source_bytes() -> None:
    photo = synthetic_photo()
    dimmed = render_highlight(
        photo, POLYGON, HighlightStyle.DIM, HighlightConfig(dim_factor=1.0)
    )
    saturated = render_highlight(
        photo,
        POLYGON,
        HighlightStyle.SATURATE,
        HighlightConfig(saturation_factor=1.0),
    )
    assert dimmed.tobytes() == photo.tobytes()
    assert saturated.tobytes() == photo.tobytes()
    assert dimmed is not photo


def test_render_does_not_mutate_the_photo() -> None:
    photo = synthetic_photo()
    before = photo.tobytes()
    render_highlight(photo, POLYGON, HighlightStyle.OUTLINE)
    render_highlight(photo, POLYGON, HighlightStyle.SATURATE)
    render_highlight(photo, POLYGON, HighlightStyle.CIRCLE)
    render_highlight(photo, POLYGON, HighlightStyle.DIM)
    assert photo.tobytes() == before


def test_rgba_photo_renders_rgb() -> None:
    photo = synthetic_photo().convert("RGBA")
    rendered = render_highlight(photo, POLYGON, HighlightStyle.OUTLINE)
    assert rendered.mode == "RGB"
    assert rendered.getpixel(OUTLINE_PIXEL) == FUCHSIA
    assert photo.mode == "RGBA"


def test_polygon_lists_and_whole_floats_match_int_tuples() -> None:
    photo = synthetic_photo()
    listed = render_highlight(
        photo,
        [[30, 20], [90, 20], [90, 60], [30, 60]],
        HighlightStyle.OUTLINE,
    )
    floated = render_highlight(
        photo,
        [(30.0, 20.0), (90.0, 20.0), (90.0, 60.0), (30.0, 60.0)],
        HighlightStyle.OUTLINE,
    )
    expected = render_highlight(photo, POLYGON, HighlightStyle.OUTLINE)
    assert listed.tobytes() == expected.tobytes()
    assert floated.tobytes() == expected.tobytes()


def test_circle_padding_moves_the_ring() -> None:
    photo = synthetic_photo()
    tight = render_highlight(
        photo,
        POLYGON,
        HighlightStyle.CIRCLE,
        HighlightConfig(circle_padding_px=0, circle_rgb=(9, 8, 7)),
    )
    # (25, 36) is on the zero-padding ring. (104, 40) is on the default ring.
    assert tight.getpixel((25, 36)) == (9, 8, 7)
    assert tight.getpixel(CIRCLE_PIXEL) == (70, 110, 90)


@pytest.mark.parametrize(
    ("polygon", "match"),
    [
        ([(0, 0), (1, 1)], "at least 3"),
        ([(0, 0), (1, 1), (2, float("nan"))], "finite"),
        ("abc", "sequence of points"),
        ([(0, 0, 0), (1, 1, 1), (2, 2, 2)], "pair"),
    ],
)
def test_polygon_rejects_bad_input(polygon: object, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        render_highlight(synthetic_photo(), polygon, HighlightStyle.OUTLINE)  # type: ignore[arg-type]


def test_style_and_photo_are_validated() -> None:
    photo = synthetic_photo()
    with pytest.raises(ValueError, match="HighlightStyle"):
        render_highlight(photo, POLYGON, "outline")  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="RGB or RGBA"):
        render_highlight(photo.convert("L"), POLYGON, HighlightStyle.DIM)
    with pytest.raises(ValueError, match="HighlightConfig"):
        render_highlight(photo, POLYGON, HighlightStyle.DIM, config="nope")  # type: ignore[arg-type]


@pytest.mark.parametrize(
    ("kwargs", "match"),
    [
        ({"outline_width_px": 0}, "outline_width_px"),
        ({"outline_rgb": (256, 0, 0)}, "outline_rgb"),
        ({"outline_rgb": (1, 2)}, "outline_rgb"),
        ({"circle_width_px": False}, "circle_width_px"),
        ({"circle_padding_px": -1}, "circle_padding_px"),
        ({"dim_factor": -0.1}, "dim_factor"),
        ({"dim_factor": 1.1}, "dim_factor"),
        ({"saturation_factor": -1}, "saturation_factor"),
        ({"saturation_factor": float("nan")}, "saturation_factor"),
    ],
)
def test_config_rejects_bad_parameters(kwargs: dict[str, object], match: str) -> None:
    with pytest.raises(ValueError, match=match):
        HighlightConfig(**kwargs)  # type: ignore[arg-type]


def test_twelve_megapixel_render_stays_under_one_second() -> None:
    size = (4000, 3000)
    assert size[0] * size[1] == 12_000_000
    photo = Image.new("RGB", size, (90, 110, 70))
    polygon = ((400, 300), (2800, 400), (3000, 2200), (500, 2400), (200, 800))
    for style in HighlightStyle:
        start = time.perf_counter()
        rendered = render_highlight(photo, polygon, style)
        elapsed = time.perf_counter() - start
        assert rendered.size == size
        assert rendered.mode == "RGB"
        assert elapsed < 1.0, f"{style.value} took {elapsed:.3f}s"
