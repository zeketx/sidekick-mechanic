"""Compare the owner's plug photo with the plug on one manual page.

The vision model only describes the two images in closed words. Code decides
the verdict, and ``render_verdict`` is the only sentence Zeke reads. That prose
never repeats a pin count, a color, or a label the model read, because Zeke can
see both pictures and the model can be wrong about any of them.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from enum import Enum, StrEnum

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from llm import ChatTurn, ImageInput, LLMClient, LLMError, log_llm_failure

SHAPES: tuple[str, ...] = ("rectangular", "round", "oval", "other", "unclear")
COLORS: tuple[str, ...] = (
    "black", "gray", "white", "blue", "brown", "green", "red", "yellow", "unclear",
)
UNCLEAR = "unclear"
MAX_PIN_COUNT = 40
MAX_LABEL_LENGTH = 40
# "pin 12" is a terminal id, not a count, so only the hyphenated form counts.
_PRINTED_PIN_COUNT_RE = re.compile(r"\b(\d{1,2})-pin\b", re.IGNORECASE)

VISION_INSTRUCTION = (
    "You see two images. The first is a repair manual page. The second is a photo "
    "of a plug. Describe the plug in each image. "
    "Reply with one JSON object and no other text. "
    "Keys: page, photo. Each has shape, pin_count, color, label. "
    f"shape is one of: {', '.join(SHAPES)}. "
    f"color is one of: {', '.join(COLORS)}. "
    "pin_count is an integer or null. Use null when you cannot count the pins. "
    "label is the writing you can read on or next to the plug, or null. "
    "If the page shows more than one plug, use unclear and null for page. "
    "Do not say whether they match. If you are guessing, use unclear and null."
)
VISION_PROMPT = "Describe the plug on this manual page, then the plug in this photo."


class PlugLook(BaseModel):
    """One image, as the model saw it. Not a verdict."""

    model_config = ConfigDict(extra="forbid", strict=True)

    shape: str
    pin_count: int | None = Field(default=None, ge=1, le=MAX_PIN_COUNT)
    color: str
    label: str | None = None

    @field_validator("shape")
    @classmethod
    def _known_shape(cls, value: str) -> str:
        if value not in SHAPES:
            raise ValueError("shape is not one of SHAPES")
        return value

    @field_validator("color")
    @classmethod
    def _known_color(cls, value: str) -> str:
        if value not in COLORS:
            raise ValueError("color is not one of COLORS")
        return value

    @field_validator("label")
    @classmethod
    def _short_label(cls, value: str | None) -> str | None:
        text = (value or "").strip()
        if len(text) > MAX_LABEL_LENGTH:
            raise ValueError("label is too long")
        return text or None


class PlugLooks(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    page: PlugLook
    photo: PlugLook


class PlugField(StrEnum):
    SHAPE = "shape"
    PIN_COUNT = "pin_count"
    COLOR = "color"
    LABEL = "label"


class UnsureReason(StrEnum):
    MISSING_IMAGE = "missing_image"
    NO_PAGE_TEXT = "no_page_text"
    VISION_UNAVAILABLE = "vision_unavailable"
    MODEL_INVALID = "model_invalid"
    PAGE_TEXT_CONFLICT = "page_text_conflict"
    INCOMPLETE = "incomplete"


@dataclass(frozen=True)
class PlugMatch:
    label_agreed: bool


@dataclass(frozen=True)
class PlugDiffers:
    fields: frozenset[PlugField]

    def __post_init__(self) -> None:
        if not self.fields:
            raise ValueError("differs needs at least one field")


@dataclass(frozen=True)
class PlugUnsure:
    reason: UnsureReason


PlugVerdict = PlugMatch | PlugDiffers | PlugUnsure


class _Call(Enum):
    AGREE = "agree"
    DISAGREE = "disagree"
    SKIP = "skip"


_CORE_FIELDS = (PlugField.SHAPE, PlugField.PIN_COUNT, PlugField.COLOR)
_FIELD_WORDS: dict[PlugField, str] = {
    PlugField.SHAPE: "the outline",
    PlugField.PIN_COUNT: "the number of pins",
    PlugField.COLOR: "the color",
    PlugField.LABEL: "the writing",
}

MATCH_TEXT = (
    "The outline, the number of pins, and the color look the same as the plug on "
    "this page. I can still be wrong. Hold them next to each other before you "
    "unplug anything."
)
MATCH_WITH_WRITING_TEXT = (
    "The outline, the number of pins, the color, and the writing look the same as "
    "the plug on this page. I can still be wrong. Hold them next to each other "
    "before you unplug anything."
)
DIFFERS_TAIL = (
    "I would not call this the same plug. Look for another plug nearby, or take a "
    "closer photo straight at the pins."
)
UNSURE_LEAD = "I can't tell if this plug matches the one on the page."
_RETAKE = "Take another photo with the pins facing the camera and any writing in the light."
_UNSURE_NEXT: dict[UnsureReason, str] = {
    UnsureReason.MISSING_IMAGE: "I could not open the photo or the page. Attach the photo again.",
    UnsureReason.NO_PAGE_TEXT: (
        "This page has no printed words to check the photo against, so I will not "
        "call it a match."
    ),
    UnsureReason.VISION_UNAVAILABLE: (
        "The photo check is not working right now. Compare the plug with the page "
        "yourself before you unplug anything."
    ),
    UnsureReason.MODEL_INVALID: _RETAKE,
    UnsureReason.PAGE_TEXT_CONFLICT: (
        "The drawing and the words on this page do not agree, so I will not call it "
        "a match."
    ),
    UnsureReason.INCOMPLETE: _RETAKE,
}


def check_plug(
    photo_jpeg: bytes | None,
    *,
    page_png: bytes | None,
    page_text: str | None,
    vision: LLMClient | None,
) -> PlugVerdict:
    """Ask the vision model to describe both images, then decide in code."""
    if not photo_jpeg or not page_png:
        return PlugUnsure(UnsureReason.MISSING_IMAGE)
    text = (page_text or "").strip()
    if not text:
        return PlugUnsure(UnsureReason.NO_PAGE_TEXT)
    if vision is None:
        return PlugUnsure(UnsureReason.VISION_UNAVAILABLE)
    turns = [
        ChatTurn(role="system", content=VISION_INSTRUCTION),
        ChatTurn(
            role="user",
            content=VISION_PROMPT,
            images=(
                ImageInput(media_type="image/png", data=page_png),
                ImageInput(media_type="image/jpeg", data=photo_jpeg),
            ),
        ),
    ]
    try:
        result = vision.complete(turns)
    except LLMError as exc:
        log_llm_failure(exc)
        return PlugUnsure(UnsureReason.VISION_UNAVAILABLE)
    looks = _parse_looks(result.text)
    if looks is None:
        return PlugUnsure(UnsureReason.MODEL_INVALID)
    return decide_plug(looks, text)


def decide_plug(looks: PlugLooks, page_text: str) -> PlugVerdict:
    """A match needs the core looks to agree and one anchor our code found in the page text."""
    text = page_text.strip()
    if not text:
        return PlugUnsure(UnsureReason.NO_PAGE_TEXT)
    printed = _printed_pin_count(text)
    page, photo = looks.page, looks.photo
    if printed is not None and page.pin_count is not None and page.pin_count != printed:
        return PlugUnsure(UnsureReason.PAGE_TEXT_CONFLICT)

    calls = {
        PlugField.SHAPE: _compare_words(page.shape, photo.shape),
        PlugField.PIN_COUNT: _compare_pins(page.pin_count, photo.pin_count, printed),
        PlugField.COLOR: _compare_words(page.color, photo.color),
        PlugField.LABEL: _compare_labels(page.label, photo.label, text),
    }
    disagreeing = frozenset(name for name, call in calls.items() if call is _Call.DISAGREE)
    core_agrees = all(calls[name] is _Call.AGREE for name in _CORE_FIELDS)
    core_decided = all(calls[name] is not _Call.SKIP for name in _CORE_FIELDS)

    if core_agrees and calls[PlugField.LABEL] is not _Call.DISAGREE and _anchored(photo, printed, text):
        return PlugMatch(label_agreed=calls[PlugField.LABEL] is _Call.AGREE)
    # A close-up can hide the outline and still show the pins, so a pin count
    # difference stands alone. An outline or color difference needs all three read.
    if calls[PlugField.PIN_COUNT] is _Call.DISAGREE or (disagreeing and core_decided):
        return PlugDiffers(disagreeing)
    return PlugUnsure(UnsureReason.INCOMPLETE)


def render_verdict(verdict: PlugVerdict) -> str:
    match verdict:
        case PlugMatch(label_agreed=True):
            return MATCH_WITH_WRITING_TEXT
        case PlugMatch():
            return MATCH_TEXT
        case PlugDiffers(fields=fields):
            words = [_FIELD_WORDS[name] for name in PlugField if name in fields]
            verb = "does not match" if len(words) == 1 else "do not match"
            lead = f"{_join_words(words)} {verb} the plug on this page."
            return f"{lead[0].upper()}{lead[1:]} {DIFFERS_TAIL}"
        case PlugUnsure(reason=reason):
            return f"{UNSURE_LEAD} {_UNSURE_NEXT[reason]}"


def _parse_looks(raw: str) -> PlugLooks | None:
    text = raw.strip()
    if text.startswith("```"):
        text = text.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    try:
        return PlugLooks.model_validate(payload)
    except ValidationError:
        return None


def _printed_pin_count(page_text: str) -> int | None:
    """The page's own count, only when it prints exactly one."""
    counts = {int(found) for found in _PRINTED_PIN_COUNT_RE.findall(page_text)}
    if len(counts) != 1:
        return None
    return counts.pop()


