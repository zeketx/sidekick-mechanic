"""Safety note for answers that contain procedure steps.

`SAFETY_NOTE` is the only copy of the wording. The owner must review it
before relying on it. Generic hazards only: no torques, pinouts, part
numbers, wire colors, or other vehicle-specific specs.

Detection rule (`is_procedure_answer`):

A payload is a procedure answer when `kind` is `"answer"` and `text`
contains at least one step line. A step line is a line that, after
optional indent, is either:

- digits, then `.` or `)`, then whitespace, then more text
  (`1. ...`, `2) ...`)
- `Step`, whitespace, digits, then `:`, `.`, or `)`, then whitespace,
  then more text (`Step 1: ...`). Matching is case-insensitive.

Anything else is not a procedure answer. That includes refusals (even
when their text has step lines), bullet lists, unnumbered prose, and a
hyphen after the number (`1 - ...`).

`apply_safety_preamble` inserts `SAFETY_NOTE` and a blank line before
the original text. If the text already starts with `SAFETY_NOTE`, it is
left unchanged. The input dict is not mutated.
"""

from __future__ import annotations

import re
from typing import Any

# OWNER REVIEW: only copy of the safety note. Review this wording.
# Generic hazards only. Do not add vehicle-specific specs.
SAFETY_NOTE = (
    "Safety: Let the engine cool before you touch it. "
    "Disconnect the battery when the step calls for it. "
    "Support the vehicle on stands before you work underneath."
)

_STEP_LINE = re.compile(
    r"^\s*(?:\d+[.)]|step\s+\d+[.:)])\s+\S",
    re.MULTILINE | re.IGNORECASE,
)


def is_procedure_answer(payload: dict[str, Any]) -> bool:
    """Return whether `payload` is a found answer that contains a step line."""
    if payload.get("kind") != "answer":
        return False
    text = payload.get("text")
    if not isinstance(text, str):
        return False
    return _STEP_LINE.search(text) is not None


def apply_safety_preamble(payload: dict[str, Any]) -> dict[str, Any]:
    """Return `payload` with the safety note first when it is a procedure."""
    if not is_procedure_answer(payload):
        return payload
    text = payload["text"]
    if text.startswith(SAFETY_NOTE):
        return payload
    updated = dict(payload)
    updated["text"] = f"{SAFETY_NOTE}\n\n{text}"
    return updated
