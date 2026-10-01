"""Scaffold tests that stay collected alongside tests/ and root-level test_*.py."""

import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def test_python_meets_repo_minimum() -> None:
    assert sys.version_info >= (3, 11), sys.version


def test_pyproject_declares_python_311() -> None:
    pyproject = (BACKEND_ROOT / "pyproject.toml").read_text(encoding="utf-8")
    assert 'requires-python = ">=3.11"' in pyproject
