#!/usr/bin/env python3
"""Low-fi iPhone wireframes for the Sidekick Mechanic user-journey design.

Grayscale boxes and placeholder copy only. No vehicle facts: specs, pinouts,
wire colors, part numbers, firing order, and torque values stay out. Manual
pointers use FAKE-DOC-2JZ and p. 999. The 2JZ-GE is naturally aspirated; the
placeholder bay has no turbo.

stdlib only. From the repo root:

    python3 docs/design/wireframes/generate_wireframes.py
"""

from __future__ import annotations

from pathlib import Path

OUT = Path(__file__).resolve().parent

# Logical iPhone 14 size, drawn 2x for GitHub.
SCALE = 2
PHONE_W, PHONE_H = 390, 844
PAD = 28
CANVAS_W = PHONE_W + PAD * 2
CANVAS_H = PHONE_H + PAD * 2 + 8

INK = "#222222"
MUTED = "#6e6e6e"
LINE = "#b4b4b4"
FILL = "#e8e8e8"
FILL_DARK = "#cfcfcf"
PAPER = "#ffffff"
SCREEN = "#f4f4f4"
BEZEL = "#1a1a1a"


def esc(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def rrect(
    x: float,
    y: float,
    w: float,
    h: float,
    rx: float = 8,
    fill: str = FILL,
    stroke: str | None = None,
    sw: float = 1,
    opacity: float | None = None,
) -> str:
    extra = ""
    if stroke:
        extra += f' stroke="{stroke}" stroke-width="{sw}"'
    else:
        extra += ' stroke="none"'
    if opacity is not None:
        extra += f' opacity="{opacity}"'
    return (
        f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
        f'rx="{rx:.1f}" fill="{fill}"{extra}/>'
    )


def line(x1: float, y1: float, x2: float, y2: float, stroke: str = LINE, sw: float = 1) -> str:
    return (
        f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
        f'stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round"/>'
    )


def text(
    x: float,
    y: float,
    body: str,
    size: float = 13,
    fill: str = INK,
    anchor: str = "start",
    weight: str = "400",
    family: str = "-apple-system, Helvetica, Arial, sans-serif",
) -> str:
    return (
        f'<text x="{x:.1f}" y="{y:.1f}" fill="{fill}" font-size="{size}" '
        f'font-weight="{weight}" font-family="{family}" text-anchor="{anchor}" '
        f'dominant-baseline="middle">{esc(body)}</text>'
    )


def multiline(
    x: float,
    y: float,
    body: str,
    size: float = 13,
    fill: str = INK,
    width: float = 300,
    leading: float = 1.35,
    weight: str = "400",
    anchor: str = "start",
) -> str:
    # Naive wrap on spaces. Wireframe copy is short on purpose.
    words = body.split()
    lines: list[str] = []
    row = ""
    avg = size * 0.52
    for word in words:
        trial = f"{row} {word}".strip()
        if avg * len(trial) > width and row:
            lines.append(row)
            row = word
        else:
            row = trial
    if row:
        lines.append(row)
    parts = []
    for i, row in enumerate(lines):
        parts.append(text(x, y + i * size * leading, row, size=size, fill=fill, weight=weight, anchor=anchor))
    return "\n".join(parts)


def chip(x: float, y: float, label: str, filled: bool = False) -> tuple[str, float]:
    pad_x = 8
    w = max(52, 7.2 * len(label) + pad_x * 2)
    h = 22
    if filled:
        shape = rrect(x, y, w, h, rx=11, fill=INK)
        label_el = text(x + w / 2, y + h / 2, label, size=11, fill=PAPER, anchor="middle", weight="600")
    else:
        shape = rrect(x, y, w, h, rx=11, fill=PAPER, stroke=LINE, sw=1)
        label_el = text(x + w / 2, y + h / 2, label, size=11, fill=INK, anchor="middle")
    return shape + "\n" + label_el, w


def button(x: float, y: float, w: float, h: float, label: str, primary: bool = True) -> str:
    if primary:
        return rrect(x, y, w, h, rx=12, fill=INK) + "\n" + text(
            x + w / 2, y + h / 2, label, size=15, fill=PAPER, anchor="middle", weight="600"
        )
    return rrect(x, y, w, h, rx=12, fill=PAPER, stroke=INK, sw=1.2) + "\n" + text(
        x + w / 2, y + h / 2, label, size=15, fill=INK, anchor="middle", weight="600"
    )


def handle(cx: float, y: float) -> str:
    return rrect(cx - 18, y, 36, 5, rx=2.5, fill=LINE)


def dots(cx: float, y: float, n: int, active: int) -> str:
    gap = 10
    start = cx - ((n - 1) * gap) / 2
    parts = []
    for i in range(n):
        fill = INK if i == active else LINE
        parts.append(f'<circle cx="{start + i * gap:.1f}" cy="{y:.1f}" r="3.2" fill="{fill}"/>')
    return "\n".join(parts)


def icon_pinch(x: float, y: float) -> str:
    # Magnifying glass = pinch-to-zoom. Drawn, not a photo.
    return "\n".join(
        [
            f'<circle cx="{x}" cy="{y}" r="16" fill="{PAPER}" fill-opacity="0.92" stroke="{INK}" stroke-width="1"/>',
            f'<circle cx="{x - 2}" cy="{y - 2}" r="6" fill="none" stroke="{INK}" stroke-width="1.5"/>',
            f'<line x1="{x + 2.2}" y1="{y + 2.2}" x2="{x + 7}" y2="{y + 7}" stroke="{INK}" stroke-width="1.6" stroke-linecap="round"/>',
        ]
    )


def placeholder_bay(
    x: float,
    y: float,
    w: float,
    h: float,
    *,
    outline: str | None = None,
    dashed: bool = False,
    label: str | None = None,
    banner: str | None = None,
) -> str:
    """Abstract NA 2JZ bay. Boxes only. Not Zeke's truck. No turbo snail."""
    show_labels = h >= 160
    parts = [rrect(x, y, w, h, rx=10, fill=FILL_DARK)]
    # Radiator across the front (top of the frame).
    parts.append(rrect(x + w * 0.08, y + h * 0.08, w * 0.84, h * 0.12, rx=4, fill=FILL, stroke=LINE, sw=1))
    if show_labels:
        parts.append(text(x + w * 0.5, y + h * 0.14, "radiator area", size=9, fill=MUTED, anchor="middle"))
    # Long engine block — inline six, naturally aspirated. No turbo. No label: it collides with the air box.
    block = (x + w * 0.18, y + h * 0.28, w * 0.64, h * 0.46)
    parts.append(rrect(*block, rx=6, fill="#d4d4d4", stroke=LINE, sw=1))
    # Air box on top of the engine (intake). The part we outline in most frames.
    air = (x + w * 0.28, y + h * 0.32, w * 0.44, h * 0.16)
    parts.append(rrect(*air, rx=5, fill="#eeeeee", stroke=LINE, sw=1))
    if show_labels:
        parts.append(text(x + w * 0.5, y + h * 0.40, "air box", size=10, fill=MUTED, anchor="middle"))
    # Battery and fuse box as anonymous squares so we never name a real part number.
    parts.append(rrect(x + w * 0.08, y + h * 0.72, w * 0.18, h * 0.16, rx=4, fill=FILL, stroke=LINE, sw=1))
    parts.append(rrect(x + w * 0.74, y + h * 0.70, w * 0.16, h * 0.18, rx=4, fill=FILL, stroke=LINE, sw=1))
    if outline:
        ox, oy, ow, oh = air
        dash = ' stroke-dasharray="6 5"' if dashed else ""
        stroke_w = 2.4 if not dashed else 2.0
        parts.append(
            f'<rect x="{ox - 3:.1f}" y="{oy - 3:.1f}" width="{ow + 6:.1f}" height="{oh + 6:.1f}" '
            f'rx="7" fill="none" stroke="{INK}" stroke-width="{stroke_w}"{dash}/>'
        )
        if label and h >= 200:
            lw = min(ow + 8, 120)
            parts.append(rrect(ox + (ow - lw) / 2, oy + oh + 10, lw, 18, rx=4, fill=PAPER, stroke=INK, sw=1))
            parts.append(text(ox + ow / 2, oy + oh + 19, label, size=10, fill=INK, anchor="middle", weight="600"))
    if banner:
        parts.append(rrect(x + 8, y + 8, w - 16, 24, rx=6, fill=PAPER, stroke=INK, sw=1, opacity=0.95))
        parts.append(text(x + w / 2, y + 20, banner, size=11, fill=INK, anchor="middle", weight="700"))
    return "\n".join(parts)


def status_bar(sx: float, sy: float, sw: float) -> str:
    return "\n".join(
        [
            text(sx + 18, sy + 14, "9:41", size=12, weight="600"),
            text(sx + sw - 18, sy + 14, "lll", size=11, fill=MUTED, anchor="end"),
        ]
    )


def island(sx: float, sy: float, sw: float) -> str:
    return rrect(sx + sw / 2 - 48, sy + 6, 96, 26, rx=13, fill=BEZEL)


def home_bar(sx: float, sy: float, sw: float, sh: float) -> str:
    return rrect(sx + sw / 2 - 54, sy + sh - 12, 108, 5, rx=2.5, fill=INK, opacity=0.25)


def nav(sx: float, sy: float, sw: float, title: str, trailing: str | None = None) -> str:
    parts = [text(sx + sw / 2, sy + 44, title, size=16, anchor="middle", weight="700")]
    if trailing:
        parts.append(text(sx + sw - 16, sy + 44, trailing, size=13, fill=MUTED, anchor="end"))
    return "\n".join(parts)


def phone_shell(inner: str) -> str:
    px, py = PAD, PAD
    sx, sy = px + 10, py + 10
    sw, sh = PHONE_W - 20, PHONE_H - 20
    return "\n".join(
        [
            rrect(px, py, PHONE_W, PHONE_H, rx=48, fill=BEZEL),
            rrect(sx, sy, sw, sh, rx=40, fill=SCREEN),
            f'<clipPath id="screen"><rect x="{sx:.1f}" y="{sy:.1f}" width="{sw:.1f}" height="{sh:.1f}" rx="40"/></clipPath>',
            f'<g clip-path="url(#screen)">\n{inner}\n</g>',
            island(sx, sy, sw),
            home_bar(sx, sy, sw, sh),
        ]
    )


def svg_doc(inner: str) -> str:
    # Unique clip ids: wrap each file separately so clipPath ids do not collide if inlined.
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_W * SCALE}" height="{CANVAS_H * SCALE}" '
        f'viewBox="0 0 {CANVAS_W} {CANVAS_H}" role="img">\n'
        f'<rect width="{CANVAS_W}" height="{CANVAS_H}" fill="#fafafa"/>\n'
        f"{inner}\n</svg>\n"
    )


