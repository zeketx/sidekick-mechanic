# Part resolver

This page describes the resolver that merged in [issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32). It is slated to be reworked. The product rule is a precise outline on any still photo, including one that has never been traced. A bounding box is never the highlight. Confident, unsure ("Is this it?"), and not-found behavior is [issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87). The pipeline spike is [issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85). [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33) replace this path. Until then, this resolver still emits only `bay_photo_id` and `part_id`, and only for a confirmed region. Do not treat that limit as the product rule, and do not change the schema here.

The answer can point at one bay-map part. The highlight is that part on the photo where its confirmed region is largest. An unsure, unknown, or unmapped choice highlights nothing.

`BayMapView` in `backend/part_resolver.py` is the view the resolver reads. `as_bay_map_view` in `backend/bay_map.py` builds it from the bay map schema. Polygons, image size, display names, aliases, license, and source stay in that schema.

## Call

```python
payload = resolve_answer(answer, selection_text, bay_map)
```

`answer` matches `backend/contracts/answer.schema.json`. `selection_text` is the model reply. `bay_map` is a `BayMapView`.

`LlmAnswerProducer` makes that second model call only when it is constructed with a non-empty `BayMapView`. The default producer passes no map, so `POST /chat` does not highlight until a caller supplies one. End-to-end photo rendering is issue #33.

## What the model may return

The prompt lists every `part_id` on the view. The reply is one JSON object:

- `{"part_id": "<id>"}` where `<id>` is copied from that list
- `{"part_id": null}` when no single listed part applies, or the model is unsure

Anything else is not a selection. An array, a second key, prose, or two ids is ambiguous. A single JSON string that is not in the list is unknown. The resolver does not search the answer text for a part.

One surrounding Markdown code fence is stripped, so a fenced JSON object still counts. Trailing prose is ambiguous.

## What the owner sees

| Selection | Highlight | Answer text |
| --- | --- | --- |
| One listed part with a confirmed region of `area_px` > 0 | `bay_photo_id` of that region, plus `part_id` | Unchanged |
| Explicit null | None | Unchanged |
| Ambiguous | None | Unchanged |
| Unknown id, or a listed part with no usable region | None | Appends `This part is not mapped yet.` |

A refusal is returned without a highlight and without that sentence. The sentence is not added twice.

Usable regions are `confirmed` and `area_px` > 0. Unconfirmed regions never win, including when their area is larger. That flag is how this resolver follows the shipped bay-map rule. The product rule is the note at the top of this page: a missing trace does not block a highlight.

The winning region is the maximum `area_px`. The #26 adapter must pass areas on one scale (same image size, or one normalized unit). Equal areas break ties by `bay_photo_id`, then `angle_id`, so the choice does not move between runs.

A failed selection call logs a warning and leaves the answer without a highlight. It does not claim the part is unmapped, because the model never chose.

## Fixtures

Tests use `fake-part-*`, `fake-bay-photo-*`, `fake-angle-*`, `FAKE-DOC`, and page 999. No truck part number, pinout, torque, wire color, or manual page is stored here.
