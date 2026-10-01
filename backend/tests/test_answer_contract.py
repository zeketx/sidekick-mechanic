from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema.validators import Draft202012Validator

CONTRACTS_DIR = Path(__file__).resolve().parents[1] / "contracts"
SCHEMA_PATH = CONTRACTS_DIR / "answer.schema.json"
FIXTURES_DIR = CONTRACTS_DIR / "fixtures"
REQUIRED_FIXTURES = (
    "plain.json",
    "with_citations.json",
    "with_highlight.json",
    "refusal.json",
)


def _schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def _validator() -> Draft202012Validator:
    return Draft202012Validator(_schema())


def _load_fixture(name: str) -> dict[str, Any]:
    path = FIXTURES_DIR / name
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(payload, dict)
    return payload


def test_required_fixtures_exist() -> None:
    names = {path.name for path in FIXTURES_DIR.glob("*.json")}
    assert names == set(REQUIRED_FIXTURES)


@pytest.mark.parametrize("name", REQUIRED_FIXTURES)
def test_every_fixture_matches_schema(name: str) -> None:
    _validator().validate(_load_fixture(name))


def test_plain_answer_fixture() -> None:
    payload = _load_fixture("plain.json")
    _validator().validate(payload)
    assert payload == {
        "kind": "answer",
        "text": "This is a fixture-only reply with no manual citations.",
        "citations": [],
    }
    assert "highlight" not in payload
    assert "reason" not in payload


def test_citations_fixture() -> None:
    payload = _load_fixture("with_citations.json")
    _validator().validate(payload)
    assert payload["kind"] == "answer"
    assert payload["text"] == (
        "Start with the fake intake path described in the fixture snippet. "
        "This is not a procedure."
    )
    assert payload["citations"] == [
        {
            "doc_id": "FAKE-DOC-2JZ",
            "page": 999,
            "snippet": "FAKE-SNIPPET: no real spec. Value FAKE-SPEC.",
        }
    ]
    assert "highlight" not in payload


def test_highlight_fixture() -> None:
    payload = _load_fixture("with_highlight.json")
    _validator().validate(payload)
    assert payload["kind"] == "answer"
    assert payload["text"] == "Look at the fake intake area on the fixture bay photo."
    assert payload["citations"] == [
        {
            "doc_id": "FAKE-DOC-2JZ",
            "page": 999,
            "snippet": "FAKE-SNIPPET: check the mapped fixture part.",
        }
    ]
    assert payload["highlight"] == {
        "bay_photo_id": "fake-bay-photo-front",
        "part_id": "fake-part-intake",
    }


def test_refusal_fixture() -> None:
    payload = _load_fixture("refusal.json")
    _validator().validate(payload)
    assert payload == {
        "kind": "refusal",
        "text": "Not found in the manual. I do not have a cited page for this.",
        "reason": "not_found_in_manual",
    }
    assert "citations" not in payload
    assert "highlight" not in payload


@pytest.mark.parametrize(
    "payload",
    [
        {
            "kind": "answer",
            "citations": [],
        },
        {
            "kind": "answer",
            "text": "",
            "citations": [],
        },
        {
            "kind": "answer",
            "text": "Missing page on the citation.",
            "citations": [
                {
                    "doc_id": "FAKE-DOC-2JZ",
                    "snippet": "FAKE-SNIPPET",
                }
            ],
        },
        {
            "kind": "answer",
            "text": "Page zero is not a real page.",
            "citations": [
                {
                    "doc_id": "FAKE-DOC-2JZ",
                    "page": 0,
                    "snippet": "FAKE-SNIPPET",
                }
            ],
        },
        {
            "kind": "answer",
            "text": "Highlight without a part.",
            "citations": [],
            "highlight": {
                "bay_photo_id": "fake-bay-photo-front",
            },
        },
        {
            "kind": "refusal",
            "text": "Not found in the manual.",
        },
        {
            "kind": "refusal",
            "text": "Not found in the manual.",
            "reason": "not_found_in_manual",
            "highlight": {
                "bay_photo_id": "fake-bay-photo-front",
                "part_id": "fake-part-intake",
            },
        },
        {
            "kind": "unknown",
            "text": "Not a valid kind.",
            "citations": [],
        },
        {
            "kind": "answer",
            "text": "Extra field.",
            "citations": [],
            "extra": True,
        },
    ],
    ids=[
        "answer_missing_text",
        "answer_empty_text",
        "citation_missing_page",
        "citation_page_zero",
        "highlight_missing_part_id",
        "refusal_missing_reason",
        "refusal_with_highlight",
        "unknown_kind",
        "extra_property",
    ],
)
def test_invalid_payloads_fail_schema(payload: dict[str, Any]) -> None:
    errors = list(_validator().iter_errors(payload))
    assert errors