def write(name: str, inner: str) -> None:
    path = OUT / name
    path.write_text(svg_doc(phone_shell(inner)), encoding="utf-8")
    print(f"wrote {path.name}")


def screen_origin() -> tuple[float, float, float, float]:
    px, py = PAD, PAD
    sx, sy = px + 10, py + 10
    sw, sh = PHONE_W - 20, PHONE_H - 20
    return sx, sy, sw, sh


def onboarding_1() -> str:
    sx, sy, sw, sh = screen_origin()
    parts = [
        status_bar(sx, sy, sw),
        nav(sx, sy, sw, "Sidekick", trailing="Skip"),
        placeholder_bay(sx + 24, sy + 72, sw - 48, 220, outline="outline"),
        text(sx + 28, sy + 322, "Your mechanic. One truck.", size=22, weight="700"),
        multiline(
            sx + 28,
            sy + 352,
            "Ask about a problem in chat. Sidekick answers from the manuals, with the page, and shows the part on a photo.",
            size=14,
            fill=MUTED,
            width=sw - 56,
        ),
        rrect(sx + 24, sy + 430, sw - 48, 64, rx=12, fill=PAPER, stroke=LINE, sw=1),
        text(sx + 40, sy + 452, "1990 Land Cruiser LJ78", size=13, weight="600"),
        text(sx + 40, sy + 472, "2JZ-GE swap · no turbo · donor year TBD", size=12, fill=MUTED),
        dots(sx + sw / 2, sy + sh - 86, 3, 0),
        button(sx + 24, sy + sh - 72, sw - 48, 44, "Next"),
    ]
    return "\n".join(parts)


