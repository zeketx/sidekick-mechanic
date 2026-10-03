# Open-world part masks

**Status:** recommendation + spike plan. No pipeline in this change.

Product Lead decisions in this page are locked (2026-10-03). A parallel docs PR is restating the product rule (highlight any photo, pixel-precise outline, never a box; tracing optional). This page does not rewrite `VISION.md`, `ROADMAP.md`, or `docs/BAY_MAP.md`. It assumes that rule and decides how to get a mask.

Related code: answer contract (#10), bay map (#26), Python renderer (#29), Swift renderer (#31), part resolver (#32), end-to-end highlight (#33), highlight eval (#34). Follow-on issues (Product Lead files them; do not open them from this PR): spike #TBD, confidence UX #TBD, acceptance metrics/eval #TBD, answer contract v2 #TBD, held-out labeled photo set #TBD.

## Recommendation

Run locate+mask on the **backend**. Keep the traced bay-map path as a **fast lookup** when the photo is already in the catalog. For any other photo, locate the named part with a grounding VLM (box, or a box plus one point), then cut a mask with **SAM 2**. Convert the mask to the same normalized polygons the renderer already draws. Do not highlight from a bounding box.

Spike default for candidate **A**: **Gemini 2.5 Flash** spatial output (`box_2d` or points, thinking off) into **SAM 2** with a **box prompt**. **Qwen2.5-VL → SAM 2** is the open drop-in for A if Gemini is unavailable. Candidate **B** is **Grounding DINO + SAM 2**. Candidate **C** is **Gemini direct segmentation**. Every candidate gets a **verify-crop** pass. The 3-state gate (outline / confirm / abstain) reads VLM yes/no, SAM `predicted_iou`, and mask sanity.

**A and C need zeke's OK and a Gemini API key** before they can ship in product. The spike may use a key in env. Nothing new lands in git.

Do **not** put open-vocab locate on the iPhone for Phase 1. Apple already publishes Core ML SAM 2, and #31 already renders a polygon. The missing piece is naming a never-seen part. Phase 2's YOLO dry run (#36) is a closed set after labeling; it does not replace this.

**Tap to confirm is in v1**, minimal only. Abstain omits `highlight`. A wrong fuchsia outline is worse than a blank slot. If no pipeline can hold wrong-part ≤ 5% at any threshold, **stop and rethink**. Do not ship a looser gate.

Do not implement the pipeline until the spike picks a winner. Decision this week. The owner's plan ends around 2026-10-12.

## Options compared

Spike compares **A / B / C**. The other rows stay as context.

| Option | Locate | Mask | Fits renderer | Fine-grained bay parts | Host | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| **A. Grounding VLM → SAM 2** | Gemini 2.5 Flash box/point (0–1000), or Qwen2.5-VL box | SAM 2 | Yes, after contour | Strong language, unproven on 2JZ clutter | API + GPU SAM | Recommended default. Gemini needs zeke's OK + key. Qwen is the open option. |
| **B. Grounding DINO → SAM 2** | Open-vocab box + logit | SAM 2 | Yes | Weaker on small or grouped parts | Local GPU | Open baseline. Fastest cited path. Strong SAM scores for the gate. |
| **C. Gemini direct masks** | Same Gemini query | Gemini `mask` | Yes if the contour is real | Same locate risk | API only | No SAM. Gemini needs zeke's OK + key. 3.x mask support is inconsistent (see risks). |
| Florence-2 RES / OV | Phrase or referring | Florence polygon or SAM 2 | Yes | Weaker zero-shot than DINO 1.5 | Local | Not a spike candidate. |
| On-device VLM + Core ML SAM 2 | Unproven small VLM | Core ML SAM 2 / EdgeSAM | Yes | Unlikely by 2026-10-12 | iPhone | Mask is ready. Locate is not. |
| Mapped lookup only | Closed `part_id` | Traced polygons | Already | Perfect on mapped photos, zero on new ones | None | Fast path and eval answer key. Fallback if A/B/C fail the wrong-part bar. |

**Box vs point into SAM (A and B).** Use the box as the default prompt. SAM's `predicted_iou` is usually higher on a tight box than on a single click, and a box stops the mask from jumping to a neighboring hose. Add a positive point when the VLM is more sure of a center than of a box (oil dipstick, oil filler cap). Add a negative point only when the VLM names a neighbor to exclude. One `predict` call, not a refine loop. Enable `multimask_output` and take the top `predicted_iou`; if the top two are close, hedge or abstain.

**Groups.** Coil packs are one highlight: several masks unioned into one region, same as a bay-map region with more than one polygon. Radiator cap + upper hose is the same idea (two named pieces, one region). The renderer strokes polygons, not a box around the group. The resolver today returns one `part_id` ([part-resolver.md](part-resolver.md)); contract v2 #TBD adds optional `part_ids`.

**Bay map as context.** If `bay_photo_id` is in the catalog and the part is confirmed, **do not locate**. Copy the traced polygons. If the photo is new but a traced crop of the same `part_id` exists, the spike may attach that crop as a second image on the VLM call. That is an accuracy boost, not a requirement to highlight.

**How the answer already names a part.** `LlmAnswerProducer` writes text, then `part_resolver` asks for one id from the closed list, or null. That `part_id` (plus `display_name` / aliases from the map) is the locate query. If the list has no id, locate may still run on the display phrase, but the gate starts in the hedge/abstain band. Do not scrape a part name out of prose any other way.

## Contract diff proposal

Today `highlight` is optional on a found answer and is only `{bay_photo_id, part_id}` ([`backend/contracts/answer.schema.json`](../../backend/contracts/answer.schema.json)). The phone looks that pair up in the bay map. An untraced photo has no row, so `resolve` returns nil.

**Keep the existing object valid.** Add optional fields. Do not add a `kind` discriminator (that would break `contracts/fixtures/with_highlight.json` and `HighlightRef`). Land this in answer contract v2 #TBD.

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
- `display` omitted means `outline`. `confirm` is the unsure “Is this it?” state. Abstain **omits** `highlight`.
- `part_ids` is the optional group. `part_id` stays the primary label (coil packs, radiator cap + upper hose).
- Coordinate space is the bay map's: normalized, origin top left, x right, y down. Gemini's 0–1000 and SAM pixel masks convert at the backend boundary.
- Wire polygons, not a PNG and not a box. `render_highlight` already takes a pixel polygon ([`backend/highlight.py`](../../backend/highlight.py)). A region with several rings is several calls, or one later union — same as today's multi-polygon bay-map region.
- Swift `HighlightRef` and the decoder grow in contract v2 #TBD, not here. Old payloads keep decoding.

Rejected as too big for the first landing: a `kind: mapped | located` split, inline raster masks, or moving polygons onto `HighlightRef` only (that was already rejected in [bay-map.md](bay-map.md); we add them now because the photo may have no catalog row).

## Runtime, latency, and cost

Chat budget today: p50 under 4 s and p95 under 8 s send-to-render ([VISION.md](../../VISION.md)). Product Lead's ship bar for locate+mask is **backend p95 ≤ 8 s** and **≤ $0.03 per photo**. The producer already does retrieval, one answer completion, and a second part-selection completion. Mapped lookup is microseconds. Locate+mask is new time on top.

Figures below are **estimates** unless a source states a measured number. Prices checked 2026-10-03. Spike latency is measured on a **GPU host**, not this CPU VM.

| Path | Where | Latency (estimate unless cited) | Cost / photo (estimate) | Sources |
| --- | --- | --- | --- | --- |
| Mapped lookup | Backend + phone | under 10 ms lookup + #31 render budget 200 ms | $0 | Existing map / #31 |
| A. Gemini 2.5 Flash box → SAM 2 | Backend GPU | Gemini short JSON **est. 0.8–3 s** + SAM 2 **55 ms** on A100 (cited) or **est. 0.2–0.8 s** on a small GPU | Gemini 2.5 Flash **est. $0.001–0.01** (258–~1.8k image tokens at $0.30 / 1M in, tiny JSON out at $2.50 / 1M) plus verify-crop. SAM 2 **est. under $0.001** if a GPU is already up. Under the $0.03 bar on paper | [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [token tiling](https://ai.google.dev/gemini-api/docs/tokens), [GD-1.5 + SAM 2.1 = 110+55 ms on A100](https://arxiv.org/html/2603.00184v1) |
| A-open. Qwen2.5-VL → SAM 2 | Backend GPU | Qwen2.5-VL-7B vLLM TTFT **~4.4–4.8 s** on a VisionArena-style load; smaller images help. Plus SAM | Hosted VL **est. $0.001–0.01** at about $0.20 / 1M in and out (aggregator listings). Self-host = GPU rent | [vLLM Qwen2.5-VL notes](https://github.com/vllm-project/recipes/blob/main/Qwen/Qwen2.5-VL.md), [Qwen2.5-VL 7B price listings](https://pricepertoken.com/pricing-page/model/qwen-qwen-2-5-vl-7b-instruct) |
| B. Grounding DINO → SAM 2 | Backend GPU | **165 ms** (110+55) cited on A100 for DINO 1.5 + SAM 2.1. Open DINO-T **est. 0.3–1.5 s** | Self-host: GPU time only. **est. $20–80 / month** for a small always-on GPU, **under $0.001 / photo** if busy | [Grounded SAM 2](https://github.com/IDEA-Research/Grounded-SAM-2), [2603.00184 latency table](https://arxiv.org/html/2603.00184v1) |
| C. Gemini native mask | Backend | **est. 1.5–5 s** (larger `mask` payload). No SAM | Same input + larger output + verify-crop. **est. $0.002–0.02**. Thinking must be off | [Gemini 2.5 segmentation blog](https://developers.googleblog.com/en/conversational-image-segmentation-gemini-2-5/), [image understanding (polygon `mask` on current Flash)](https://ai.google.dev/gemini-api/docs/image-understanding) |
| On-device | iPhone | EdgeSAM encode **26 ms** on iPhone 14 (cited). SAM 2 tiny video path **~1 FPS** on iPhone 15 Pro Max (EdgeTAM paper). Still-image **est. 0.2–1.0 s**. Open-vocab locate on device: unknown | $0 / photo after the model download | [EdgeSAM](https://arxiv.org/html/2312.06660v2), [EdgeTAM](https://ar5iv.labs.arxiv.org/html/2501.07256), [apple/coreml-sam2.1-tiny](https://huggingface.co/apple/coreml-sam2.1-tiny) |

**Gemini 3.8 Flash** (current default Flash on the pricing page) is $0.75 / 1M input and $3.75 / 1M output through 2026-12-31. That is about 2.5× the 2.5 Flash input rate. The spike names **2.5 Flash**. If that model is gated, stop and get zeke's OK before substituting 3.x.

**Fit to the 8 s backend bar.** Sequential A or C plus verify-crop can land near the bar. Do this:

1. Measure locate+mask (+ verify-crop) p95 on GPU. That number is the ship bar.
2. Skip locate on a confirmed map row.
3. Skip verify-crop when SAM `predicted_iou` and sanity are already in the outline band **and** the crop VLM is the only thing left. Do not skip it to chase coverage if the wrong-part rate is live.
4. Downscale the locate image (long side 1024) before the VLM. SAM can use a larger frame.
5. Returning text before the outline is an implementation choice if chat p50 would otherwise miss 4 s. The 8 s bar is backend locate+mask, not a ban on a later highlight attach.

On-device locate is the right privacy story later. It is not the Phase 1 decision. The phone still renders.

## Confidence and abstain

Three UX states, one wire. **Tap to confirm is in scope**, minimal version only (confidence UX #TBD). No drag-to-correct.

| State | Wire | UI |
| --- | --- | --- |
| Precise outline (confident) | `highlight` + `geometry`, `display` omitted or `outline` | Today's fuchsia outline / saturate |
| Unsure | `highlight` + `geometry`, `display: confirm` | Softer highlight. Copy: “Is this it?” Buttons: **Yes** / **Not this** |
| Abstain (not found / refuse) | no `highlight` | Answer text only |

**Yes** keeps the outline and treats the case as a confirmed highlight. **Not this** drops the highlight (not-found), and the backend **logs the photo, part, mask, and rejection** as eval data. Do not ask the owner to drag a better outline.

A missing highlight already scores 0 on the mapped correct-part rate ([docs/METRICS.md](../METRICS.md)). Keep that for the mapped eval. The open-world spike scores confident highlights separately from unsure and from abstain, so a 40% abstain rate is not a failed correct-part score.

Signals that feed the 3-state gate. Any hard fail → abstain. Every spike candidate (A, B, C) runs **verify-crop**.

1. **Closed name.** `part_id` from the resolver, or a display name / alias from the locked list below. Free prose is not a name.
2. **Verify-crop (VLM yes/no).** Crop the mask (small pad). Ask the same VLM (Gemini for A/C, a small VLM or the same Qwen for A-open / B): “Is this a {display_name}? yes/no.” **No → abstain.** Yes supports outline. Unsure / unparseable → confirm band, not outline.
3. **SAM `predicted_iou`.** Model's own mask quality. Automatic mask gen defaults filter below **0.8**. Candidate C has no SAM score; the gate then leans on verify-crop and sanity.
4. **SAM `stability_score`** (A/B). IoU of the mask at two binarization thresholds. Automatic mask gen defaults keep **≥ 0.95**.
5. **Top-2 gap** (A/B). If `multimask_output` returns two masks whose `predicted_iou` differs by less than 0.05, hedge or abstain.
6. **Mask sanity (normalized plane).**
   - Area fraction outside **[0.002, 0.35]** → abstain (whole-bay or a single bolt). Coil packs as a group may sit high in that range; oil dipstick and oil filler cap sit low. Bucket IoU by size so a small-part miss does not hide inside a plenum win.
   - Compactness `4πA / P²` very low → hedge or abstain (cracked mask or a belt that became the whole bay).
   - Mask touches three or more image borders → abstain.
7. **Grounding score** when present (DINO logit). Gemini often has none; then 2–6 carry the gate.
8. **Reference agreement (optional).** If a traced crop was used, IoU of the new mask against a coarsely aligned reference below 0.3 → abstain.

Starting bars for the spike (calibrate against the ship bar, do not loosen the 5% wrong-part cap):

- **Outline:** name closed AND verify-crop **yes** AND (SAM `predicted_iou` ≥ 0.88 AND stability ≥ 0.95, or C with sanity pass) AND area in range AND top-2 gap ≥ 0.05 when SAM ran.
- **Confirm:** name closed AND verify-crop is not **no** AND SAM `predicted_iou` ≥ 0.80 (if SAM ran) AND sanity pass.
- **Abstain:** everything else, including verify-crop no and true not-visible (pipeline says not found).

If raising the outline threshold is the only way to stay ≤ 5% wrong, raise it. Do not lower it to chase coverage. Abstain up to 40% is allowed.

## Spike plan (2–3 days)

Throwaway scripts under `backend/spikes/` (spike #TBD). Do not fold a winner into `/chat` in the spike PR. Held-out labels live with photo-set #TBD. Metrics land in acceptance eval #TBD.

### Locked part list

Locations only. No torque, clearance, pinout, wire color, or catalog number. About ten queries per photo:

| Query | Kind | Size band (for IoU buckets) |
| --- | --- | --- |
| throttle body | single | medium |
| intake plenum | single | large |
| coil packs | **group** | medium |
| alternator | single | medium |
| serpentine belt | single | large / thin |
| oil filler cap | single | **small** |
| oil dipstick | single | **small** |
| radiator cap + upper hose | **group** | medium |
| battery terminals | group of two small posts | small |
| fuse/relay box | single | medium |

`part_id` / `display_name` values are chosen when the labeled set is written. They are labels, not parts-store numbers. Fixture leftovers stay `fake-*`.

### Eval set

The owner's bay is not shot. Score **held-out public photos only**.

- Required: the one prototype frame in [`backend/data/prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json) (`hrymx-2jz-ge-25308847029`, CC BY 2.0).
- Add more licensed public 2JZ bay photos the same way that file records license and URL, until **photo × part queries land in ~100–160**. That is about 10–16 frames × the 10 queries, plus true not-visible rows. Keep extra frames out of the product catalog if the parallel docs PR is still defining that list. A spike manifest next to the scripts is enough.
- Hold out **photos** used for the ship-bar numbers. Traced maps on other frames are few-shot context only, never part of the reported score.
- **True not-visible queries:** for each photo, include at least one listed part that is not in the frame (or is fully occluded). The correct output is not-found (no highlight). That counts as correct, not as a miss.

If licensed photos stay scarce, say so and do not pretend crops of the same frame are held-out.

### Ground truth

- Label Studio polygons, same export as [docs/BAY_MAP.md](../BAY_MAP.md). `bay_map_labels.py` writes the answer key (held-out labeled photo set #TBD).
- A confirmed region on a traced map **is** the key for that `(photo, part)`.
- Not-visible rows have no region and `visible: false`.
- Do not commit the JPEGs. Do not invent specs.

### Metrics

Score on **raster** masks at the photo's pixel size. `eval/iou.py` requires convex rings and will reject a SAM outline. Do not use it for this spike.

Report each rate with a **confidence interval** (Wilson or bootstrap) over the ~100–160 queries.

| Metric | Definition |
| --- | --- |
| Confident correct-part | Among `display: outline` only: same `part_id` as the key |
| Confident wrong-part | Among `display: outline` only: different `part_id` (or a mask on the wrong object) |
| Median mask IoU | Median pixel IoU among confident **and** correct. Also bucket by size: small / medium / large (and thin, for the belt) |
| Abstain rate | Unsure (`confirm`) + not-found (no highlight) / all queries. v1 allow **up to 40%** |
| Not-visible correctness | Not-visible queries whose output is not-found / those queries. That is a correct refuse |
| Confirm mix | Count of `display: confirm`. Yes / Not this are logged when the UI exists; the spike can simulate Not this only if a reviewer marks it |
| Latency p50 / p95 | Locate+mask + verify-crop, **on GPU** |
| Cost / photo | Provider usage or GPU-seconds, written on the results JSON |

Ship bar (Product Lead, held-out public photos only):

- Among **confident** highlights: correct part **≥ 85%** and wrong part **≤ 5%**
- Median mask IoU **≥ 0.6**
- Abstain rate (unsure + not found) **≤ 40%**
- Backend p95 **≤ 8 s** (GPU)
- Cost **≤ $0.03** per photo

The mapped-eval targets in [VISION.md](../../VISION.md) (correct-part ≥ 0.90, region IoU ≥ 0.80) stay the later owner-bay bar. They are not this spike's gate.

### Pipelines to run (three)

Every one runs verify-crop and the 3-state gate.

1. **A.** Gemini 2.5 Flash `box_2d` or points (thinking off) → SAM 2 box prompt. If Gemini is blocked, run **Qwen2.5-VL box/points → SAM 2** as A-open and say so.
2. **B.** Grounding DINO (open Tiny, or 1.5 if a key exists) → SAM 2.
3. **C.** Gemini direct `mask` (2.5 Flash thinking off). No SAM. If the `mask` field is not a usable contour in an hour, record the failure and do not invent a fourth candidate.

Optional extra, not a fourth pipeline: attach a traced crop of the same `part_id` to A and report the delta.

### Decision rule

Measured on held-out public photos only.

1. Drop any candidate whose **confident wrong-part** cannot be brought **≤ 5%** at any threshold. If **all three** fail that, **stop and rethink**. Do not ship.
2. Among candidates that pass the 5% wrong-part cut, keep those that also meet correct ≥ 85%, median IoU ≥ 0.6, abstain ≤ 40%, GPU p95 ≤ 8 s, and cost ≤ $0.03 / photo.
3. Prefer **A** (Gemini → SAM 2) when it qualifies: mechanic language, groups, and small parts. Needs zeke's OK + key to ship.
4. Else prefer **A-open** (Qwen → SAM 2) if it was the A run and it qualifies.
5. Else prefer **B** (DINO → SAM 2) if it qualifies: no Gemini key.
6. Else prefer **C** if it qualifies **and** the mask is a real contour, not a box and not an unreadable `<seg_*>` string. Needs zeke's OK + key.
7. Else **mapped lookup only** on catalog photos, abstain on untraced ones, and write that open-world highlight is a rethink.

Ties among qualifiers: lower wrong-part rate, then higher median IoU, then lower p95, then lower cost.

Write the numbers into `backend/eval/results/` from the scripts. Do not type them by hand.

## Risks and open questions

- **Gemini needs zeke's OK and an API key** for product use of A or C. Qwen (A-open) and DINO (B) do not.
- **Gemini segmentation is in flux.** Google's 2.5 blog (2025-07-21) recommends `gemini-2.5-flash`, `thinkingBudget=0`, and a PNG probability map. Current image-understanding docs show polygon `mask` on `gemini-3.8-flash`. A 2026 forum thread says 3.x dropped segmentation and that 2.5 sometimes emits `<start_of_mask><seg_*>`. The spike must print the raw `mask` field before anyone trusts C.
- **2.5 access.** Google has steered new projects off 2.5 toward current Flash. If 2.5 is gated, do not silently switch C to 3.x.
- **One licensed prototype photo.** [`prototype_bay_photos.json`](../../backend/data/prototype_bay_photos.json) already says the CC search produced one 2JZ-GE bay frame. The 100–160 query count needs more licensed frames (photo-set #TBD).
- **Convex IoU in the harness.** Shipping pixel-IoU into `eval/iou.py` is a later change (acceptance metrics #TBD). The spike stays separate.
- **Session `bay_photo_id` lifecycle** (how long the phone keeps the bytes) is an app decision. The schema only needs a stable handle for one answer.
- **Renderer is one polygon per call.** Groups (coil packs, radiator cap + upper hose) need several rings. That is an applicator change, not a new style.
- **On-device later.** Core ML SAM 2 is real. Open-vocab locate on ANE is not in this plan. Do not block Phase 1 on it.
- **Keys.** No new provider key lands in git. Spike reads env, same as `.env.example`.

### Product decisions (locked)

1. Part list is the ten location queries above (group + small targets included). Locations only.
2. Ship bar is the confident 85% / 5% / 0.6 IoU / 40% abstain / 8 s / $0.03 set, held-out public photos only. No pipeline at ≤ 5% wrong → stop and rethink.
3. Score ~100–160 photo × part queries with confidence intervals, IoU by size, and true not-visible rows. Latency on GPU.
4. Tap to confirm is in v1: softer highlight, “Is this it?”, Yes / Not this. Not this → not-found + eval log. No drag-to-correct.
5. Product Lead files spike, confidence UX, acceptance metrics/eval, answer contract v2, and held-out labeled photo set. This PR does not create issues.

### Still needs zeke

- OK to call Gemini in product (A and C), and a Gemini API key in env.
- Enough extra licensed public bay photos to reach ~100–160 queries, or an explicit smaller-N exception.
