"""Convert a Label Studio JSON export into a bay map.

Label Studio Community Edition is the labeling tool. Its JSON export stores
rectangle and polygon coordinates as percentages of the image. Dividing by
100 is the whole conversion into the bay map unit square. Pixel width and
height are copied into ``image_size`` and are not a scale factor.

The same project exports COCO and YOLO for a Phase 2 detector. This module
does not write those files and does not train a model. See docs/BAY_MAP.md.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from bay_map import BayMapError, load_bay_map

# A Label Studio percent can sit a float past 0 or 100. A visible miss still fails.
_PERCENT_SLACK = 1e-6
_SOURCE_KINDS = frozenset({"public_prototype", "owner_observation"})
_HEX = frozenset("0123456789abcdefABCDEF")


class LabelConvertError(ValueError):
    """The export or manifest cannot become a valid bay map."""


@dataclass(frozen=True)
class _NamedRef:
    kind: str
    reference: str


@dataclass(frozen=True)
class _License:
    name: str
    reference: str


@dataclass(frozen=True)
class _PhotoSpec:
    file: str
    bay_photo_id: str
    angle_id: str
    source: _NamedRef
    license: _License
    width: int | None
    height: int | None


@dataclass(frozen=True)
class _PartSpec:
    label: str
    part_id: str
    display_name: str
    aliases: tuple[str, ...]
    confirmation: dict[str, str]


def convert_label_studio_export(
    export_payload: Any, manifest_payload: Any
) -> dict[str, Any]:
    """Return a bay map dict that ``load_bay_map`` has already accepted."""
    photos = _photos(manifest_payload)
    parts = _parts(manifest_payload)
    tasks = _tasks(export_payload)
    photos_by_file = {photo.file: photo for photo in photos}
    parts_by_label = {part.label: part for part in parts}
    matched = _match_tasks(tasks, photos_by_file)
    payload = {
        "schema_version": 1,
        "coordinate_space": {
            "units": "normalized",
            "origin": "top_left",
            "x_axis": "right",
            "y_axis": "down",
        },
        "parts": [
            {
                "part_id": part.part_id,
                "display_name": part.display_name,
                "aliases": list(part.aliases),
            }
            for part in parts
        ],
        "photos": [
            _photo_payload(matched[photo.file], photo, parts_by_label)
            for photo in photos
        ],
    }
    _require_every_part_used(payload["photos"], parts)
    try:
        loaded = load_bay_map(json.dumps(payload).encode("utf-8"))
    except BayMapError as exc:
        raise LabelConvertError(str(exc)) from exc
    decoded: dict[str, Any] = json.loads(loaded.canonical_json())
    return decoded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert a Label Studio JSON export into a bay map."
    )
    parser.add_argument("--export", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        export_payload = json.loads(args.export.read_text(encoding="utf-8"))
        manifest_payload = json.loads(args.manifest.read_text(encoding="utf-8"))
        payload = convert_label_studio_export(export_payload, manifest_payload)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        text = json.dumps(payload, indent=2) + "\n"
        args.output.write_text(text, encoding="utf-8")
    except LabelConvertError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"invalid JSON: {exc}", file=sys.stderr)
        return 1
    except (OSError, UnicodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"wrote {args.output}")
    return 0


def _photos(manifest: Any) -> tuple[_PhotoSpec, ...]:
    root = _object(manifest, "manifest")
    _exact_keys(
        root,
        {"source", "license", "photos", "parts"},
        {"source", "license", "photos", "parts"},
        "manifest",
    )
    default_source = _source(root["source"], "manifest source")
    default_license = _license(root["license"], "manifest license")
    raw_photos = root["photos"]
    if not isinstance(raw_photos, list) or not raw_photos:
        raise LabelConvertError("manifest photos must be a non-empty array")
    photos: list[_PhotoSpec] = []
    files: set[str] = set()
    photo_ids: set[str] = set()
    for index, item in enumerate(raw_photos):
        photo = _photo_spec(item, index, default_source, default_license)
        if photo.file in files:
            raise LabelConvertError(f"duplicate manifest file: {photo.file}")
        if photo.bay_photo_id in photo_ids:
            raise LabelConvertError(f"duplicate bay_photo_id: {photo.bay_photo_id}")
        files.add(photo.file)
        photo_ids.add(photo.bay_photo_id)
        photos.append(photo)
    return tuple(photos)


def _photo_spec(
    item: Any,
    index: int,
    default_source: _NamedRef,
    default_license: _License,
) -> _PhotoSpec:
    what = f"manifest photo {index}"
    obj = _object(item, what)
    _exact_keys(
        obj,
        {"file", "bay_photo_id", "angle_id", "source", "license", "width", "height"},
        {"file", "bay_photo_id", "angle_id"},
        what,
    )
    width, height = _optional_size(obj, what)
    source = (
        default_source
        if "source" not in obj
        else _source(obj["source"], f"{what} source")
    )
    license_info = (
        default_license
        if "license" not in obj
        else _license(obj["license"], f"{what} license")
    )
    return _PhotoSpec(
        file=_req_str(obj, "file", what),
        bay_photo_id=_req_str(obj, "bay_photo_id", what),
        angle_id=_req_str(obj, "angle_id", what),
        source=source,
        license=license_info,
        width=width,
        height=height,
    )


def _parts(manifest: dict[str, Any]) -> tuple[_PartSpec, ...]:
    raw_parts = manifest["parts"]
    if not isinstance(raw_parts, list) or not raw_parts:
        raise LabelConvertError("manifest parts must be a non-empty array")
    parts: list[_PartSpec] = []
    labels: set[str] = set()
    part_ids: set[str] = set()
    for index, item in enumerate(raw_parts):
        part = _part_spec(item, index)
        if part.label in labels:
            raise LabelConvertError(f"duplicate manifest label: {part.label}")
        if part.part_id in part_ids:
            raise LabelConvertError(f"duplicate part_id: {part.part_id}")
        labels.add(part.label)
        part_ids.add(part.part_id)
        parts.append(part)
    return tuple(parts)


def _part_spec(item: Any, index: int) -> _PartSpec:
    what = f"manifest part {index}"
    obj = _object(item, what)
    _exact_keys(
        obj,
        {"label", "part_id", "display_name", "aliases", "confirmation"},
        {"label", "part_id", "display_name", "aliases"},
        what,
    )
    aliases = obj["aliases"]
    if not isinstance(aliases, list) or any(_blank_string(alias) for alias in aliases):
        raise LabelConvertError(f"{what} aliases must be an array of non-empty strings")
    if len(aliases) != len(set(aliases)):
        raise LabelConvertError(f"{what} has a duplicate alias")
    confirmation = (
        {"kind": "unconfirmed"}
        if "confirmation" not in obj
        else _confirmation(obj["confirmation"], f"{what} confirmation")
    )
    return _PartSpec(
        label=_req_str(obj, "label", what),
        part_id=_req_str(obj, "part_id", what),
        display_name=_req_str(obj, "display_name", what),
        aliases=tuple(aliases),
        confirmation=confirmation,
    )


def _tasks(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        payload = [payload]
    if not isinstance(payload, list) or not payload:
        raise LabelConvertError("export must be a JSON array of tasks")
    tasks: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise LabelConvertError(f"export task {index} must be an object")
        tasks.append(item)
    return tasks


def _match_tasks(
    tasks: list[dict[str, Any]],
    photos_by_file: dict[str, _PhotoSpec],
) -> dict[str, dict[str, Any]]:
    matched: dict[str, dict[str, Any]] = {}
    for task in tasks:
        basename = _image_basename(task)
        hits = [
            photo.file
            for photo in photos_by_file.values()
            if _file_matches(basename, photo.file)
        ]
        if not hits:
            raise LabelConvertError(f"export task is not in the manifest: {basename}")
        if len(hits) > 1:
            raise LabelConvertError(
                f"export task matches more than one manifest photo: {basename}"
            )
        file_name = hits[0]
        if file_name in matched:
            raise LabelConvertError(
                f"manifest photo matches more than one task: {file_name}"
            )
        matched[file_name] = task
    for file_name in photos_by_file:
        if file_name not in matched:
            raise LabelConvertError(f"manifest photo has no task: {file_name}")
    return matched


def _image_basename(task: dict[str, Any]) -> str:
    data = task.get("data")
    if not isinstance(data, dict):
        raise LabelConvertError("task data must be an object")
    image = data.get("image")
    if not isinstance(image, str) or image.strip() == "":
        raise LabelConvertError("task has no image")
    path = image.split("?", 1)[0].split("#", 1)[0]
    basename = path.rstrip("/").rsplit("/", 1)[-1]
    if basename == "":
        raise LabelConvertError("task has no image")
    return basename


def _file_matches(basename: str, file_name: str) -> bool:
    if basename == file_name:
        return True
    prefix, sep, rest = basename.partition("-")
    if sep != "-" or rest != file_name or len(prefix) < 8:
        return False
    return all(char in _HEX for char in prefix)


def _photo_payload(
    task: dict[str, Any],
    photo: _PhotoSpec,
    parts_by_label: dict[str, _PartSpec],
) -> dict[str, Any]:
    annotation = _choose_annotation(_annotation_list(task))
    results = [] if annotation is None else _result_list(annotation)
    width, height = _image_size(results, photo)
    by_part_id = {part.part_id: part for part in parts_by_label.values()}
    polygons_by_part: dict[str, list[list[tuple[float, float]]]] = {}
    for result in results:
        _reject_image_rotation(result)
        label, polygon = _shape(result)
        part = parts_by_label.get(label)
        if part is None:
            raise LabelConvertError(f"label is not in the manifest: {label}")
        polygons_by_part.setdefault(part.part_id, []).append(polygon)
    regions = [
        {
            "part_id": part_id,
            "polygons": [
                {"points": [{"x": x, "y": y} for x, y in polygon]}
                for polygon in polygons
            ],
            "confirmation": dict(by_part_id[part_id].confirmation),
        }
        for part_id, polygons in polygons_by_part.items()
    ]
    return {
        "bay_photo_id": photo.bay_photo_id,
        "angle_id": photo.angle_id,
        "image_size": {"width": width, "height": height},
        "source": {"kind": photo.source.kind, "reference": photo.source.reference},
        "license": {"name": photo.license.name, "reference": photo.license.reference},
        "regions": regions,
    }


def _require_every_part_used(
    photos: list[dict[str, Any]], parts: tuple[_PartSpec, ...]
) -> None:
    used = {region["part_id"] for photo in photos for region in photo["regions"]}
    for part in parts:
        if part.part_id not in used:
            raise LabelConvertError(f"manifest part has no region: {part.label}")


def _annotation_list(task: dict[str, Any]) -> list[dict[str, Any]]:
    raw = task.get("annotations", [])
    if not isinstance(raw, list):
        raise LabelConvertError("annotations must be an array")
    return [_object(item, "annotation") for item in raw]


def _choose_annotation(annotations: list[dict[str, Any]]) -> dict[str, Any] | None:
    active = [item for item in annotations if not _flag(item, "was_cancelled")]
    if not active:
        return None
    truth = [item for item in active if _flag(item, "ground_truth")]
    if len(truth) > 1:
        raise LabelConvertError("task has more than one ground_truth annotation")
    if len(truth) == 1:
        return truth[0]
    if len(active) == 1:
        return active[0]
    chosen: dict[str, Any] | None = None
    best_id: int | None = None
    for item in active:
        raw_id = item.get("id")
        if isinstance(raw_id, bool) or not isinstance(raw_id, int):
            raise LabelConvertError(
                "task has more than one annotation; mark one ground_truth"
            )
        if best_id is None or raw_id > best_id:
            best_id = raw_id
            chosen = item
        elif raw_id == best_id:
            raise LabelConvertError(
                "task has more than one annotation with the same id"
            )
    return chosen


def _result_list(annotation: dict[str, Any]) -> list[dict[str, Any]]:
    raw = annotation.get("result", [])
    if not isinstance(raw, list):
        raise LabelConvertError("annotation result must be an array")
    return [_object(item, "result") for item in raw]


def _image_size(results: list[dict[str, Any]], photo: _PhotoSpec) -> tuple[int, int]:
    found: tuple[int, int] | None = None
    for result in results:
        has_width = "original_width" in result
        has_height = "original_height" in result
        if has_width != has_height:
            raise LabelConvertError("annotation result is missing original_width")
        if not has_width:
            continue
        size = (
            _positive_int(result["original_width"], "original_width"),
            _positive_int(result["original_height"], "original_height"),
        )
        if found is None:
            found = size
        elif found != size:
            raise LabelConvertError("annotation results disagree on image size")
    if photo.width is not None and photo.height is not None:
        declared = (photo.width, photo.height)
        if found is not None and found != declared:
            raise LabelConvertError("image size does not match the manifest")
        return declared
    if found is None:
        if not results:
            raise LabelConvertError(f"photo has no image size: {photo.file}")
        raise LabelConvertError("annotation result is missing original_width")
    return found


def _shape(result: dict[str, Any]) -> tuple[str, list[tuple[float, float]]]:
    result_type = result.get("type")
    if not isinstance(result_type, str):
        raise LabelConvertError("result type is missing")
    value = _object(result.get("value"), "result value")
    if result_type == "polygonlabels":
        return _one_label(value, "polygonlabels"), _polygon_points(value)
    if result_type == "rectanglelabels":
        return _one_label(value, "rectanglelabels"), _rectangle_points(value)
    raise LabelConvertError(
        f"result type is not polygonlabels or rectanglelabels: {result_type}"
    )


def _polygon_points(value: dict[str, Any]) -> list[tuple[float, float]]:
    raw = value.get("points")
    if not isinstance(raw, list):
        raise LabelConvertError("polygon points must be an array")
    points: list[tuple[float, float]] = []
    for point in raw:
        if not isinstance(point, list) or len(point) != 2:
            raise LabelConvertError("polygon point must be an x, y pair")
        points.append(
            (_percent(point[0], "polygon x"), _percent(point[1], "polygon y"))
        )
    # Label Studio sometimes repeats the first point. The bay map loader rejects that ring.
    if len(points) >= 4 and points[0] == points[-1]:
        points = points[:-1]
    if len(points) < 3:
        raise LabelConvertError("polygon needs at least 3 points")
    return points


def _rectangle_points(value: dict[str, Any]) -> list[tuple[float, float]]:
    rotation = value.get("rotation", 0)
    if (
        isinstance(rotation, bool)
        or not isinstance(rotation, (int, float))
        or rotation != 0
    ):
        raise LabelConvertError("rotated rectangle is not converted")
    x = _number(value.get("x"), "rectangle x")
    y = _number(value.get("y"), "rectangle y")
    width = _number(value.get("width"), "rectangle width")
    height = _number(value.get("height"), "rectangle height")
    if width <= 0 or height <= 0:
        raise LabelConvertError("rectangle width or height is not positive")
    if x + width > 100 + _PERCENT_SLACK or y + height > 100 + _PERCENT_SLACK:
        raise LabelConvertError("rectangle extends outside the image")
    return [
        (_percent(x, "rectangle x"), _percent(y, "rectangle y")),
        (_percent(x + width, "rectangle x"), _percent(y, "rectangle y")),
        (_percent(x + width, "rectangle x"), _percent(y + height, "rectangle y")),
        (_percent(x, "rectangle x"), _percent(y + height, "rectangle y")),
    ]


def _one_label(value: dict[str, Any], key: str) -> str:
    raw = value.get(key)
    if not isinstance(raw, list) or len(raw) == 0:
        raise LabelConvertError("region has no label")
    if len(raw) != 1 or not isinstance(raw[0], str) or raw[0] == "":
        raise LabelConvertError("region has more than one label")
    return raw[0]


def _reject_image_rotation(result: dict[str, Any]) -> None:
    rotation = result.get("image_rotation", 0)
    if (
        isinstance(rotation, bool)
        or not isinstance(rotation, (int, float))
        or rotation != 0
    ):
        raise LabelConvertError("image_rotation is not 0")


def _source(value: Any, what: str) -> _NamedRef:
    obj = _object(value, what)
    _exact_keys(obj, {"kind", "reference"}, {"kind", "reference"}, what)
    kind = _req_str(obj, "kind", what)
    if kind not in _SOURCE_KINDS:
        raise LabelConvertError(
            f"{what} kind is not public_prototype or owner_observation"
        )
    return _NamedRef(kind=kind, reference=_req_str(obj, "reference", what))


def _license(value: Any, what: str) -> _License:
    obj = _object(value, what)
    _exact_keys(obj, {"name", "reference"}, {"name", "reference"}, what)
    return _License(
        name=_req_str(obj, "name", what), reference=_req_str(obj, "reference", what)
    )


def _confirmation(value: Any, what: str) -> dict[str, str]:
    obj = _object(value, what)
    kind = obj.get("kind")
    if kind == "unconfirmed":
        _exact_keys(obj, {"kind"}, {"kind"}, what)
        return {"kind": "unconfirmed"}
    if kind == "confirmed":
        _exact_keys(obj, {"kind", "confirmed_by"}, {"kind", "confirmed_by"}, what)
        return {
            "kind": "confirmed",
            "confirmed_by": _req_str(obj, "confirmed_by", what),
        }
    raise LabelConvertError(f"{what} kind is not confirmed or unconfirmed")


def _optional_size(obj: dict[str, Any], what: str) -> tuple[int | None, int | None]:
    has_width = "width" in obj
    has_height = "height" in obj
    if has_width != has_height:
        raise LabelConvertError(f"{what} width and height must both be set")
    if not has_width:
        return None, None
    return _positive_int(obj["width"], f"{what} width"), _positive_int(
        obj["height"], f"{what} height"
    )


def _object(value: Any, what: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise LabelConvertError(f"{what} must be an object")
    return value


def _exact_keys(
    obj: dict[str, Any], allowed: set[str], required: set[str], what: str
) -> None:
    missing = sorted(required - obj.keys())
    extra = sorted(set(obj.keys()) - allowed)
    if missing:
        raise LabelConvertError(f"{what} is missing {missing[0]}")
    if extra:
        raise LabelConvertError(f"{what} has unknown field {extra[0]}")


def _blank_string(value: Any) -> bool:
    return not isinstance(value, str) or value == ""


def _req_str(obj: dict[str, Any], key: str, what: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or value == "":
        raise LabelConvertError(f"{what} {key} must be a non-empty string")
    return value


def _flag(obj: dict[str, Any], key: str) -> bool:
    value = obj.get(key, False)
    if not isinstance(value, bool):
        raise LabelConvertError(f"annotation {key} must be a boolean")
    return value


def _positive_int(value: Any, what: str) -> int:
    if isinstance(value, bool):
        raise LabelConvertError(f"{what} must be an integer >= 1")
    if isinstance(value, int):
        number = value
    elif isinstance(value, float) and value.is_integer():
        number = int(value)
    else:
        raise LabelConvertError(f"{what} must be an integer >= 1")
    if number < 1:
        raise LabelConvertError(f"{what} must be an integer >= 1")
    return number


def _number(value: Any, what: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise LabelConvertError(f"{what} is not a number")
    return float(value)


def _percent(value: Any, what: str) -> float:
    number = _number(value, what)
    if number < -_PERCENT_SLACK or number > 100 + _PERCENT_SLACK:
        raise LabelConvertError(f"{what} is outside the image")
    clamped = min(100.0, max(0.0, number))
    return clamped / 100.0


if __name__ == "__main__":
    raise SystemExit(main())