def onboarding_2() -> str:
    sx, sy, sw, sh = screen_origin()
    cards = [
        ("1. Chat", "Describe the problem in your own words. You do not need part names."),
        ("2. Cited answer", "A short reply plus a chip like FAKE-DOC-2JZ · p. 999. Tap it to see that page."),
        ("3. Outline on a photo", "A line around the part. If your photo is new, the line goes on a labeled reference photo instead."),
    ]
    parts = [
        status_bar(sx, sy, sw),
        nav(sx, sy, sw, "How it works", trailing="Skip"),
        text(sx + 28, sy + 78, "Three things, every time", size=20, weight="700"),
    ]
    y = 108
    for title, body in cards:
        parts.append(rrect(sx + 24, sy + y, sw - 48, 112, rx=14, fill=PAPER, stroke=LINE, sw=1))
        parts.append(text(sx + 42, sy + y + 28, title, size=15, weight="700"))
        parts.append(multiline(sx + 42, sy + y + 52, body, size=13, fill=MUTED, width=sw - 92))
        y += 124
    parts += [
        dots(sx + sw / 2, sy + sh - 86, 3, 1),
        button(sx + 24, sy + sh - 72, sw - 48, 44, "Next"),
    ]
    return "\n".join(parts)


def onboarding_3() -> str:
    sx, sy, sw, sh = screen_origin()
    confirmed = [
        ("Chassis", "1990 Land Cruiser LJ78"),
        ("Engine", "2JZ-GE swap"),
        ("Donor ECU", "Lexus · year TBD"),
    ]
    tbd = [
        ("OBD type", "TBD"),
        ("Harness", "TBD"),
        ("Photo angles", "TBD"),
    ]
    parts = [
        status_bar(sx, sy, sw),
        nav(sx, sy, sw, "Your garage", trailing="Skip"),
        text(sx + 28, sy + 78, "Known facts only", size=20, weight="700"),
        multiline(
            sx + 28,
            sy + 106,
            "Nothing is filled in from memory. TBD stays TBD until it is confirmed in TRUCK.md.",
            size=13,
            fill=MUTED,
            width=sw - 56,
        ),
        text(sx + 28, sy + 168, "Confirmed", size=12, fill=MUTED, weight="700"),
    ]
    y = 184
    for k, v in confirmed:
        parts.append(rrect(sx + 24, sy + y, sw - 48, 44, rx=10, fill=PAPER, stroke=LINE, sw=1))
        parts.append(text(sx + 40, sy + y + 22, k, size=13, fill=MUTED))
        parts.append(text(sx + sw - 40, sy + y + 22, v, size=13, weight="600", anchor="end"))
        y += 50
    parts.append(text(sx + 28, sy + y + 10, "Still TBD", size=12, fill=MUTED, weight="700"))
    y += 26
    for k, v in tbd:
        parts.append(rrect(sx + 24, sy + y, sw - 48, 44, rx=10, fill=FILL))
        parts.append(text(sx + 40, sy + y + 22, k, size=13, fill=MUTED))
        parts.append(text(sx + sw - 40, sy + y + 22, v, size=13, fill=MUTED, anchor="end", weight="700"))
        y += 50
    parts += [
        dots(sx + sw / 2, sy + sh - 86, 3, 2),
        button(sx + 24, sy + sh - 72, sw - 48, 44, "Start chatting"),
    ]
    return "\n".join(parts)


