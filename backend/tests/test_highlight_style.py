"""Default highlight style on the five synthetic phone scenes."""

from __future__ import annotations

import pytest

from highlight_style import (
    HighlightStyleError,
    apply_highlight,
    bakeoff_scenes,
    default_highlight_style,
    style_from_json,
)

_INK = (255, 0, 255)


def test_default_style_is_the_bakeoff_winner() -> None:
    style = default_highlight_style()
    assert style.name == "fuchsia-trace"
    assert style.outline_rgba == (255, 0, 255, 255)
    assert style.outline_width_px == 8
    assert style.saturate == 3.0
    assert style.dim == 1.0
    assert style.circle_enabled is False
    assert style.circle_rgba == (0, 0, 0, 0)
    assert style.circle_width_px == 0
    assert style.circle_pad_px == 0


def test_default_outline_saturates_part_and_leaves_context() -> None:
    style = default_highlight_style()
    scenes = {scene.scene_id: scene for scene in bakeoff_scenes()}
    assert tuple(scenes) == ("dark", "bright", "mid", "clutter", "small")

    dark = apply_highlight(scenes["dark"].image, scenes["dark"].polygon, style)
    assert dark.getpixel((0, 0)) == (16, 18, 22)
    assert dark.getpixel((20, 30)) == (28, 32, 36)
    assert dark.getpixel((78, 112)) == _INK
    assert dark.getpixel((122, 148)) == (6, 48, 18)

    bright = apply_highlight(scenes["bright"].image, scenes["bright"].polygon, style)
    assert bright.getpixel((0, 0)) == (236, 234, 228)
    assert bright.getpixel((20, 30)) == (214, 216, 220)
    assert bright.getpixel((200, 48)) == _INK
    assert bright.getpixel((252, 94)) == (208, 196, 148)

    small = apply_highlight(scenes["small"].image, scenes["small"].polygon, style)
    assert small.getpixel((0, 0)) == (48, 52, 56)
    assert small.getpixel((292, 168)) == _INK
    assert small.getpixel((308, 182)) == (60, 78, 54)

    mid = apply_highlight(scenes["mid"].image, scenes["mid"].polygon, style)
    assert mid.getpixel((0, 0)) == (88, 92, 96)
    clutter = apply_highlight(scenes["clutter"].image, scenes["clutter"].polygon, style)
    assert clutter.getpixel((0, 0)) == (62, 66, 70)
    assert clutter.getpixel((132, 124)) == _INK


def test_style_rejects_extra_keys_and_a_blank_treatment() -> None:
    payload = default_highlight_style().to_json()
    payload["wire_color"] = "FAKE-RED"
    with pytest.raises(HighlightStyleError):
        style_from_json(payload)
    blank = default_highlight_style().to_json()
    blank["outline_width_px"] = 0
    blank["saturate"] = 1.0
    blank["dim"] = 1.0
    blank["circle_enabled"] = False
    with pytest.raises(HighlightStyleError):
        style_from_json(blank)
