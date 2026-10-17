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
   Or skip this step: without a cache the game opens its import screen, where you pick the folder and it runs the
   same importer locally.
3. Play (Godot 4.7.2 is downloaded on first use by `scripts/godot.sh`, outside the repo):
   ```bash
   bash scripts/run.sh
   ```
   Title -> Start -> pick a stage -> defeat its three bosses at 5:00, 10:00 and 15:00. The final fight continues past
   15:00; death or a clear shows the results. Retry or go back to the stage
   select. Your best result per stage is kept in `%APPDATA%/MapleSurvivors/save.json`.
4. Optional: `bash scripts/export.sh` builds a stand-alone Windows game in `game/export/` (`MapleSurvivors.exe` with
   `wzimport.exe` beside it; needs the Godot 4.7.2 export templates).

## Controls

| Action | Keys |
|---|---|
| Move | Left / Right arrows (or A / D) |
| Jump | Left Alt (or C) |
| Talk to a scroll NPC (Free Market) | Space (or double-click it) |
| Climb a ladder or rope | Up / Down next to it (or W / S) |
| Use a same-map portal | Hold Up inside its entrance |
| Drop through a platform | Down + Jump |
| Drink HP potion | Delete (or Q) |
| Drink MP potion | End (or E) |
| Teleport (after learning it) | X + direction; hold X to repeat; facing if no direction |
| Pick an upgrade / job | Mouse, 1 / 2 / 3, or Up / Down + Enter |
| Pause (Resume / Quit to stage select) | Esc |
| Performance overlay | F3 |

Attacks cast on their own; Teleport uses X after you learn it. You choose where to stand, what to pick up and which upgrades to take. Hanging on a rope
stops new casts and weapon swings; active buffs and Recovery continue. Job skills spend MP and wait when it is short.

## For developers

`bash scripts/test.sh` runs the unit tests, `bash scripts/playtest.sh` plays a scripted run with screenshots and
frame-time statistics into `evidence/`, and `bash scripts/balance.sh` reports the pacing over several seeds. See
[`AGENTS.md`](AGENTS.md).

Playtests allow up to 30:00 by default so the final boss can die. `--minutes` is an absolute run-time limit, including
any `--warp` fast-forward. Balance defaults to training seeds 1–6. Tune only on 1–60 and 2026; after freezing a
candidate, explicitly report `101..130` on both stages with `--policy=bot` and `--policy=random`.

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
