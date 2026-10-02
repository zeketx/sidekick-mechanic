"""Label Studio JSON → bay map. Fixtures use FAKE-* ids, never catalog part numbers."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema.validators import Draft202012Validator

from bay_map import BayPoint, load_bay_map
from bay_map_labels import LabelConvertError, convert_label_studio_export, main

FIXTURES = Path(__file__).resolve().parent / "fixtures"
EXPORT_PATH = FIXTURES / "fake-label-studio-export.json"
MANIFEST_PATH = FIXTURES / "fake-label-manifest.json"
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "contracts" / "bay_map.schema.json"


def _pair() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    export = json.loads(EXPORT_PATH.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    assert isinstance(export, list)
    assert isinstance(manifest, dict)
    return export, manifest


def _active_results(
    export: list[dict[str, Any]], basename: str
) -> list[dict[str, Any]]:
    for task in export:
        image = task["data"]["image"]
        if basename in image:
            for annotation in task["annotations"]:
                if annotation["was_cancelled"] is False:
                    result = annotation["result"]
                    assert isinstance(result, list)
                    return result
    raise AssertionError(basename)


def test_fixture_converts_to_a_schema_valid_bay_map() -> None:
    export, manifest = _pair()
    cancelled = export[0]["annotations"][0]
    assert cancelled["was_cancelled"] is True
    assert cancelled["result"][0]["value"]["polygonlabels"] == ["NOT-A-MANIFEST-LABEL"]
    assert export[0]["predictions"][0]["result"][0]["value"]["rectanglelabels"] == [
        "NOT-A-MANIFEST-LABEL"
    ]

    payload = convert_label_studio_export(export, manifest)
    Draft202012Validator(json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))).validate(
        payload
    )
    bay_map = load_bay_map(json.dumps(payload).encode("utf-8"))

    assert payload["schema_version"] == 1
    assert payload["coordinate_space"] == {
        "units": "normalized",
        "origin": "top_left",
        "x_axis": "right",
        "y_axis": "down",
    }
    assert payload["parts"] == [
        {
            "part_id": "fake-part-hidden",
            "display_name": "FAKE-NAME-HIDDEN",
            "aliases": [],
        },
        {
            "part_id": "fake-part-intake",
            "display_name": "FAKE-NAME-INTAKE",
            "aliases": ["FAKE-ALIAS-INTAKE"],
        },
    ]
    assert [part.part_id for part in bay_map.parts] == [
        "fake-part-hidden",
        "fake-part-intake",
    ]

    front = payload["photos"][0]
    assert front["bay_photo_id"] == "fake-bay-photo-front"
    assert front["angle_id"] == "fake-angle-front"
    assert front["image_size"] == {"width": 200, "height": 100}
    assert front["source"] == {"kind": "public_prototype", "reference": "FAKE-SOURCE"}
    assert front["license"] == {"name": "FAKE-LICENSE", "reference": "FAKE-LICENSE-REF"}
    assert front["regions"][0] == {
        "part_id": "fake-part-hidden",
        "polygons": [
            {
                "points": [
                    {"x": 0.5, "y": 0.0},
                    {"x": 1.0, "y": 0.0},
                    {"x": 1.0, "y": 0.5},
                    {"x": 0.5, "y": 0.5},
                ]
            }
        ],
        "confirmation": {"kind": "unconfirmed"},
    }
    assert front["regions"][1]["part_id"] == "fake-part-intake"
    assert front["regions"][1]["confirmation"] == {
        "kind": "confirmed",
        "confirmed_by": "FAKE-OWNER",
    }
    assert front["regions"][1]["polygons"] == [
        {"points": [{"x": 0.0, "y": 0.0}, {"x": 0.5, "y": 0.0}, {"x": 0.5, "y": 0.5}]},
        {"points": [{"x": 0.0, "y": 0.5}, {"x": 0.5, "y": 0.5}, {"x": 0.5, "y": 1.0}]},
    ]

    side = payload["photos"][1]
    assert side["bay_photo_id"] == "fake-bay-photo-side"
    assert side["angle_id"] == "fake-angle-side"
    assert side["image_size"] == {"width": 400, "height": 400}
    assert side["source"] == {"kind": "owner_observation", "reference": "FAKE-OBS-SIDE"}
    assert side["license"] == {
        "name": "FAKE-LICENSE-SIDE",
        "reference": "FAKE-LICENSE-SIDE-REF",
    }
    assert side["regions"] == [
        {
            "part_id": "fake-part-intake",
            "polygons": [
                {
                    "points": [
                        {"x": 0.0, "y": 0.0},
                        {"x": 1.0, "y": 0.0},
                        {"x": 1.0, "y": 1.0},
                        {"x": 0.0, "y": 1.0},
                    ]
                }
            ],
            "confirmation": {"kind": "confirmed", "confirmed_by": "FAKE-OWNER"},
        }
    ]

    assert [
        (choice.part_id, choice.bay_photo_id) for choice in bay_map.highlight_choices
    ] == [
        ("fake-part-intake", "fake-bay-photo-side"),
    ]
    assert bay_map.resolve("fake-bay-photo-front", "fake-part-hidden") is None
    intake = bay_map.resolve("fake-bay-photo-front", "fake-part-intake")
    assert intake is not None
    assert intake.confirmed_by == "FAKE-OWNER"
    assert intake.polygons[0].points == (
        BayPoint(0, 0),
        BayPoint(0.5, 0),
        BayPoint(0.5, 0.5),
    )
    assert len(intake.polygons) == 2


def test_greatest_annotation_id_wins_unless_one_is_ground_truth() -> None:
    low = _box(10, annotation_id=1)
    high = _box(20, annotation_id=2)
    export, manifest = _tiny([low, high])
    payload = convert_label_studio_export(export, manifest)
    assert payload["photos"][0]["regions"][0]["polygons"][0]["points"][0] == {
        "x": 0.2,
        "y": 0.0,
    }

    low["ground_truth"] = True
    export, manifest = _tiny([low, high])
    payload = convert_label_studio_export(export, manifest)
    assert payload["photos"][0]["regions"][0]["polygons"][0]["points"][0] == {
        "x": 0.1,
        "y": 0.0,
    }


def test_two_ground_truth_annotations_fail() -> None:
    export, manifest = _tiny(
        [
            _box(10, annotation_id=1, ground_truth=True),
            _box(20, annotation_id=2, ground_truth=True),
        ]
    )
    with pytest.raises(LabelConvertError, match="more than one ground_truth"):
        convert_label_studio_export(export, manifest)


def test_manifest_size_fills_a_result_that_omits_original_width() -> None:
    export, manifest = _pair()
    for task in export:
        for annotation in task["annotations"]:
            for result in annotation["result"]:
                result.pop("original_width", None)
                result.pop("original_height", None)
    manifest["photos"][0]["width"] = 200
    manifest["photos"][0]["height"] = 100
    manifest["photos"][1]["width"] = 400
    manifest["photos"][1]["height"] = 400
    payload = convert_label_studio_export(export, manifest)
    assert payload["photos"][0]["image_size"] == {"width": 200, "height": 100}
    assert payload["photos"][1]["image_size"] == {"width": 400, "height": 400}


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        ("rotated", "rotated rectangle is not converted"),
        ("outside", "polygon x is outside the image"),
        ("brush", "result type is not polygonlabels or rectanglelabels: brushlabels"),
        ("unknown", "label is not in the manifest: FAKE-PART-MISSING"),
        ("missing_photo", "manifest photo has no task: FAKE-missing.jpg"),
        ("size_mismatch", "image size does not match the manifest"),
        ("unused_part", "manifest part has no region: FAKE-PART-UNUSED"),
        ("bad_prefix", "export task is not in the manifest: nothex-FAKE-front.jpg"),
    ],
)
def test_convert_rejects(mutate: str, message: str) -> None:
    export, manifest = _pair()
    if mutate == "rotated":
        _active_results(export, "FAKE-front.jpg")[2]["value"]["rotation"] = 15
    elif mutate == "outside":
        _active_results(export, "FAKE-front.jpg")[0]["value"]["points"][1][0] = 120
    elif mutate == "brush":
        _active_results(export, "FAKE-front.jpg")[0]["type"] = "brushlabels"
    elif mutate == "unknown":
        _active_results(export, "FAKE-front.jpg")[2]["value"]["rectanglelabels"] = [
            "FAKE-PART-MISSING"
        ]
    elif mutate == "missing_photo":
        manifest["photos"].append(
            {
                "file": "FAKE-missing.jpg",
                "bay_photo_id": "fake-bay-photo-missing",
                "angle_id": "fake-angle-missing",
            }
        )
    elif mutate == "size_mismatch":
        manifest["photos"][0]["width"] = 10
        manifest["photos"][0]["height"] = 10
    elif mutate == "unused_part":
        manifest["parts"].append(
            {
                "label": "FAKE-PART-UNUSED",
                "part_id": "fake-part-unused",
                "display_name": "FAKE-NAME-UNUSED",
                "aliases": [],
            }
        )
    elif mutate == "bad_prefix":
        export[0]["data"]["image"] = "/data/upload/1/nothex-FAKE-front.jpg"
    with pytest.raises(LabelConvertError, match=message):
        convert_label_studio_export(export, manifest)


def test_cli_writes_a_bay_map_and_a_failure_writes_nothing(tmp_path: Path) -> None:
    output = tmp_path / "bay-map.json"
    assert (
        main(
            [
                "--export",
                str(EXPORT_PATH),
                "--manifest",
                str(MANIFEST_PATH),
                "--output",
                str(output),
            ]
        )
        == 0
    )
    payload = json.loads(output.read_text(encoding="utf-8"))
    Draft202012Validator(json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))).validate(
        payload
    )
    assert payload["photos"][0]["bay_photo_id"] == "fake-bay-photo-front"

    broken = tmp_path / "broken.json"
    export = json.loads(EXPORT_PATH.read_text(encoding="utf-8"))
    export[0]["annotations"][1]["result"][2]["value"]["rotation"] = 15
    export_path = tmp_path / "export.json"
    export_path.write_text(json.dumps(export), encoding="utf-8")
    assert (
        main(
            [
                "--export",
                str(export_path),
                "--manifest",
                str(MANIFEST_PATH),
                "--output",
                str(broken),
            ]
        )
        == 1
    )
    assert not broken.exists()


def _box(x: float, *, annotation_id: int, ground_truth: bool = False) -> dict[str, Any]:
    return {
        "id": annotation_id,
        "was_cancelled": False,
        "ground_truth": ground_truth,
        "result": [
            {
                "type": "rectanglelabels",
                "original_width": 100,
                "original_height": 100,
                "image_rotation": 0,
                "value": {
                    "x": x,
                    "y": 0,
                    "width": 10,
                    "height": 10,
                    "rotation": 0,
                    "rectanglelabels": ["FAKE-PART-INTAKE"],
                },
            }
        ],
    }


def _tiny(
    annotations: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    export = [{"id": 1, "data": {"image": "FAKE-only.jpg"}, "annotations": annotations}]
    manifest = {
        "source": {"kind": "public_prototype", "reference": "FAKE-SOURCE"},
        "license": {"name": "FAKE-LICENSE", "reference": "FAKE-LICENSE-REF"},
        "photos": [
            {
                "file": "FAKE-only.jpg",
                "bay_photo_id": "fake-bay-photo-only",
                "angle_id": "fake-angle-only",
            }
        ],
        "parts": [
            {
                "label": "FAKE-PART-INTAKE",
                "part_id": "fake-part-intake",
                "display_name": "FAKE-NAME-INTAKE",
                "aliases": [],
                "confirmation": {"kind": "confirmed", "confirmed_by": "FAKE-OWNER"},
            }
        ],
    }
    return export, manifest