def chat_backdrop(sx: float, sy: float, sw: float) -> str:
    parts = [
        status_bar(sx, sy, sw),
        nav(sx, sy, sw, "Sidekick"),
        rrect(sx + 86, sy + 72, sw - 110, 48, rx=16, fill=INK),
        multiline(sx + 102, sy + 88, "Rough idle after a cold start", size=12, fill=PAPER, width=sw - 140),
        rrect(sx + 16, sy + 132, sw - 72, 118, rx=16, fill=PAPER, stroke=LINE, sw=1),
        multiline(
            sx + 32,
            sy + 152,
            "Start with the air box on top of the engine. FAKE-DOC-2JZ p. 999 points there first.",
            size=13,
            width=sw - 110,
        ),
    ]
    chip_svg, _ = chip(sx + 32, sy + 214, "FAKE-DOC-2JZ · p. 999")
    parts.append(chip_svg)
    return "\n".join(parts)


def composer(sx: float, sy: float, sw: float, sh: float, y_from_bottom: float) -> str:
    y = sy + sh - y_from_bottom
    return "\n".join(
        [
            rrect(sx + 16, y, sw - 80, 40, rx=20, fill=PAPER, stroke=LINE, sw=1),
            text(sx + 32, y + 20, "Describe the problem", size=13, fill=MUTED),
            rrect(sx + sw - 56, y + 2, 36, 36, rx=18, fill=INK),
            f'<path d="M{sx + sw - 38:.1f},{y + 12:.1f} L{sx + sw - 48:.1f},{y + 28:.1f} L{sx + sw - 28:.1f},{y + 28:.1f} Z" fill="{PAPER}"/>',
        ]
    )


