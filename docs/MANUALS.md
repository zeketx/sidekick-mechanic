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
python3 ingest.py
python3 retrieval.py build
```

## Documents

Edition, page count, and SHA-256 for these two rows were recorded on 2026-10-06 from the owner's local copies of `manuals/<id>.pdf`. Those PDFs stay out of git. Hash the file you have before you change a row (`sha256sum manuals/<id>.pdf`).

| ID | Title | Edition | Page count | SHA-256 | Status |
| --- | --- | --- | --- | --- | --- |
| 2jz-ge-rm | Lexus IS300 2004 repair manual RM1054U (2JZ-GE VVTi) | RM1054U | 1959 | 4464676a7fda45ada554909dc875ce12c4554f96d45c9ef400788e5e20d6008d | ingest |
| lj78-wiring | Toyota EWD117F Dec 1990 (LJ7x wiring) | EWD117F | 84 | eff462ba654ae488df12dbacb040771dba20d4f12eb8e5926024e8f03f632851 | blocked |

`Status` is `ingest` or `blocked`. `python3 manifest.py` still requires the file and checks SHA-256 for every row, including `blocked`. `python3 ingest.py` extracts only `ingest` rows. `python3 retrieval.py build` indexes those chunks.

`2jz-ge-rm` is a text-layer PDF. Prefer this copy over RM1140U for DI/VVT. Status is `ingest`.

`lj78-wiring` is image-only. Prefer this copy over EWD168F. The on-disk PDF is AES-encrypted. Status is `blocked`: the PDF stays at `manuals/lj78-wiring.pdf`, and this inventory does not decrypt or OCR it. The EWD lists LJ70, LJ72, LJ73, LJ77, and LJ79. It does not name LJ78. The ID stays `lj78-wiring`. What an unblock would take is in [ewd-ingest-unblock.md](design/ewd-ingest-unblock.md).

IDs are lowercase, filesystem-safe, and stable. Do not invent Toyota publication numbers, years, or page counts. A new row stays `TBD` until that PDF is on disk and hashed.

Wiring-diagram pages are cited as page images. Text extraction and OCR on synthetic pages are recorded in [wiring-diagram-spike.md](design/wiring-diagram-spike.md). Accuracy on `lj78-wiring` stays `TBD`.

Which documents belong in Phase 1 is taken from [VISION.md](../VISION.md) and [ROADMAP.md](../ROADMAP.md) (2JZ-GE repair manual and LJ78 wiring docs). Additional manuals get a new row before ingestion may use them.

## How ingestion uses this file

`backend/manifest.py` parses the table above. For each row, including `blocked`, it requires `manuals/<id>.pdf` and compares SHA-256. `backend/ingest.py` calls that verifier first, then writes page-level chunks (`doc_id`, PDF page number, text) for `ingest` rows only, plus a report of empty pages and skipped IDs. Extra files in `manuals/` that are not in this table are ignored. `backend/retrieval.py build` turns that JSONL into the SQLite FTS5 index (`docs/design/retrieval-index.md`).
