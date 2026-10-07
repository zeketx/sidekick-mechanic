# Wiring diagram text and page images

Issue #22 asks whether a wiring diagram page can be searched as text, or whether M2 should cite the page image, before anyone builds a pinout lookup.

## What was measured

`lj78-wiring` is not in this measurement. The PDF is not in the repo. Accuracy on that file is `TBD`.

`backend/spikes/wiring_spike.py` builds five synthetic one-page PDFs and reads each page two ways. `pypdf` reads the text layer. Poppler rasterizes the page at 150 DPI, and Tesseract reads that image. A reading counts as usable for lookup only when every planted label is present and labels that share a row stay next to each other. The match is an exact substring. A near miss counts as missing, because one wrong character would be a wrong label.

Every label is a `FAKE-*` fixture. None of them is a pin, a wire color, or a part number.

The counts and the quoted strings below are from `backend/eval/results/wiring-spike.json`. That file records tesseract 5.3.4, pdftotext 24.02.0, and pypdf 6.19.0.

The five pages are:

1. `text-layer-rows`. Horizontal text in row order.
2. `image-only`. Horizontal labels painted into a JPEG, with no text layer.
3. `scrambled-order`. Two visual rows, written in the PDF content stream as columns.
4. `vertical-image`. Two labels rotated a quarter turn inside a JPEG, with no text layer.
5. `mixed-caption`. Diagram labels only in the JPEG, plus a text-layer caption.

## Results

| Page | Sample | Text extraction | OCR |
| --- | --- | --- | --- |
| 1 | text-layer-rows | usable, 2 of 2 rows | usable, 2 of 2 rows |
| 2 | image-only | empty, both labels missing | usable, both labels |
| 3 | scrambled-order | 4 labels found, 0 of 2 rows intact | usable, 2 of 2 rows |
| 4 | vertical-image | empty, both labels missing | non-empty, neither label, unanchored |
| 5 | mixed-caption | caption only, both diagram labels missing | usable, all 3 labels |

### Page 1, both readers keep the rows

Text extraction on sample page 1 returned `FAKE-ROW-1A FAKE-ROW-1B` and then `FAKE-ROW-2A FAKE-ROW-2B`. OCR returned the same four labels, with a blank line between the rows. Both readings are usable for lookup.

### Page 2, an image page has no text layer

Text extraction on sample page 2 returned an empty string. `FAKE-SCAN-1` and `FAKE-SCAN-2` were missing. OCR returned `FAKE-SCAN-1 FAKE-SCAN-2`.

`ingest.py` would list this page in `empty_pages` and would not write a chunk. The raster still shows both labels.

### Page 3, full token recall with the rows broken

Text extraction on sample page 3 returned the four labels in this order. `FAKE-PAIR-L1`, then `FAKE-PAIR-L2`, then `FAKE-PAIR-R1`, then `FAKE-PAIR-R2`. The planted rows are `FAKE-PAIR-L1` with `FAKE-PAIR-R1`, and `FAKE-PAIR-L2` with `FAKE-PAIR-R2`. Neither row stayed intact. `tokens_missing` is empty, and `usable_as_lookup` is false.

OCR of the same page returned `FAKE-PAIR-L1 FAKE-PAIR-R1` and then `FAKE-PAIR-L2 FAKE-PAIR-R2`. Both rows stayed intact.

An index of the extracted text would contain every label and would still pair the wrong labels.

### Page 4, OCR returned text that is not on the page

Text extraction on sample page 4 was empty. `FAKE-VERT-1` and `FAKE-VERT-2` were missing. OCR returned `CLdsaN AVA` and `TLdsaANsV4`. Neither planted label appears in that string. `unanchored_text` is true. That string is not a snippet for those labels.

### Page 5, a non-empty chunk can omit the diagram

Text extraction on sample page 5 returned only `FAKE-CAPTION`. `FAKE-DIAGRAM-1` and `FAKE-DIAGRAM-2` were missing. One of the two rows stayed intact, the caption row. `usable_as_lookup` is false.

The page is not empty, so `ingest.py` would store a chunk and would not list the page in `empty_pages`. The chunk does not contain the diagram labels.

OCR returned `FAKE-DIAGRAM-1 FAKE-DIAGRAM-2` and then `FAKE-CAPTION`.

## Recommendation for M2

Cite the page image for a wiring diagram page.

Text extraction is enough for a prose page whose text layer is already in reading order. Sample page 1 is that case. Diagram pages need the image. Image-only labels disappear in extraction, on sample pages 2 and 4. Column order breaks rows even when every label is present, on sample page 3. A stored chunk can be the caption alone, on sample page 5.

OCR recovered the large horizontal labels on sample pages 1, 2, 3, and 5. On sample page 4 it wrote an unanchored string. At answer time a real manual has no planted-label key, so the pipeline cannot tell those two outcomes apart. Keep OCR text out of citation snippets.

The page image does not promote either string into a claim. The owner sees the page. That is the M2 citation for a diagram page.

This script is throwaway. Leave it out of `ingest.py`. A later feature should attach the rendered page to the citation and should keep text chunks for prose pages.

## Out of scope

- Pinout lookup, a connector index, and wire-color lookup.
- Any pin, color, or part number from `lj78-wiring` or `2jz-ge-rm`. Those stay `TBD`.
- OCR inside ingestion.
- Deciding which pages of the real PDF are diagrams. The file is absent.
- Changes to the answer contract.

## How to rerun

Install `tesseract-ocr`, `poppler-utils`, and `fonts-dejavu-core`. From `backend/`:

```bash
python3 spikes/wiring_spike.py --output eval/results/wiring-spike.json
```

`docs/MANUALS.md` records the SHA-256 for `lj78-wiring`. The on-disk PDF is AES-encrypted, and `backend/ingest.py` refuses encrypted PDFs. Measuring that file is a later issue. Quote a label from it only with the document id and the page.

## Limits

These five PDFs were built for the spike. They are not pages from the manuals named in `docs/MANUALS.md`. The unanchored string on sample page 4 is from tesseract 5.3.4. Another version can spell that misread differently. The decision uses the fact that the string contains neither planted label.

Poppler rasterizes the PDF before OCR. The image samples are JPEGs inside the PDF, so OCR sees a render of that JPEG, not a photo of a printed page.