def job_sheet_collapsed() -> str:
    sx, sy, sw, sh = screen_origin()
    sheet_h = 132
    sheet_y = sy + sh - sheet_h
    chip_svg, _ = chip(sx + 80, sheet_y + 86, "intake")
    return "\n".join(
        [
            chat_backdrop(sx, sy, sw),
            composer(sx, sy, sw, sh, 184),
            rrect(sx, sheet_y, sw, sheet_h + 24, rx=18, fill=PAPER, stroke=LINE, sw=1),
            handle(sx + sw / 2, sheet_y + 10),
            text(sx + 20, sheet_y + 36, "Job · Cold idle", size=15, weight="700"),
            text(sx + sw - 20, sheet_y + 36, "Open", size=13, fill=MUTED, anchor="end"),
            rrect(sx + 20, sheet_y + 56, 48, 48, rx=8, fill=FILL_DARK),
            text(sx + 80, sheet_y + 72, "Photo + outline sit here", size=12, fill=MUTED),
            chip_svg,
        ]
    )


def job_sheet_half() -> str:
    sx, sy, sw, sh = screen_origin()
    sheet_h = 448
    sheet_y = sy + sh - sheet_h
    parts = [
        chat_backdrop(sx, sy, sw),
        rrect(sx, sy, sw, sh, rx=0, fill=INK, opacity=0.12),
        rrect(sx, sheet_y, sw, sheet_h + 24, rx=20, fill=PAPER),
        handle(sx + sw / 2, sheet_y + 10),
        text(sx + 20, sheet_y + 36, "Job · Cold idle", size=16, weight="700"),
        text(sx + sw - 20, sheet_y + 36, "Close", size=13, fill=MUTED, anchor="end"),
        placeholder_bay(sx + 16, sheet_y + 52, sw - 32, 128, outline="outline"),
        multiline(
            sx + 20,
            sheet_y + 196,
            "Start with the air box on top. FAKE-DOC-2JZ p. 999. No guessed numbers.",
            size=13,
            width=sw - 40,
        ),
    ]
    x = sx + 20
    for label in ("FAKE-DOC-2JZ · p. 999", "intake"):
        el, w = chip(x, sheet_y + 248, label)
        parts.append(el)
        x += w + 8
    parts += [
        text(sx + 20, sheet_y + 292, "Steps  1 of 3", size=12, fill=MUTED, weight="700"),
        rrect(sx + 20, sheet_y + 306, 18, 18, rx=4, fill=INK),
        text(sx + 48, sheet_y + 315, "Look at the air box", size=13),
        rrect(sx + 20, sheet_y + 332, 18, 18, rx=4, fill=PAPER, stroke=LINE, sw=1),
        text(sx + 48, sheet_y + 341, "Next step (from the cited page)", size=13, fill=MUTED),
        line(sx + 20, sheet_y + 368, sx + sw - 20, sheet_y + 368),
        text(sx + 20, sheet_y + 392, "Outcome", size=12, fill=MUTED, weight="700"),
        text(sx + 90, sheet_y + 392, "Worked   Partly   Didn't", size=13, weight="600"),
    ]
    return "\n".join(parts)


