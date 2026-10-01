"""Pick a bay-map highlight from a closed part list, or none.

The bay map schema (#26) is not merged. ``BayMapView`` is the slice this
module needs. An adapter from that schema should build this view. It should
not grow polygons, image size, names, aliases, license, or source.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass
from enum import Enum
from typing import Any

from llm import ChatTurn, LLMClient

NOT_MAPPED_SENTENCE = "This part is not mapped yet."

SELECTION_SYSTEM = (
    "You select a bay-map part for a highlight. "
    "Reply with JSON only, one object, one key: "
    '{"part_id": "<id from the closed list>"} or {"part_id": null}. '
    "Use null when the answer is not about one listed part, or when you are unsure. "
    "An id that is not in the closed list is not allowed. "
    "Do not invent part numbers, torque values, pinouts, or wire colors."
)


class SelectionKind(Enum):
    PART = "part"
    NONE = "none"
    UNKNOWN = "unknown"
    AMBIGUOUS = "ambiguous"


class ResolutionKind(Enum):
    HIGHLIGHT = "highlight"
    NOT_MAPPED = "not_mapped"
    NONE = "none"
    AMBIGUOUS = "ambiguous"


@dataclass(frozen=True)
class PartSelection:
    kind: SelectionKind
    part_id: str | None = None


@dataclass(frozen=True)
class Resolution:
    kind: ResolutionKind
    part_id: str | None = None
    bay_photo_id: str | None = None
    angle_id: str | None = None


@dataclass(frozen=True)
class PartRegionView:
    """One region reduced to a comparable area.

    ``area_px`` is polygon pixel area. The #26 adapter must pass areas on
    one scale. Unconfirmed regions are never highlighted.
    """

    bay_photo_id: str
    angle_id: str
    area_px: int
    confirmed: bool

    def __post_init__(self) -> None:
        _require_id(self.bay_photo_id, "bay_photo_id")
        _require_id(self.angle_id, "angle_id")
        if type(self.area_px) is not int or self.area_px < 0:
            raise ValueError("area_px must be an int >= 0")
        if type(self.confirmed) is not bool:
            raise ValueError("confirmed must be a bool")


@dataclass(frozen=True)
class BayPartView:
    part_id: str
    regions: tuple[PartRegionView, ...]

    def __post_init__(self) -> None:
        _require_id(self.part_id, "part_id")
        object.__setattr__(self, "regions", tuple(self.regions))


@dataclass(frozen=True)
class BayMapView:
    """Closed part list. Empty means no catalog is loaded."""

    parts: tuple[BayPartView, ...]

    def __post_init__(self) -> None:
        parts = tuple(self.parts)
        seen: set[str] = set()
        for part in parts:
            if part.part_id in seen:
                raise ValueError(f"duplicate part_id: {part.part_id}")
            seen.add(part.part_id)
        object.__setattr__(self, "parts", parts)

    def part_ids(self) -> tuple[str, ...]:
        return tuple(part.part_id for part in self.parts)


def selection_messages(*, answer_text: str, bay_map: BayMapView) -> list[ChatTurn]:
    """Prompt that asks for one closed-list id, or null."""

    lines = ["Closed list:"]
    lines.extend(bay_map.part_ids())
    lines.append("")
    lines.append("Answer:")
    lines.append(answer_text)
    return [
        ChatTurn(role="system", content=SELECTION_SYSTEM),
        ChatTurn(role="user", content="\n".join(lines)),
    ]


def complete_selection(
    client: LLMClient,
    *,
    answer_text: str,
    bay_map: BayMapView,
) -> str:
    messages = selection_messages(answer_text=answer_text, bay_map=bay_map)
    return client.complete(messages).text


def parse_selection(raw: str, bay_map: BayMapView) -> PartSelection:
    """Accept one closed-list id, explicit null, or neither.

    Free text is ambiguous even when it mentions a listed id. The resolver
    does not guess a part from prose.
    """

    payload = _json_object(raw)
    if payload is None or set(payload) != {"part_id"}:
        return PartSelection(kind=SelectionKind.AMBIGUOUS)
    part_id = payload["part_id"]
    if part_id is None:
        return PartSelection(kind=SelectionKind.NONE)
    if not isinstance(part_id, str):
        return PartSelection(kind=SelectionKind.AMBIGUOUS)
    token = part_id.strip()
    if not token:
        return PartSelection(kind=SelectionKind.AMBIGUOUS)
    if token in bay_map.part_ids():
        return PartSelection(kind=SelectionKind.PART, part_id=token)
    return PartSelection(kind=SelectionKind.UNKNOWN, part_id=token)


def resolve_part(selection_text: str, bay_map: BayMapView) -> Resolution:
    selection = parse_selection(selection_text, bay_map)
    if selection.kind is SelectionKind.NONE:
        return Resolution(kind=ResolutionKind.NONE)
    if selection.kind is SelectionKind.AMBIGUOUS:
        return Resolution(kind=ResolutionKind.AMBIGUOUS)
    if selection.kind is SelectionKind.UNKNOWN:
        return Resolution(kind=ResolutionKind.NOT_MAPPED, part_id=selection.part_id)

    part = _part_by_id(bay_map, selection.part_id)
    region = largest_confirmed_region(part) if part is not None else None
    if part is None or region is None or selection.part_id is None:
        return Resolution(kind=ResolutionKind.NOT_MAPPED, part_id=selection.part_id)
    return Resolution(
        kind=ResolutionKind.HIGHLIGHT,
        part_id=selection.part_id,
        bay_photo_id=region.bay_photo_id,
        angle_id=region.angle_id,
    )


def largest_confirmed_region(part: BayPartView) -> PartRegionView | None:
    """Largest confirmed region. Equal areas use the lower photo id, then angle id.

    Equal areas are the same size, so a stable id keeps tests and eval fixed.
    """

    usable = [
        region for region in part.regions if region.confirmed and region.area_px > 0
    ]
    if not usable:
        return None
    return min(
        usable,
        key=lambda region: (-region.area_px, region.bay_photo_id, region.angle_id),
    )


def apply_resolution(
    answer: Mapping[str, Any], resolution: Resolution
) -> dict[str, Any]:
    """Copy the answer. A refusal never gains a highlight or the unmapped sentence."""

    kind = answer.get("kind")
    payload = dict(answer)
    payload.pop("highlight", None)
    if kind == "refusal":
        return payload
    if kind != "answer":
        raise ValueError("answer kind must be 'answer' or 'refusal'")
    if resolution.kind is ResolutionKind.NOT_MAPPED:
        payload["text"] = _with_not_mapped(str(payload["text"]))
    elif resolution.kind is ResolutionKind.HIGHLIGHT:
        if not resolution.bay_photo_id or not resolution.part_id:
            raise ValueError("highlight resolution requires bay_photo_id and part_id")
        payload["highlight"] = {
            "bay_photo_id": resolution.bay_photo_id,
            "part_id": resolution.part_id,
        }
    return payload


def resolve_answer(
    answer: Mapping[str, Any],
    selection_text: str,
    bay_map: BayMapView,
) -> dict[str, Any]:
    return apply_resolution(answer, resolve_part(selection_text, bay_map))


def _part_by_id(bay_map: BayMapView, part_id: str | None) -> BayPartView | None:
    if part_id is None:
        return None
    for part in bay_map.parts:
        if part.part_id == part_id:
            return part
    return None


def _with_not_mapped(text: str) -> str:
    if NOT_MAPPED_SENTENCE in text:
        return text
    if not text or text.endswith((" ", "\n")):
        return f"{text}{NOT_MAPPED_SENTENCE}"
    return f"{text} {NOT_MAPPED_SENTENCE}"


def _require_id(value: str, label: str) -> None:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(
            f"{label} must be a non-empty string with no surrounding space"
        )
    if "\n" in value or "\r" in value:
        raise ValueError(f"{label} must be a single line")


def _json_object(raw: str) -> dict[str, Any] | None:
    text = _strip_one_fence(raw.strip().lstrip("\ufeff"))
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    if isinstance(value, dict):
        return value
    return None


def _strip_one_fence(text: str) -> str:
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if len(lines) < 2 or lines[-1].strip() != "```":
        return text
    return "\n".join(lines[1:-1]).strip()
