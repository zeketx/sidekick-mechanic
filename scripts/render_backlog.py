#!/usr/bin/env python3
"""Render BACKLOG.md from backlog/issues.json and backlog/milestones.json.

issues.json is the source of truth. Edit it, then run:
    python3 scripts/render_backlog.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
issues = json.loads((ROOT / "backlog/issues.json").read_text())
milestones = json.loads((ROOT / "backlog/milestones.json").read_text())


def section(body, name):
    m = re.search(rf"## {name}\n\n(.*?)(?=\n\n## |\n\n\*\*Size|\Z)", body, re.S)
    return m.group(1).strip() if m else ""


out = [
    "# Backlog",
    "",
    "Generated from `backlog/issues.json` by `scripts/render_backlog.py`. Edit the JSON, not this file.",
    "",
    "Create these on GitHub with `scripts/create_issues.sh` (see `docs/KANBAN.md`).",
    "",
    "Labels: `phase:1/2/3`, `area:ios/ml/telemetry/rag/highlight/docs`, `type:feature/chore/spike/bug`, `size:S/M/L`.",
    "",
]
counts = {m["title"]: sum(1 for i in issues if i["milestone"] == m["title"]) for m in milestones}
out += ["| Milestone | Issues |", "|---|---|"]
out += [f"| {m['title']} | {counts[m['title']]} |" for m in milestones]
out.append("")

n = 0
for m in milestones:
    group = [i for i in issues if i["milestone"] == m["title"]]
    if not group:
        continue
    out += [f"## {m['title']}", "", m["description"], ""]
    for i in group:
        n += 1
        size = next(l for l in i["labels"] if l.startswith("size:")).split(":")[1]
        labels = " ".join(f"`{l}`" for l in i["labels"])
        out += [f"### {n}. {i['title']}", "", f"**Labels:** {labels}  ", f"**Size:** {size}", ""]
        out += [f"**Goal.** {section(i['body'], 'Goal')}", "", "**Acceptance criteria**", "", section(i["body"], "Acceptance criteria"), ""]
        notes = section(i["body"], "Notes")
        if notes:
            out += [f"**Notes.** {notes}", ""]

(ROOT / "BACKLOG.md").write_text("\n".join(out).rstrip() + "\n")
print(f"Wrote BACKLOG.md with {n} issues")
