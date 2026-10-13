# Bay map schema

## Requirement change (2026-10-02)

The owner changed the product rule, and the product lead and the engineer agreed the follow-on work.

A highlight works on any still photo, including one that has never been traced. The mark is a precise outline of the part, or of a group of parts. A bounding box is never the highlight. Styles stay outline, saturate, circle, and dim the rest. Phase 1 does not track the live camera. The person asking knows nothing about engines or part names. Pointing at the right thing is the core of the product.

This bay map is optional. It is an accuracy boost on the owner's reference photos, and the answer key for mask IoU against hand labels. [Issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84) is the held-out labeled set: about 20 public photos, about 100–160 photo×part queries including "not visible", polygon labels.

How a new photo becomes a mask is [issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85), a spike of about 2–3 days. Three pipelines, each with a verify pass that sets confidence. No pick yet.

- **A (preferred).** A vision model grounds the part, then SAM 2 cuts the mask.
- **B (open baseline).** Grounding DINO plus SAM 2.
- **C.** A vision model draws the mask directly.

Zeke approved a paid vision API on 2026-10-02. The provider is OpenRouter. Paths A and C are unblocked for the #85 spike. The cost target is still ≤ $0.03 per photo. The key is a Railway secret for the product and is never committed. If no candidate gets wrong-part ≤ 5%, stop and rethink. Do not ship.

