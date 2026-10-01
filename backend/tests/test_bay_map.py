from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema.validators import Draft202012Validator

from bay_map import BayMapError, BayPoint, load_bay_map

CONTRACTS_DIR = Path(__file__).resolve().parents[1] / "contracts"
SCHEMA_PATH = CONTRACTS_DIR / "bay_map.schema.json"
FIXTURE_PATH = CONTRACTS_DIR / "fixtures" / "bay-map" / "fake-bay-map.json"


def _schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def _fixture() -> dict[str, Any]:
    payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    assert isinstance(payload, dict)
    return payload


def _minimal() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "coordinate_space": {
            "units": "normalized",
            "origin": "top_left",
            "x_axis": "right",
            "y_axis": "down",
        },
        "parts": [
            {
                "part_id": "fake-part-intake",
                "display_name": "FAKE-NAME-INTAKE",
                "aliases": [],
            }
        ],
        "photos": [
            {
                "bay_photo_id": "fake-bay-photo-front",
                "angle_id": "fake-angle-front",
                "image_size": {"width": 8, "height": 8},
                "source": {"kind": "public_prototype", "reference": "FAKE-SOURCE"},
                "license": {"name": "FAKE-LICENSE", "reference": "FAKE-LICENSE-REF"},
                "regions": [
                    {
                        "part_id": "fake-part-intake",
                        "polygons": [
                            {
                                "points": [
                                    {"x": 0, "y": 0},
                                    {"x": 0.5, "y": 0},
                                    {"x": 0.5, "y": 0.5},
                                ]
                            }
                        ],
                        "confirmation": {"kind": "confirmed", "confirmed_by": "FAKE-OWNER"},
                    }
                ],
            }
        ],
    }


def test_fixture_matches_schema_and_resolves_confirmed_regions() -> None:
    payload = _fixture()
    Draft202012Validator(_schema()).validate(payload)
    bay_map = load_bay_map(FIXTURE_PATH.read_bytes())

    assert [part.part_id for part in bay_map.parts] == [
        "fake-part-hidden",
        "fake-part-intake",
        "fake-part-tied",
    ]
    assert [(choice.part_id, choice.bay_photo_id) for choice in bay_map.highlight_choices] == [
        ("fake-part-intake", "fake-bay-photo-wide"),
        ("fake-part-tied", "fake-bay-photo-aaa"),
    ]

    front = bay_map.resolve("fake-bay-photo-front", "fake-part-intake")
    assert front is not None
    assert front.confirmed_by == "FAKE-OWNER"
    assert front.photo.width == 100
    assert front.photo.height == 50
    assert front.photo.angle_id == "fake-angle-front"
    assert len(front.polygons) == 2
    assert front.polygons[0].points[0] == BayPoint(0, 0)
    assert front.polygons[0].points[1] == BayPoint(0.5, 0)
    assert front.polygons[0].points[2] == BayPoint(0.5, 0.5)

    wide = bay_map.resolve("fake-bay-photo-wide", "fake-part-intake")
    assert wide is not None
    assert wide.photo.width == 400
    assert wide.photo.height == 400
    assert bay_map.highlight_choices[0].bay_photo_id == "fake-bay-photo-wide"

    assert bay_map.resolve("fake-bay-photo-side", "fake-part-intake") is None
    assert bay_map.resolve("fake-bay-photo-front", "fake-part-hidden") is None
    assert bay_map.resolve("fake-bay-photo-missing", "fake-part-intake") is None

    angles = {photo.bay_photo_id: photo.angle_id for photo in bay_map.photos}
    assert angles["fake-bay-photo-aaa"] == "fake-angle-shared"
    assert angles["fake-bay-photo-mmm"] == "fake-angle-shared"
    assert bay_map.photos[0].license_name == "FAKE-LICENSE"


def test_round_trip_keeps_the_unconfirmed_region() -> None:
    bay_map = load_bay_map(FIXTURE_PATH.read_bytes())
    again = load_bay_map(bay_map.canonical_json())
    assert again.highlight_choices == bay_map.highlight_choices
    assert again.resolve("fake-bay-photo-side", "fake-part-intake") is None
    encoded = json.loads(bay_map.canonical_json())
    side = next(photo for photo in encoded["photos"] if photo["bay_photo_id"] == "fake-bay-photo-side")
    assert side["regions"][0]["confirmation"] == {"kind": "unconfirmed"}


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        ("duplicate_photo", "duplicate bay_photo_id"),
        ("duplicate_region", "duplicate region for bay_photo_id and part_id"),
        ("orphan_part", "part has no region"),
        ("unknown_part", "region part_id is not in parts"),
        ("zero_area", "polygon area must be positive"),
        ("closed_ring", "polygon repeats its first point"),
        ("alias_collision", "alias collides with a part id or display name"),
    ],
)
def test_semantic_rules_reject(mutate: str, message: str) -> None:
    payload = _minimal()
    if mutate == "duplicate_photo":
        payload["photos"].append(json.loads(json.dumps(payload["photos"][0])))
    elif mutate == "duplicate_region":
        payload["photos"][0]["regions"].append(json.loads(json.dumps(payload["photos"][0]["regions"][0])))
    elif mutate == "orphan_part":
        payload["parts"].append(
            {"part_id": "fake-part-hidden", "display_name": "FAKE-NAME-HIDDEN", "aliases": []}
        )
    elif mutate == "unknown_part":
        payload["photos"][0]["regions"][0]["part_id"] = "fake-part-missing"
    elif mutate == "zero_area":
        payload["photos"][0]["regions"][0]["polygons"][0]["points"] = [
            {"x": 0, "y": 0},
            {"x": 0.5, "y": 0},
            {"x": 1, "y": 0},
        ]
    elif mutate == "closed_ring":
        payload["photos"][0]["regions"][0]["polygons"][0]["points"] = [
            {"x": 0, "y": 0},
            {"x": 0.5, "y": 0},
            {"x": 0.5, "y": 0.5},
            {"x": 0, "y": 0},
        ]
    elif mutate == "alias_collision":
        payload["parts"][0]["aliases"] = ["fake-part-intake"]
    with pytest.raises(BayMapError, match=message):
        load_bay_map(json.dumps(payload).encode("utf-8"))


@pytest.mark.parametrize(
    "payload",
    [
        {"schema_version": 1},
        {
            **_minimal(),
            "photos": [
                {
                    **_minimal()["photos"][0],
                    "license": {"name": "FAKE-LICENSE"},
                }
            ],
        },
        {
            **_minimal(),
            "photos": [
                {
                    **_minimal()["photos"][0],
                    "regions": [
                        {
                            **_minimal()["photos"][0]["regions"][0],
                            "confirmation": {"kind": "unconfirmed", "confirmed_by": "FAKE-OWNER"},
                        }
                    ],
                }
            ],
        },
        {
            **_minimal(),
            "coordinate_space": {
                "units": "normalized",
                "origin": "top_left",
                "x_axis": "right",
                "y_axis": "up",
            },
        },
    ],
    ids=["missing_photos", "license_missing_reference", "unconfirmed_with_confirmed_by", "y_axis_up"],
)
def test_schema_rejects_bad_shape(payload: dict[str, Any]) -> None:
    errors = list(Draft202012Validator(_schema()).iter_errors(payload))
    assert errors