def job_sheet_full() -> str:
    sx, sy, sw, sh = screen_origin()
    parts = [
        status_bar(sx, sy, sw),
        rrect(sx, sy, sw, sh, rx=0, fill=PAPER),
        handle(sx + sw / 2, sy + 40),
        text(sx + sw / 2, sy + 62, "Job · Cold idle", size=16, weight="700", anchor="middle"),
        placeholder_bay(sx + 16, sy + 80, sw - 32, 168, outline="outline"),
        text(sx + 20, sy + 268, "Answer", size=12, fill=MUTED, weight="700"),
        multiline(
            sx + 20,
            sy + 288,
            "Start with the air box on top of the engine. Cited page only. FAKE-SPEC never shown as a real number.",
            size=13,
            width=sw - 40,
        ),
    ]
    x = sx + 20
    for label in ("FAKE-DOC-2JZ · p. 999", "intake", "watch"):
        el, w = chip(x, sy + 340, label, filled=(label == "watch"))
        parts.append(el)
        x += w + 6
    parts += [
        text(sx + 20, sy + 384, "Steps", size=12, fill=MUTED, weight="700"),
        rrect(sx + 20, sy + 398, 18, 18, rx=4, fill=INK),
        text(sx + 48, sy + 407, "Look at the air box", size=13),
        rrect(sx + 20, sy + 422, 18, 18, rx=4, fill=PAPER, stroke=LINE, sw=1),
        text(sx + 48, sy + 431, "Follow the cited page", size=13),
        rrect(sx + 20, sy + 446, 18, 18, rx=4, fill=PAPER, stroke=LINE, sw=1),
        text(sx + 48, sy + 455, "Stop if anything is TBD", size=13),
        text(sx + 20, sy + 490, "Notes", size=12, fill=MUTED, weight="700"),
        rrect(sx + 16, sy + 504, sw - 32, 56, rx=10, fill=SCREEN, stroke=LINE, sw=1),
        text(sx + 28, sy + 532, "Hoses look dry. No numbers guessed.", size=13, fill=MUTED),
        text(sx + 20, sy + 584, "Tags", size=12, fill=MUTED, weight="700"),
    ]
    x = sx + 20
    for label in ("cooling", "intake", "inspected"):
        el, w = chip(x, sy + 598, label)
        parts.append(el)
        x += w + 6
    parts.append(text(sx + x + 4, sy + 609, "+ add", size=12, fill=MUTED))
    parts += [
        text(sx + 20, sy + 648, "How did it go?", size=12, fill=MUTED, weight="700"),
        button(sx + 16, sy + 664, 108, 36, "Worked", primary=True),
        button(sx + 132, sy + 664, 108, 36, "Partly", primary=False),
        button(sx + 248, sy + 664, 108, 36, "Didn't", primary=False),
        rrect(sx + 16, sy + 712, sw - 32, 40, rx=10, fill=SCREEN, stroke=LINE, sw=1),
        text(sx + 28, sy + 732, "What fixed it? (optional)", size=13, fill=MUTED),
    ]
    return "\n".join(parts)


