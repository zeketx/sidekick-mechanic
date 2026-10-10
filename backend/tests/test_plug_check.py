from __future__ import annotations

import json
import re
from typing import Any

import pytest

from llm import FakeLLMClient, LLMError
from plug_check import (
    COLORS,
    SHAPES,
    VISION_INSTRUCTION,
    PlugDiffers,
    PlugField,
    PlugLook,
    PlugLooks,
    PlugMatch,
    PlugUnsure,
    UnsureReason,
    check_plug,
    decide_plug,
    render_verdict,
)

PAGE_TEXT = "FAKE-PLUG 2-pin connector. No real spec."
FAKE_PNG = b"\x89PNG\r\n\x1a\nFAKE-PAGE"
FAKE_JPEG = b"\xff\xd8\xffFAKE-PHOTO"

MATCH_PROSE = (
    "The outline, the number of pins, the color, and the writing look the same as "
    "the plug on this page. I can still be wrong. Hold them next to each other "
    "before you unplug anything."
)
RETAKE_PROSE = (
    "I can't tell if this plug matches the one on the page. Take another photo with "
    "the pins facing the camera and any writing in the light."
)
NO_PAGE_TEXT_PROSE = (
    "I can't tell if this plug matches the one on the page. This page has no printed "
    "words to check the photo against, so I will not call it a match."
)


def _look(**overrides: Any) -> dict[str, Any]:
    look: dict[str, Any] = {
        "shape": "rectangular",
        "pin_count": 2,
        "color": "black",
        "label": "FAKE-PLUG",
    }
    look.update(overrides)
    return look


def _looks(page: dict[str, Any] | None = None, photo: dict[str, Any] | None = None) -> PlugLooks:
    return PlugLooks(
        page=PlugLook(**(page or _look())),
        photo=PlugLook(**(photo or _look())),
    )


def _reply(page: dict[str, Any] | None = None, photo: dict[str, Any] | None = None) -> str:
    return json.dumps({"page": page or _look(), "photo": photo or _look()})


def _assert_no_digit(text: str) -> None:
    assert re.search(r"\d", text) is None, text


def test_agreeing_looks_with_label_and_printed_count_match() -> None:
    verdict = decide_plug(_looks(), PAGE_TEXT)

    assert verdict == PlugMatch(label_agreed=True)
    prose = render_verdict(verdict)
    assert prose == MATCH_PROSE
    _assert_no_digit(prose)
    assert "FAKE-PLUG" not in prose
    assert "black" not in prose


def test_agreeing_looks_with_empty_page_text_are_unsure() -> None:
    verdict = decide_plug(_looks(), "   ")

    assert verdict == PlugUnsure(UnsureReason.NO_PAGE_TEXT)
    prose = render_verdict(verdict)
    assert prose == NO_PAGE_TEXT_PROSE
    assert prose != MATCH_PROSE
    _assert_no_digit(prose)


def test_photo_pin_count_against_printed_count_differs_without_a_digit() -> None:
    verdict = decide_plug(_looks(photo=_look(pin_count=4)), PAGE_TEXT)

    assert verdict == PlugDiffers(frozenset({PlugField.PIN_COUNT}))
    prose = render_verdict(verdict)
    assert prose == (
        "The number of pins does not match the plug on this page. I would not call "
        "this the same plug. Look for another plug nearby, or take a closer photo "
        "straight at the pins."
    )
    _assert_no_digit(prose)


def test_a_reply_that_decides_instead_of_describing_is_unsure() -> None:
    verdict = check_plug(
        FAKE_JPEG,
        page_png=FAKE_PNG,
        page_text=PAGE_TEXT,
        vision=FakeLLMClient(text='{"match": true}'),
    )

    assert verdict == PlugUnsure(UnsureReason.MODEL_INVALID)
    assert render_verdict(verdict) == RETAKE_PROSE


def test_check_sends_the_page_then_the_photo_and_decides_in_code() -> None:
    vision = FakeLLMClient(text=_reply())

    verdict = check_plug(FAKE_JPEG, page_png=FAKE_PNG, page_text=PAGE_TEXT, vision=vision)

    assert verdict == PlugMatch(label_agreed=True)
    system, user = vision.calls[0]
    assert system.content == VISION_INSTRUCTION
    assert [(image.media_type, image.data) for image in user.images] == [
        ("image/png", FAKE_PNG),
        ("image/jpeg", FAKE_JPEG),
    ]
    assert ", ".join(SHAPES) in VISION_INSTRUCTION
    assert ", ".join(COLORS) in VISION_INSTRUCTION


