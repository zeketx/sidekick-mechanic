from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from prototype_photos import PrototypePhotoError, fetch_photos, load_manifest, main

MANIFEST = Path(__file__).resolve().parent / "data" / "prototype_bay_photos.json"
_FORBIDDEN_KEYS = {
    "part_id",
    "part_number",
    "parts",
    "torque",
    "pinout",
    "wire_color",
    "connector",
}


def _payload() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def _write(directory: Path, payload: dict) -> Path:
    path = directory / "manifest.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def _keys(value: object, found: set[str]) -> None:
    if isinstance(value, dict):
        found.update(value)
        for child in value.values():
            _keys(child, found)
    elif isinstance(value, list):
        for child in value:
            _keys(child, found)


def test_committed_manifest_records_the_one_verified_photo() -> None:
    manifest = load_manifest(MANIFEST)

    assert manifest.label == "Prototype stand-in. Not Zeke's truck. Replaced in M5."
    assert manifest.replaced_in == "M5"
    assert manifest.owners_truck is False
    assert manifest.shot_list_source == "docs/vehicle/DAY_ONE.md"
    assert manifest.shot_list_angles == (
        "front",
        "overhead",
        "vehicle-left",
        "vehicle-right",
        "firewall",
    )
    assert manifest.angles["front"] == ("hrymx-2jz-ge-25308847029",)
    assert manifest.angles["overhead"] == ()
    assert manifest.angles["vehicle-left"] == ()
    assert manifest.angles["vehicle-right"] == ()
    assert manifest.angles["firewall"] == ()
    assert manifest.gaps.below_requested_range is True
    assert manifest.gaps.requested_min == 10
    assert manifest.gaps.requested_max == 20
    assert manifest.gaps.verified_count == 1
    assert manifest.gaps.missing_angles == (
        "overhead",
        "vehicle-left",
        "vehicle-right",
        "firewall",
    )
    assert "below the 10 to 20" in manifest.gaps.summary
    assert any("2JZ-GTE" in item for item in manifest.gaps.excluded)

    photo = manifest.photos[0]
    assert photo.id == "hrymx-2jz-ge-25308847029"
    assert photo.filename == "hrymx-2jz-ge-25308847029.jpg"
    assert photo.angle_id == "front"
    assert photo.label == manifest.label
    assert photo.owners_truck is False
    assert photo.author == "HRYMX"
    assert photo.author_url == "https://www.flickr.com/photos/henrymaxm/"
    assert photo.license == "CC BY 2.0"
    assert photo.license_url == "https://creativecommons.org/licenses/by/2.0/"
    assert photo.license_evidence == (
        "Flickr photo license field 4 and oEmbed license_id 4, "
        "both CC BY 2.0, checked 2026-10-01."
    )
    assert photo.source_url == "https://www.flickr.com/photos/henrymaxm/25308847029/"
    assert (
        photo.download_url
        == "https://live.staticflickr.com/5713/25308847029_ee56ff65af_o.jpg"
    )
    assert photo.attribution == (
        '"2JZ-GE Engine" by HRYMX, licensed under CC BY 2.0. '
        "https://www.flickr.com/photos/henrymaxm/25308847029/"
    )
    assert photo.source_subject == (
        "Toyota FRS with a 2JZ-GE Engine.\n\n"
        "--\n"
        "Cars and Coffee (Miami)\n"
        "Saturday, November 12th, 2016"
    )
    assert photo.sha256 == (
        "ebe2ead77c0ed06717fbc221c226d1d9fae168ac580869abde3f943b748d7682"
    )
    assert photo.byte_size == 7519365
    assert photo.width == 5184
    assert photo.height == 3456
    assert photo.media_type == "image/jpeg"


def test_committed_manifest_has_no_part_fields() -> None:
    found: set[str] = set()
    _keys(_payload(), found)
    assert found.isdisjoint(_FORBIDDEN_KEYS)


def test_validate_command_accepts_the_committed_manifest() -> None:
    assert main(["validate"]) == 0


def test_rejects_noncommercial_license(tmp_path: Path) -> None:
    payload = _payload()
    payload["photos"][0]["license"] = "CC BY-NC 2.0"

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "CC BY-NC 2.0" in str(caught.value)
    assert "hrymx-2jz-ge-25308847029" in str(caught.value)


def test_rejects_no_derivatives_license(tmp_path: Path) -> None:
    payload = _payload()
    payload["photos"][0]["license"] = "CC BY-ND 2.0"

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "CC BY-ND 2.0" in str(caught.value)