def _compare_words(page: str, photo: str) -> _Call:
    if page == UNCLEAR or photo == UNCLEAR:
        return _Call.SKIP
    return _Call.AGREE if page == photo else _Call.DISAGREE


def _compare_pins(page: int | None, photo: int | None, printed: int | None) -> _Call:
    if photo is None:
        return _Call.SKIP
    if printed is not None and photo != printed:
        return _Call.DISAGREE
    if page is None:
        return _Call.SKIP
    return _Call.AGREE if page == photo else _Call.DISAGREE


def _compare_labels(page: str | None, photo: str | None, page_text: str) -> _Call:
    if page is None and photo is None:
        return _Call.SKIP
    in_text = page_text.casefold()
    if photo is not None and photo.casefold() not in in_text:
        return _Call.DISAGREE
    if page is not None and photo is not None:
        return _Call.AGREE if page.casefold() == photo.casefold() else _Call.DISAGREE
    return _Call.SKIP


def _anchored(photo: PlugLook, printed: int | None, page_text: str) -> bool:
    """A color word somewhere on the page is not an anchor. These two are."""
    label_on_page = photo.label is not None and photo.label.casefold() in page_text.casefold()
    printed_count = printed is not None and printed == photo.pin_count
    return label_on_page or printed_count


def _join_words(words: list[str]) -> str:
    if len(words) <= 2:
        return " and ".join(words)
    return f"{', '.join(words[:-1])}, and {words[-1]}"
