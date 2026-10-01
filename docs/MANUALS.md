# Manual inventory

Phase 1 answers are grounded in these documents. Citation `{doc_id, page}` values use the **ID** column.

This file is the committed manifest. Copyrighted PDFs are not in git.

## Storage policy

1. **PDFs stay out of git.** `.gitignore` already excludes `manuals/` and `*.pdf`. Do not force-add them. Extracted page images also stay under `manuals/` (or another gitignored path), never in the repo.
2. **Local copies** live at `manuals/<id>.pdf` at the repository root (`manuals/2jz-ge-rm.pdf`, `manuals/lj78-wiring.pdf`). Create `manuals/` on your machine; git will not track it.
3. **External storage** is allowed (a drive, a private bucket). Before ingestion, place or symlink each file at `manuals/<id>.pdf` so the path is stable.
4. **Only this manifest is committed.** After you add a PDF, record its edition (or `TBD`), page count, and SHA-256 here. Ingestion reads this table and **fails** if a file is missing, a SHA-256 is still `TBD`, or the file hash does not match.
5. **Do not fill page counts or checksums from memory or from a listing online.** Hash the file you actually have (`sha256sum manuals/<id>.pdf`) and count pages from that same file.

To verify local copies against this table (from `backend/`):

```bash
python3 manifest.py
```

## Documents

Edition, page count, and SHA-256 are `TBD` until the matching PDF is on disk and recorded. This environment did not have those files.

| ID | Title | Edition | Page count | SHA-256 |
| --- | --- | --- | --- | --- |
| 2jz-ge-rm | 2JZ-GE repair manual | TBD | TBD | TBD |
| lj78-wiring | LJ78 wiring documentation | TBD | TBD | TBD |

IDs are lowercase, filesystem-safe, and stable. Do not invent Toyota publication numbers, years, or page counts. When the owner has the real cover pages, replace the titles and `TBD` fields with what is printed on those copies.

Which documents belong in Phase 1 is taken from [VISION.md](../VISION.md) and [ROADMAP.md](../ROADMAP.md) (2JZ-GE repair manual and LJ78 wiring docs). Additional manuals get a new row before ingestion may use them.

## How ingestion uses this file

`backend/manifest.py` parses the table above. For each row it requires `manuals/<id>.pdf` and compares SHA-256. A later issue (#18) will chunk those verified PDFs; it should call the same verifier first rather than trusting files by name.
