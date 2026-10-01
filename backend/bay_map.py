from __future__ import annotations

import json
import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

CONTRACTS_DIR = Path(__file__).resolve().parent / "contracts"
BAY_MAP_SCHEMA_PATH = CONTRACTS_DIR / "bay_map.schema.json"
BAY_MAP_FIXTURE_PATH = CONTRACTS_DIR / "fixtures" / "bay-map" / "fake-bay-map.json"

COORDINATE_SPACE = {
    "units": "normalized",
    "origin": "top_left",
    "x_axis": "right",
    "y_axis": "down",
}


class BayMapError(ValueError):
    pass


@dataclass(frozen=True)
class BayPoint:
    x: float
    y: float


@dataclass(frozen=True)
class BayPolygon:
    points: tuple[BayPoint, ...]


@dataclass(frozen=True)
class BayPart:
    part_id: str
    display_name: str
    aliases: tuple[str, ...]


@dataclass(frozen=True)
class BayPhoto:
    bay_photo_id: str
    angle_id: str
    width: int
    height: int
    source_kind: str
    source_reference: str
    license_name: str
    license_reference: str


@dataclass(frozen=True)
class HighlightChoice:
    part: BayPart
    bay_photo_id: str
    part_id: str


@dataclass(frozen=True)
class ConfirmedHighlight:
    part: BayPart
    photo: BayPhoto
    polygons: tuple[BayPolygon, ...]
    confirmed_by: str

    @property
    def bay_photo_id(self) -> str:
        return self.photo.bay_photo_id

    @property
    def part_id(self) -> str:
        return self.part.part_id


@dataclass(frozen=True)
class _Region:
    part_id: str
    polygons: tuple[BayPolygon, ...]
    confirmed_by: str | None

    @property
    def normalized_area(self) -> float:
        return sum(_polygon_area(polygon) for polygon in self.polygons)


@dataclass(frozen=True)
class _StoredPhoto:
    photo: BayPhoto
    regions: tuple[_Region, ...]


@dataclass(frozen=True)
class BayMap:
    """`highlight_choices` and `resolve` skip unconfirmed regions."""

    schema_version: int
    parts: tuple[BayPart, ...]
    photos: tuple[BayPhoto, ...]
    _stored_photos: tuple[_StoredPhoto, ...]

    @property
    def highlight_choices(self) -> tuple[HighlightChoice, ...]:
        best: dict[str, tuple[int, str, str]] = {}
        for stored in self._stored_photos:
            for region in stored.regions:
                if region.confirmed_by is None:
                    continue
                photo = stored.photo
                candidate = (
                    _pixel_area(region.normalized_area, photo.width, photo.height),
                    photo.bay_photo_id,
                    photo.angle_id,
                )
                current = best.get(region.part_id)
                if current is None or _prefer(candidate, current):
                    best[region.part_id] = candidate
        parts_by_id = {part.part_id: part for part in self.parts}
        choices: list[HighlightChoice] = []
        for part_id in sorted(best):
            _area, photo_id, _angle_id = best[part_id]
            choices.append(
                HighlightChoice(
                    part=parts_by_id[part_id],
                    bay_photo_id=photo_id,
                    part_id=part_id,
                )
            )
        return tuple(choices)

    def resolve(self, bay_photo_id: str, part_id: str) -> ConfirmedHighlight | None:
        part = next((item for item in self.parts if item.part_id == part_id), None)
        stored = next(
            (item for item in self._stored_photos if item.photo.bay_photo_id == bay_photo_id),
            None,
        )
        if part is None or stored is None:
            return None
        region = next((item for item in stored.regions if item.part_id == part_id), None)
        if region is None or region.confirmed_by is None:
            return None
        return ConfirmedHighlight(
            part=part,
            photo=stored.photo,
            polygons=region.polygons,
            confirmed_by=region.confirmed_by,
        )

    def canonical_json(self) -> bytes:
        return json.dumps(_canonical_payload(self), separators=(",", ":")).encode("utf-8")


def load_bay_map(data: bytes) -> BayMap:
    payload = json.loads(data)
    if not isinstance(payload, dict):
        raise BayMapError("bay map must be an object")
    try:
        _validator().validate(payload)
    except ValidationError as exc:
        raise BayMapError(exc.message) from exc
    return _interpret(payload)


def _prefer(candidate: tuple[int, str, str], current: tuple[int, str, str]) -> bool:
    candidate_area, candidate_photo, candidate_angle = candidate
    current_area, current_photo, current_angle = current
    if candidate_area != current_area:
        return candidate_area > current_area
    if candidate_photo != current_photo:
        return candidate_photo < current_photo
    return candidate_angle < current_angle


def _pixel_area(normalized_area: float, width: int, height: int) -> int:
    """Normalized shoelace times the photo's pixel size, rounded half away from zero."""
    return math.floor(normalized_area * width * height + 0.5)


def _polygon_area(polygon: BayPolygon) -> float:
    points = polygon.points
    total = 0.0
    for index, point in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        total += point.x * nxt.y - nxt.x * point.y
    return abs(total) / 2


