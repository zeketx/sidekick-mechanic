"""Demo-mode bay photos and highlight resolution.

Scripted polygons and ``demo_state`` values. Not Zeke's truck. Not a
measured confidence gate. Constrains the existing part resolver to one
photo's closed part list.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Mapping
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

from highlight import HighlightConfig
from part_resolver import (
    BayMapView,
    BayPartView,
    PartRegionView,
    Resolution,
    ResolutionKind,
    resolve_part,
)

DEMO_DIR = Path(__file__).resolve().parent / "data" / "demo"
CATALOG_PATH = DEMO_DIR / "demo_bay_photos.json"
ATTRIBUTION_PATH = DEMO_DIR / "ATTRIBUTION.md"
PHOTOS_DIR = DEMO_DIR / "photos"

DEMO_LABEL = "Demo data. Scripted highlights. Not Zeke's truck."
DEMO_DIAGRAM_POINTER = (
    "This part is not on this demo photo. "
    "See the manual diagram (placeholder): 2JZ-GE repair manual, page TBD."
)
# Confirmed in docs/vehicle/TRUCK.md. VVT-i and donor year stay TBD.
DEMO_VEHICLE = "1990 Toyota Land Cruiser LJ78 with a 2JZ-GE swap"
DEMO_VEHICLE_CONTEXT = (
    f"The owner's truck is a {DEMO_VEHICLE}. "
    "Demo photos are stand-in 2JZ bays, not the truck. "
    "Donor year, VVT-i, and ECU details are TBD. Do not invent them."
)
DEMO_SYSTEM_PROMPT = (
    "You are Sidekick Mechanic. Answer the owner's question. "
    f"{DEMO_VEHICLE_CONTEXT} "
    "Do not invent torque values, part numbers, pinouts, wire colors, or other specs. "
    "If you do not know a spec, say so."
)
DEMO_DEFAULT_PHOTO_ID = "commons-hilux-2jz"
DEMO_SHORT_NAMES = {
    "hrymx-2jz-ge-25308847029": "2JZ-GE prototype",
    "commons-hilux-2jz": "Hilux",
    "commons-supra-n5abh": "Supra (2JZ-GTE)",
    "flickr-robmarson-6763892857": "2JZ bay",
}
DEMO_ANGLE_ID = "demo"
DEMO_STATES = frozenset({"outline", "confirm", "not_found"})
# Brightness left after dim. 0.40 ≈ 60% dim, inside the 55–65% band.
DEMO_DIM_FACTOR = 0.40
LOGGER = logging.getLogger("sidekick.demo")

DemoState = Literal["outline", "confirm", "not_found"]
DemoFeedbackAction = Literal["yes", "not_this"]


@dataclass(frozen=True)
class DemoPoint:
    x: float
    y: float


@dataclass(frozen=True)
class DemoPolygon:
    points: tuple[DemoPoint, ...]


@dataclass(frozen=True)
class DemoPart:
    part_id: str
    display_name: str
    demo_state: DemoState
    polygons: tuple[DemoPolygon, ...]


@dataclass(frozen=True)
class DemoPhoto:
    photo_id: str
    image_file: str
    attribution: str
    author: str
    license: str
    license_url: str
    source_page_url: str
    engine_as_stated: str
    width: int
    height: int
    parts: tuple[DemoPart, ...]

    def part(self, part_id: str) -> DemoPart | None:
        for item in self.parts:
            if item.part_id == part_id:
                return item
        return None

    @property
    def image_path(self) -> Path:
        return DEMO_DIR / self.image_file

    @property
    def share_alike(self) -> bool:
        return self.license.startswith("CC BY-SA")

    @property
    def short_name(self) -> str:
        return DEMO_SHORT_NAMES.get(self.photo_id, self.photo_id)


@dataclass(frozen=True)
class DemoCatalog:
    photos: tuple[DemoPhoto, ...]

    def photo(self, photo_id: str) -> DemoPhoto | None:
        for item in self.photos:
            if item.photo_id == photo_id:
                return item
        return None

    def photo_ids(self) -> tuple[str, ...]:
        return tuple(photo.photo_id for photo in self.photos)


class DemoCatalogError(Exception):
    """The demo catalog or a photo file is invalid."""


@lru_cache(maxsize=1)
def load_catalog(path: Path | None = None) -> DemoCatalog:
    catalog_path = CATALOG_PATH if path is None else path
    try:
        payload = json.loads(catalog_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise DemoCatalogError(f"missing demo catalog: {catalog_path}") from exc
    except json.JSONDecodeError as exc:
        raise DemoCatalogError(f"demo catalog is not JSON: {catalog_path}") from exc
    if not isinstance(payload, dict):
        raise DemoCatalogError("demo catalog must be a JSON object")
    photos = _photos(payload.get("photos"))
    return DemoCatalog(photos=photos)


def has_photo(photo_id: str) -> bool:
    return load_catalog().photo(photo_id) is not None


def photo_file(photo_id: str) -> Path | None:
    photo = load_catalog().photo(photo_id)
    if photo is None or not photo.image_path.is_file():
        return None
    return photo.image_path


def catalog_public() -> dict[str, Any]:
    catalog = load_catalog()
    return {
        "demo": True,
        "label": DEMO_LABEL,
        "attribution_url": "/demo/attribution",
        "default_photo_id": DEMO_DEFAULT_PHOTO_ID,
        "photos": [_public_photo(photo) for photo in catalog.photos],
    }


def bay_map_view_for_photo(photo_id: str) -> BayMapView:
    photo = load_catalog().photo(photo_id)
    if photo is None:
        raise DemoCatalogError(f"unknown demo photo: {photo_id}")
    return BayMapView(parts=tuple(_bay_part(photo, part) for part in photo.parts))


def resolve_demo_answer(
    answer: Mapping[str, Any],
    selection_text: str,
    photo_id: str,
) -> dict[str, Any]:
    """Resolve a part from the user's question (or a JSON selection), then demo_state."""
    return apply_demo_resolution(
        answer,
        resolution_from_user_text(selection_text, photo_id),
        photo_id,
    )


