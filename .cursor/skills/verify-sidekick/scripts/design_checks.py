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
  nav           Jobs / Scan log / Back / Close / Garage: plain text. FAIL on a
                glass, shadow, or capsule behind the label (real pixels vs the bar,
                not a style flag). XCUITest frames are the glyph; a 4pt ring is
                still inside iOS 26 Liquid Glass.
  chrome        status bar contrast and the neutral #F4F4F4 background (FAIL only)
  large_text    Accessibility XXXL frames from taps/layout-axxxl.json: horizontal overflow,
                status-bar / island overlap, header-control overlap, ellipsis, narrow-column
                wrap. Those are FAIL. Mid-word hyphenation VoiceOver still reads in full stays
                REVIEW (open screenshots/axxxl/). See docs/DYNAMIC_TYPE.md.
Rows pixels cannot decide (highlight outline shape, every Figma difference, mid-word hyphenation)
are REVIEW: the agent must open compare/<screen>.png and the AXXXL shots and fill them.
Nothing here ever reports an overall PASS.
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
    "chat": ["chat.garage"],
    "onboarding-1": ["onboarding.skip"],
    "onboarding-2": ["onboarding.skip"],
    "onboarding-3": ["onboarding.skip"],
    "job-history": ["lookBack.back", "jobHistory.scanLog"],
    "job-sheet-half": ["jobSheet.close"],
    "job-sheet-full": ["jobSheet.close"],
    "job-sheet-closeout": ["jobSheet.close"],
}
OUTCOME_FILL_SCREENS = ("job-sheet-full", "job-sheet-closeout")
OUTCOME_FILL_ID = "jobSheet.outcome.worked"
RULES = [
    ("highlight", "Highlight outline (never a box)"),
    ("edge", "Sheet edge to edge"),
    ("composer", "Composer pill / one background"),
    ("nav", "Plain-text nav buttons"),
    ("chrome", "Status bar, titles, #F4F4F4"),
    ("large_text", "Large text (AXXXL)"),
    ("figma", "Matches Figma (every difference listed)"),
]
# Same set as verify_sidekick.AXXXL_SCREENS. Self-test checks they match.
AXXXL_SCREENS = (
    "chat",
    "onboarding-1",
    "onboarding-2",
    "onboarding-3",
    "job-sheet-half",
    "job-sheet-full",
    "job-sheet-closeout",
    "citation-page",
    "job-history",
    "scan-log",
)
AXXXL_EYE = (
    "Geometry fits (no horizontal overflow, header controls clear the island). "
    "Open the AXXXL screenshot and FAIL this row if a word breaks mid-word "
    "(Ma/nu…, Col/d i…, Bat-/tery) or a date is cut (Tod…). "
    "XCUITest reads the full accessibility label, so hyphenation and tail truncation "
    "often do not appear in the label."
)


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


def load_axxxl(run_dir: Path) -> dict[str, Any] | None:
    path = run_dir / "taps" / "layout-axxxl.json"
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    screens = payload.get("screens")
    return screens if isinstance(screens, dict) else None


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


def _collect_pixels(px, x0: int, y0: int, x1: int, y1: int, w: int, h: int):
    pts = []
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            pts.append(px[x, y])
    return pts


def _median_rgb(pts) -> tuple[int, int, int]:
    if not pts:
        return BG_F4
    return tuple(int(statistics.median(p[i] for p in pts)) for i in range(3))


def _lums(pts) -> list[float]:
    return [lum(p) for p in pts]