def highlight_card(
    *,
    state: str,
    outline: str | None,
    dashed: bool = False,
    banner: str | None = None,
    footer: list[str] | None = None,
    chips: list[str] | None = None,
    confirm: bool = False,
    flag: bool = False,
) -> str:
    sx, sy, sw, sh = screen_origin()
    card_top = sy + 78 if flag else sy + 56
    card_h = sh - 232 if confirm else sh - 210
    parts = [
        rrect(sx, sy, sw, sh, rx=0, fill=SCREEN),
        # Tinder-style stack: a card behind, then the photo card.
        rrect(sx + 22, card_top + 10, sw - 44, card_h - 8, rx=18, fill=FILL, stroke=LINE, sw=1),
        rrect(sx + 12, card_top, sw - 24, card_h, rx=18, fill=FILL_DARK),
        placeholder_bay(
            sx + 20, card_top + 8, sw - 40, card_h - 16, outline=outline, dashed=dashed, banner=banner
        ),
        icon_pinch(sx + sw - 44, card_top + card_h - 36),
        text(sx + sw - 44, card_top + card_h - 12, "pinch", size=9, fill=INK, anchor="middle"),
        text(sx + 20, sy + 36, "Close", size=13, fill=INK),
        text(sx + sw / 2, sy + 36, state, size=13, fill=MUTED, anchor="middle", weight="700"),
    ]
    if flag:
        parts.append(rrect(sx + 16, sy + 48, sw - 32, 22, rx=8, fill=INK))
        parts.append(
            text(
                sx + sw / 2,
                sy + 59,
                "Internal only · flag off in v1",
                size=11,
                fill=PAPER,
                anchor="middle",
                weight="600",
            )
        )
    y = sy + sh - 148
    if chips:
        x = sx + 16
        for label in chips:
            el, w = chip(x, y, label)
            parts.append(el)
            x += w + 6
        y += 32
    if confirm:
        parts.append(text(sx + sw / 2, y + 10, "Is this it?", size=18, weight="700", anchor="middle"))
        parts.append(button(sx + 16, y + 28, (sw - 44) / 2, 44, "Yes"))
        parts.append(button(sx + 28 + (sw - 44) / 2, y + 28, (sw - 44) / 2, 44, "Not this", primary=False))
    if footer:
        fy = sy + sh - 86
        for i, line_text in enumerate(footer):
            parts.append(text(sx + 20, fy + i * 16, line_text, size=12, fill=INK if i == 0 else MUTED))
    return "\n".join(parts)


def job_history() -> str:
    sx, sy, sw, sh = screen_origin()
    rows = [
        ("Cold idle", "Today", "Worked", True),
        ("Hard start", "Yesterday", "Partly", False),
        ("Battery light", "Sep 28", "Didn't", False),
        ("Hose check", "Sep 20", "Worked", True),
    ]
    parts = [
        status_bar(sx, sy, sw),
        nav(sx, sy, sw, "Jobs"),
        text(sx + 24, sy + 78, "One row per ask", size=13, fill=MUTED),
    ]
    y = 100
    for title, when, badge, filled in rows:
        parts.append(rrect(sx + 16, sy + y, sw - 32, 72, rx=14, fill=PAPER, stroke=LINE, sw=1))
        parts.append(rrect(sx + 28, sy + y + 14, 44, 44, rx=8, fill=FILL_DARK))
        parts.append(text(sx + 84, sy + y + 28, title, size=15, weight="700"))
        parts.append(text(sx + 84, sy + y + 48, when, size=12, fill=MUTED))
        el, w = chip(sx + sw - 32 - (7.2 * len(badge) + 20), sy + y + 25, badge, filled=filled)
        parts.append(el)
        y += 84
    parts.append(rrect(sx + 40, sy + sh - 28, sw - 80, 6, rx=3, fill=FILL))
    return "\n".join(parts)


