# Implementation plan

## Phase 0: research and architecture (done 2026-10-13)

Docs: `ARCHITECTURE.md`, `RESEARCH.md` (+ `research/`), `ASSET_PIPELINE.md`, `GAME_DESIGN.md`, this file, `AGENTS.md`.

## Phase 1: playable vertical slice

Work packages, in dependency order. A and B run in parallel; C needs A's cache; D needs B and C.

| WP | Scope | Done when |
|---|---|---|
| **A. Importer** (`tools/wzimport`) | WZ reader (header, version hash, GMS keystream, offsets, strings, dirs, imgs, all property types), canvas decode (1/2/513/517, zlib + block-encrypted), Sound_DX8 (MP3/PCM->WAV), UOL resolution, mob links, manifest expansion (maps -> backs/tiles/objs/bgm/mobs; mobs -> links/sounds; character ids -> dirs; items), atlas packing, cache writer, incremental import, `dump` subcommand, synthetic-fixture tests, real-data tests behind `MAPLE_WZ_ROOT` | `cargo test` green; real import of the Phase 1 manifest succeeds; spot-checked PNGs look right |
| **B. Sim core** (`game/scripts/sim`) | Every contract in `ARCHITECTURE.md` §4.4 + `data/survivor/*.json` + `data/canonical/jobs.json`, with unit tests: footholds, bounds, ladders, player physics, nav graph, mob swarm movement, spatial hash, projectiles, pickups, combat math, skills/loadout/runner, EXP/level/jobs, upgrades eligibility and draws, spawn director, `RunWorld` and a headless full-run test | `bash scripts/test.sh` green; a seeded 15-minute headless run reaches Magician and stays under budget |
| **C. Presentation foundations** (`scripts/assets`, `render`, `audio`) | `Assets` autoload + `WzImg` + `SpriteAnim`; `MapRenderer` (backs, layers, animated objs, parallax, scroll, front); camera; `AvatarRenderer` (composited beginner, stances); `MobRenderer`; `FxRenderer`; `DamageNumbers`; `Hud`; BGM/SFX; a map-viewer debug scene | Screenshots of 104040000 and the character match the original look by eye |
| **D. Integration** (`scripts/run`, `scripts/ui`, scenes) | `RunScene` (fixed-tick loop, input, sim <-> render), level-up window, job advancement window, pause, results, title, stage select, import screen; audio cues; tuning | Every acceptance check below passes in the real game |
| D (open item) | The import screen must find `wzimport` both in dev (`tools/wzimport/target/release/`) and in an export (next to the game exe); exports must bundle it | resolved before the first export |
| **E. Verification** | Offline test, perf benchmark (`bench.sh`), scripted playtest with screenshots (`playtest.sh`), adversarial review against the brief | Evidence recorded below |

### Acceptance checks (from the brief)

| Check | How it is verified |
|---|---|
| Launches and plays with no internet and no server | `test_offline.gd` + Rust `no_network_deps`; run with the network adapter disabled; no child process other than the local importer |
| Map rendered from original assets | screenshot of 104040000 from the cache; `require_cache` tests on map structure |
| Movement and animations recognisably MapleStory | Physics.img-driven `PlayerMotion` tests (walk 125 px/s, jump apex 77 px, gravity, terminal 670); stance animations with WZ delays; playtest video frames |
| Enemies spawn continuously and pursue | `SpawnDirector` + `MobSwarm` tests; playtest shows mobs closing in across platforms |
| Three Snails fires automatically and damages | `SkillRunner` tests; playtest damage numbers |
| Enemies die and reward EXP | swarm death + pickup tests; playtest EXP bar moves |
| Level-up choices visibly change behaviour | upgrade tests (count/cooldown/pierce/rank); screenshots before/after Additional Shell and Stronger Snails |
| Magician advancement reachable and selectable | progression test; seeded headless run reaches Lv 8; screenshot of the window |
| Difficulty increases | director curve test; alive-count log over time in playtest |
| Death, results, restart | run-state tests; playtest of death -> results -> retry |
| Responsive under density | `bench.sh` µs/tick at 100/300/600/1000 mobs; playtest frame-time p95 at 15:00 |

## Phase 2: job and skill expansion

Fire/Poison Wizard at 30 (Fire Arrow with the five listed upgrades incl. Burning DoT; Poison Breath with the
canonical poison tick), Magic Claw/Energy Bolt polish, Teleport as a dash, second stage set (The Tree That Grew I,
Henesys Hunting Ground II), more mobs (Green Mushroom, Horny Mushroom, Stumps), stage select with map previews.

## Phase 3: expanded survivor systems

Other Explorer paths (Warrior/Bowman/Thief/Pirate first jobs and skills), 3rd/4th job, bosses (Mushmom, King Slime,
Mano), elite waves and modifiers, passive items, skill evolutions and synergies, run modifiers, unlockable starting
configurations, persistent progression and achievements (local save file).

## Performance log

| Date | Build | Scenario | Result |
|---|---|---|---|
| 2026-10-13 | Phase 0 probe | GDScript SoA sim, 1000 mobs, Forward+ | 2.5-3.3 ms/frame (editor), 2.1-2.6 ms (release) |
| 2026-10-13 | sim-world (`scripts/bench.sh`, editor binary headless, other agents running) | `MobSwarm.step` + `SpatialHash.rebuild` + 20 radius-420 queries per tick, 104040000 / synthetic map | 100: 0.30 / 0.26 ms; 300: 0.75 / 0.56 ms; 600: 1.44 / 1.01 ms; 1000: 2.09 / 1.66 ms per tick (step alone at 1000: 1.19 / 0.87 ms) |
| 2026-10-13 | sim-world fix pass (drop step-off, mob wall checks, ceilings; same setup) | same | 100: 0.25 / 0.21 ms; 300: 0.65 / 0.53 ms; 600: 1.38 / 0.92 ms; 1000: 1.95 / 1.72 ms per tick (step alone at 1000: 1.07 / 0.96 ms); 0 lost |
| 2026-10-13 | sim-run (`scripts/bench.sh run`, editor binary headless, other agents running) | whole `RunWorld.step` (player, swarm, director refilling to N, hash, skills, shots, drops, touch) with a god-mode kiting bot and a late-game build (5 shells pierce 3, 4 Energy Bolts, Magic Claw), synthetic / 104040000 | 100: 0.32 / 0.40 ms; 300: 0.74 / 0.81 ms; 600: 1.24 / 1.39 ms; 1000: 2.35 / 2.36 ms per tick |
| 2026-10-13 | presentation (`map_viewer.tscn -- --mobs=N --perf=1200 --vsync=off`, editor binary, windowed 1600x1200, GL Compatibility, HUD on, other agents running) | N animated mobs walking on 104040000 floors via `MobRenderer` (one RS canvas item each) + map + HUD | 300: frame avg 1.38 ms, p95 1.90, p99 2.17 (726 fps), `MobRenderer.update_from` 0.37 ms; 1000: avg 3.71 ms, p95 5.13, p99 5.86 (270 fps), update_from 1.31 ms |

## Progress log

| Date | Milestone |
|---|---|
| 2026-10-13 | Phase 0 complete: research, architecture decision (Godot 4.7.2 + Rust importer), docs, repo skeleton |
