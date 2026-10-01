# Highlight style bakeoff

The default highlight is an 8 px fuchsia outline around the part, with the part's interior saturation at 3.0. The rest of the photo is unchanged. There is no circle.

The config is [`backend/data/highlight_style.json`](../../backend/data/highlight_style.json). `default_highlight_style()` loads it.

## What was compared

Three style configs, rendered by one applicator on the same five 390×260 scenes: `dark`, `bright`, `mid`, `clutter`, `small`.

The licensed manifest ([`backend/data/prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json)) has one photo. That is not five photos, and this bakeoff does not add another third-party image. The five scenes are synthetic. They are not the owner's truck.

Issue #26 (bay map schema) and issue #29 (highlight renderer) are not merged. The applicator is the local stand-in `(photo, polygon, style) -> image` in `backend/highlight_style.py`. It is not the #29 renderer: no golden-image suite and no 12 MP timing claim. Polygons are passed in. This module does not define a bay map.

`~/.cursor/rules/pstack-models.mdc` was not present, so the arena used its fallback runners: one candidate each on Claude Opus, GPT, and Grok, then a Claude Opus cross-judge.

## Rubric

Each criterion was scored 0, 1, or 2.

1. The part is obvious at a glance on a 390 px-wide image.
2. Context stays readable. Neighboring shapes keep their structure.
3. The part is findable on the dark scene.
4. The part is findable on the bright scene.
5. On the clutter scene and the small part, one part is singled out. The stroke does not eat the small part, and a circle does not enclose neighbors.
6. The config is one small object: outline, saturate, dim, optional circle. No vehicle facts.

## Scores

The parent read and the cross-judge picked the same base. The only score that differed was context on the magenta ring: the parent gave it 1, the judge gave it 0. Both still ranked that candidate last. The table is the judge's scores.

| Criterion | fuchsia-trace | magenta-focus-ring | blaze-contour |
| --- | --- | --- | --- |
| Glance | 2 | 2 | 2 |
| Context | 2 | 0 | 2 |
| Dark | 2 | 1 | 2 |
| Bright | 2 | 1 | 2 |
| Clutter and small | 2 | 1 | 1 |
| Config | 2 | 2 | 2 |
| Total | 12 | 7 | 11 |

`fuchsia-trace` is an opaque `[255, 0, 255, 255]` stroke, 8 px, saturate 3.0, dim 1.0, circle off, disabled circle fields zeroed.

`magenta-focus-ring` is a 10 px magenta stroke, saturate 2.7, dim 0.7, and a 5 px circle with 14 px pad.

`blaze-contour` is a 12 px orange stroke, saturate 3.0, dim 1.0, circle off.

Two of the three candidates agreed on the shape: a chromatic outline, saturation inside, no dim, no circle. The base is the 8 px fuchsia version. It leaves the surround pixel-identical outside the stroke, and it leaves more of the small part uncovered than the 12 px stroke (the small-part interior pixel `(308, 182)` stays a darkened green, not ink).

## Grafts

Nothing from the losers was copied into the config.

Rejected:

- The 0.7 dim. It grays the bright scene and pushes the dark scene's faint shapes toward the canvas.
- The always-on circle. It crosses neighbors on the large parts and on the clutter blobs. It helped only the small part.
- The 12 px orange stroke. It covers the small part, and orange sits close to green interiors under simulated protan vision. The disabled circle color was also left orange; disabled fields on the winner are zero.

The stand-in applicator draws a disk at each polygon vertex. Pillow's polyline leaves a gap where the outline closes, and that notch showed up at 8 px during the bakeoff. The disks close the joint. They do not change the config.

Deferred, not built here:

- Drawing the stroke outside the polygon, so a thick line does not cover a small part. That belongs to the #29 renderer.
- A circle that appears only for a small part and only when it would not cross another region. The config cannot say that. It needs its own issue.

## Check

`backend/tests/test_highlight_style.py` loads the default and checks literal pixels on all five scenes: untouched context, fuchsia at the closing vertex, saturated interior, and a still-visible small-part interior. No phone and no Xcode run. There is no app-target Swift in this change.
