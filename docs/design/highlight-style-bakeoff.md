# Highlight style bakeoff

The default highlight config is an 8 px fuchsia outline and interior saturation of 3.0. Dim is off (`dim_factor` 1.0). The treatment does not draw a circle.

Those values are the defaults on `HighlightConfig` in [`backend/highlight.py`](../../backend/highlight.py). `render_highlight` applies one operation per call. The winning treatment is saturate, then outline.

## What was compared

Three style configs, on the same five 390×260 scenes: `dark`, `bright`, `mid`, `clutter`, `small`.

The licensed manifest ([`backend/data/prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json)) has one photo. That is not five photos, and this bakeoff does not add another third-party image. The five scenes are synthetic. They are not the owner's truck.

`~/.cursor/rules/pstack-models.mdc` was not present, so the arena used its fallback runners: one candidate each on Claude Opus, GPT, and Grok, then a Claude Opus cross-judge.

The bay map schema and the highlight renderer merged to main while the comparison was in progress. The comparison used a local applicator with the same four operations. That applicator is not in the tree. The winner is the default `HighlightConfig`, drawn by `render_highlight`.

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

`fuchsia-trace` is an opaque fuchsia stroke, 8 px, saturate 3.0, dim off, circle off.

`magenta-focus-ring` is a 10 px magenta stroke, saturate 2.7, dim 0.7, and a 5 px circle with 14 px pad.

`blaze-contour` is a 12 px orange stroke, saturate 3.0, dim off, circle off.

Two of the three candidates agreed on the shape: a chromatic outline, saturation inside, no dim, no circle. The base is the 8 px fuchsia version. It leaves the surround unchanged outside the stroke, and it leaves more of the small part uncovered than the 12 px stroke.

## Grafts

Nothing from the losers was copied into the config.

Rejected:

- The 0.7 dim. It grays the bright scene and pushes the dark scene's faint shapes toward the canvas. The default `dim_factor` is 1.0, which leaves the photo unchanged. A caller can still pass a lower factor.
- The always-on circle. It crosses neighbors on the large parts and on the clutter blobs. It helped only the small part. `HighlightConfig` still has circle fields because `render_highlight` can draw that style when asked. The default circle ink is the same fuchsia, so it is not a second color. The winning treatment does not call it.
- The 12 px orange stroke. It covers the small part, and orange sits close to green interiors under simulated protan vision.

The comparison applicator drew a disk at each vertex because its polyline left a gap where the outline closed. That applicator is gone. `render_highlight` strokes with `ImageDraw.polygon`, which closes the outline. An outward stroke, so a thick line would sit outside a small part, was not added here.

## Check

`backend/tests/test_highlight.py` asserts the default config and literal pixels for outline, saturate, circle, and dim, and matches the golden images. The five-scene sheets were re-rendered with `render_highlight` after the defaults changed: each scene's corner pixel stayed the source color. No phone and no Xcode run. There is no app-target Swift in this change.