Confidence is [issue #87](https://github.com/zeketx/sidekick-mechanic/issues/87). Confident means a precise outline. Unsure means a softer highlight and "Is this it?" with Yes and Not this, logged as eval data. Not found means no highlight, plus a pointer to the manual diagram. Thresholds are precision-first. A wrong highlight is worse than none. A confirmed highlight can be saved back as a traced region.

The wire highlight is still `{bay_photo_id, part_id}`. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) is contract v2: a photo ref, polygons plus an optional mask, labels, state (`confident`, `unsure`, `not_found`), method (`traced` or `inferred`), and scores. It reopens [issue #9](https://github.com/zeketx/sidekick-mechanic/issues/9) and [issue #10](https://github.com/zeketx/sidekick-mechanic/issues/10). This page does not change the schema. The bay-map-only resolver from [issue #32](https://github.com/zeketx/sidekick-mechanic/issues/32) is reworked through #86 and [issue #33](https://github.com/zeketx/sidekick-mechanic/issues/33).

Proposed targets, pending Zeke's confirmation after #85, are in [VISION.md](../../VISION.md) and [ROADMAP.md](../../ROADMAP.md). Acceptance eval is [issue #88](https://github.com/zeketx/sidekick-mechanic/issues/88).

Order: #84 → #85 → Engineer design PR → #86 → #87 → [issue #31](https://github.com/zeketx/sidekick-mechanic/issues/31) → #33 → #88.

The sections below describe the schema that is in the repo today.

## Problem

A highlight on an answer is already `{bay_photo_id, part_id}`. Nothing in the repo can say whether that pair is a real, confirmed region. Labeling (#28), the Python renderer (#29), the Swift renderer (#31), and the part resolver (#32) all need one catalog for angles, photos, parts, polygons, confirmation, source, and license. The answer wire does not change in this schema. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) is the later change. Real angles and parts stay TBD until the owner photographs the bay.

## Usage (caller's view)

Decode the file and ask the map. The caller does not sum areas or read a confirmation flag.

```swift
let map = try JSONDecoder().decode(BayMap.self, from: data)
let allowed = map.highlightChoices.map(\.part.id)
if let highlight = found.highlight.flatMap(map.resolve) {
    draw(highlight.geometry.polygons, highlight.photo.imageSize)
}
```

The resolver (#32) offers the model `highlightChoices` and copies `choice.reference` onto the answer. A part that is missing, or that only has unconfirmed regions, is not in that list.

```python
bay_map = load_bay_map(path.read_bytes())
choice = next((item for item in bay_map.highlight_choices if item.part_id == picked), None)
highlight = None if choice is None else {
    "bay_photo_id": choice.bay_photo_id,
    "part_id": choice.part_id,
}
```

`resolve` is the draw path. It returns nil for an unknown pair and for an unconfirmed pair. It does not switch the answer to a larger photo.

## Shape

`BayMap` is the public module. It decodes `backend/contracts/bay_map.schema.json` and keeps regions in private indexes. `highlightChoices` lists each part that has at least one confirmed region, paired with the preferred photo. `resolve` returns a `ConfirmedHighlight` only for a confirmed pair. That type has no public initializer. An unconfirmed region is stored and round-trips through JSON, and it has no `ConfirmedHighlight`.

The preferred photo is the confirmed region with the greatest pixel area. Pixel area is the normalized shoelace sum times `width * height`, rounded half away from zero to an integer. Equal areas pick the smaller `bay_photo_id`, then the smaller `angle_id`. That is the same order as `largest_confirmed_region` in `part_resolver.py`. The shoelace sum walks points in file order and closes from the last point back to the first. Image size is also what a converter divides by when it turns COCO pixels or Label Studio percentages into the unit square.

Coordinates in the file are normalized. The origin is the top left. x increases to the right. y increases down. Each axis is in 0...1 inclusive. The schema fixes that as four constants on `coordinate_space`. The app target flips y for Core Image. `SidekickCore` does not import Core Image.

Photos and regions are arrays, not objects keyed by id. A duplicate `bay_photo_id`, `part_id`, or `(bay_photo_id, part_id)` pair is a second array element, so both the Python loader and the Swift decoder reject it. JSON object keys would not. `json.loads` and `JSONDecoder` keep one copy and drop the other.

Each photo has an `angle_id`, `image_size`, `source`, and `license`. Angle ids may repeat. Two frames can share an angle while a public prototype and an owner retake both exist. Source `kind` is `public_prototype` or `owner_observation`. Every photo has a license `name` and `reference`, so a frame cannot be saved with the rights fields left off. The fixture values are `FAKE-*`. Real license text stays TBD.

A part has `part_id`, `display_name`, and `aliases`. Every part must appear on at least one region, confirmed or not. The resolver's closed list is `highlightChoices`, not the full part list. Aliases are unique, and an alias cannot equal a part id or a display name.

A region has one or more polygons. Occlusion is another polygon on the same region, not a second region for the pair. Confirmation is `kind: confirmed` plus `confirmed_by`, or `kind: unconfirmed` with no `confirmed_by`. `schema_version` is 1.

Validation of shape, ranges, and those `kind` values is the JSON Schema. Uniqueness, alias collisions, positive area, and a polygon that repeats its first point are loader checks, because Draft 2020-12 cannot say them. Swift `Codable` still ignores unknown keys. The Python schema is the strict wire check, same as the answer contract.

`Answer` does not import `BayMap`. `HighlightRef` keys stay `bay_photo_id` and `part_id` until [issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86).

This is the first landing. A later change to these keys runs `/blast-radius` before the edit. This change does not.

## Synthesis decision

Three architect runners were scheduled. The Opus runner timed out and wrote nothing. Sol and Grok both finished. Opus and Sol are the runners scheduled that day. The current roster is the Grok map in [`.cursor/rules/pstack-models.mdc`](../../.cursor/rules/pstack-models.mdc).

Sol is the base. Its public surface is the catalog plus `highlightChoices` and `resolve`, and `ConfirmedHighlight` is the only highlight value. Grok exposed draft regions on the Swift type and used a `1e-9` area tie that is not a total order.

Grafted from Grok:

- The fixture cases. An unconfirmed region on `fake-part-intake` itself, a second polygon for occlusion, a confirmed region on a larger image, and an equal-area tie between `fake-bay-photo-aaa` and `fake-bay-photo-mmm`.
- The Python loader in this change, with the same outcomes as the Swift tests.
- Alias and display-name collision checks.

Rejected from Grok:

- The `1e-9` tie. Comparison is integer pixel area, then photo id, then angle id. Fixture coordinates are dyadic, so the shoelace sums match in both languages before they are scaled by image size.
- Public draft lookup in `SidekickCore`.
- Type names that collide with SwiftUI (`UnitPoint`, `CoordinateSpace`, `Polygon`, `Part`).
- License omitted on owner photos. Every photo in this version has source and license. The owner can split that later if owner frames should not carry a license string.

Changed from Sol's wire, because the duplicate-key hole was blocking. Sol keyed parts, photos, and regions by id and treated uniqueness as a property of JSON objects. Parsers drop duplicate keys before validation, and Swift cannot see them. Arrays keep both copies, and both loaders reject the duplicate. `reference` on `ConfirmedHighlight` is computed from the photo id and the part id.

## Tradeoffs accepted

- We accept pixel area for photo choice, in exchange for matching `largest_confirmed_region`. A larger image can outrank a region that covers more of a smaller frame. The polygons stay normalized so labeling tools still convert into one coordinate space.
- We accept a required license on owner photos in exchange for one provenance shape. Real license wording stays TBD.
- We accept that a bare `HighlightRef` can still name an unconfirmed pair, in exchange for leaving the answer contract alone. Drawing goes through `resolve`.
- We accept exterior rings only, in exchange for a geometry type both standard libraries can decode. Holes wait for a real label that needs one.
- We accept Swift and Python both implementing the checks the schema cannot express, in exchange for one fixture both sides assert.
- We accept that `highlightChoices` sums polygon areas independently, in exchange for keeping a polygon-union library out of the contract.

## Alternatives considered

- **ID-keyed JSON objects.** Uniqueness looks structural, and a hand edit that repeats a key silently keeps one region. Arrays plus a loader check hide the same rule behind `BayMap` and fail closed in Swift.
- **A boolean `confirmed` and an optional `confirmed_by`.** A confirmed region with nobody named, and an unconfirmed region with a name, would both decode. The `kind` sum type removes those two states.
- **Polygons on `HighlightRef`.** The phone could draw without the map. The answer payload would grow geometry, unconfirmed drafts would have nowhere to live except the answer, and the existing highlight keys would change. Rejected for this schema. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) reopens it: a precise outline on a photo that is not in the map.

## Open questions and risks

- Will a real bracket need a hole in the polygon, or is a second exterior ring enough for the detector?
- Should owner photos drop the license fields once the owner says their frames are not licensed works?
- Should `confirmed_by` stay a free string, or become an observation id that `TRUCK.md` must already contain?
- Paid vision API: decided 2026-10-02. Provider is OpenRouter. Paths A and C of [issue #85](https://github.com/zeketx/sidekick-mechanic/issues/85) are unblocked. The key is a Railway secret and is never committed. Cost target stays ≤ $0.03 per photo.
- Highlight ship targets stay proposed until Zeke confirms them after #85.

## Next implementation step

#28 converts a Label Studio JSON export into this file. The steps and the command are in [docs/BAY_MAP.md](../BAY_MAP.md). The renderer takes `ConfirmedHighlight.geometry.polygons` in one call, with `photo.imageSize` as the scale. That converter has landed. The next highlight work is the order in the requirement section above.