def resolution_from_user_text(text: str, photo_id: str) -> Resolution:
    """Prefer a JSON ``{"part_id": ...}`` selection; otherwise match the question."""
    photo = load_catalog().photo(photo_id)
    if photo is None:
        raise DemoCatalogError(f"unknown demo photo: {photo_id}")
    bay_map = bay_map_view_for_photo(photo_id)
    stripped = text.strip()
    if stripped.startswith("{"):
        return resolve_part(stripped, bay_map)
    matched = match_part_from_question(stripped, photo)
    if matched is None:
        return Resolution(kind=ResolutionKind.NONE)
    return resolve_part(json.dumps({"part_id": matched.part_id}), bay_map)


def match_part_from_question(question: str, photo: DemoPhoto) -> DemoPart | None:
    """Pick the one catalog part whose name appears in the question, or none.

    Constrained to this photo's parts. Does not read the model reply.
    """
    haystack = _normalize_phrase(question)
    hits: list[DemoPart] = []
    for part in photo.parts:
        if any(alias in haystack for alias in _part_aliases(part)):
            hits.append(part)
    if len(hits) == 1:
        return hits[0]
    return None


def apply_demo_resolution(
    answer: Mapping[str, Any],
    resolution: Resolution,
    photo_id: str,
) -> dict[str, Any]:
    """Copy the answer. Demo highlights are marked ``demo: true``.

    ``outline`` and ``confirm`` ride on ``display`` plus ``geometry``.
    Abstain (not found, unknown id, or no usable region) omits ``highlight``
    and appends the manual-diagram placeholder. A refusal is unchanged.
    """
    kind = answer.get("kind")
    payload = dict(answer)
    payload.pop("highlight", None)
    if kind == "refusal":
        return payload
    if kind != "answer":
        raise ValueError("answer kind must be 'answer' or 'refusal'")

    photo = load_catalog().photo(photo_id)
    if photo is None:
        raise DemoCatalogError(f"unknown demo photo: {photo_id}")

    if resolution.kind is ResolutionKind.HIGHLIGHT and resolution.part_id:
        part = photo.part(resolution.part_id)
        if part is not None and part.demo_state in {"outline", "confirm"}:
            payload["highlight"] = {
                "bay_photo_id": photo.photo_id,
                "part_id": part.part_id,
                "display": part.demo_state,
                "geometry": _geometry_payload(part),
                "demo": True,
            }
            payload["text"] = _located_text(part)
            return payload

    if resolution.kind in {ResolutionKind.NOT_MAPPED, ResolutionKind.HIGHLIGHT}:
        payload["text"] = _not_visible_text(photo, resolution.part_id)
    return payload


def log_demo_feedback(
    *,
    photo_id: str,
    part_id: str,
    action: DemoFeedbackAction,
) -> dict[str, Any]:
    LOGGER.info(
        "demo confirm tap photo_id=%s part_id=%s action=%s",
        photo_id,
        part_id,
        action,
    )
    return {"ok": True, "demo": True}


