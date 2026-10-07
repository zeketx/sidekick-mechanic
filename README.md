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

Tapping a citation chip opens a white sheet (`CitationPageView`) for that cited page. It shows the document id, page number, a rendered page image, the cited snippet, and a short **Go deeper** block. `FAKE-DOC*` pages use a generated stand-in on device. Real documents request `GET /manuals/{doc_id}/pages/{page}.png` from the backend, which rasterizes `manuals/<id>.pdf` (gitignored). Go deeper for live pages is `GET /manuals/{doc_id}/pages/{page}/go-deeper`, grounded only in that page. Page images are not committed.

## Verification

Agents prove behavior with the project-local skills in `.cursor/skills/`, then keep the maps honest with `/maintain-verification-skill`.

- Linux: [verify-backend](.cursor/skills/verify-backend/SKILL.md) launches FastAPI, posts `/chat` using the `FAKE-*` fixtures, and checks the answer contract, refusals, the spec guard, and citations. The same run executes `swift test` in `app/SidekickCore` and `make eval`.
- Owner's Mac: [verify-ios](.cursor/skills/verify-ios/SKILL.md) builds with `xcodebuild`, boots a simulator with `simctl`, and runs a UI test that sends a message. There is no `xcodeproj` in the repo yet, and Linux cannot run this skill.
