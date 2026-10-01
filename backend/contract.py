"""Validate answer payloads against the shared JSON Schema contract."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema.validators import Draft202012Validator

CONTRACTS_DIR = Path(__file__).resolve().parent / "contracts"
ANSWER_SCHEMA_PATH = CONTRACTS_DIR / "answer.schema.json"
FIXTURES_DIR = CONTRACTS_DIR / "fixtures"


@lru_cache(maxsize=1)
def answer_validator() -> Draft202012Validator:
    schema = json.loads(ANSWER_SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


def validate_answer(payload: dict[str, Any]) -> dict[str, Any]:
    answer_validator().validate(payload)
    return payload


def load_answer_fixture(name: str) -> dict[str, Any]:
    path = FIXTURES_DIR / name
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"fixture {name} is not an object")
    return validate_answer(payload)
