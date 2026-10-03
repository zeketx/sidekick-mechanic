# Bay map labeling

Highlighting a photo does not require this map. A highlight is a precise outline of a part, or of a group of parts, on any still photo, including one that has never been traced. A bounding box is never the highlight. Phase 1 does not track the live camera.

This page is how to draw regions when you choose to. The hand-traced map is optional. On the owner's reference photos it is an accuracy boost. It is also the answer key for scoring highlight accuracy: IoU against these hand labels. A highlight the user confirms in the app can be saved back here as a traced region.

[Issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84) uses this same workflow for the held-out set: about 20 public photos, about 100–160 photo×part queries including "not visible", polygon labels only. Those labels are the answer key. They are not a trace the highlighter must have before it can run.

The same drawing can feed a Phase 2 detector later.

## Tool

Label Studio Community Edition is the labeling tool. It is free and runs on your machine. The labeling UI is Label Studio. A project uses polygon and rectangle controls. Export **JSON** for the bay map. Export **COCO** or **YOLO** from that same project when a detector needs the labels.

CVAT is also free and self-hostable. This repo converts Label Studio because a handful of bay photos is one local process, and the JSON export stores shapes as percentages of the image. [docs/design/bay-map.md](design/bay-map.md) already turns those percentages into the unit square by dividing by 100.

## Where the photos are

Day-one photos live in `bay-photos/day-one/` at the repo root, next to `backend/` and `docs/`. The directory is gitignored (`bay-photos/` in `.gitignore`). Do not commit the image files. File names and the five angle ids are in [docs/vehicle/DAY_ONE.md](vehicle/DAY_ONE.md). Label frame `_01` of each angle. Leave the drawing until after the delivery visit.

Prototype stand-ins live in `bay-photos/prototype/`, also gitignored. Keep them out of `bay-photos/day-one/`. License name and reference for a prototype frame are already on that photo in [backend/data/prototype_bay_photos.json](../backend/data/prototype_bay_photos.json). Copy them into the manifest. Do not retype a license from memory.

## Steps

### 1. Start Label Studio

Install it on its own. It is not a backend dependency.

```bash
pip install label-studio
label-studio start
```

Create the local account the first run asks for, then create one project. Import the image files from `bay-photos/day-one/` (or from `bay-photos/prototype/` for a stand-in).

### 2. Paste the labeling config

In the project labeling config, the `value` strings are the manifest `label` fields. The sample values below are fixtures. They are not parts on the truck, and they are not catalog part numbers. Replace them with the ids you choose for this map.

```xml
<View>
  <Image name="image" value="$image"/>
  <PolygonLabels name="polygon" toName="image">
    <Label value="FAKE-PART-INTAKE"/>
    <Label value="FAKE-PART-HIDDEN"/>
  </PolygonLabels>
  <RectangleLabels name="box" toName="image">
    <Label value="FAKE-PART-INTAKE"/>
    <Label value="FAKE-PART-HIDDEN"/>
  </RectangleLabels>
</View>
```

