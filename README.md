# Sidekick Mechanic

Chat-first AI mechanic on iPhone for one truck: a 1990 Land Cruiser LJ78 with a 2JZ-GE swap. Describe a problem. It answers from the real manuals with page citations, and shows an engine-bay photo with the relevant part highlighted.

Phase 1 is the chat sidekick. The truck is not delivered yet; unknowns stay TBD.

Proposed minimum iOS version: iOS 17 (owner confirms).

- [VISION.md](VISION.md) — why this exists
- [ROADMAP.md](ROADMAP.md) — phases and milestones
- [Backlog](https://github.com/zeketx/sidekick-mechanic/issues) — GitHub Issues and [milestones](https://github.com/zeketx/sidekick-mechanic/milestones)
- [AGENTS.md](AGENTS.md) — how agents should work in this repo
- [docs/](docs/) — kanban, poteto plan, and the [build log](docs/build-log/)

Layout: `app/` (Xcode, owner-built), `backend/` (RAG), `ml/`, `docs/` (`docs/vehicle/`, `docs/build-log/`), `scripts/`. Manual PDFs stay in gitignored `manuals/`.