def measure_nav_button(img, frame: list[float], window: list[float]) -> dict[str, Any]:
    """FAIL a glass/shadow/capsule behind the label using real pixels.

    XCUITest frames are the glyph, not the Liquid Glass pill. A 4pt ring around
    the text is still inside the glass, so that ring must not be the bar sample.
    Sample empty header paper ~28–56pt beside the label, then compare a halo
    (expanded box minus the text) and a shadow ring just outside the halo.
    """
    w, h = img.size
    px = img.load()
    scale = w / window[2]
    tx0 = int(frame[0] * scale)
    ty0 = int(frame[1] * scale)
    tx1 = int((frame[0] + frame[2]) * scale)
    ty1 = int((frame[1] + frame[3]) * scale)
    cy = (ty0 + ty1) // 2
    patch = max(6, int(round(8 * scale)))

    bar_pts = []
    bar_color = BG_F4
    bar_lum = -1.0
    for off_pt in (28, 40, 56, -28, -40, -56):
        off = int(round(off_pt * scale))
        if off >= 0:
            x0 = tx1 + off
        else:
            x0 = tx0 + off - patch
        y0 = cy - patch // 2
        pts = _collect_pixels(px, x0, y0, x0 + patch, y0 + patch, w, h)
        if len(pts) < 8:
            continue
        med = _median_rgb(pts)
        L = lum(med)
        if L > bar_lum:
            bar_pts = pts
            bar_color = med
            bar_lum = L
    if bar_lum < 0:
        bar_lum = lum(BG_F4)

    # Glass extends ~12pt around the glyph. Stay mostly in the header row so the
    # status bar / Dynamic Island above Garage is not the halo.
    pad_x = int(round(14 * scale))
    pad_y = int(round(8 * scale))
    text_inset = max(1, int(round(1.5 * scale)))
    hx0, hy0 = tx0 - pad_x, ty0 - pad_y
    hx1, hy1 = tx1 + pad_x, ty1 + pad_y
    ix0, iy0 = tx0 + text_inset, ty0 + text_inset
    ix1, iy1 = tx1 - text_inset, ty1 - text_inset
    halo = []
    for y in range(max(0, hy0), min(h, hy1)):
        for x in range(max(0, hx0), min(w, hx1)):
            if ix0 <= x < ix1 and iy0 <= y < iy1:
                continue
            halo.append(px[x, y])
    # Ignore island/ink (much darker than paper). Glass is paper-or-brighter.
    glass = [p for p in halo if lum(p) >= bar_lum - 5]
    glass_lums = _lums(glass)
    halo_lum = statistics.median(glass_lums) if glass_lums else bar_lum
    halo_stdev = statistics.pstdev(glass_lums) if len(glass_lums) > 1 else 0.0
    brighter = (
        sum(1 for L in glass_lums if L > bar_lum + 6) / len(glass_lums) if glass_lums else 0.0
    )

    # Liquid Glass drop shadow sits under the capsule, not in the status bar.
    sy0 = ty1 + max(1, int(round(2 * scale)))
    sy1 = ty1 + int(round(12 * scale))
    sx0 = tx0 - int(round(10 * scale))
    sx1 = tx1 + int(round(10 * scale))
    shadow = _collect_pixels(px, sx0, sy0, sx1, sy1, w, h)
    shadow_lums = _lums(shadow)
    if shadow_lums:
        shadow_lums_sorted = sorted(shadow_lums)
        darkest = shadow_lums_sorted[: max(1, len(shadow_lums_sorted) // 5)]
        shadow_dark = statistics.median(darkest)
    else:
        shadow_dark = bar_lum

    reasons: list[str] = []
    if halo_lum > bar_lum + 6:
        reasons.append(
            f"brighter glass fill behind the label (halo lum {halo_lum:.0f} vs bar {bar_lum:.0f}, "
            f"{hexc(_median_rgb(glass)) if glass else hexc(bar_color)} on {hexc(bar_color)})"
        )
    elif brighter > 0.35:
        reasons.append(
            f"glass/capsule fill around the label ({brighter:.0%} of halo brighter than the bar)"
        )
    if bar_lum - shadow_dark >= 10:
        reasons.append(
            f"drop shadow around the label (dark band lum {shadow_dark:.0f} vs bar {bar_lum:.0f})"
        )
    if halo_stdev >= 18 and brighter > 0.15:
        reasons.append(
            f"uneven capsule/shadow halo (luminance stdev {halo_stdev:.1f})"
        )

    verdict = "FAIL" if reasons else "PASS"
    return {
        "frame_pt": frame,
        "background": hexc(bar_color),
        "halo_lum": round(halo_lum, 1),
        "bar_lum": round(bar_lum, 1),
        "halo_stdev": round(halo_stdev, 1),
        "brighter_halo_fraction": round(brighter, 3),
        "shadow_ring_lum": round(shadow_dark, 1),
        "verdict": verdict,
        "reasons": reasons,
    }


def measure_outcome_fill(img, frame: list[float], window: list[float]) -> dict[str, Any]:
    """Selected Worked must be a filled segment (dark fill), not paper plus underline."""
    w, h = img.size
    px = img.load()
    scale = w / window[2]
    inset = max(2, int(round(4 * scale)))
    x0 = int(frame[0] * scale) + inset
    y0 = int(frame[1] * scale) + inset
    x1 = int((frame[0] + frame[2]) * scale) - inset
    y1 = int((frame[1] + frame[3]) * scale) - inset
    pts = _collect_pixels(px, x0, y0, x1, y1, w, h)
    if len(pts) < 12:
        return {
            "frame_pt": frame,
            "verdict": "FAIL",
            "reasons": ["outcome.worked frame is too small to measure a fill"],
        }
    fill = _median_rgb(pts)
    fill_lum = lum(fill)
    dark = sum(1 for p in pts if lum(p) < 90) / len(pts)
    reasons: list[str] = []
    # Filled Worked is black (or near-black) with white label. Underline-only is paper.
    if fill_lum > 140 or dark < 0.35:
        reasons.append(
            f"selected Worked is not a filled segment (median {hexc(fill)}, lum {fill_lum:.0f}, "
            f"{dark:.0%} dark pixels)"
        )
    return {
        "frame_pt": frame,
        "fill": hexc(fill),
        "fill_lum": round(fill_lum, 1),
        "dark_fraction": round(dark, 3),
        "verdict": "FAIL" if reasons else "PASS",
        "reasons": reasons,
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


# ---------------------------------------------------------------- accessibility XXXL
# Thresholds match DriveUITests.measureScreenFit. See docs/DYNAMIC_TYPE.md.


def _axxxl_frame(value: Any) -> list[float] | None:
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        return None
    try:
        return [float(part) for part in value]
    except (TypeError, ValueError):
        return None


def _axxxl_name(item: dict[str, Any]) -> str:
    ident = str(item.get("id") or "")
    label = str(item.get("label") or "")
    return f"{item.get('type') or 'element'} {ident or label}"


def _axxxl_overflow(frame: list[float], window: list[float]) -> str | None:
    x, y, w, h = frame
    wx, wy, ww, wh = window
    visible_w = max(0.0, min(x + w, wx + ww) - max(x, wx))
    visible_h = max(0.0, min(y + h, wy + wh) - max(y, wy))
    if visible_w <= 2 or visible_h <= 2:
        return None
    past_left = wx - x
    past_right = (x + w) - (wx + ww)
    if past_left <= 2 and past_right <= 2:
        return None
    return (
        f"extends past the window (minX {x:.0f}, maxX {x + w:.0f}, "
        f"window {wx:.0f}…{wx + ww:.0f})"
    )


def _axxxl_island(item: dict[str, Any], inset: float, window: list[float]) -> str | None:
    """Match DriveUITests.islandOverlap. Status-bar chrome is ignored. Body copy is not a header."""
    if item.get("id") == "jobSheet.dim" or item.get("islandExempt"):
        return None
    _, y, _, h = item["frame"]
    if h >= window[3] * 0.45:
        return None
    ident = str(item.get("id") or "")
    if not ident and y + h <= inset + 2:
        return None
    if y >= inset - 2:
        return None
    lower = ident.lower()
    header_word = any(part in lower for part in ("title", "close", "open", "skip", "garage", "back", "header"))
    header = (
        header_word
        or (item.get("type") == "button" and not item.get("inStatusBar"))
        or (item.get("type") == "staticText" and not ident and not item.get("inStatusBar"))
    )
    if not header:
        return None
    return f"minY {y:.0f} is under the status bar / island (safe area {inset:.0f})"


def _axxxl_truncation(item: dict[str, Any]) -> str | None:
    if item.get("inStatusBar"):
        return None
    label = str(item.get("label") or "")
    if "…" in label or "..." in label:
        return f"label looks truncated: {label}"
    tokens = [token for token in label.replace("·", " ").split() if token]
    longest = max((len(token) for token in tokens), default=0)
    width = item["frame"][2]
    height = item["frame"][3]
    if longest >= 6 and width < 72 and height > width * 1.35 and width > 1:
        return (
            f"label {label} is squeezed into a {width:.0f}×{height:.0f}pt column "
            "(mid-word wrap proxy)"
        )
    return None


def _contains_frame(outer: list[float], inner: list[float]) -> bool:
    return (
        outer[0] <= inner[0] + 2
        and outer[1] <= inner[1] + 2
        and outer[0] + outer[2] >= inner[0] + inner[2] - 2
        and outer[1] + outer[3] >= inner[1] + inner[3] - 2
    )


# Fallback when text is not inside a user-scrollable viewport: it starts in the
# top 80% of the window and still runs more than 80pt (and more than 35% of its
# height) past the window. A bottom-edge peek of the next row is not a clip.
# Scroll views and fixed cards are judged separately. See docs/DYNAMIC_TYPE.md.
AXXXL_CLIP_MIN_INTERSECTION = 48.0
AXXXL_CLIP_PAST = 80.0
AXXXL_CLIP_PAST_FRACTION = 0.35
AXXXL_CLIP_MAX_MIN_Y_FRACTION = 0.80
AXXXL_CONTROL_OVERLAP = 4.0
AXXXL_SCRIM_FRACTION = 0.45


def _rect_intersection(a: list[float], b: list[float]) -> list[float] | None:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x0 = max(ax, bx)
    y0 = max(ay, by)
    x1 = min(ax + aw, bx + bw)
    y1 = min(ay + ah, by + bh)
    if x1 - x0 <= 0 or y1 - y0 <= 0:
        return None
    return [x0, y0, x1 - x0, y1 - y0]


def _center_in(frame: list[float], outer: list[float]) -> bool:
    cx = frame[0] + frame[2] / 2
    cy = frame[1] + frame[3] / 2
    return outer[0] <= cx <= outer[0] + outer[2] and outer[1] <= cy <= outer[1] + outer[3]


def _payload_frames(payload: dict[str, Any], key: str) -> list[dict[str, Any]]:
    raw = payload.get(key) or []
    if not isinstance(raw, list):
        return []
    found: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        frame = _axxxl_frame(item.get("frame"))
        if frame is None:
            continue
        found.append({"id": str(item.get("id") or ""), "frame": frame})
    return found


def _dimmed(payload: dict[str, Any], elements: list[dict[str, Any]]) -> bool:
    if "dimmed" in payload:
        return bool(payload.get("dimmed"))
    return any(item.get("id") == "jobSheet.dim" for item in elements)


def _sheet_frame(payload: dict[str, Any], elements: list[dict[str, Any]]) -> list[float] | None:
    direct = _axxxl_frame(payload.get("sheet"))
    if direct is not None:
        return direct
    for ident in ("jobSheet.half", "jobSheet.full", "jobSheet.collapsed"):
        for item in elements:
            if item.get("id") == ident:
                return item["frame"]
    return None


def _behind_sheet(item: dict[str, Any], dimmed: bool, sheet: list[float] | None) -> bool:
    """Chat under the scrim is not on screen. The Garage sliver and the sheet's own controls are."""
    if not dimmed:
        return False
    ident = str(item.get("id") or "")
    if ident == "jobSheet.dim" or ident == "chat.garage" or ident.startswith("jobSheet."):
        return False
    if ident.startswith("answerCard.") or ident.startswith("chat."):
        return True
    if sheet is not None and not _center_in(item["frame"], sheet):
        return True
    return item.get("hittable") is False


def _scroll_frames(payload: dict[str, Any]) -> list[list[float]]:
    return [item["frame"] for item in _payload_frames(payload, "scrollViews")]


def _mostly_above_window(frame: list[float], window: list[float]) -> bool:
    """A chip scrolled to y=-128 still reports a 1pt intersection. That is not on screen."""
    inter = _rect_intersection(frame, window)
    if inter is None:
        return True
    return frame[1] < window[1] - 2 and inter[3] <= 8


def _scrolled_away(
    item: dict[str, Any],
    scrolls: list[list[float]],
    window: list[float],
) -> bool:
    """Fully outside every scroll viewport. On-screen headers and the Garage sliver stay."""
    if not scrolls:
        return False
    visible = False
    for scroll in scrolls:
        inter = _rect_intersection(item["frame"], scroll)
        if inter is not None and inter[2] > 2 and inter[3] > 2:
            visible = True
            break
    if visible:
        return False
    window_inter = _rect_intersection(item["frame"], window)
    window_h = 0.0 if window_inter is None else window_inter[3]
    if item.get("hittable") is False or window_h <= 2:
        return True
    return False


def _window_clip(frame: list[float], window: list[float]) -> str | None:
    """Match DriveUITests.windowClipReason. Only when no scroll view holds the first line."""
    inter = _rect_intersection(frame, window)
    if inter is None or inter[3] <= AXXXL_CLIP_MIN_INTERSECTION:
        return None
    y, h = frame[1], frame[3]
    if y >= window[3] * AXXXL_CLIP_MAX_MIN_Y_FRACTION:
        return None
    past_bottom = (y + h) - (window[1] + window[3])
    if past_bottom <= AXXXL_CLIP_PAST or h <= 0 or past_bottom <= h * AXXXL_CLIP_PAST_FRACTION:
        return None
    return (
        f"clipped by its container (minY {y:.0f}, {past_bottom:.0f}pt past the bottom of {h:.0f}pt)"
    )


def _tightest_scroll(frame: list[float], scrolls: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Smallest user-scrollable viewport that contains this text's first line.

    `scrollViews` are XCUIElement type `.scrollView`. Extending below one is not a failure.
    """
    cx = frame[0] + frame[2] / 2
    best: dict[str, Any] | None = None
    best_area: float | None = None
    for scroll in scrolls:
        outer = scroll["frame"]
        if not (outer[0] <= cx <= outer[0] + outer[2]):
            continue
        if frame[1] < outer[1] - 2 or frame[1] >= outer[1] + outer[3]:
            continue
        area = outer[2] * outer[3]
        if best is None or best_area is None or area < best_area:
            best = scroll
            best_area = area
    return best


def _fixed_clip(item: dict[str, Any], clips: list[dict[str, Any]]) -> str | None:
    """A `clips` entry is not user-scrollable. Past its bottom is a cut-off card."""
    frame = item["frame"]
    for clip in clips:
        outer = clip["frame"]
        if not _center_in(frame, outer):
            continue
        name = clip.get("id") or "clip"
        past_bottom = (frame[1] + frame[3]) - (outer[1] + outer[3])
        if past_bottom > 4:
            return f"clipped by its container {name} ({past_bottom:.0f}pt past the bottom)"
        if (
            frame[0] < outer[0] - 4
            or frame[1] < outer[1] - 4
            or frame[0] + frame[2] > outer[0] + outer[2] + 4
        ):
            return f"extends outside fixed container {name}"
    return None


def _is_overlap_control(item: dict[str, Any], window: list[float]) -> bool:
    ident = str(item.get("id") or "")
    if "pageDots" in ident:
        return True
    if ident == "jobSheet.dim":
        return False
    if item.get("type") != "button" or item.get("hittable") is False:
        return False
    return item["frame"][3] < window[3] * AXXXL_SCRIM_FRACTION


def _text_over_controls(
    texts: list[dict[str, Any]],
    elements: list[dict[str, Any]],
    window: list[float],
) -> list[str]:
    """Text that starts above a button or the page dots and runs into it."""
    controls = [item for item in elements if _is_overlap_control(item, window)]
    reasons: list[str] = []
    for text in texts:
        if text.get("type") not in ("staticText", "textView", "textField"):
            continue
        for control in controls:
            if text["id"] == control["id"] and text["frame"] == control["frame"]:
                continue
            # A button that contains its own label is not an overlap. Text that
            # covers the page dots does contain that control, and that is a failure.
            if _contains_frame(control["frame"], text["frame"]):
                continue
            if text["frame"][1] >= control["frame"][1] - AXXXL_CONTROL_OVERLAP:
                continue
            inter = _rect_intersection(text["frame"], control["frame"])
            if inter is None or inter[2] <= AXXXL_CONTROL_OVERLAP or inter[3] <= AXXXL_CONTROL_OVERLAP:
                continue
            reasons.append(f"{_axxxl_name(text)} overlaps {_axxxl_name(control)}")
    return reasons


def _axxxl_keep(
    item: dict[str, Any],
    payload: dict[str, Any],
    elements: list[dict[str, Any]],
    window: list[float],
) -> tuple[bool, list[str]]:
    """Visible elements only. Returns (measure?, extra reasons). Thresholds match DriveUITests."""
    if item.get("id") == "jobSheet.dim":
        return False, []
    dimmed = _dimmed(payload, elements)
    if _behind_sheet(item, dimmed, _sheet_frame(payload, elements)):
        return False, []
    if _mostly_above_window(item["frame"], window):
        return False, []
    if _scrolled_away(item, _scroll_frames(payload), window):
        return False, []
    reasons: list[str] = []
    # A scroll view may continue below the fold. Only the first line has to be on screen.
    if _tightest_scroll(item["frame"], _payload_frames(payload, "scrollViews")) is None:
        clipped = _window_clip(item["frame"], window)
        if clipped:
            reasons.append(clipped)
    fixed = _fixed_clip(item, _payload_frames(payload, "clips"))
    if fixed:
        reasons.append(fixed)
    if item.get("hittable") is False and not reasons:
        return False, []
    if dimmed and item.get("id") == "chat.garage":
        item["islandExempt"] = True
    return True, reasons


def _axxxl_overlaps(items: list[dict[str, Any]], inset: float) -> list[str]:
    band = []
    for item in items:
        frame = item["frame"]
        if item.get("inStatusBar") or item.get("id") == "jobSheet.dim" or item.get("islandExempt"):
            continue
        if frame[1] < inset + 96 and frame[3] < 160 and frame[3] > 1:
            band.append(item)
    reasons: list[str] = []
    for index, first in enumerate(band):
        for second in band[index + 1 :]:
            if _contains_frame(first["frame"], second["frame"]) or _contains_frame(
                second["frame"], first["frame"]
            ):
                continue
            ax, ay, aw, ah = first["frame"]
            bx, by, bw, bh = second["frame"]
            overlap_w = min(ax + aw, bx + bw) - max(ax, bx)
            overlap_h = min(ay + ah, by + bh) - max(ay, by)
            if overlap_w > 4 and overlap_h > 4:
                reasons.append(f"{_axxxl_name(first)} overlaps {_axxxl_name(second)}")
    return reasons


def measure_axxxl(payload: dict[str, Any] | None, screen: str) -> dict[str, Any]:
    evidence = f"screenshots/axxxl/{screen}.png"
    if payload is None:
        return {
            "verdict": "FAIL",
            "evidence": evidence,
            "reasons": [
                "taps/layout-axxxl.json has no frames for this screen. "
                "Accessibility XXXL was not measured."
            ],
        }
    if payload.get("skipped"):
        return {
            "verdict": "N/A",
            "evidence": evidence,
            "reasons": [str(payload.get("reason") or "skipped")],
        }
    window = _axxxl_frame(payload.get("window"))
    if window is None:
        return {
            "verdict": "FAIL",
            "evidence": evidence,
            "reasons": ["AXXXL window frame missing"],
        }
    try:
        inset = float(payload.get("safeAreaTop") or 0)
    except (TypeError, ValueError):
        inset = 0.0
    reasons: list[str] = []
    parsed: list[dict[str, Any]] = []
    raw_elements = payload.get("elements") or []
    if not isinstance(raw_elements, list):
        raw_elements = []
    staged: list[dict[str, Any]] = []
    for raw in raw_elements:
        if not isinstance(raw, dict):
            continue
        frame = _axxxl_frame(raw.get("frame"))
        if frame is None:
            continue
        staged.append(
            {
                "id": str(raw.get("id") or ""),
                "label": str(raw.get("label") or ""),
                "type": str(raw.get("type") or ""),
                "inStatusBar": bool(raw.get("inStatusBar")),
                "hittable": True if "hittable" not in raw else bool(raw.get("hittable")),
                "frame": frame,
            }
        )
    for item in staged:
        keep, extra = _axxxl_keep(item, payload, staged, window)
        if not keep:
            continue
        parsed.append(item)
        for reason in extra:
            reasons.append(f"{_axxxl_name(item)} {reason}")
        overflow = _axxxl_overflow(item["frame"], window)
        if overflow:
            reasons.append(f"{_axxxl_name(item)} {overflow}")
        island = _axxxl_island(item, inset, window)
        if island:
            reasons.append(f"{_axxxl_name(item)} {island}")
        truncated = _axxxl_truncation(item)
        if truncated:
            reasons.append(f"{_axxxl_name(item)} {truncated}")
    reasons.extend(_axxxl_overlaps(parsed, inset))
    reasons.extend(_text_over_controls(parsed, staged, window))
    if reasons:
        return {"verdict": "FAIL", "evidence": evidence, "reasons": reasons, "safeAreaTop": inset}
    return {
        "verdict": "REVIEW",
        "evidence": evidence,
        "reasons": [AXXXL_EYE],
        "safeAreaTop": inset,
    }


# ---------------------------------------------------------------- report


def evaluate(run_dir: Path, compare_dir: Path) -> dict[str, Any]:
    from PIL import Image

    shots = run_dir / "screenshots"
    frames = load_frames(run_dir)
    axxxl = load_axxxl(run_dir)
    report: dict[str, Any] = {"screens": {}, "frames_source": bool(frames), "axxxl_source": axxxl is not None}
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
                    "reasons": reasons or ["plain text on the bar; check truncation by eye"],
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
            chrome["reasons"] = [
                "status bar contrast passes; horizontal overflow and the island are on the large-text row"
            ]
        cells["chrome"] = chrome
        if screen in AXXXL_SCREENS:
            if axxxl is None:
                cells["large_text"] = {
                    "verdict": "FAIL",
                    "evidence": f"screenshots/axxxl/{screen}.png",
                    "reasons": [
                        "taps/layout-axxxl.json missing; Accessibility XXXL frames were not recorded"
                    ],
                }
            else:
                cells["large_text"] = measure_axxxl(axxxl.get(screen), screen)
        else:
            cells["large_text"] = {"verdict": "N/A"}
        cells["figma"] = (
            {"verdict": "REVIEW", "evidence": f"compare/{shot.name}", "reasons": ["list every difference"]}
            if side.is_file()
            else {"verdict": "NO REF", "reasons": ["no features/figma ref for this screen"]}
        )
        if screen in OUTCOME_FILL_SCREENS:
            info = frames.get(screen, {})
            worked = info.get("elements", {}).get(OUTCOME_FILL_ID)
            if worked and info.get("window"):
                fill = measure_outcome_fill(img, worked, info["window"])
                fill["evidence"] = rel
                cells["outcome_fill"] = fill
            else:
                cells["outcome_fill"] = {
                    "verdict": "REVIEW",
                    "evidence": rel,
                    "reasons": [
                        f"no XCUITest frame for {OUTCOME_FILL_ID}; selected Worked must look filled"
                    ],
                }
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
        large = cells.get("large_text")
        if large and large.get("verdict") == "REVIEW":
            detail = "; ".join(large.get("reasons", []))
            lines.append(
                f"- **{screen} / Large text (AXXXL): REVIEW** - {detail} (`{large.get('evidence', '')}`)"
            )
        extra = cells.get("outcome_fill")
        if extra and extra.get("verdict") in ("FAIL", "PASS"):
            detail = "; ".join(extra.get("reasons", [])) or (
                f"Worked fill {extra.get('fill')} lum {extra.get('fill_lum')} "
                f"({extra.get('dark_fraction', 0):.0%} dark)"
            )
            lines.append(
                f"- **{screen} / Selected outcome filled: {extra['verdict']}** - {detail} "
                f"(`{extra.get('evidence', '')}`)"
            )
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
    if key == "nav":
        return "plain text on the bar; check truncation by eye"
    if key == "large_text":
        return "AXXXL geometry"
    return ""


def _draw_label(draw, box, text: str, fill) -> None:
    x0, y0, x1, y1 = box
    # Block letters so the self-test does not need a font file.
    pad = max(2, (y1 - y0) // 5)
    draw.rectangle([x0 + pad, y0 + pad, x1 - pad, y1 - pad], fill=fill)


def self_test() -> int:
    """Synthetic pixels: plain text PASSes; glass+shadow FAILs. No simulator."""
    from PIL import Image, ImageDraw, ImageFilter

    scale = 3.0
    window = [0.0, 0.0, 402.0, 200.0]
    frame = [16.0, 62.0, 58.0, 22.0]  # glyph-only, like XCUITest
    w, h = int(window[2] * scale), int(window[3] * scale)
    paper = BG_F4
    tx0, ty0 = int(frame[0] * scale), int(frame[1] * scale)
    tx1 = int((frame[0] + frame[2]) * scale)
    ty1 = int((frame[1] + frame[3]) * scale)

    plain = Image.new("RGB", (w, h), paper)
    _draw_label(ImageDraw.Draw(plain), (tx0, ty0, tx1, ty1), "Garage", (20, 20, 20))
    plain_result = measure_nav_button(plain, frame, window)

    glass = Image.new("RGB", (w, h), paper)
    gx0 = tx0 - int(12 * scale)
    gy0 = ty0 - int(8 * scale)
    gx1 = tx1 + int(12 * scale)
    gy1 = ty1 + int(8 * scale)
    shadow = Image.new("RGB", (w, h), paper)
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        [gx0, gy0 + int(3 * scale), gx1, gy1 + int(4 * scale)],
        radius=int(18 * scale),
        fill=(180, 180, 180),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=int(3 * scale)))
    glass.paste(shadow)
    gdraw = ImageDraw.Draw(glass)
    gdraw.rounded_rectangle(
        [gx0, gy0, gx1, gy1],
        radius=int(16 * scale),
        fill=(255, 255, 255),
    )
    _draw_label(gdraw, (tx0, ty0, tx1, ty1), "Garage", (20, 20, 20))
    glass_result = measure_nav_button(glass, frame, window)

    worked_frame = [16.0, 120.0, 110.0, 40.0]
    wx0 = int(worked_frame[0] * scale)
    wy0 = int(worked_frame[1] * scale)
    wx1 = int((worked_frame[0] + worked_frame[2]) * scale)
    wy1 = int((worked_frame[1] + worked_frame[3]) * scale)
    filled = Image.new("RGB", (w, h), (255, 255, 255))
    fdraw = ImageDraw.Draw(filled)
    fdraw.rounded_rectangle([wx0, wy0, wx1, wy1], radius=int(10 * scale), fill=(20, 20, 20))
    # Small white glyph so the median stays the black fill.
    cx = (wx0 + wx1) // 2
    cy = (wy0 + wy1) // 2
    fdraw.rectangle([cx - int(18 * scale), cy - int(3 * scale), cx + int(18 * scale), cy + int(3 * scale)], fill=(250, 250, 250))
    filled_result = measure_outcome_fill(filled, worked_frame, window)

    underline = Image.new("RGB", (w, h), (255, 255, 255))
    udraw = ImageDraw.Draw(underline)
    udraw.rectangle([cx - int(18 * scale), cy - int(3 * scale), cx + int(18 * scale), cy + int(3 * scale)], fill=(20, 20, 20))
    udraw.line([(wx0 + 24, wy1 - int(6 * scale)), (wx1 - 24, wy1 - int(6 * scale))], fill=(20, 20, 20), width=max(2, int(scale)))
    underline_result = measure_outcome_fill(underline, worked_frame, window)

    window = [0.0, 0.0, 402.0, 874.0]
    clean = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "chat.garage", "label": "Garage", "type": "button", "frame": [16, 80, 120, 44]},
                {
                    "id": "",
                    "label": "9:41",
                    "type": "staticText",
                    "inStatusBar": True,
                    "frame": [24, 14, 48, 18],
                },
                {
                    "id": "jobSheet.dim",
                    "label": "Close job sheet",
                    "type": "button",
                    "frame": [0, 0, 402, 180],
                },
                {
                    "id": "wifi",
                    "label": "3 of 3 Wi-Fi bars",
                    "type": "button",
                    "inStatusBar": True,
                    "frame": [300, 12, 20, 16],
                },
            ],
        },
        "chat",
    )
    overflow = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "chat.jobs", "label": "Jobs", "type": "button", "frame": [360, 80, 80, 44]},
            ],
        },
        "chat",
    )
    both_edges = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "lookBack.title", "label": "Jobs", "type": "staticText", "frame": [-30, 70, 480, 40]},
            ],
        },
        "job-history",
    )
    island = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "jobSheet.title", "label": "Job · Cold idle", "type": "staticText", "frame": [16, 12, 220, 36]},
            ],
        },
        "job-sheet-half",
    )
    truncated = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "jobHistory.date", "label": "Tod…", "type": "staticText", "frame": [16, 120, 70, 28]},
            ],
        },
        "job-history",
    )
    squeezed = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "jobHistory.row", "label": "Battery", "type": "staticText", "frame": [16, 140, 36, 110]},
            ],
        },
        "job-history",
    )
    overlap = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "chat.garage", "label": "Garage", "type": "button", "frame": [16, 70, 140, 40]},
                {"id": "chat.title", "label": "Sidekick", "type": "staticText", "frame": [90, 72, 160, 36]},
            ],
        },
        "chat",
    )
    contained = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "elements": [
                {"id": "chat.garage", "label": "Garage", "type": "button", "frame": [16, 70, 160, 44]},
                {"id": "", "label": "Garage", "type": "staticText", "frame": [24, 78, 90, 28]},
            ],
        },
        "chat",
    )
    skipped = measure_axxxl(
        {"skipped": True, "reason": "jobHistory.list is not on this checkout (PR #114, later)."},
        "job-history",
    )
    missing = measure_axxxl(None, "scan-log")
    # Scrolled-off sheet content, chat behind the scrim, and the Garage sliver must not fail.
    clipped_away = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "dimmed": True,
            "sheet": [0, 95, 402, 779],
            "scrollViews": [{"id": "jobSheet.body", "frame": [0, 250, 402, 330]}],
            "elements": [
                {
                    "id": "jobSheet.dim",
                    "label": "Close job sheet",
                    "type": "button",
                    "hittable": True,
                    "frame": [0, 0, 402, 874],
                },
                {
                    "id": "chat.garage",
                    "label": "Garage",
                    "type": "button",
                    "hittable": True,
                    "frame": [16, 28, 165, 63],
                },
                {
                    "id": "jobSheet.chip.0",
                    "label": "FAKE-DOC-2JZ · p. 999",
                    "type": "button",
                    "hittable": True,
                    "frame": [16, -128, 370, 129],
                },
                {
                    "id": "jobSheet.partChip",
                    "label": "fuse/relay",
                    "type": "staticText",
                    "hittable": False,
                    "frame": [16, 9, 370, 71],
                },
                {
                    "id": "jobSheet.stepsHeading",
                    "label": "Steps 1 of 3",
                    "type": "staticText",
                    "hittable": False,
                    "frame": [16, 87, 256, 59],
                },
                {
                    "id": "answerCard.chip.0",
                    "label": "FAKE-DOC-2JZ · p. 999",
                    "type": "button",
                    "hittable": True,
                    "frame": [30, 556, 529, 71],
                },
                {
                    "id": "",
                    "label": "You said Rough idle after a cold start",
                    "type": "staticText",
                    "hittable": False,
                    "frame": [98, -119, 288, 207],
                },
                {
                    "id": "jobSheet.title",
                    "label": "Job · Cold idle",
                    "type": "staticText",
                    "hittable": True,
                    "frame": [16, 117, 207, 125],
                },
                {
                    "id": "jobSheet.close",
                    "label": "Close",
                    "type": "button",
                    "hittable": True,
                    "frame": [337, 122, 43, 43],
                },
            ],
        },
        "job-sheet-half",
    )
    body_clip = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "scrollViews": [{"id": "onboarding.welcome", "frame": [0, 200, 402, 510]}],
            "elements": [
                {
                    "id": "",
                    "label": "Ask about a problem in chat.",
                    "type": "staticText",
                    "hittable": True,
                    "frame": [24, 636, 349, 497],
                },
                {
                    "id": "onboarding.next",
                    "label": "Next",
                    "type": "button",
                    "hittable": True,
                    "frame": [24, 737, 354, 87],
                },
            ],
        },
        "onboarding-1",
    )
    # Round-2 citation page: the explanation continues below the fold inside a ScrollView.
    scrollable_continuation = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "scrollViews": [
                {"id": "jobSheet.body", "frame": [0, 250.33333333333334, 402, 310.33333333333326]},
                {"id": "", "frame": [0, 62, 402, 811.9999999999999]},
                {"id": "chat.messageList", "frame": [0, 0, 402, 874]},
                {"id": "answerCard.chips", "frame": [30, 555.6666666666666, 310, 70.66666666666663]},
            ],
            "elements": [
                {
                    "id": "",
                    "label": (
                        "The fuse/relay box is the plastic box that holds the fuses "
                        "and relays for this engine bay."
                    ),
                    "type": "staticText",
                    "hittable": True,
                    "frame": [16, 668.3749999999999, 351.3333333333333, 373.33333333333314],
                },
                {
                    "id": "citation.close",
                    "label": "Close",
                    "type": "button",
                    "hittable": True,
                    "frame": [16, 72, 55.66666666666666, 52.33333333333333],
                },
                {
                    "id": "jobSheet.dim",
                    "label": "Close job sheet",
                    "type": "button",
                    "hittable": True,
                    "frame": [0, 0, 402, 874],
                },
            ],
        },
        "citation-page",
    )
    # Round-2 how-it-works body, judged against the card rather than a scroll view.
    card_clip = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "clips": [{"id": "onboarding.step.1", "frame": [24, 353.6666666666667, 354, 348]}],
            "elements": [
                {
                    "id": "",
                    "label": "Describe the problem in your own words. You do not need part names.",
                    "type": "staticText",
                    "hittable": True,
                    "frame": [40, 441, 322, 290.66666666666663],
                }
            ],
        },
        "onboarding-2",
    )
    # Round-2 welcome body. The scroll view is user-scrollable; the dots and Next are not.
    dots_overlap = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "scrollViews": [
                {"id": "onboarding.welcome", "frame": [0, 200.66666666666666, 402, 501]}
            ],
            "elements": [
                {
                    "id": "",
                    "label": (
                        "Ask about a problem in chat. Sidekick answers from the manuals, "
                        "with the page, and shows the part on a photo."
                    ),
                    "type": "staticText",
                    "hittable": True,
                    "frame": [24, 419.6666666666667, 348.6666666666667, 497.3333333333332],
                },
                {
                    "id": "onboarding.pageDots",
                    "label": "Screen 1 of 3",
                    "type": "other",
                    "hittable": True,
                    "frame": [182.5, 713.6666666666666, 37, 7],
                },
                {
                    "id": "onboarding.next",
                    "label": "Next",
                    "type": "button",
                    "hittable": True,
                    "frame": [24, 736.6666666666666, 354, 87.33333333333337],
                },
            ],
        },
        "onboarding-1",
    )
    bay_spill = measure_axxxl(
        {
            "window": window,
            "safeAreaTop": 59,
            "clips": [{"id": "onboarding.bay", "frame": [24, 210, 354, 120]}],
            "elements": [
                {
                    "id": "onboarding.bay.radiator",
                    "label": "radiator area",
                    "type": "staticText",
                    "hittable": True,
                    "frame": [30, 200, 300, 80],
                }
            ],
        },
        "onboarding-1",
    )

    import tempfile

    import verify_sidekick

    flag_errors = verify_sidekick.axxxl_flag_errors()
    if set(verify_sidekick.AXXXL_SCREENS) != set(AXXXL_SCREENS):
        flag_errors.append(
            f"screen lists differ: {verify_sidekick.AXXXL_SCREENS} vs {AXXXL_SCREENS}"
        )

    with tempfile.TemporaryDirectory() as tmp_name:
        tmp = Path(tmp_name)
        shot_dir = tmp / "screenshots"
        shot_dir.mkdir()
        Image.new("RGB", (402, 300), BG_F4).save(shot_dir / "chat.png")
        taps = tmp / "taps"
        taps.mkdir()
        (taps / "layout-axxxl.json").write_text(
            json.dumps(
                {
                    "screens": {
                        "chat": {
                            "window": window,
                            "safeAreaTop": 59,
                            "elements": [
                                {
                                    "id": "chat.jobs",
                                    "label": "Jobs",
                                    "type": "button",
                                    "frame": [360, 80, 80, 44],
                                }
                            ],
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        wired = evaluate(tmp, tmp / "compare")
        wired_cell = wired["screens"]["chat"]["large_text"]
        missing_dir = Path(tmp_name) / "no-axxxl"
        (missing_dir / "screenshots").mkdir(parents=True)
        Image.new("RGB", (402, 300), BG_F4).save(missing_dir / "screenshots" / "chat.png")
        unwired = evaluate(missing_dir, missing_dir / "compare")

    errors: list[str] = []
    if plain_result["verdict"] != "PASS":
        errors.append(f"plain Garage should PASS, got {plain_result}")
    if glass_result["verdict"] != "FAIL":
        errors.append(f"glass Garage should FAIL, got {glass_result}")
    if filled_result["verdict"] != "PASS":
        errors.append(f"filled Worked should PASS, got {filled_result}")
    if underline_result["verdict"] != "FAIL":
        errors.append(f"underlined Worked should FAIL, got {underline_result}")
    if clean["verdict"] != "REVIEW":
        errors.append(f"fitting Garage should be REVIEW, got {clean}")
    if overflow["verdict"] != "FAIL" or not any("extends past" in reason for reason in overflow["reasons"]):
        errors.append(f"Jobs past the right edge should FAIL, got {overflow}")
    if both_edges["verdict"] != "FAIL" or not any("extends past" in reason for reason in both_edges["reasons"]):
        errors.append(f"title clipped on both edges should FAIL, got {both_edges}")
    if island["verdict"] != "FAIL" or not any("island" in reason for reason in island["reasons"]):
        errors.append(f"title under the island should FAIL, got {island}")
    if truncated["verdict"] != "FAIL" or not any("truncated" in reason for reason in truncated["reasons"]):
        errors.append(f"Tod… should FAIL, got {truncated}")
    if squeezed["verdict"] != "FAIL" or not any("squeezed" in reason for reason in squeezed["reasons"]):
        errors.append(f"narrow Battery column should FAIL, got {squeezed}")
    if overlap["verdict"] != "FAIL" or not any("overlaps" in reason for reason in overlap["reasons"]):
        errors.append(f"Garage overlapping the title should FAIL, got {overlap}")
    if contained["verdict"] != "REVIEW":
        errors.append(f"a button containing its label should be REVIEW, got {contained}")
    if skipped["verdict"] != "N/A":
        errors.append(f"skipped Jobs screen should be N/A, got {skipped}")
    if missing["verdict"] != "FAIL":
        errors.append(f"missing scan-log frames should FAIL, got {missing}")
    if clipped_away["verdict"] != "REVIEW":
        errors.append(f"scrolled-off sheet content and the Garage sliver should be REVIEW, got {clipped_away}")
    if body_clip["verdict"] != "FAIL" or not any("overlaps" in reason for reason in body_clip["reasons"]):
        errors.append(f"welcome body over Next should FAIL, got {body_clip}")
    if scrollable_continuation["verdict"] != "REVIEW":
        errors.append(
            f"citation explanation below the fold should be REVIEW, got {scrollable_continuation}"
        )
    if card_clip["verdict"] != "FAIL" or not any(
        "clipped by its container" in reason for reason in card_clip["reasons"]
    ):
        errors.append(f"text clipped by a non-scrollable card should FAIL, got {card_clip}")
    if dots_overlap["verdict"] != "FAIL" or not any(
        "pageDots" in reason for reason in dots_overlap["reasons"]
    ):
        errors.append(f"welcome body overlapping the page dots should FAIL, got {dots_overlap}")
    if bay_spill["verdict"] != "FAIL" or not any("fixed container" in reason for reason in bay_spill["reasons"]):
        errors.append(f"illustration label outside its box should FAIL, got {bay_spill}")
    if flag_errors:
        errors.extend(flag_errors)
    if wired_cell["verdict"] != "FAIL":
        errors.append(f"evaluate() should FAIL chat large_text, got {wired_cell}")
    if wired["fail_count"] < 1:
        errors.append(f"evaluate() fail_count should include large_text, got {wired['fail_count']}")
    if unwired["screens"]["chat"]["large_text"]["verdict"] != "FAIL":
        errors.append(f"missing layout-axxxl.json should FAIL, got {unwired['screens']['chat']['large_text']}")
    if "Large text (AXXXL)" not in "\n".join(checklist_lines(wired)):
        errors.append("checklist omitted the large-text row")
    if errors:
        print("self-test FAIL")
        for err in errors:
            print(err)
        return 1
    print("self-test PASS")
    print(
        f"plain Garage {plain_result['verdict']} (halo {plain_result['halo_lum']} vs bar {plain_result['bar_lum']})"
    )
    print(f"glass Garage FAIL: {'; '.join(glass_result['reasons'])}")
    print(
        f"filled Worked PASS (lum {filled_result['fill_lum']}, "
        f"{filled_result['dark_fraction']:.0%} dark)"
    )
    print(f"underline Worked FAIL: {'; '.join(underline_result['reasons'])}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Synthetic glass/plain Garage and filled/underline Worked. No simulator.",
    )
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.run_dir is None:
        parser.error("provide --run-dir or --self-test")
    compare_dir = args.run_dir / "compare"
    compare_dir.mkdir(parents=True, exist_ok=True)
    report = evaluate(args.run_dir, compare_dir)
    (compare_dir / "design-checks.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("\n".join(checklist_lines(report)))
    return 3 if report["fail_count"] else 0


if __name__ == "__main__":
    sys.exit(main())