Use the polygon tool. The outline follows the part or the assembly. The rectangle control is still in the config because the converter can store an axis-aligned box. That box is not a highlight, and it is not an eval label for [issue #84](https://github.com/zeketx/sidekick-mechanic/issues/84). One label on a region. Keep the shape inside the photo. Leave the photo and the box unrotated. A brush mask is not a bay-map region. A second outline of the same part on the same photo, for a piece hidden behind something else, is another polygon with the same label. The converter stores that as another polygon on one region.

Submit the task when the photo is done. A skipped task is ignored. A model prediction is ignored until you submit an annotation.

### 3. Export JSON

In the project, click **Export**, choose **JSON**, and click **Export**. The file is an array of tasks. JSON-MIN is a different shape. This converter reads the JSON task array (`annotations`, then `result`). You can also export from the machine that runs Label Studio:

```bash
label-studio export <project-id> JSON --export-path=<output-path>
```

The image field is often an upload path. Label Studio may prefix the file name with eight or more hex characters and a hyphen, as in `abcd1234-YYYY-MM-DD_front_01.jpg`. The converter matches the manifest `file` to the basename, or to that hex prefix plus the file name. A `?` query on the image URL is ignored.

Leave the export out of git. It can contain local paths.

### 4. Write a manifest

The export has shapes and labels. The bay map also needs an angle id, a photo id, source, license, a display name, and whether you have confirmed the region. Those fields go in a manifest beside the export.

| Field | What to write |
| --- | --- |
| `file` | File name in `bay-photos/day-one/`, including the extension the phone wrote |
| `bay_photo_id` | That file name without the extension. DAY_ONE calls the `_01` filename the photo id |
| `angle_id` | `front`, `overhead`, `vehicle-left`, `vehicle-right`, or `firewall` |
| `source.kind` | `owner_observation` for a day-one frame, `public_prototype` for a stand-in |
| `source.reference` | A pointer you write, for example `owner observation, bay-photos/day-one/YYYY-MM-DD_front_01.jpg`. That pattern is not a file you already shot |
| `license.name`, `license.reference` | For your own frames, `TBD` until you decide the wording. The schema requires both strings. `TBD` does not invent a license. For a prototype frame, copy the name and reference from `prototype_bay_photos.json` |
| `label` | The string you clicked in Label Studio |
| `part_id` | A short id you choose. Not a catalog part number, pin, or connector id. Today's answer highlight names this id. [Issue #86](https://github.com/zeketx/sidekick-mechanic/issues/86) will also carry a mask |
| `display_name` | Words you want on screen. Not a spec |
| `aliases` | Other strings for the same part, or `[]` |
| `confirmation` | Omit it, and the region stays `unconfirmed`. The current loader will not draw an unconfirmed region as a highlight. After you check the outline, set `kind` to `confirmed` and `confirmed_by` to the name you want stored. A missing trace does not block highlighting the photo. That product rule is ahead of the current answer contract. See [docs/design/bay-map.md](design/bay-map.md) |

Every region of a part gets that part's confirmation. A part you list and never draw is an error. A label you draw that is missing from the manifest is an error.

Pixel size comes from `original_width` and `original_height` on the export. Set `width` and `height` on a photo only when the export omitted them. If you set both and they disagree with the export, the script stops.

The block below is the shape of the committed test fixture. The ids are `FAKE-*`. Copy the shape. Do not copy the fake ids into a real map.

```json
{
  "source": {"kind": "owner_observation", "reference": "TBD"},
  "license": {"name": "TBD", "reference": "TBD"},
  "photos": [
    {
      "file": "YYYY-MM-DD_front_01.jpg",
      "bay_photo_id": "YYYY-MM-DD_front_01",
      "angle_id": "front"
    }
  ],
  "parts": [
    {
      "label": "FAKE-PART-INTAKE",
      "part_id": "fake-part-intake",
      "display_name": "FAKE-NAME-INTAKE",
      "aliases": [],
      "confirmation": {"kind": "unconfirmed"}
    }
  ]
}
```

### 5. Convert

From `backend/`:

```bash
python3 bay_map_labels.py \
  --export /path/to/label-studio.json \
  --manifest /path/to/manifest.json \
  --output /path/to/bay-map.json
```

The script writes the file only after the JSON validates against [backend/contracts/bay_map.schema.json](../backend/contracts/bay_map.schema.json) and the checks in `bay_map.py` (unique ids, positive area, no repeated first point). Percentages are divided by 100. Image width and height are stored as `image_size`. They are not the scale factor. A rectangle becomes four corners: top left, top right, bottom right, bottom left. Origin is the top left. Y grows downward. A polygon that repeats its first point drops that repeat, because the loader rejects a closed ring.

Exit code 0 prints the output path. Any other exit prints one reason and writes nothing.

The tests that lock this conversion use [backend/tests/fixtures/fake-label-studio-export.json](../backend/tests/fixtures/fake-label-studio-export.json) and [backend/tests/fixtures/fake-label-manifest.json](../backend/tests/fixtures/fake-label-manifest.json). They do not use a photo of the truck.

Filling a real map and confirming regions for the golden questions is [issue #40](https://github.com/zeketx/sidekick-mechanic/issues/40). The command above is the tool for that pass.

## Phase 2 detector

The JSON export is the bay map path. The same Label Studio project feeds a detector without drawing the regions again.

- **COCO.** Click **Export**, choose **COCO**, click **Export**. Rectangles become `bbox` in pixels. Polygons become `segmentation`. Category names are the label strings in the manifest.
- **YOLO.** Click **Export**, choose **YOLO**, click **Export**. That file is the YOLOv3/v4 box format for rectangle labels: class index, center x, center y, width, height, normalized. Polygon labels are not in that YOLO export. Use the COCO file when the outline is a polygon.

Training, Ultralytics, and Core ML export stay on the M4 dry run and Phase 2. This script does not train a model and does not write weights.

## What the converter will not accept

- It does not read pixels from `bay-photos/`, and it does not fetch the image URL.
- It does not accept a rotated box, a rotated image, or a brush mask. Redraw those as a polygon or an axis-aligned box.
- It does not invent `part_id`, license text, or angle ids. Those come from the manifest.
- It does not treat a model prediction as a region. Submit the annotation.
