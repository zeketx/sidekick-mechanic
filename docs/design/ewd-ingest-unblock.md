# Unblocking `lj78-wiring`

`docs/MANUALS.md` keeps the row. The PDF stays at `manuals/lj78-wiring.pdf` and out of git. Status is `blocked`, so `manifest.py` still checks the SHA-256 and `ingest.py` does not open the file. The ID stays `lj78-wiring`.

The 2026-10-06 inventory on that row is the source for the file facts: edition EWD117F, 84 pages, image-only, AES-encrypted. That inventory says the EWD lists LJ70, LJ72, LJ73, LJ77, and LJ79, and does not name LJ78.

This note does not add a decrypt path or an OCR path.

## What a later change would do

1. **Install `cryptography`.** pypdf 6.19.0 uses that package for AES. Without it, opening an AES PDF raises `DependencyError` (`cryptography>=3.1 is required for AES algorithm`). That type is not a `PyPdfError`, so `ingest.py` does not turn it into `IngestError`. With `cryptography` installed, `PdfReader` finishes, `is_encrypted` stays true, and the existing check raises `IngestError` (`encrypted PDF for document ...`).

2. **Owner password, if one exists.** A later change would pass that password into pypdf. Do not invent one. If the owner has no password, decryption stays blocked.

3. **Image-only pages.** Text extraction on those pages is empty. A later path would OCR them or cite the page image. [wiring-diagram-spike.md](wiring-diagram-spike.md) says to cite the page image and to keep OCR text out of citation snippets.

Flip `Status` from `blocked` to `ingest` only after those three exist and `python3 ingest.py` then `python3 retrieval.py build` succeeds for this ID.