def scan_log() -> str:
    sx, sy, sw, sh = screen_origin()
    parts = [
        status_bar(sx, sy, sw),
        nav(sx, sy, sw, "Scan log"),
        text(sx + 24, sy + 74, "Photos and outlines, filterable", size=13, fill=MUTED),
    ]
    x = sx + 16
    y = 96
    for label in ("all", "intake", "cooling", "ignition", "electrical", "fuel", "inspected", "watch"):
        el, w = chip(x, sy + y, label, filled=(label == "intake"))
        parts.append(el)
        x += w + 6
        if x > sx + sw - 80:
            x = sx + 16
            y += 28
    y = 160
    gap = 8
    cell = (sw - 32 - gap * 2) / 3
    thumbs = [
        True,
        True,
        False,
        True,
        False,
        True,
        True,
        True,
        False,
    ]
    tags = ["intake", "cooling", "—", "ignition", "—", "fuel", "intake", "electrical", "—"]
    for i, has_outline in enumerate(thumbs):
        col = i % 3
        row = i // 3
        cx = sx + 16 + col * (cell + gap)
        cy = sy + y + row * (cell + 28)
        outline = "outline" if has_outline else None
        parts.append(placeholder_bay(cx, cy, cell, cell, outline=outline))
        parts.append(text(cx + 4, cy + cell + 14, tags[i], size=10, fill=MUTED))
    return "\n".join(parts)


def main() -> None:
    write("onboarding-1.svg", onboarding_1())
    write("onboarding-2.svg", onboarding_2())
    write("onboarding-3.svg", onboarding_3())
    write("job-sheet-collapsed.svg", job_sheet_collapsed())
    write("job-sheet-half.svg", job_sheet_half())
    write("job-sheet-full.svg", job_sheet_full())
    write(
        "highlight-confident.svg",
        highlight_card(
            state="Your photo",
            outline="outline",
            chips=["intake", "inspected"],
            footer=["Confident outline  ·  pinch to zoom"],
        ),
    )
    write(
        "highlight-unsure.svg",
        highlight_card(
            state="Unsure",
            outline="outline",
            dashed=True,
            chips=["intake"],
            confirm=True,
            flag=True,
        ),
    )
    write(
        "highlight-not-found.svg",
        highlight_card(
            state="Your photo",
            outline=None,
            footer=[
                "Not in this photo",
                "Open diagram  ·  FAKE-DOC-2JZ p. 999",
            ],
        ),
    )
    write(
        "highlight-reference.svg",
        highlight_card(
            state="Reference",
            outline="outline",
            banner="Reference, not your truck",
            chips=["intake"],
            footer=[
                "No outline on your photo (not traced yet)",
                "Retake from a standard angle · TBD",
                "Diagram  ·  FAKE-DOC-2JZ p. 999",
            ],
        ),
    )
    write("job-history.svg", job_history())
    write("scan-log.svg", scan_log())
    try:
        import cairosvg  # type: ignore
    except ImportError:
        print("cairosvg not installed; SVG only. pip install cairosvg to also write PNG.")
        return
    for svg in sorted(OUT.glob("*.svg")):
        png = svg.with_suffix(".png")
        cairosvg.svg2png(
            url=str(svg),
            write_to=str(png),
            output_width=CANVAS_W * SCALE,
            output_height=CANVAS_H * SCALE,
        )
        print(f"wrote {png.name}")


if __name__ == "__main__":
    main()
