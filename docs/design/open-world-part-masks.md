# Open-world part masks

**Status:** recommendation + spike plan. No pipeline in this change.

A parallel docs PR is restating the product rule (highlight any photo, pixel-precise outline, never a box; tracing optional). This page does not rewrite `VISION.md`, `ROADMAP.md`, or `docs/BAY_MAP.md`. It assumes that rule and decides how to get a mask.

Related: answer contract (#10), bay map (#26), Python renderer (#29), Swift renderer (#31), part resolver (#32), end-to-end highlight (#33), highlight eval (#34).

## Recommendation

Run locate+mask on the **backend**. Keep the traced bay-map path as a **fast lookup** when the photo is already in the catalog. For any other photo, locate the named part with a grounding VLM (box, or a box plus one point), then cut a mask with **SAM 2**. Convert the mask to the same normalized polygons the renderer already draws. Do not highlight from a bounding box.

Default locate model for the spike: **Gemini Flash spatial output** (`box_2d` / optional point, thinking off). Default mask model: **SAM 2** with a **box prompt**. Keep **Grounding DINO + SAM 2** as the cheap local baseline, and **Gemini native contour masks** as the no-SAM alternative.

Do **not** put open-vocab locate on the iPhone for Phase 1. Apple already publishes Core ML SAM 2, and #31 already renders a polygon. The missing piece is naming a never-seen part. That is the VLM. Phase 2's YOLO dry run (#36) is a closed set after labeling; it does not replace this.

Bias the gate toward **no highlight**. A wrong fuchsia outline is worse than a blank slot. `display: confirm` is only for the middle band. Abstain omits `highlight` entirely.

Do not implement the pipeline until the spike below picks a winner. Decision this week. The owner's plan ends around 2026-10-12.

## Options compared

| Option | Locate | Mask | Fits renderer | Fine-grained bay parts | Host | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| A. Gemini spatial → SAM 2 | Box or point, 0–1000 | SAM 2 | Yes, after contour | Strong language, unproven on 2JZ clutter | API + GPU/CPU SAM | Recommended default. Box prompt into SAM. |
| B. Gemini native masks | Same query | Gemini `mask` | Yes if polygon; 2.5 used a PNG map | Same locate risk | API only | Fastest to stand up. 3.x segmentation support is inconsistent (see risks). |
| C. Qwen2.5-VL → SAM 2 | Absolute box on the processed image | SAM 2 | Yes | Good referring; must rescale via processor size | Hosted API or vLLM | Coordinate bugs on large photos are documented. |
| D. Grounding DINO → SAM 2 | Open-vocab box + logit | SAM 2 | Yes | Weaker on “IAC valve” vs neighbor solenoid | Local GPU | Fastest and cheapest. Strong SAM scores for the gate. |
| E. Florence-2 RES / OV | Phrase or referring | Florence polygon or SAM 2 | Yes | Weaker zero-shot detect than DINO 1.5 | Local | Useful tiny baseline. Florence boxes often lack a confidence. |
| F. On-device VLM + Core ML SAM 2 | Unproven small VLM | Core ML SAM 2 / EdgeSAM | Yes | Unlikely by 2026-10-12 | iPhone | Mask is ready. Locate is not. |
| G. Mapped lookup only | Closed `part_id` | Traced polygons | Already | Perfect on mapped photos, zero on new ones | None | Keep as the fast path and the eval answer key. |

**Box vs point into SAM.** Use the box as the default prompt. SAM's own `predicted_iou` is usually higher on a tight box than on a single click, and a box stops the mask from jumping to a neighboring hose. Add a positive point when the VLM is more sure of a center than of a box (small sensor). Add a negative point only when the VLM names a neighbor to exclude. One `predict` call, not a refine loop. Enable `multimask_output` and take the top `predicted_iou`; if the top two are close, hedge or abstain.

**Groups.** The resolver today returns one `part_id` ([docs/design/part-resolver.md](part-resolver.md)). A group (“the coils”) is several masks unioned into one region, same as a bay-map region with more than one polygon. The renderer still strokes polygons, not a box around the group.

**Bay map as context.** If `bay_photo_id` is in the catalog and the part is confirmed, **do not locate**. Copy the traced polygons. If the photo is new but a traced crop of the same `part_id` exists, the spike may attach that crop as a second image on the VLM call. That is an accuracy boost, not a requirement to highlight.

**How the answer already names a part.** `LlmAnswerProducer` writes text, then `part_resolver` asks for one id from the closed list, or null. That `part_id` (plus `display_name` / aliases from the map) is the locate query. If the list has no id for the answer, locate may still run on the display phrase, but the gate starts in the hedge/abstain band. Do not scrape a part name out of prose any other way.

## Contract diff proposal

Today `highlight` is optional on a found answer and is only `{bay_photo_id, part_id}` ([`backend/contracts/answer.schema.json`](../../backend/contracts/answer.schema.json)). The phone looks that pair up in the bay map. An untraced photo has no row, so `resolve` returns nil.

**Keep the existing object valid.** Add optional fields. Do not add a `kind` discriminator (that would break `contracts/fixtures/with_highlight.json` and `HighlightRef`).

Proposed `$defs.highlight_ref` (proposal only; not applied in this PR):

```json
"highlight_ref": {
  "type": "object",
  "additionalProperties": false,
  "required": ["bay_photo_id", "part_id"],
  "properties": {
    "bay_photo_id": { "type": "string", "minLength": 1 },
    "part_id": { "type": "string", "minLength": 1 },
    "part_ids": {
      "type": "array",
      "minItems": 1,
      "items": { "type": "string", "minLength": 1 }
    },
    "geometry": { "$ref": "#/$defs/highlight_geometry" },
    "display": { "enum": ["outline", "confirm"] }
  }
},
"highlight_geometry": {
  "type": "object",
  "additionalProperties": false,
  "required": ["polygons"],
  "properties": {
    "polygons": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["points"],
        "properties": {
          "points": {
            "type": "array",
            "minItems": 3,
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["x", "y"],
              "properties": {
                "x": { "type": "number", "minimum": 0, "maximum": 1 },
                "y": { "type": "number", "minimum": 0, "maximum": 1 }
              }
            }
          }
        }
      }
    }
  }
}
```

Rules:

- Existing `{bay_photo_id, part_id}` still validates and still means “look up the map.”
- When `geometry` is present, the renderer draws those polygons and **must not** require a confirmed map row. `bay_photo_id` is the photo handle. A user or session frame gets a session-scoped id in that same field (do not add a second photo object on the first landing).
- `display` omitted means `outline`. `confirm` is the hedged “tap to confirm.” Abstain **omits** `highlight`.
- `part_ids` is the optional group. `part_id` stays the primary label.
- Coordinate space is the bay map's: normalized, origin top left, x right, y down. Gemini's 0–1000 and SAM pixel masks convert at the backend boundary.
- Wire polygons, not a PNG and not a box. `render_highlight` already takes a pixel polygon ([`backend/highlight.py`](../../backend/highlight.py)). A region with several rings is several calls, or one later union — same as today's multi-polygon bay-map region.
- Swift `HighlightRef` and the decoder grow in the contract PR, not here. Old payloads keep decoding.

Rejected as too big for the first landing: a `kind: mapped | located` split, inline raster masks, or moving polygons onto `HighlightRef` only (that was already rejected in [bay-map.md](bay-map.md); we add them now because the photo may have no catalog row).

## Runtime, latency, and cost

Chat budget today: p50 under 4 s and p95 under 8 s send-to-render ([VISION.md](../../VISION.md)). The producer already does retrieval, one answer completion, and a second part-selection completion. Mapped lookup is microseconds. Locate+mask is new time on top.

Figures below are **estimates** unless a source states a measured number. Prices checked 2026-10-03.

| Path | Where | Latency (estimate unless cited) | Cost / photo (estimate) | Sources |
| --- | --- | --- | --- | --- |
| Mapped lookup | Backend + phone | under 10 ms lookup + #31 render budget 200 ms | $0 | Existing map / #31 |
| A. Gemini box → SAM 2 | Backend | Gemini short JSON **est. 0.8–3 s** + SAM 2 **55 ms** on A100 (cited in a SAM 2.1 paper) or **est. 0.3–2 s** on CPU/small GPU | Gemini 2.5 Flash **est. $0.001–0.01** (258–~1.8k image tokens at $0.30 / 1M in, tiny JSON out at $2.50 / 1M). SAM 2 self-host **est. under $0.001** if a GPU is already up | [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [token tiling](https://ai.google.dev/gemini-api/docs/tokens), [GD-1.5 + SAM 2.1 = 110+55 ms on A100](https://arxiv.org/html/2603.00184v1) |
| B. Gemini native mask | Backend | **est. 1.5–5 s** (larger `mask` payload). No SAM | Same input + larger output. **est. $0.002–0.02**. Thinking must be off | [Gemini 2.5 segmentation blog](https://developers.googleblog.com/en/conversational-image-segmentation-gemini-2-5/), [image understanding (polygon `mask` on current Flash)](https://ai.google.dev/gemini-api/docs/image-understanding) |
| C. Qwen2.5-VL → SAM 2 | Backend | Qwen2.5-VL-7B vLLM TTFT **~4.4–4.8 s** on a VisionArena-style load; smaller images help. Plus SAM as above | Hosted VL **est. $0.001–0.01** at about $0.20 / 1M in and out (aggregator listings, not Together's official VL row). Self-host = GPU rent | [vLLM Qwen2.5-VL notes](https://github.com/vllm-project/recipes/blob/main/Qwen/Qwen2.5-VL.md), [Qwen2.5-VL 7B price listings](https://pricepertoken.com/pricing-page/model/qwen-qwen-2-5-vl-7b-instruct) |
| D. Grounding DINO → SAM 2 | Backend GPU | **165 ms** (110+55) cited on A100 for DINO 1.5 + SAM 2.1. Open DINO-T on a T4 **est. 0.3–1.5 s** | Self-host: GPU time only. **est. $20–80 / month** for a small always-on GPU, **under $0.001 / photo** if busy | [Grounded SAM 2](https://github.com/IDEA-Research/Grounded-SAM-2), [2603.00184 latency table](https://arxiv.org/html/2603.00184v1) |
| E. Florence-2 | Backend | **est. 0.3–1.5 s** on GPU | Self-host, ~$0 API | [Florence-2 tasks](https://huggingface.co/docs/transformers/model_doc/florence2) |
| F. On-device | iPhone | EdgeSAM encode **26 ms** on iPhone 14 (cited). SAM 2 tiny video path **~1 FPS** on iPhone 15 Pro Max (EdgeTAM paper). Still-image encode+decode **est. 0.2–1.0 s**. Open-vocab locate on device: **unknown**, likely seconds and weak | $0 / photo after the model download | [EdgeSAM](https://arxiv.org/html/2312.06660v2), [EdgeTAM](https://ar5iv.labs.arxiv.org/html/2501.07256), [apple/coreml-sam2.1-tiny](https://huggingface.co/apple/coreml-sam2.1-tiny) |

**Gemini 3.8 Flash** (current default Flash on the pricing page) is $0.75 / 1M input and $3.75 / 1M output through 2026-12-31. That is about 2.5× the 2.5 Flash input rate. Use it for locate if 2.5 is gated for new projects.

**Fit to the 4 s / 8 s budget.** Sequential A or B on a slow call will miss p50. Do this:

1. Return the text answer first. Attach `highlight` when locate finishes (product decision: second payload vs placeholder slot).
2. Skip locate on a confirmed map row.
3. Skip the verify-crop call when grounding score, SAM `predicted_iou`, and SAM stability are all high.
4. Downscale the locate image (long side 1024) before the VLM. SAM can use a larger frame.

On-device locate is the right privacy story later. It is not the Phase 1 decision. The phone still renders.

## Confidence and abstain

Three UX states, one wire:

| State | Wire | UI |
| --- | --- | --- |
| Precise outline | `highlight` + `geometry`, `display` omitted or `outline` | Today's fuchsia outline / saturate |
| Hedged | `highlight` + `geometry`, `display: confirm` | Same geometry, “Tap to confirm this is the {display_name}.” No auto-confident outline |
| Abstain | no `highlight` | Answer text only |

A missing highlight already scores 0 on correct-part rate ([docs/METRICS.md](../METRICS.md)). Keep that for the mapped eval. The open-world spike **also** reports precision-among-shown and false-highlight rate, so abstaining is not punished as a wrong part.

Signals, in order. Any hard fail → abstain.

1. **Closed name.** `part_id` from the resolver, or a display name / alias. Free prose is not a name.
2. **Grounding score.** DINO logit, or the VLM's structured confidence if it has one. Gemini/Florence often have none — then this signal is missing, and the other bars carry more weight.
3. **SAM `predicted_iou`.** Model's own mask quality. Automatic mask gen defaults filter below **0.8**.
4. **SAM `stability_score`.** IoU of the mask at two binarization thresholds. Automatic mask gen defaults keep **≥ 0.95**.
5. **Top-2 gap.** If `multimask_output` returns two masks whose `predicted_iou` differs by less than 0.05, hedge or abstain.
6. **Verify-crop.** Crop the mask (with a small pad), ask the same VLM: “Is this a {display_name}? yes/no.” No → abstain. Skip when 3 and 4 are both high.
7. **Mask sanity (normalized plane).**
   - Area fraction outside **[0.002, 0.35]** → abstain (whole-bay or a single bolt). A part that is honestly huge (the engine) is a group with its own allow-list, not a looser default.
   - Compactness `4πA / P²` very low → likely a hose spaghetti or a cracked mask → hedge or abstain.
   - Mask touches three or more image borders → abstain.
8. **Reference agreement (optional).** If a traced crop was used, IoU of the new mask against a coarsely aligned reference below 0.3 → abstain.

Starting bars for the spike (calibrate, do not ship these as law):

- **Outline:** name closed AND (grounding present ≥ mid-band OR verify-crop yes) AND `predicted_iou` ≥ 0.88 AND stability ≥ 0.95 AND area in range AND top-2 gap ≥ 0.05.
- **Confirm:** name closed AND `predicted_iou` ≥ 0.80 AND stability ≥ 0.90 AND area in range AND verify-crop is not no.
- **Abstain:** everything else, including verify-crop no.

Wrong outline must stay rare. If the spike's false-highlight rate (shown and wrong part) is above the bar, raise the outline threshold; do not lower it to chase coverage.

## Spike plan (2–3 days)

Throwaway scripts under `backend/spikes/`. Do not fold a winner into `/chat` in the spike PR.

### Eval set

The owner's bay is not shot. Use public 2JZ-GE (and, if needed to reach count, 2JZ-in-bay) photos that already have a recorded license.

- Required: the one prototype frame in [`backend/data/prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json) (`hrymx-2jz-ge-25308847029`, CC BY 2.0).
- Add 5–10 more frames the same way that file records license and URL. Keep them out of the product catalog if the parallel docs PR is still defining that list. A spike manifest next to the scripts is enough.
- Target **≥ 6 photos × 8 visible parts ≈ 48** locate+mask cases. Parts are display names / `part_id`s from the map or golden set, not catalog numbers. Skip a part that is not in the frame.
- Hold out **photos**, not only parts: at least two frames must be ones the pipeline has no traced polygons for at run time. Traced maps on the other frames are few-shot context only.

If licensed photos stay at one, say so in the spike write-up and treat rotated/cropped views as a weak extra, not as “never seen.”

### Ground truth

- Label Studio polygons, same export as [docs/BAY_MAP.md](../BAY_MAP.md). `bay_map_labels.py` writes the answer key.
- A confirmed region on a traced map **is** the key for that `(photo, part)`.
- Do not commit the JPEGs. Do not invent specs. Fixture leftovers stay `fake-*`.

### Metrics

Score on **raster** masks at the photo's pixel size. `eval/iou.py` requires convex rings and will reject a SAM outline. Do not use it for this spike.

| Metric | Definition |
| --- | --- |
| Coverage | Fraction of cases that emit `highlight` |
| Precision among shown | Shown and same `part_id` as the key / shown |
| False-highlight rate | Shown and wrong `part_id` / all cases. Must stay low |
| Correct-part (legacy) | Same as [METRICS.md](../METRICS.md): missing = 0. Report it. Do not optimize it by outlining junk |
| Pixel IoU | Mean IoU of predicted mask vs key, **among shown and correct part** |
| Outline / confirm / abstain mix | Counts |
| Latency p50 / p95 | Locate+mask only, and full `/chat` if wired |
| Cost / photo | Provider usage or GPU-seconds, written on the results JSON |

Pass bars for **choosing a pipeline**, not for closing M3:

- Precision among shown ≥ **0.90**
- False-highlight rate ≤ **0.05**
- Mean pixel IoU among shown-correct ≥ **0.70** (M3's 0.80 stays the ship bar once the key is the owner's bay)
- Coverage ≥ **0.40** on untraced frames, or a written “mapped-only until more photos” decision
- Locate+mask p95 **est. 6 s or under** on the spike box; call out if text+highlight would break the 8 s chat p95

### Pipelines to run (three)

1. **Gemini Flash `box_2d` (thinking off) → SAM 2 box prompt**, plus verify-crop and the sanity checks.
2. **Grounding DINO (open Tiny, or 1.5 if a key exists) → SAM 2.**
3. **Gemini native `mask`** (2.5 Flash thinking off if reachable; else current Flash polygon `mask` per the image-understanding docs). No SAM.

If (3) cannot return a usable contour in an hour, replace it with **Qwen2.5-VL box → SAM 2**. Do not add a fourth until one of these three finishes.

Optional extra, not a fourth pipeline: attach a traced crop of the same `part_id` to (1) and report the delta.

### Decision rule

Pick **one** ship path for Phase 1:

1. If (1) meets the bars on untraced frames, ship A (Gemini locate + SAM 2). It matches mechanic language and already-planned cloud calls.
2. Else if (2) meets the bars and (1) does not, ship D. Accept weaker names, keep the speed and the SAM scores.
3. Else if (3) meets the bars and is simpler operationally (no GPU), ship B, but only if the mask is a real contour, not a box and not an unreadable `<seg_*>` string.
4. Else **ship mapped lookup only**, abstain on untraced photos, and write that open-world highlight misses the 2026-10-12 window.

Ties: lower false-highlight rate, then higher IoU, then lower p95, then lower cost.

Write the numbers into `backend/eval/results/` from the scripts. Do not type them by hand.

## Risks and open questions

- **Gemini segmentation is in flux.** Google's 2.5 blog (2025-07-21) recommends `gemini-2.5-flash`, `thinkingBudget=0`, and a PNG probability map. Current image-understanding docs show polygon `mask` on `gemini-3.8-flash`. A 2026 forum thread says 3.x dropped segmentation and that 2.5 sometimes emits `<start_of_mask><seg_*>`. The spike must print the raw `mask` field before anyone trusts B.
- **2.5 access.** Google has steered new projects off 2.5 toward current Flash. Confirm the project can call the model the spike names.
- **One licensed prototype photo.** [`prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json) already says the CC search produced one 2JZ-GE bay frame. The spike is only as “open-world” as the extra licensed frames we add.
- **Convex IoU in the harness.** Shipping pixel-IoU into `eval/iou.py` is a later contract with #34. The spike stays separate.
- **Chat latency.** Without a deferred highlight, A/B/C will fight the 4 s / 8 s target. Product Lead/zeke decide whether the outline may arrive after the text.
- **`display: confirm` copy and tap behavior** are not in the app yet (#33).
- **Session `bay_photo_id` lifecycle** (how long the phone keeps the bytes) is an app decision. The schema only needs a stable handle for one answer.
- **Renderer is one polygon per call.** Groups and occlusion already need several rings. That is an applicator change, not a new style.
- **On-device later.** Core ML SAM 2 is real. Open-vocab locate on ANE is not in this plan. Do not block Phase 1 on it.
- **Keys.** No new provider key lands in git. Spike reads env, same as `.env.example`.

### Needs a product decision

1. May the highlight land after the text, or must one `/chat` body include the outline?
2. Is coverage below 0.40 on untraced photos acceptable if false-highlight stays ≤ 0.05 (mapped photos still outline)?
3. Is `display: confirm` wanted in Phase 1, or is the gate outline vs nothing?
4. May the spike add more licensed 2JZ-in-bay photos that are not captioned 2JZ-GE, for eval only?
5. Which Gemini model is allowed (2.5 Flash vs current 3.x Flash) given the segmentation split above?
