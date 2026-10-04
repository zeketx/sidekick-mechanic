"""Render demo-mode highlight proofs with highlight.py.

One photo per scripted state. The HRYMX stand-in is grayscale, so saturate
is a no-op there; outline and confirm proofs use the Hilux bay (color).
Not Zeke's truck. Confirm uses the softer demo config.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from demo import (
    DEMO_DIM_FACTOR,
    DEMO_LABEL,
    confirm_highlight_config,
    load_catalog,
    pixel_rings,
)
from highlight import HighlightConfig, HighlightStyle, render_highlight

# photo_id, part_id — color bay for fill styles; HRYMX for the abstain state.
STATE_TARGETS = {
    "outline": ("commons-hilux-2jz", "fuse-relay-box"),
    "confirm": ("commons-hilux-2jz", "radiator-cap-upper-hose"),
    "not_found": ("hrymx-2jz-ge-25308847029", "coil-packs"),
}


def render_proofs(dest: Path) -> list[Path]:
    dest.mkdir(parents=True, exist_ok=True)
    catalog = load_catalog()
    written: list[Path] = []
    notes: list[str] = [DEMO_LABEL]
    for state, (photo_id, part_id) in STATE_TARGETS.items():
        photo = catalog.photo(photo_id)
        if photo is None:
            raise SystemExit(f"missing demo photo {photo_id}")
        part = photo.part(part_id)
        if part is None:
            raise SystemExit(f"missing part {part_id}")
        source = Image.open(photo.image_path).convert("RGB")
        notes.append(f"{state}: {part.display_name} on {photo.attribution}")
        if state == "not_found":
            path = dest / f"{state}.jpg"
            source.save(path, quality=85)
            written.append(path)
            continue
        rings = pixel_rings(part, source.width, source.height)
        for style in HighlightStyle:
            if state == "confirm":
                config = confirm_highlight_config()
            elif style is HighlightStyle.DIM:
                # Bakeoff default dim_factor is 1.0 (no-op). Proofs use the
                # same 55–65% dim as the demo overlay (~0.40 brightness).
                config = HighlightConfig(dim_factor=DEMO_DIM_FACTOR)
            else:
                config = HighlightConfig()
            rendered = source.copy()
            for ring in rings:
                rendered = render_highlight(rendered, ring, style, config)
            path = dest / f"{state}-{style.value}.jpg"
            rendered.save(path, quality=85)
            written.append(path)
    notes.append(
        "Styles: outline, saturate, circle, dim. "
        "Confirm uses a thinner stroke and saturation 2.0. "
        f"Dim uses dim_factor {DEMO_DIM_FACTOR} (~60% darken) for both rows; "
        "confirm stays softer via stroke and saturation, not a weaker dim. "
        "Circle uses the bounding-box center. The bakeoff default dim is 1.0."
    )
    (dest / "README.txt").write_text("\n".join(notes) + "\n", encoding="utf-8")
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dest",
        type=Path,
        default=Path("/opt/cursor/artifacts/demo-highlight-proofs"),
    )
    args = parser.parse_args(argv)
    paths = render_proofs(args.dest)
    print(f"wrote {len(paths)} proof image(s) into {args.dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