def _interpret(payload: dict[str, Any]) -> BayMap:
    parts = tuple(_part(item) for item in payload["parts"])
    _check_parts(parts)
    stored = tuple(_photo(item) for item in payload["photos"])
    _check_photos(stored, parts)
    ordered_parts = tuple(sorted(parts, key=lambda part: part.part_id))
    ordered_photos = tuple(
        sorted(
            (
                _StoredPhoto(
                    photo=item.photo,
                    regions=tuple(sorted(item.regions, key=lambda region: region.part_id)),
                )
                for item in stored
            ),
            key=lambda item: item.photo.bay_photo_id,
        )
    )
    return BayMap(
        schema_version=payload["schema_version"],
        parts=ordered_parts,
        photos=tuple(item.photo for item in ordered_photos),
        _stored_photos=ordered_photos,
    )


def _part(item: dict[str, Any]) -> BayPart:
    return BayPart(
        part_id=item["part_id"],
        display_name=item["display_name"],
        aliases=tuple(item["aliases"]),
    )


def _check_parts(parts: tuple[BayPart, ...]) -> None:
    ids = [part.part_id for part in parts]
    if len(ids) != len(set(ids)):
        raise BayMapError("duplicate part_id")
    names = [part.display_name for part in parts]
    if len(names) != len(set(names)):
        raise BayMapError("duplicate display_name")
    taken = set(ids) | set(names)
    seen_aliases: set[str] = set()
    for part in parts:
        for alias in part.aliases:
            if alias in taken or alias in seen_aliases:
                raise BayMapError("alias collides with a part id or display name")
            seen_aliases.add(alias)


def _photo(item: dict[str, Any]) -> _StoredPhoto:
    source = item["source"]
    license_info = item["license"]
    size = item["image_size"]
    photo = BayPhoto(
        bay_photo_id=item["bay_photo_id"],
        angle_id=item["angle_id"],
        width=size["width"],
        height=size["height"],
        source_kind=source["kind"],
        source_reference=source["reference"],
        license_name=license_info["name"],
        license_reference=license_info["reference"],
    )
    regions = tuple(_region(region) for region in item["regions"])
    region_ids = [region.part_id for region in regions]
    if len(region_ids) != len(set(region_ids)):
        raise BayMapError("duplicate region for bay_photo_id and part_id")
    return _StoredPhoto(photo=photo, regions=regions)


def _region(item: dict[str, Any]) -> _Region:
    polygons = tuple(_polygon(polygon) for polygon in item["polygons"])
    confirmation = item["confirmation"]
    confirmed_by = confirmation.get("confirmed_by") if confirmation["kind"] == "confirmed" else None
    return _Region(part_id=item["part_id"], polygons=polygons, confirmed_by=confirmed_by)


def _polygon(item: dict[str, Any]) -> BayPolygon:
    points = tuple(BayPoint(x=float(point["x"]), y=float(point["y"])) for point in item["points"])
    if points[0] == points[-1]:
        raise BayMapError("polygon repeats its first point")
    polygon = BayPolygon(points=points)
    if _polygon_area(polygon) == 0:
        raise BayMapError("polygon area must be positive")
    return polygon


def _check_photos(photos: tuple[_StoredPhoto, ...], parts: tuple[BayPart, ...]) -> None:
    photo_ids = [item.photo.bay_photo_id for item in photos]
    if len(photo_ids) != len(set(photo_ids)):
        raise BayMapError("duplicate bay_photo_id")
    part_ids = {part.part_id for part in parts}
    referenced: set[str] = set()
    for stored in photos:
        for region in stored.regions:
            if region.part_id not in part_ids:
                raise BayMapError("region part_id is not in parts")
            referenced.add(region.part_id)
    if part_ids != referenced:
        raise BayMapError("part has no region")


def _canonical_payload(bay_map: BayMap) -> dict[str, Any]:
    regions_by_photo: dict[str, list[_Region]] = {
        stored.photo.bay_photo_id: list(stored.regions) for stored in bay_map._stored_photos
    }
    return {
        "schema_version": bay_map.schema_version,
        "coordinate_space": dict(COORDINATE_SPACE),
        "parts": [
            {
                "part_id": part.part_id,
                "display_name": part.display_name,
                "aliases": list(part.aliases),
            }
            for part in bay_map.parts
        ],
        "photos": [
            {
                "bay_photo_id": photo.bay_photo_id,
                "angle_id": photo.angle_id,
                "image_size": {"width": photo.width, "height": photo.height},
                "source": {"kind": photo.source_kind, "reference": photo.source_reference},
                "license": {"name": photo.license_name, "reference": photo.license_reference},
                "regions": [_region_payload(region) for region in regions_by_photo[photo.bay_photo_id]],
            }
            for photo in bay_map.photos
        ],
    }


def _region_payload(region: _Region) -> dict[str, Any]:
    confirmation: dict[str, str]
    if region.confirmed_by is None:
        confirmation = {"kind": "unconfirmed"}
    else:
        confirmation = {"kind": "confirmed", "confirmed_by": region.confirmed_by}
    return {
        "part_id": region.part_id,
        "polygons": [
            {"points": [{"x": point.x, "y": point.y} for point in polygon.points]}
            for polygon in region.polygons
        ],
        "confirmation": confirmation,
    }


@lru_cache(maxsize=1)
def _validator() -> Draft202012Validator:
    schema = json.loads(BAY_MAP_SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)