def test_rejects_source_text_that_does_not_name_2jz_ge(tmp_path: Path) -> None:
    payload = _payload()
    payload["photos"][0]["source_subject"] = "Toyota Supra turbo engine bay"

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "does not name 2JZ-GE" in str(caught.value)


def test_rejects_unknown_angle(tmp_path: Path) -> None:
    payload = _payload()
    payload["photos"][0]["angle_id"] = "hood"
    payload["angles"]["front"] = []
    payload["angles"]["hood"] = ["hrymx-2jz-ge-25308847029"]

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "unknown angle 'hood'" in str(caught.value)


def test_rejects_unsafe_filename(tmp_path: Path) -> None:
    payload = _payload()
    payload["photos"][0]["filename"] = "../secret.jpg"

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "unsafe filename" in str(caught.value)


def test_short_set_must_record_the_gap(tmp_path: Path) -> None:
    payload = _payload()
    payload["gaps"]["below_requested_range"] = False

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "below_requested_range" in str(caught.value)


def test_full_range_cannot_keep_the_shortfall_flag(tmp_path: Path) -> None:
    payload = _payload()
    photo = payload["photos"][0]
    photos = []
    for index in range(10):
        item = json.loads(json.dumps(photo))
        item["id"] = f"photo-{index}"
        item["filename"] = f"photo-{index}.jpg"
        photos.append(item)
    payload["photos"] = photos
    payload["angles"] = {angle: [] for angle in payload["shot_list_angles"]}
    payload["angles"]["front"] = [item["id"] for item in photos]
    payload["gaps"]["verified_count"] = 10
    payload["gaps"]["missing_angles"] = [
        "overhead",
        "vehicle-left",
        "vehicle-right",
        "firewall",
    ]
    payload["gaps"]["below_requested_range"] = True

    with pytest.raises(PrototypePhotoError) as caught:
        load_manifest(_write(tmp_path, payload))

    assert "below_requested_range" in str(caught.value)

    payload["gaps"]["below_requested_range"] = False
    manifest = load_manifest(_write(tmp_path, payload))
    assert len(manifest.photos) == 10
    assert manifest.gaps.below_requested_range is False
    assert manifest.gaps.missing_angles == (
        "overhead",
        "vehicle-left",
        "vehicle-right",
        "firewall",
    )


def test_fetch_writes_matching_bytes_and_skips_a_second_download(tmp_path: Path) -> None:
    body = b"\xff\xd8\xffFAKE-JPEG-BYTES"
    payload = _payload()
    payload["photos"][0]["sha256"] = hashlib.sha256(body).hexdigest()
    payload["photos"][0]["byte_size"] = len(body)
    manifest = load_manifest(_write(tmp_path, payload))
    calls = {"count": 0}

    def opener(url: str) -> bytes:
        calls["count"] += 1
        assert url == manifest.photos[0].download_url
        return body

    dest = tmp_path / "prototype"
    written = fetch_photos(manifest, dest, opener)
    assert written == [dest / "hrymx-2jz-ge-25308847029.jpg"]
    assert written[0].read_bytes() == body

    def fail(url: str) -> bytes:
        raise AssertionError(url)

    again = fetch_photos(manifest, dest, fail)
    assert again == written
    assert calls["count"] == 1


def test_fetch_rejects_checksum_mismatch(tmp_path: Path) -> None:
    body = b"\xff\xd8\xffFAKE-JPEG-BYTES"
    payload = _payload()
    payload["photos"][0]["sha256"] = hashlib.sha256(body).hexdigest()
    payload["photos"][0]["byte_size"] = len(body)
    manifest = load_manifest(_write(tmp_path, payload))

    other = b"\xff\xd8\xff" + b"X" * (len(body) - 3)
    with pytest.raises(PrototypePhotoError) as caught:
        fetch_photos(manifest, tmp_path / "out", lambda url: other)

    message = str(caught.value)
    assert "checksum mismatch" in message
    assert "hrymx-2jz-ge-25308847029" in message


def test_fetch_rejects_non_jpeg_bytes(tmp_path: Path) -> None:
    body = b"not-a-jpeg"
    payload = _payload()
    payload["photos"][0]["sha256"] = hashlib.sha256(body).hexdigest()
    payload["photos"][0]["byte_size"] = len(body)
    manifest = load_manifest(_write(tmp_path, payload))

    with pytest.raises(PrototypePhotoError) as caught:
        fetch_photos(manifest, tmp_path / "out", lambda url: body)

    assert "not a JPEG" in str(caught.value)
