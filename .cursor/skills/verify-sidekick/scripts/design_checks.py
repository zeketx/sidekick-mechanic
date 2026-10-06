#!/usr/bin/env python3
"""Measure the standing design checklist rows that pixels can decide.

    python3 .cursor/skills/verify-sidekick/scripts/design_checks.py --run-dir artifacts/verify/<id>

Inputs (all under the run dir):
  screenshots/<screen>.png        simctl shots at 9:41 (verify_sidekick.py screens)
  taps/layout-frames.json         XCUITest element frames in points (DriveUITests.testRecordLayoutFrames)
  taps/layout-composer-multiline.json + taps/taps-composer-multiline.png
                                  composer after typing a long problem (testComposerStaysPillWhenMultiline)

Automated rows (PASS or FAIL with numbers):
  edge-to-edge  job-sheet-* shots: side inset, bottom gap at full, rounded top, white sheet, scrim strength
  composer      chat shot (+ multiline shot): fitted corner radius vs half height (>= 0.75), background above vs below
  nav           Jobs / Scan log / Back / Close: plain text, no filled capsule behind the label
  chrome        status bar contrast and the neutral #F4F4F4 background (FAIL only; clipping stays REVIEW)
Rows pixels cannot decide (highlight outline shape, every Figma difference) are REVIEW: the agent
must open compare/<screen>.png and fill them. Nothing here ever reports an overall PASS.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any

POINT_WIDTH = 402.0  # iPhone 17 Pro; replaced by the XCUITest window width when frames exist
BG_F4 = (244, 244, 244)
SHEET_SCREENS = ("job-sheet-collapsed", "job-sheet-half", "job-sheet-full", "job-sheet-closeout")
HIGHLIGHT_SCREENS = (
    "highlight-confident",
    "highlight-unsure",
    "highlight-not-found",
    "highlight-reference",
)
NEUTRAL_BG_SCREENS = ("chat", "job-history", "scan-log")
NAV_IDS = {
    "chat": ["chat.jobs", "chat.scanLog"],
    "job-history": ["lookBack.back", "jobHistory.scanLog"],
    "job-sheet-half": ["jobSheet.close"],
    "job-sheet-full": ["jobSheet.close"],
}
RULES = [
    ("highlight", "Highlight outline (never a box)"),
    ("edge", "Sheet edge to edge"),
    ("composer", "Composer pill / one background"),
    ("nav", "Plain-text nav buttons"),
    ("chrome", "Status bar, titles, #F4F4F4"),
    ("figma", "Matches Figma (every difference listed)"),
]


def lum(p) -> float:
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def is_white(p, t: int = 250) -> bool:
    return p[0] >= t and p[1] >= t and p[2] >= t


def hexc(p) -> str:
    return "#%02X%02X%02X" % tuple(int(v) for v in p[:3])


def cdiff(a, b) -> int:
    return max(abs(int(a[i]) - int(b[i])) for i in range(3))


def median_color(px, x0: int, y0: int, x1: int, y1: int, w: int, h: int):
    xs = range(max(0, x0), min(w, x1))
    ys = range(max(0, y0), min(h, y1))
    pts = [px[x, y] for y in ys for x in xs]
    if not pts:
        return (0, 0, 0)
    return tuple(int(statistics.median(p[i] for p in pts)) for i in range(3))


def load_frames(run_dir: Path) -> dict[str, Any]:
    frames: dict[str, Any] = {}
    for name in ("layout-frames.json", "layout-composer-multiline.json"):
        path = run_dir / "taps" / name
        if path.is_file():
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            frames.update(payload.get("screens", {}))
    return frames


# ---------------------------------------------------------------- sheet


def measure_sheet(img, screen: str, frame_info: dict[str, Any] | None) -> dict[str, Any]:
    w, h = img.size
    px = img.load()
    scale = w / POINT_WIDTH
    if frame_info and frame_info.get("window"):
        scale = w / frame_info["window"][2]
    margin = int(round(16 * scale)) - 3  # inside the 16pt content padding the sheet is blank white

    def left_white(y: int):
        for x in range(0, margin):
            if is_white(px[x, y]):
                return x if all(is_white(px[xx, y]) for xx in range(x, margin)) else None
        return None

    def right_white(y: int):
        for i in range(0, margin):
            x = w - 1 - i
            if is_white(px[x, y]):
                return i if all(is_white(px[w - 1 - j, y]) for j in range(i, margin)) else None
        return None

    def sheet_row(y: int) -> bool:
        return left_white(y) is not None and right_white(y) is not None

    bottom = None
    for y in range(h - 1, int(h * 0.3), -1):
        if sheet_row(y):
            bottom = y
            break
    if bottom is None:
        return {"found": False, "verdict": "FAIL", "reasons": ["no white sheet found in the lower 70% of the shot"]}
    top = bottom
    gap = 0
    y = bottom - 1
    while y > 0 and gap <= 4:
        if sheet_row(y):
            top = y
            gap = 0
        else:
            gap += 1
        y -= 1
    mid = (top + bottom) // 2
    rows = [yy for yy in range(mid - 10, mid + 11) if sheet_row(yy)]
    lx = int(statistics.median(left_white(yy) for yy in rows)) if rows else left_white(mid) or 0
    rx = int(statistics.median(right_white(yy) for yy in rows)) if rows else right_white(mid) or 0
    # true top edge: walk up a blank column of the header (60% across)
    cx = int(w * 0.6)
    true_top = top
    while true_top > 0 and lum(px[cx, true_top - 1]) >= 245:
        true_top -= 1
    corner_lx = None
    for x in range(0, w // 4):
        if is_white(px[x, true_top + 2]):
            corner_lx = x
            break
    rounded_top = corner_lx is None or corner_lx > lx + 3 * scale
    sheet_color = median_color(px, lx + 4, mid - 4, margin, mid + 4, w, h)
    sy = max(2, true_top - int(14 * scale))
    scrim = median_color(px, 2, sy - 3, 10, sy + 4, w, h)
    dim = round(244 - lum(scrim), 1)
    bottom_gap = h - 1 - bottom

    reasons: list[str] = []
    if lx > 2 or rx > 2:
        reasons.append(
            f"side inset: first white sheet pixel at x={lx}px from the left and {rx}px from the right "
            f"({lx / scale:.1f}pt / {rx / scale:.1f}pt; edge to edge needs 0)"
        )
    if screen == "job-sheet-full" and bottom_gap > 2:
        reasons.append(
            f"full height stops {bottom_gap}px ({bottom_gap / scale:.1f}pt) above the screen bottom "
            f"(gray strip, rounded bottom)"
        )
    if not rounded_top:
        reasons.append("top corners look square")
    if not is_white(sheet_color, 248):
        reasons.append(f"sheet is {hexc(sheet_color)}, not white")
    if screen == "job-sheet-collapsed" and dim > 40:
        reasons.append(f"collapsed scrim is too dark: {hexc(scrim)} ({dim} below #F4F4F4)")
    if screen in ("job-sheet-half", "job-sheet-full") and dim < 40:
        reasons.append(f"scrim too light at {screen}: {hexc(scrim)} ({dim} below #F4F4F4)")

    result: dict[str, Any] = {
        "found": True,
        "scale": round(scale, 3),
        "sheet_rows_px": [true_top, bottom],
        "left_inset_px": lx,
        "right_inset_px": rx,
        "left_inset_pt": round(lx / scale, 1),
        "right_inset_pt": round(rx / scale, 1),
        "bottom_gap_px": bottom_gap,
        "bottom_gap_pt": round(bottom_gap / scale, 1),
        "rounded_top": rounded_top,
        "sheet_color": hexc(sheet_color),
        "scrim_color": hexc(scrim),
        "scrim_dim": dim,
    }
    if frame_info:
        elements = frame_info.get("elements", {})
        win = frame_info.get("window")
        detent = {"job-sheet-collapsed": "jobSheet.collapsed", "job-sheet-half": "jobSheet.half",
                  "job-sheet-full": "jobSheet.full"}.get(screen, "")
        sheet = elements.get(detent)
        if win and sheet:
            result["xcuitest_frame_pt"] = {detent: [round(v, 1) for v in sheet]}
            result["xcuitest_inset_pt"] = {
                "left": round(sheet[0] - win[0], 1),
                "right": round(win[0] + win[2] - (sheet[0] + sheet[2]), 1),
                "bottom": round(win[1] + win[3] - (sheet[1] + sheet[3]), 1),
            }
    result["reasons"] = reasons
    result["verdict"] = "FAIL" if reasons else "PASS"
    return result


# ---------------------------------------------------------------- composer


def measure_pill(img, frame: list[float], window: list[float], check_background: bool) -> dict[str, Any]:
    """`chat.composer` is the TextField; its rounded background sits outside the frame
    (12pt / 8pt padding today). Walk out from the frame to the outline, then fit the corner."""
    w, h = img.size
    px = img.load()
    scale = w / window[2]
    x0, y0, fw, fh = (v * scale for v in frame)
    xc = int(x0 + min(fw, 40 * scale) / 2)  # a column near the left, inside the field
    yc = int(y0 + fh / 2)
    fill = px[max(0, int(x0) - 2), yc]  # field fill just left of the text frame
    limit = int(30 * scale)

    def walk(x: int, y: int, dx: int, dy: int):
        """First pixel that is no longer the field fill, walking (dx, dy) from (x, y)."""
        for step in range(limit):
            xx, yy = x + dx * step, y + dy * step
            if not (0 <= xx < w and 0 <= yy < h):
                return None
            if cdiff(px[xx, yy], fill) > 6:
                return xx, yy
        return None

    left = walk(max(0, int(x0) - 1), yc, -1, 0)
    top = walk(xc, max(0, int(y0) - 1), 0, -1)
    bottom = walk(xc, min(h - 1, int(y0 + fh) + 1), 0, 1)
    if left is None or top is None or bottom is None:
        return {"verdict": "FAIL", "reasons": ["could not find the composer outline around its XCUITest frame"]}
    xl, top_y, bottom_y = left[0], top[1], bottom[1]
    bg = median_color(px, xl - int(8 * scale), yc - 3, xl - int(4 * scale), yc + 4, w, h)

    def edge_x(y: int):
        for x in range(max(0, xl - int(4 * scale)), min(w, xl + int(60 * scale))):
            if cdiff(px[x, y], bg) > 6:
                return x
        return None

    height = bottom_y - top_y + 1
    half = height / 2.0
    offsets = []
    for dy in range(0, int(half)):
        ex = edge_x(top_y + dy)
        offsets.append((dy, (ex - xl) if ex is not None else half))
    best_r, best_err = 1, float("inf")
    for r in range(1, int(half) + 2):
        err = 0.0
        for dy, off in offsets:
            pred = r - math.sqrt(max(0.0, r * r - (r - dy) ** 2)) if dy < r else 0.0
            err += (off - pred) ** 2
        if err < best_err:
            best_r, best_err = r, err
    ratio = min(1.0, best_r / half)
    result: dict[str, Any] = {
        "outline_px": [xl, top_y, height],
        "height_pt": round(height / scale, 1),
        "corner_radius_pt": round(best_r / scale, 1),
        "half_height_pt": round(half / scale, 1),
        "radius_over_half_height": round(ratio, 2),
        "field_fill": hexc(fill),
        "background_left": hexc(bg),
    }
    reasons: list[str] = []
    # A circular-arc fit reads SwiftUI's .continuous corners ~15-20% small (the squircle is
    # flatter at 45 degrees), so 0.75 is the pill threshold: a continuous r=18 on a 37pt field
    # reads ~0.80 and passes; the same r=18 on a wrapped 100pt field reads ~0.3 and fails.
    if ratio < 0.75:
        reasons.append(
            f"corners are ~{best_r / scale:.1f}pt on a {height / scale:.1f}pt-tall field "
            f"(a pill needs ~{half / scale:.1f}pt; ratio {ratio:.2f}) - boxy corners"
        )
    if check_background:
        gap = int(10 * scale)
        cx = int(x0 + fw / 2)
        above = median_color(px, cx - 20, top_y - gap - 3, cx + 20, top_y - gap + 4, w, h)
        below = median_color(px, cx - 20, bottom_y + gap - 3, cx + 20, bottom_y + gap + 4, w, h)
        result["background_above"] = hexc(above)
        result["background_below"] = hexc(below)
        if cdiff(above, below) > 6 or cdiff(above, bg) > 6:
            reasons.append(
                f"background differs around the composer: above {hexc(above)}, below {hexc(below)}, left {hexc(bg)}"
            )
    result["reasons"] = reasons
    result["verdict"] = "FAIL" if reasons else "PASS"
    return result


# ---------------------------------------------------------------- nav / chrome


def measure_nav_button(img, frame: list[float], window: list[float]) -> dict[str, Any]:
    w, h = img.size
    px = img.load()
    scale = w / window[2]
    pad = int(4 * scale)
    x0 = int(frame[0] * scale) - pad
    y0 = int(frame[1] * scale) - pad
    x1 = int((frame[0] + frame[2]) * scale) + pad
    y1 = int((frame[1] + frame[3]) * scale) + pad
    ring = [px[x, y0] for x in range(max(0, x0), min(w, x1))] + [px[x, min(h - 1, y1)] for x in range(max(0, x0), min(w, x1))]
    bg = tuple(int(statistics.median(p[i] for p in ring)) for i in range(3)) if ring else BG_F4
    total = fill = 0
    for y in range(max(0, y0 + 1), min(h, y1)):
        for x in range(max(0, x0 + 1), min(w, x1)):
            p = px[x, y]
            total += 1
            d = cdiff(p, bg)
            if 3 <= d <= 40 and lum(p) >= lum(bg) - 40:
                fill += 1
    fraction = fill / total if total else 0.0
    verdict = "FAIL" if fraction > 0.35 else "PASS"
    return {
        "frame_pt": frame,
        "background": hexc(bg),
        "tinted_fill_fraction": round(fraction, 3),
        "verdict": verdict,
        "reasons": [f"filled shape behind the label ({fraction:.0%} tinted pixels)"] if verdict == "FAIL" else [],
    }


def measure_chrome(img, screen: str) -> dict[str, Any]:
    w, h = img.size
    px = img.load()
    scale = w / POINT_WIDTH
    lums = [lum(px[x, y]) for y in range(int(14 * scale), int(48 * scale), 2) for x in range(int(24 * scale), int(110 * scale), 2)]
    contrast = round(max(lums) - min(lums), 1)
    result: dict[str, Any] = {"status_bar_contrast": contrast}
    reasons: list[str] = []
    if contrast < 90:
        reasons.append(f"status bar time is low contrast ({contrast} luminance spread)")
    if screen in NEUTRAL_BG_SCREENS:
        sample = median_color(px, int(4 * scale), int(110 * scale), int(10 * scale), int(118 * scale), w, h)
        result["background"] = hexc(sample)
        if cdiff(sample, BG_F4) > 3:
            reasons.append(f"background is {hexc(sample)}, not #F4F4F4")
    result["reasons"] = reasons
    result["verdict"] = "FAIL" if reasons else "REVIEW"
    return result


# ---------------------------------------------------------------- report


def evaluate(run_dir: Path, compare_dir: Path) -> dict[str, Any]:
    from PIL import Image

    shots = run_dir / "screenshots"
    frames = load_frames(run_dir)
    report: dict[str, Any] = {"screens": {}, "frames_source": bool(frames)}
    for shot in sorted(p for p in shots.glob("*.png") if not p.name.startswith("._")):
        screen = shot.stem
        img = Image.open(shot).convert("RGB")
        rel = f"screenshots/{shot.name}"
        side = compare_dir / shot.name
        cells: dict[str, dict[str, Any]] = {}
        cells["highlight"] = (
            {"verdict": "REVIEW", "evidence": f"compare/{shot.name}", "reasons": ["outline shape needs eyes"]}
            if screen in HIGHLIGHT_SCREENS
            else {"verdict": "N/A"}
        )
        if screen in SHEET_SCREENS:
            m = measure_sheet(img, screen, frames.get(screen))
            m["evidence"] = rel
            cells["edge"] = m
        else:
            cells["edge"] = {"verdict": "N/A"}
        if screen == "chat":
            info = frames.get("chat", {})
            comp = info.get("elements", {}).get("chat.composer")
            if comp and info.get("window"):
                single = measure_pill(img, comp, info["window"], check_background=True)
                single["evidence"] = rel
                combined = {"single_line": single, "reasons": list(single["reasons"]), "evidence": rel}
                multi_info = frames.get("chat-multiline", {})
                multi_frame = multi_info.get("elements", {}).get("chat.composer")
                multi_shot = run_dir / "taps" / "taps-composer-multiline.png"
                if multi_frame and multi_info.get("window") and multi_shot.is_file():
                    multi = measure_pill(Image.open(multi_shot).convert("RGB"), multi_frame, multi_info["window"], check_background=False)
                    multi["evidence"] = "taps/taps-composer-multiline.png"
                    combined["multi_line"] = multi
                    combined["reasons"] += [f"multi-line: {r}" for r in multi["reasons"]]
                    combined["evidence"] = f"{rel}, taps/taps-composer-multiline.png"
                else:
                    combined["reasons"].append("multi-line composer shot missing (DriveUITests did not run)")
                combined["verdict"] = "FAIL" if combined["reasons"] else "PASS"
                cells["composer"] = combined
            else:
                cells["composer"] = {
                    "verdict": "REVIEW",
                    "evidence": rel,
                    "reasons": ["no XCUITest frame for chat.composer (taps skipped or failed); judge by eye"],
                }
        else:
            cells["composer"] = {"verdict": "N/A"}
        nav_ids = NAV_IDS.get(screen, [])
        if nav_ids:
            info = frames.get(screen, {})
            buttons = {}
            for ident in nav_ids:
                frame = info.get("elements", {}).get(ident)
                if frame and info.get("window"):
                    buttons[ident] = measure_nav_button(img, frame, info["window"])
            if buttons:
                reasons = [f"{k}: {r}" for k, v in buttons.items() for r in v["reasons"]]
                missing = [i for i in nav_ids if i not in buttons]
                cells["nav"] = {
                    "buttons": buttons,
                    "missing_frames": missing,
                    "reasons": reasons or ["no capsule fill; check truncation by eye"],
                    "verdict": "FAIL" if reasons else "PASS",
                    "evidence": rel,
                }
            else:
                cells["nav"] = {"verdict": "REVIEW", "evidence": rel, "reasons": ["no XCUITest frames for nav buttons"]}
        else:
            cells["nav"] = {"verdict": "N/A"}
        chrome = measure_chrome(img, screen)
        chrome["evidence"] = rel
        if chrome["verdict"] == "REVIEW":
            chrome["reasons"] = ["auto parts pass; check clipping/overlap by eye"]
        cells["chrome"] = chrome
        cells["figma"] = (
            {"verdict": "REVIEW", "evidence": f"compare/{shot.name}", "reasons": ["list every difference"]}
            if side.is_file()
            else {"verdict": "NO REF", "reasons": ["no features/figma ref for this screen"]}
        )
        report["screens"][screen] = cells
    verdicts = [c["verdict"] for s in report["screens"].values() for c in s.values()]
    report["fail_count"] = verdicts.count("FAIL")
    report["review_count"] = verdicts.count("REVIEW")
    report["overall"] = "FAIL" if report["fail_count"] else "NEEDS REVIEW"
    return report


def checklist_lines(report: dict[str, Any]) -> list[str]:
    lines = [
        f"**Overall: {report['overall']}** ({report['fail_count']} automated FAIL, "
        f"{report['review_count']} REVIEW cells for the agent). Measured by `design_checks.py`; "
        "numbers are in `compare/design-checks.json`.",
        "",
        "## Per-screen checklist",
        "",
        "| Screen | " + " | ".join(label for _, label in RULES) + " |",
        "| --- | " + " | ".join("---" for _ in RULES) + " |",
    ]
    for screen, cells in report["screens"].items():
        lines.append(f"| {screen} | " + " | ".join(cells[key]["verdict"] for key, _ in RULES) + " |")
    lines.extend(["", "## Measured evidence (FAIL / PASS cells)", ""])
    for screen, cells in report["screens"].items():
        for key, label in RULES:
            cell = cells[key]
            if cell["verdict"] not in ("FAIL", "PASS"):
                continue
            detail = "; ".join(cell.get("reasons", [])) or summary(key, cell)
            lines.append(f"- **{screen} / {label}: {cell['verdict']}** - {detail} (`{cell.get('evidence', '')}`)")
    return lines


def summary(key: str, cell: dict[str, Any]) -> str:
    if key == "edge":
        return (
            f"inset {cell['left_inset_pt']}pt/{cell['right_inset_pt']}pt, bottom gap {cell['bottom_gap_pt']}pt, "
            f"scrim {cell['scrim_color']}"
        )
    if key == "composer":
        s = cell.get("single_line", {})
        return f"radius {s.get('corner_radius_pt')}pt on {s.get('height_pt')}pt"
    return ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args(argv)
    compare_dir = args.run_dir / "compare"
    compare_dir.mkdir(parents=True, exist_ok=True)
    report = evaluate(args.run_dir, compare_dir)
    (compare_dir / "design-checks.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("\n".join(checklist_lines(report)))
    return 3 if report["fail_count"] else 0


if __name__ == "__main__":
    sys.exit(main())