def confirm_highlight_config() -> HighlightConfig:
    """Softer ink for the unsure 'Is this it?' state.

    Dim stays in the 55–65% band (same strength as the outline proofs).
    Confirm reads softer via a thinner stroke and lower saturation, not a
    weaker dim — 30% dim was invisible on these photos.
    """
    return HighlightConfig(
        outline_width_px=4,
        saturation_factor=2.0,
        circle_width_px=2,
        circle_padding_px=16,
        dim_factor=DEMO_DIM_FACTOR,
    )


def pixel_rings(part: DemoPart, width: int, height: int) -> list[list[tuple[float, float]]]:
    rings: list[list[tuple[float, float]]] = []
    for polygon in part.polygons:
        rings.append(
            [(point.x * width, point.y * height) for point in polygon.points]
        )
    return rings


def _public_photo(photo: DemoPhoto) -> dict[str, Any]:
    return {
        "photo_id": photo.photo_id,
        "short_name": photo.short_name,
        "image_url": f"/demo/photos/{photo.photo_id}/image",
        "attribution": photo.attribution,
        "author": photo.author,
        "license": photo.license,
        "license_url": photo.license_url,
        "source_page_url": photo.source_page_url,
        "engine_as_stated": photo.engine_as_stated,
        "share_alike": photo.share_alike,
        "width": photo.width,
        "height": photo.height,
        "parts": [
            {
                "part_id": part.part_id,
                "display_name": part.display_name,
                "demo_state": part.demo_state,
            }
            for part in photo.parts
        ],
    }


def _photos(raw: object) -> tuple[DemoPhoto, ...]:
    if not isinstance(raw, list) or not raw:
        raise DemoCatalogError("demo catalog needs at least one photo")
    photos: list[DemoPhoto] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            raise DemoCatalogError("each demo photo must be an object")
        photo = _photo(item)
        if photo.photo_id in seen:
            raise DemoCatalogError(f"duplicate demo photo_id: {photo.photo_id}")
        seen.add(photo.photo_id)
        photos.append(photo)
    return tuple(photos)


def _photo(item: dict[str, object]) -> DemoPhoto:
    photo_id = _require_str(item, "photo_id")
    image_file = _require_str(item, "image_file")
    if Path(image_file).parts[0] != "photos" or Path(image_file).suffix != ".jpg":
        raise DemoCatalogError(f"unsafe image_file for {photo_id}: {image_file!r}")
    photo = DemoPhoto(
        photo_id=photo_id,
        image_file=image_file,
        attribution=_require_str(item, "attribution"),
        author=_require_str(item, "author"),
        license=_require_str(item, "license"),
        license_url=_require_str(item, "license_url"),
        source_page_url=_require_str(item, "source_page_url"),
        engine_as_stated=_require_str(item, "engine_as_stated"),
        width=_positive_int(item, "width", photo_id),
        height=_positive_int(item, "height", photo_id),
        parts=_parts(item.get("parts"), photo_id),
    )
    if not photo.image_path.is_file():
        raise DemoCatalogError(f"missing demo photo file: {photo.image_path}")
    return photo


def _parts(raw: object, photo_id: str) -> tuple[DemoPart, ...]:
    if not isinstance(raw, list) or not raw:
        raise DemoCatalogError(f"{photo_id} needs at least one part")
    parts: list[DemoPart] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            raise DemoCatalogError(f"{photo_id} parts must be objects")
        part = _part(item, photo_id)
        if part.part_id in seen:
            raise DemoCatalogError(f"duplicate part_id {part.part_id} on {photo_id}")
        seen.add(part.part_id)
        parts.append(part)
    return tuple(parts)


def _part(item: dict[str, object], photo_id: str) -> DemoPart:
    part_id = _require_str(item, "part_id")
    state = item.get("demo_state")
    if state not in DEMO_STATES:
        raise DemoCatalogError(f"{photo_id}/{part_id} has invalid demo_state")
    polygons = _polygons(item.get("polygons"), photo_id, part_id)
    if state == "not_found" and polygons:
        raise DemoCatalogError(f"{photo_id}/{part_id} not_found must have no polygons")
    if state != "not_found" and not polygons:
        raise DemoCatalogError(f"{photo_id}/{part_id} {state} needs polygons")
    return DemoPart(
        part_id=part_id,
        display_name=_require_str(item, "display_name"),
        demo_state=state,
        polygons=polygons,
    )


