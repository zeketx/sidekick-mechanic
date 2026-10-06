#!/usr/bin/env python3
"""Put a simulator screenshot next to the matching Figma (or #94 wireframe) PNG.

    python3 .cursor/skills/verify-sidekick/scripts/compare_figma.py \\
        --sim artifacts/verify/<id>/screenshots/job-history.png \\
        --figma .cursor/skills/verify-sidekick/features/figma/job-history.png \\
        --out artifacts/verify/<id>/compare/job-history.png \\
        --screen job-history

    python3 .cursor/skills/verify-sidekick/scripts/compare_figma.py --run-dir artifacts/verify/<id>

Proof is the side-by-side PNG plus compare/checklist.md. This script does not
score pixels. An agent fills pass/fail after looking at every visible difference.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
FIGMA_DIR = SKILL / "features" / "figma"
REPO = Path(__file__).resolve().parents[4]

LABEL_HEIGHT = 64
PADDING = 24
BG = (28, 28, 32, 255)
LABEL_FILL = (255, 255, 255, 255)
MAX_PANEL_HEIGHT = 1600


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Side-by-side Figma vs simulator.")
    parser.add_argument("--sim", type=Path, help="Simulator screenshot PNG")
    parser.add_argument("--figma", type=Path, help="Figma / wireframe PNG")
    parser.add_argument("--out", type=Path, help="Output side-by-side PNG")
    parser.add_argument("--screen", help="Screen id used in the Figma label")
    parser.add_argument("--run-dir", type=Path, help="artifacts/verify/<run-id> with screenshots/")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Stitch a committed screenshot against its Figma ref (Linux-safe).",
    )
    args = parser.parse_args(argv)

    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:
        print(
            "compare_figma.py needs Pillow. Run: python3 -m pip install pillow",
            file=sys.stderr,
        )
        raise SystemExit(2) from exc

    if args.self_test:
        run_dir = args.run_dir or (REPO / "artifacts" / "verify" / "self-test")
        return command_self_test(Image, ImageDraw, ImageFont, run_dir)

    if args.run_dir is not None:
        return command_run_dir(Image, ImageDraw, ImageFont, args.run_dir)

    if not args.sim or not args.figma or not args.out:
        parser.error("provide --sim --figma --out, or --run-dir, or --self-test")
    screen = args.screen or args.sim.stem
    args.out.parent.mkdir(parents=True, exist_ok=True)
    stitch(Image, ImageDraw, ImageFont, args.figma, args.sim, args.out, screen)
    print(args.out)
    return 0


def command_run_dir(Image, ImageDraw, ImageFont, run_dir: Path) -> int:
    shots = run_dir / "screenshots"
    if not shots.is_dir():
        print(f"no screenshots directory: {shots}", file=sys.stderr)
        return 1
    out_dir = run_dir / "compare"
    out_dir.mkdir(parents=True, exist_ok=True)
    wrote: list[str] = []
    missing: list[str] = []
    for shot in sorted(shots.glob("*.png")):
        figma = FIGMA_DIR / shot.name
        if not figma.is_file():
            missing.append(shot.name)
            continue
        dest = out_dir / shot.name
        stitch(Image, ImageDraw, ImageFont, figma, shot, dest, shot.stem)
        wrote.append(str(dest.relative_to(run_dir)))
    write_checklist(out_dir / "checklist.md", wrote, missing)
    if not wrote:
        print("no Figma refs matched screenshots", file=sys.stderr)
        return 1
    print(f"wrote {len(wrote)} side-by-side image(s) under {out_dir}")
    for name in missing:
        print(f"no Figma ref for {name}", file=sys.stderr)
    return 0


def command_self_test(Image, ImageDraw, ImageFont, run_dir: Path) -> int:
    """Linux can prove the stitcher with a committed screenshot, not a live sim."""
    sim = REPO / "docs" / "screenshots" / "pr114" / "job-history.png"
    figma = FIGMA_DIR / "job-history.png"
    if not sim.is_file() or not figma.is_file():
        print("self-test missing job-history screenshot or Figma ref", file=sys.stderr)
        return 1
    out_dir = run_dir / "compare"
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / "job-history.png"
    stitch(Image, ImageDraw, ImageFont, figma, sim, dest, "job-history")
    write_checklist(
        out_dir / "checklist.md",
        [str(dest.relative_to(run_dir))],
        [],
        note=(
            "Linux self-test: left is the #94 wireframe, right is the committed "
            "PR #114 simulator shot. This is not a live drive. A Mac run replaces "
            "this with a fresh simctl screenshot."
        ),
    )
    print(dest)
    return 0


def stitch(Image, ImageDraw, ImageFont, figma_path: Path, sim_path: Path, out_path: Path, screen: str) -> None:
    figma = Image.open(figma_path).convert("RGBA")
    sim = Image.open(sim_path).convert("RGBA")
    figma = fit_height(Image, figma, MAX_PANEL_HEIGHT)
    sim = fit_height(Image, sim, MAX_PANEL_HEIGHT)
    panel_h = max(figma.height, sim.height)
    figma = pad_panel(Image, figma, panel_h)
    sim = pad_panel(Image, sim, panel_h)
    width = figma.width + sim.width + PADDING * 3
    height = panel_h + LABEL_HEIGHT + PADDING * 2
    canvas = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(canvas)
    font = load_font(ImageFont, 28)
    small = load_font(ImageFont, 18)
    draw.text((PADDING, PADDING), f"Figma", fill=LABEL_FILL, font=font)
    draw.text((PADDING, PADDING + 32), screen, fill=(180, 180, 186, 255), font=small)
    draw.text((PADDING * 2 + figma.width, PADDING), "Simulator", fill=LABEL_FILL, font=font)
    canvas.paste(figma, (PADDING, PADDING + LABEL_HEIGHT), figma)
    canvas.paste(sim, (PADDING * 2 + figma.width, PADDING + LABEL_HEIGHT), sim)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path, "PNG")


def fit_height(Image, image, max_height: int):
    if image.height <= max_height:
        return image
    scale = max_height / image.height
    size = (max(1, int(image.width * scale)), max_height)
    return image.resize(size, Image.Resampling.LANCZOS)


def pad_panel(Image, image, height: int):
    if image.height == height:
        return image
    canvas = Image.new("RGBA", (image.width, height), (40, 40, 44, 255))
    canvas.paste(image, (0, 0), image)
    return canvas


def load_font(ImageFont, size: int):
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def write_checklist(path: Path, wrote: list[str], missing: list[str], note: str | None = None) -> None:
    lines = [
        "# Design checklist",
        "",
        "Fill pass/fail after looking at every side-by-side. Pixel match is not required.",
        "List every visible difference against the Figma frame, not only the asked-about ones.",
        "",
    ]
    if note:
        lines.extend([note, ""])
    lines.extend(
        [
            "## Side-by-sides in this run",
            "",
        ]
    )
    if wrote:
        for name in wrote:
            lines.append(f"- `{name}`")
    else:
        lines.append("- (none)")
    if missing:
        lines.extend(["", "## Missing Figma refs", ""])
        for name in missing:
            lines.append(f"- `{name}`")
    lines.extend(
        [
            "",
            "## Standing rules (every UI change)",
            "",
            "| Rule | Pass / Fail | Evidence |",
            "| --- | --- | --- |",
            "| Highlight is a precise outline that follows the part. Never a box or rectangle. Low confidence is a dashed outline or none. |  |  |",
            "| Bottom sheet is edge to edge in collapsed, half, and full: full width, no side inset. Full height reaches the bottom of the screen with no bottom padding, gray strip, or squared-off bottom. Rounded top corners only. Sheet is white. Content behind is dimmed (scrim none/light at collapsed, stronger at half and full). |  |  |",
            "| Composer is a fully rounded pill (\"Describe the problem\") with no boxy corners, on one consistent background color above and below. |  |  |",
            "| Nav / header buttons are plain text (Close, Jobs, Scan log, Back). Never truncated glass capsules. |  |  |",
            "| Status bar and titles stay visible (no black-on-black). Nothing clipped or overlapping. Neutral #F4F4F4 background. |  |  |",
            "| Matches the Figma frame for this screen. Every visible difference is listed. |  |  |",
            "",
            "## Differences vs Figma",
            "",
            "- ",
            "",
            "Do not report done without the side-by-side PNGs and this table filled in.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
