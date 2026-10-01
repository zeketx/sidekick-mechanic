# Sidekick Mechanic

Chat-first AI mechanic on iPhone for one truck: a 1990 Land Cruiser LJ78 with a 2JZ-GE swap. Describe a problem. It answers from the real manuals with page citations, and shows an engine-bay photo with the relevant part highlighted.

Phase 1 is the chat sidekick. The truck is not delivered yet; unknowns stay TBD.

Proposed minimum iOS version: iOS 17 (owner confirms).

- [VISION.md](VISION.md) — why this exists
- [ROADMAP.md](ROADMAP.md) — phases and milestones
- [Backlog](https://github.com/zeketx/sidekick-mechanic/issues) — GitHub Issues and [milestones](https://github.com/zeketx/sidekick-mechanic/milestones)
- [AGENTS.md](AGENTS.md) — how agents should work in this repo
- [docs/](docs/) — kanban, poteto plan, and the [build log](docs/build-log/)

Layout: `app/` (Xcode, owner-built), `backend/` (RAG), `ml/`, `docs/` (`docs/vehicle/`, `docs/build-log/`), `scripts/`. Manual PDFs stay in gitignored `manuals/`. The swappable telemetry protocol and JSON scenario simulator live in `app/SidekickCore` ([docs/design/telemetry-source.md](docs/design/telemetry-source.md)). From `backend/`, `pip install -r requirements.txt && python3 ingest.py` verifies those PDFs against [docs/MANUALS.md](docs/MANUALS.md) and writes page-level chunks. `make eval` scores the golden sample (fake pages until the real question set exists) and regenerates [docs/METRICS.md](docs/METRICS.md).

Tapping a citation chip pushes `CitationPageView` with that chip's `Citation`. It shows the document id, page number, a rendered page image, and the cited snippet. The image comes from the on-device cache (`SIDEKICK_PAGE_CACHE_DIR`, or the app cache directory `sidekick-manual-pages`). On a miss, the app requests `GET /manuals/{doc_id}/pages/{page}.png` and stores the PNG. Page images are not committed.