def _polygons(raw: object, photo_id: str, part_id: str) -> tuple[DemoPolygon, ...]:
    if raw is None:
        return ()
    if not isinstance(raw, list):
        raise DemoCatalogError(f"{photo_id}/{part_id} polygons must be a list")
    rings: list[DemoPolygon] = []
    for item in raw:
        if not isinstance(item, dict):
            raise DemoCatalogError(f"{photo_id}/{part_id} each polygon must be an object")
        points_raw = item.get("points")
        if not isinstance(points_raw, list) or len(points_raw) < 3:
            raise DemoCatalogError(f"{photo_id}/{part_id} polygon needs at least 3 points")
        points = tuple(_point(point, photo_id, part_id) for point in points_raw)
        rings.append(DemoPolygon(points=points))
    return tuple(rings)


def _point(raw: object, photo_id: str, part_id: str) -> DemoPoint:
    if not isinstance(raw, dict):
        raise DemoCatalogError(f"{photo_id}/{part_id} point must be an object")
    x = raw.get("x")
    y = raw.get("y")
    if (
        isinstance(x, bool)
        or isinstance(y, bool)
        or not isinstance(x, (int, float))
        or not isinstance(y, (int, float))
        or not 0.0 <= float(x) <= 1.0
        or not 0.0 <= float(y) <= 1.0
    ):
        raise DemoCatalogError(f"{photo_id}/{part_id} point is not a 0-1 pair")
    return DemoPoint(x=float(x), y=float(y))


def _bay_part(photo: DemoPhoto, part: DemoPart) -> BayPartView:
    if part.demo_state == "not_found" or not part.polygons:
        return BayPartView(part_id=part.part_id, regions=())
    area = _area_px(part, photo.width, photo.height)
    return BayPartView(
        part_id=part.part_id,
        regions=(
            PartRegionView(
                bay_photo_id=photo.photo_id,
                angle_id=DEMO_ANGLE_ID,
                area_px=area,
                confirmed=True,
            ),
        ),
    )


def _area_px(part: DemoPart, width: int, height: int) -> int:
    total = 0.0
    for polygon in part.polygons:
        total += _shoelace_px(polygon.points, width, height)
    return max(1, int(total))


def _shoelace_px(points: tuple[DemoPoint, ...], width: int, height: int) -> float:
    acc = 0.0
    count = len(points)
    for index, point in enumerate(points):
        nxt = points[(index + 1) % count]
        x1, y1 = point.x * width, point.y * height
        x2, y2 = nxt.x * width, nxt.y * height
        acc += x1 * y2 - x2 * y1
    return abs(acc) / 2.0


def _geometry_payload(part: DemoPart) -> dict[str, Any]:
    return {
        "polygons": [
            {
                "points": [{"x": point.x, "y": point.y} for point in polygon.points],
            }
            for polygon in part.polygons
        ]
    }


def _located_text(part: DemoPart) -> str:
    if part.demo_state == "confirm":
        return (
            f"I think this is the {part.display_name} on this demo photo "
            f"of a {DEMO_VEHICLE}."
        )
    return (
        f"Here it is. The {part.display_name} is marked on this demo photo "
        f"of a {DEMO_VEHICLE}."
    )


def _not_visible_text(photo: DemoPhoto, part_id: str | None) -> str:
    part = photo.part(part_id) if part_id else None
    name = part.display_name if part is not None else "that part"
    return f"{name} — not visible in this photo. {DEMO_DIAGRAM_POINTER}"


def _part_aliases(part: DemoPart) -> tuple[str, ...]:
    phrases = {
        _normalize_phrase(part.display_name),
        _normalize_phrase(part.part_id.replace("-", " ")),
        _normalize_phrase(part.display_name.replace("/", " ")),
        _normalize_phrase(part.display_name.replace("+", " ")),
    }
    if "fuse" in part.part_id and "box" in part.part_id:
        phrases.add("fuse box")
    if part.display_name.endswith("s"):
        phrases.add(_normalize_phrase(part.display_name[:-1]))
    return tuple(p for p in phrases if p)


def _normalize_phrase(value: str) -> str:
    raw = "".join(ch.lower() if ch.isalnum() else " " for ch in value)
    return " ".join(raw.split())


def _positive_int(item: dict[str, object], key: str, photo_id: str) -> int:
    value = item.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise DemoCatalogError(f"{photo_id} {key} must be a positive integer")
    return value


def _require_str(item: dict[str, object], key: str) -> str:
    value = item.get(key)
    if not isinstance(value, str) or not value.strip():
        raise DemoCatalogError(f"missing {key}")
    return value
