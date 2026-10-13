<img src="assets/icon.svg" width="64" height="64" alt="">

# Maple Survivors

A single-player, fully offline survival game that looks, sounds and moves like **MapleStory v83**, with a
Vampire-Survivors-style loop: survive a classic map against ever-growing swarms of familiar monsters while your skills
fire automatically, pick upgrades as you level, and advance jobs at the classic milestones.

The game renders **your own** original v83 data. No MapleStory files are included in this repository, and the game
needs no server, account or internet connection.

## Quick start

1. Get the vanilla GMS v83 `.wz` files (from the official v83 installer; see `docs/ASSET_PIPELINE.md` §1).
2. Import them into the local asset cache (needs Rust/cargo once to build the importer):
   ```bash
   bash scripts/import.sh "C:/path/to/MapleStory"
   ```
3. Play (Godot 4.7.2 is downloaded on first use by `scripts/godot.sh`, outside the repo):
   ```bash
   bash scripts/run.sh
   ```

## Docs

| Doc | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Approach comparison and decision, runtime architecture, module contracts |
| [`docs/RESEARCH.md`](docs/RESEARCH.md) | Evidence: source repos, v83 client protection, WZ contents, engine probe ([full reports](docs/research/)) |
| [`docs/ASSET_PIPELINE.md`](docs/ASSET_PIPELINE.md) | WZ format facts, importer, manifest, cache format |
| [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) | The run, movement, monsters, combat, skills, upgrades, jobs, constants and provenance |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | Phases, work packages, acceptance checks, performance log |
| [`AGENTS.md`](AGENTS.md) | Conventions for contributors and coding agents |

## Legal

MapleStory is © NEXON. This is an unofficial fan project that does not distribute any NEXON data; it reads files the
player already has. Code in this repository is the project's own; third-party notices are in `THIRD_PARTY_NOTICES.md`.