def test_drawing_count_that_disagrees_with_printed_count_is_unsure() -> None:
    verdict = decide_plug(_looks(page=_look(pin_count=4), photo=_look(pin_count=4)), PAGE_TEXT)

    assert verdict == PlugUnsure(UnsureReason.PAGE_TEXT_CONFLICT)
    _assert_no_digit(render_verdict(verdict))


def test_unclear_color_is_never_a_match() -> None:
    verdict = decide_plug(_looks(photo=_look(color="unclear")), PAGE_TEXT)

    assert verdict == PlugUnsure(UnsureReason.INCOMPLETE)
    assert render_verdict(verdict) == RETAKE_PROSE


def test_match_needs_an_anchor_from_the_page_text() -> None:
    no_anchor = _looks(page=_look(label=None), photo=_look(label=None))

    assert decide_plug(no_anchor, "FAKE-PAGE: a plug drawing.") == PlugUnsure(
        UnsureReason.INCOMPLETE
    )
    assert decide_plug(no_anchor, PAGE_TEXT) == PlugMatch(label_agreed=False)


def test_outline_difference_needs_all_core_looks_read() -> None:
    hidden_pins = _looks(page=_look(pin_count=None), photo=_look(shape="round", pin_count=None))
    all_read = _looks(photo=_look(shape="round"))

    assert decide_plug(hidden_pins, PAGE_TEXT) == PlugUnsure(UnsureReason.INCOMPLETE)
    verdict = decide_plug(all_read, PAGE_TEXT)
    assert verdict == PlugDiffers(frozenset({PlugField.SHAPE}))
    assert render_verdict(verdict).startswith("The outline does not match the plug on this page.")


@pytest.mark.parametrize(
    "raw",
    [
        _reply(photo=_look(color="purple")),
        _reply(photo=_look(shape="square")),
        _reply(photo=_look(pin_count=41)),
        _reply(photo=_look(pin_count=0)),
        _reply(photo=_look(pin_count="2")),
        _reply(photo=_look(label="FAKE-" + "X" * 40)),
        json.dumps({"page": _look(), "photo": _look(), "same_plug": True}),
        json.dumps({"page": _look(), "photo": {**_look(), "confidence": 0.99}}),
        json.dumps([_look(), _look()]),
        "They look the same.",
        "",
    ],
)
def test_malformed_readings_are_unsure(raw: str) -> None:
    verdict = check_plug(
        FAKE_JPEG, page_png=FAKE_PNG, page_text=PAGE_TEXT, vision=FakeLLMClient(text=raw)
    )

    assert verdict == PlugUnsure(UnsureReason.MODEL_INVALID)


def test_fenced_json_reply_is_read() -> None:
    raw = f"```json\n{_reply()}\n```"

    verdict = check_plug(
        FAKE_JPEG, page_png=FAKE_PNG, page_text=PAGE_TEXT, vision=FakeLLMClient(text=raw)
    )

    assert verdict == PlugMatch(label_agreed=True)


@pytest.mark.parametrize(
    ("photo", "page_png", "page_text", "vision", "reason"),
    [
        (None, FAKE_PNG, PAGE_TEXT, FakeLLMClient(text=_reply()), UnsureReason.MISSING_IMAGE),
        (FAKE_JPEG, None, PAGE_TEXT, FakeLLMClient(text=_reply()), UnsureReason.MISSING_IMAGE),
        (FAKE_JPEG, FAKE_PNG, None, FakeLLMClient(text=_reply()), UnsureReason.NO_PAGE_TEXT),
        (FAKE_JPEG, FAKE_PNG, PAGE_TEXT, None, UnsureReason.VISION_UNAVAILABLE),
        (
            FAKE_JPEG,
            FAKE_PNG,
            PAGE_TEXT,
            FakeLLMClient(error=LLMError("provider down")),
            UnsureReason.VISION_UNAVAILABLE,
        ),
    ],
)
def test_missing_inputs_and_provider_errors_are_unsure(
    photo: bytes | None,
    page_png: bytes | None,
    page_text: str | None,
    vision: FakeLLMClient | None,
    reason: UnsureReason,
) -> None:
    verdict = check_plug(photo, page_png=page_png, page_text=page_text, vision=vision)

    assert verdict == PlugUnsure(reason)
    assert render_verdict(verdict).startswith(
        "I can't tell if this plug matches the one on the page. "
    )


def test_unsure_prose_never_uses_the_match_sentence() -> None:
    for reason in UnsureReason:
        prose = render_verdict(PlugUnsure(reason))
        assert "look the same" not in prose
        _assert_no_digit(prose)


def test_differs_needs_a_field() -> None:
    with pytest.raises(ValueError, match="at least one field"):
        PlugDiffers(frozenset())
