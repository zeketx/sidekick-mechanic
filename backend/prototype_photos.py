"""Validate and fetch public prototype bay photos.

The files themselves stay outside git, in bay-photos/prototype/.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

_REPO_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_MANIFEST = (
    Path(__file__).resolve().parent / "data" / "prototype_bay_photos.json"
)
_DEFAULT_DEST = _REPO_ROOT / "bay-photos" / "prototype"

SHOT_LIST_ANGLES = (
    "front",
    "overhead",
    "vehicle-left",
    "vehicle-right",
    "firewall",
)
PROTOTYPE_LABEL = "Prototype stand-in. Not Zeke's truck. Replaced in M5."
REQUESTED_MIN = 10
REQUESTED_MAX = 20
_SHA256_RE_LENGTH = 64
_JPEG_MAGIC = b"\xff\xd8\xff"
_USER_AGENT = "SidekickMechanicPrototypePhotos/1.0"

Opener = Callable[[str], bytes]


class PrototypePhotoError(Exception):
    """The manifest is invalid or a download does not match it."""


@dataclass(frozen=True)
class PrototypePhoto:
    id: str
    filename: str
    angle_id: str
    angle_note: str
    label: str
    owners_truck: bool
    source_url: str
    download_url: str
    author: str
    author_url: str
    license: str
    license_url: str
    license_evidence: str
    attribution: str
    source_subject: str
    media_type: str
    sha256: str
    byte_size: int
    width: int
    height: int


@dataclass(frozen=True)
class PrototypeGaps:
    below_requested_range: bool
    requested_min: int
    requested_max: int
    verified_count: int
    missing_angles: tuple[str, ...]
    summary: str
    excluded: tuple[str, ...]


@dataclass(frozen=True)
class PrototypeManifest:
    label: str
    replaced_in: str
    owners_truck: bool
    shot_list_source: str
    shot_list_angles: tuple[str, ...]
    angles: dict[str, tuple[str, ...]]
    gaps: PrototypeGaps
    photos: tuple[PrototypePhoto, ...]


def load_manifest(path: Path) -> PrototypeManifest:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise PrototypePhotoError(f"missing manifest: {path}") from exc
    except json.JSONDecodeError as exc:
        raise PrototypePhotoError(f"manifest is not JSON: {path}") from exc
    if not isinstance(payload, dict):
        raise PrototypePhotoError("manifest must be a JSON object")
    return _manifest_from_payload(payload)


def fetch_photos(
    manifest: PrototypeManifest,
    dest: Path,
    opener: Opener | None = None,
) -> list[Path]:
    """Download each photo into dest. Returns paths whose bytes match the manifest."""
    download = opener if opener is not None else _download
    dest.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for photo in manifest.photos:
        target = dest / photo.filename
        if target.is_file() and _sha256(target.read_bytes()) == photo.sha256:
            written.append(target)
            continue
        data = download(photo.download_url)
        _check_bytes(photo, data)
        target.write_bytes(data)
        written.append(target)
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate or fetch prototype bay photos."
    )
    parser.add_argument("command", choices=("validate", "fetch"))
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--dest", type=Path, default=_DEFAULT_DEST)
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        if args.command == "fetch":
            paths = fetch_photos(manifest, args.dest)
            print(f"fetched {len(paths)} photo(s) into {args.dest}")
        else:
            print(f"validated {len(manifest.photos)} photo(s)")
    except PrototypePhotoError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


def _manifest_from_payload(payload: dict[str, object]) -> PrototypeManifest:
    label = _require_str(payload, "label")
    if label != PROTOTYPE_LABEL:
        raise PrototypePhotoError(f"manifest label must be {PROTOTYPE_LABEL!r}")
    if payload.get("owners_truck") is not False:
        raise PrototypePhotoError("owners_truck must be false")
    if payload.get("replaced_in") != "M5":
        raise PrototypePhotoError("replaced_in must be M5")
    if payload.get("shot_list_angles") != list(SHOT_LIST_ANGLES):
        raise PrototypePhotoError(
            "shot_list_angles must be the five DAY_ONE.md angle ids"
        )
    shot_list_source = _require_str(payload, "shot_list_source")
    photos = _photos(payload.get("photos"))
    angles = _angle_groups(payload.get("angles"), photos)
    gaps = _gaps(payload.get("gaps"), photos, angles)
    return PrototypeManifest(
        label=label,
        replaced_in="M5",
        owners_truck=False,
        shot_list_source=shot_list_source,
        shot_list_angles=SHOT_LIST_ANGLES,
        angles=angles,
        gaps=gaps,
        photos=photos,
    )


def _photos(raw: object) -> tuple[PrototypePhoto, ...]:
    if not isinstance(raw, list) or not raw:
        raise PrototypePhotoError("manifest needs at least one photo")
    photos: list[PrototypePhoto] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            raise PrototypePhotoError("each photo must be an object")
        photo = _photo(item)
        if photo.id in seen:
            raise PrototypePhotoError(f"duplicate photo id: {photo.id}")
        seen.add(photo.id)
        photos.append(photo)
    return tuple(photos)


def _photo(item: dict[str, object]) -> PrototypePhoto:
    photo_id = _require_str(item, "id")
    if not _safe_id(photo_id):
        raise PrototypePhotoError(f"invalid photo id: {photo_id!r}")
    filename = _require_str(item, "filename")
    if Path(filename).name != filename or not filename.endswith(".jpg"):
        raise PrototypePhotoError(f"unsafe filename for {photo_id}: {filename!r}")
    angle_id = _require_str(item, "angle_id")
    if angle_id not in SHOT_LIST_ANGLES:
        raise PrototypePhotoError(f"{photo_id} has unknown angle {angle_id!r}")
    if item.get("label") != PROTOTYPE_LABEL:
        raise PrototypePhotoError(f"{photo_id} is missing the prototype label")
    if item.get("owners_truck") is not False:
        raise PrototypePhotoError(f"{photo_id} must set owners_truck to false")
    license_name = _require_str(item, "license")
    if not _license_allowed(license_name):
        raise PrototypePhotoError(
            f"{photo_id} license {license_name!r} is not CC0, CC BY, or CC BY-SA"
        )
    subject = _require_str(item, "source_subject")
    if "2JZ-GE" not in subject:
        raise PrototypePhotoError(
            f"{photo_id} source_subject does not name 2JZ-GE"
        )
    author = _require_str(item, "author")
    attribution = _require_str(item, "attribution")
    if author not in attribution:
        raise PrototypePhotoError(f"{photo_id} attribution does not name the author")
    license_evidence = _require_str(item, "license_evidence")
    return PrototypePhoto(
        id=photo_id,
        filename=filename,
        angle_id=angle_id,
        angle_note=_require_str(item, "angle_note"),
        label=PROTOTYPE_LABEL,
        owners_truck=False,
        source_url=_https(item, "source_url", photo_id),
        download_url=_https(item, "download_url", photo_id),
        author=author,
        author_url=_https(item, "author_url", photo_id),
        license=license_name,
        license_url=_https(item, "license_url", photo_id),
        license_evidence=license_evidence,
        attribution=attribution,
        source_subject=subject,
        media_type=_media_type(item, photo_id),
        sha256=_sha256_field(item, photo_id),
        byte_size=_positive_int(item, "byte_size", photo_id),
        width=_positive_int(item, "width", photo_id),
        height=_positive_int(item, "height", photo_id),
    )


def _angle_groups(
    raw: object, photos: tuple[PrototypePhoto, ...]
) -> dict[str, tuple[str, ...]]:
    if not isinstance(raw, dict):
        raise PrototypePhotoError("angles must be an object")
    if list(raw) != list(SHOT_LIST_ANGLES):
        raise PrototypePhotoError("angles must list the five shot-list ids in order")
    expected = {photo.id: photo.angle_id for photo in photos}
    seen: set[str] = set()
    groups: dict[str, tuple[str, ...]] = {}
    for angle_id in SHOT_LIST_ANGLES:
        members = raw[angle_id]
        if not isinstance(members, list) or not all(
            isinstance(item, str) for item in members
        ):
            raise PrototypePhotoError(f"angle {angle_id} must be a list of photo ids")
        for photo_id in members:
            if photo_id in seen:
                raise PrototypePhotoError(f"photo {photo_id} is in more than one angle")
            if expected.get(photo_id) != angle_id:
                raise PrototypePhotoError(
                    f"photo {photo_id} is grouped under {angle_id} but not declared there"
                )
            seen.add(photo_id)
        groups[angle_id] = tuple(members)
    missing = set(expected) - seen
    if missing:
        raise PrototypePhotoError(
            "photos missing from angle groups: " + ", ".join(sorted(missing))
        )
    return groups


def _gaps(
    raw: object,
    photos: tuple[PrototypePhoto, ...],
    angles: dict[str, tuple[str, ...]],
) -> PrototypeGaps:
    if not isinstance(raw, dict):
        raise PrototypePhotoError("gaps must be an object")
    count = len(photos)
    below = raw.get("below_requested_range")
    if not isinstance(below, bool):
        raise PrototypePhotoError("gaps.below_requested_range must be a boolean")
    in_range = REQUESTED_MIN <= count <= REQUESTED_MAX
    if below == in_range:
        raise PrototypePhotoError(
            "gaps.below_requested_range does not match the photo count"
        )
    if raw.get("verified_count") != count:
        raise PrototypePhotoError("gaps.verified_count does not match the photo list")
    if raw.get("requested_min") != REQUESTED_MIN or raw.get("requested_max") != REQUESTED_MAX:
        raise PrototypePhotoError("gaps requested range must be 10 to 20")
    empty = tuple(angle for angle, members in angles.items() if not members)
    if raw.get("missing_angles") != list(empty):
        raise PrototypePhotoError(
            "gaps.missing_angles must be the empty angle groups"
        )
    summary = _require_str(raw, "summary")
    excluded_raw = raw.get("excluded")
    if not isinstance(excluded_raw, list) or not excluded_raw:
        raise PrototypePhotoError("gaps.excluded must list what was left out")
    if not all(isinstance(item, str) and item.strip() for item in excluded_raw):
        raise PrototypePhotoError("gaps.excluded entries must be non-empty strings")
    return PrototypeGaps(
        below_requested_range=below,
        requested_min=REQUESTED_MIN,
        requested_max=REQUESTED_MAX,
        verified_count=count,
        missing_angles=empty,
        summary=summary,
        excluded=tuple(excluded_raw),
    )


def _check_bytes(photo: PrototypePhoto, data: bytes) -> None:
    if len(data) != photo.byte_size:
        raise PrototypePhotoError(
            f"{photo.id} byte_size: expected {photo.byte_size} got {len(data)}"
        )
    digest = _sha256(data)
    if digest != photo.sha256:
        raise PrototypePhotoError(
            f"{photo.id} checksum mismatch: expected {photo.sha256} got {digest}"
        )
    if photo.media_type == "image/jpeg" and not data.startswith(_JPEG_MAGIC):
        raise PrototypePhotoError(f"{photo.id} is not a JPEG")


def _download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.read()
    except OSError as exc:
        raise PrototypePhotoError(f"download failed for {url}: {exc}") from exc


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _license_allowed(name: str) -> bool:
    if name == "CC0" or name.startswith("CC0 "):
        return True
    if name == "CC BY-SA" or name.startswith("CC BY-SA "):
        return True
    if name == "CC BY" or name.startswith("CC BY "):
        return True
    return False


def _safe_id(value: str) -> bool:
    if not value or value[0] not in "abcdefghijklmnopqrstuvwxyz":
        return False
    return all(char.islower() or char.isdigit() or char == "-" for char in value)


def _https(item: dict[str, object], key: str, photo_id: str) -> str:
    value = _require_str(item, key)
    if not value.startswith("https://"):
        raise PrototypePhotoError(f"{photo_id} {key} must be https")
    return value


def _media_type(item: dict[str, object], photo_id: str) -> str:
    value = _require_str(item, "media_type")
    if value != "image/jpeg":
        raise PrototypePhotoError(f"{photo_id} media_type must be image/jpeg")
    return value


def _sha256_field(item: dict[str, object], photo_id: str) -> str:
    value = _require_str(item, "sha256").lower()
    if len(value) != _SHA256_RE_LENGTH or any(
        char not in "0123456789abcdef" for char in value
    ):
        raise PrototypePhotoError(f"{photo_id} has an invalid SHA-256")
    return value


def _positive_int(item: dict[str, object], key: str, photo_id: str) -> int:
    value = item.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise PrototypePhotoError(f"{photo_id} {key} must be a positive integer")
    return value


def _require_str(item: dict[str, object], key: str) -> str:
    value = item.get(key)
    if not isinstance(value, str) or not value.strip():
        raise PrototypePhotoError(f"missing {key}")
    return value


if __name__ == "__main__":
    sys.exit(main())
