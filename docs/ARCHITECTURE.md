# Architecture

Status: Phase 0 decision record (2026-10-13). Evidence lives in `docs/RESEARCH.md` and the full investigator reports in
`docs/research/`.

## 1. Goal and constraints

Make a single-player Vampire-Survivors-style game that looks, sounds and moves like MapleStory v83 (GMS, Feb 2010
build), using the original assets, with a different combat and progression loop. Hard constraints from the brief:

- Fully offline: no server, no localhost sockets, no database, no account, no Java process.
- Authentic presentation: original maps, sprites, animations, frame timings, origins, sounds, UI art.
- Hundreds of mobs, dozens to hundreds of projectiles and pickups, at a stable 60 FPS.
- Original MapleStory assets are proprietary: never committed or distributed; the player points the game at their
  own v83 install.
- Windows first; cross-platform welcome if it costs nothing now.

## 2. Approaches compared

| Criterion | 1. Patch the v83 client | 2. New runtime that imports original WZ (chosen) | 3. Adapt Cosmic's systems into a local app |
|---|---|---|---|
| Authenticity | Highest in principle (the original renderer) | High: same WZ art, timings and Physics.img constants; rendering and physics rules re-implemented from verified data and documented reimplementations | Cosmic has no renderer, physics or client logic: it would still need approach 2 for everything visible |
| Feasibility (evidence) | **Blocked.** The original `MapleStory.exe` is protected (random section names `ytkjcptk/albasygk/jbhyjsdw`, 1-function import table, entropy 7.98, no readable strings; `docs/research/rea-client.md` §3). Unpacking it is circumventing a protection measure, ruled out by the brief and by REA's own disclaimer. The only unpacked build (HeavenMS-localhost) was flagged by Defender as `Trojan:MSIL/Cryptor!rfn` (severity 5) and deleted. | Proven pieces: a from-scratch WZ reader parsed all 16 v83 archives with 0 errors (`wz-inventory.md` §1); Godot 4.7.2 loads runtime PNG/MP3 from outside `res://`, renders pixel-perfect 800x600 integer scaling, and holds 60 FPS with 4000 simulated mobs on this PC (`godot-probe.md`) | Cosmic is a Java server: MySQL, login/channel TCP servers (`cosmic-data.md` §1). Damage is client-authoritative in v83, so Cosmic does not even contain the hit formulas |
| Offline | The client is built around login/channel packets; every gameplay system (spawns, damage, EXP, drops) is server-driven | Native: there is no network layer at all | Server architecture; would need its own removal |
| Swarms (100s of mobs) | Client designed for ~30-40 mobs per map with server-driven control; uncapping is guesswork in protected code | Designed for it: struct-of-arrays sim + batched rendering; measured headroom ~5x at 1000 mobs | n/a |
| Adding systems | Binary patching of protected code | Ordinary code + data files | Java code under AGPL |
| Maintainability | Very poor | Good: typed GDScript, data-driven content, tests | Poor fit (server code for a client game) |
| Licensing | Modifying Nexon's binary; distribution impossible | Our code is ours; assets stay on the player's machine; Godot is MIT | AGPL-3.0: porting code would make the whole game AGPL |

**Decision: approach 2.** A new native runtime that reads the player's original v83 WZ files through a local importer.
Cosmic and the open-source client reimplementations are used as references for facts and algorithm descriptions only.

### 2.1 Engine choice

| Option | Verdict |
|---|---|
| **Godot 4.7.2 + GDScript** (chosen) | Already installed with export templates; MIT. Measured: full per-mob sim ~2 µs/mob in GDScript, 60 FPS held to ~4000 mobs; runtime PNG/MP3 loading works in exported builds; Movie Maker and screenshots for evidence; integer-scaled 800x600 verified pixel-perfect. GDScript is CPU-bound, so hot loops use packed arrays and the WZ decoding moves to a native tool. |
| MonoGame / FNA (C#) | No .NET SDK installed; text, audio (MP3), UI and export plumbing all hand-built. No measured advantage at our entity counts. |
| Custom Rust renderer | Fastest, but windowing, MP3 audio, fonts, UI and capture tooling would all be bespoke. Engine work instead of game work. |

**WZ decoding lives in a native Rust importer (`tools/wzimport`), not in GDScript.** Pixel conversion in GDScript is
10-40x slower than native (BGRA4444->RGBA8 1024x768: 28-94 ms vs 2.3 ms, `godot-probe.md` §2), and the WZ crypto,
block-encrypted canvases and UOL resolution are much better served by a compiled, unit-tested tool. Rust is installed;
Java/.NET/Python are not. The importer is a single self-contained executable that the game can launch locally.

## 3. System overview

```
  player's v83 install                     tools/wzimport (Rust CLI, offline)                 game/ (Godot 4.7.2)
  ┌──────────────────┐   read-only    ┌──────────────────────────────────────┐   files   ┌──────────────────────────────┐
  │ Map.wz Mob.wz    │ ─────────────► │ WZ reader (GMS keystream, v83 hash)  │ ────────► │ AssetLibrary (autoload        │
  │ Character.wz ... │                │ manifest + dependency expansion      │  cache:   │ "Assets"): img JSON trees,    │
  │ Sound.wz UI.wz   │                │ canvas decode (1/2/513/517, XOR blk) │  JSON +   │ atlas textures, MP3/WAV       │
  └──────────────────┘                │ UOL resolution, mob links            │  PNG +    ├──────────────────────────────┤
                                      │ atlas packing, MP3/WAV extraction    │  MP3      │ sim/ (pure, deterministic)    │
                                      └──────────────────────────────────────┘           │ render/ ui/ audio/ run/       │
                                                                                          └──────────────────────────────┘
```

- The importer runs once per v83 install (and again when the manifest grows). It writes the **asset cache** to the
  game's user data folder (`%APPDATA%/MapleSurvivors/asset_cache/v83/` on Windows). Format: `docs/ASSET_PIPELINE.md`.
- The game never parses `.wz` files. It reads JSON trees that mirror the WZ structure exactly (same names, same nesting,
  same order), plus PNG atlas pages and audio files. Every WZ path (`Mob.wz/0100100.img/move/0`) works unchanged.
- If the cache is missing, the game's first screen asks for the v83 folder and runs the bundled importer as a local
  child process (no network, no server).

## 4. Runtime architecture (Godot)

### 4.1 Scene flow

`main.tscn` (bootstrap) -> `ImportScreen` (only when the cache is missing) -> `TitleScreen` -> `StageSelect` ->
`RunScene` -> `ResultsScreen` -> back to `StageSelect` or a restart of the same stage.

### 4.2 Autoloads

| Autoload | Script | Role |
|---|---|---|
| `Assets` | `scripts/assets/asset_library.gd` | Locates the cache, loads/caches img JSON (`WzImg`), atlas page textures, sounds; builds `SpriteAnim` frame lists |
| `Settings` | `scripts/core/settings.gd` | `user://settings.cfg`: WZ root, volumes, window scale, key bindings |
| `Sfx` | `scripts/audio/audio_service.gd` | BGM player with fade, pooled SFX players |

Everything else is owned by the scene that uses it.

### 4.3 Simulation / presentation split

A run is a `RunWorld` (`scripts/sim/run_world.gd`), a pure object advanced in **fixed 1/60 s ticks** by `RunScene`'s
accumulator. It never touches nodes, input, time or files. Each tick it consumes a `MoveInput` and appends events
(`{"type": "mob_hit", ...}`) to `RunWorld.events`. The presentation layer drains the events every frame to spawn damage
numbers, hit effects and sounds, and reads the struct-of-arrays state directly to draw mobs, projectiles and pickups.

Benefits: every gameplay rule is testable headless with a seeded RNG; the presentation can be swapped (debug view,
recording) without changing the rules; and a full simulated run can be benchmarked without rendering.

### 4.4 Module contracts (sim core, `game/scripts/sim/`)

All classes are `RefCounted` with `class_name`. Coordinates are MapleStory world pixels (x right, y down, the same as
Godot 2D). Time is seconds (WZ `delay` ms are converted on load). `fh` = foothold index (not the WZ id), `-1` = none.

| Class | Responsibility | Key API |
|---|---|---|
| `PhysicsConstants` | Map.wz/Physics.img values | `static from_wz(physics_img: Dictionary)`, `static v83_defaults()`, fields `walk_force`, `walk_speed`, `walk_drag`, `slip_force`, `slip_speed`, `float_drag1`, `float_drag2`, `float_coefficient`, `swim_*`, `fly_*`, `gravity_acc`, `fall_speed`, `jump_speed`, `max_friction`, `min_friction`, `fly_jump_dec` |
| `FootholdMap` | Foothold geometry and queries | `static from_wz(map_img)`, `static from_segments(list)`, `count()`, `is_wall(i)`, `is_floor(i)`, `y_at(i, x)`, `find_below(x, y, ignore := -1) -> int`, `next_of(i)`, `prev_of(i)`, `bounds() -> Rect2`, `platform_of(i)`, `platform_count()`, `platform_span(p) -> Vector2` (min x, max x), packed arrays `x1 y1 x2 y2 layer group prev next`, flags `cant_through forbid_fall_down` |
| `MapBounds` | Camera/world limits | `static from_map(map_img, fhm) -> Rect2`: `info/VR*` if present, else `miniMap` rect, else foothold bbox (top -300, bottom +100) |
| `LadderSet` | Ladders and ropes | `static from_wz(map_img)`, `static from_list(list)`, `find_grab(x, y, reach) -> int`, arrays `x y1 y2 is_ladder uf page` |
| `MoveInput` | One tick of player intent | `left right up down jump_pressed jump_held` |
| `PlayerMotion` | Player movement per Physics.img | `_init(constants)`, `place(pos, fhm)`, `step(dt, input, fhm, ladders, bounds) -> int` (event flags), `knockback(dir)`, fields `pos vel fh ladder facing state speed_stat jump_stat`, `stance() -> String` |
| `NavGraph` | Platform graph for mob pathing | `static build(fhm, opts)`, `route(from_p, to_p) -> int` (edge index), `edge(e) -> Dictionary` (`kind` drop/jump, `from_p`, `to_p`, `x_from`, `x_to`), `reachable(a, b)` |
| `MobKind` | One mob type: canonical WZ stats + survivor overrides + animation timing needed by the sim | `static from_wz(mob_img, id, overrides)`, fields `id name level max_hp exp pad pdd mad mdd speed_stat move_speed can_jump hitbox die_time hit_time pushed body_attack elem_attr` |
| `MobSwarm` | All mobs, struct-of-arrays with free list | `_init(capacity)`, `spawn(kind, x, y, fh, hp) -> int`, `step(dt, ctx)`, `apply_hit(i, dmg, dir) -> bool`, `alive_count()`, packed arrays `kind x y vx vy hp max_hp state state_t fh platform facing anim_t` |
| `SpatialHash` | Broad phase for mobs | `_init(cell)`, `rebuild(xs, ys, active)`, `query_rect(r, out) -> int`, `query_radius(c, r, out) -> int` |
| `ProjectileSystem` | Shots in flight (pooled SoA) | `spawn(spec) -> int`, `step(dt, swarm, hash, events)`, per-shot pierce and already-hit list |
| `PickupSystem` | EXP drops (pooled SoA) | `spawn(pos, exp, item_id)`, `step(dt, player_pos, magnet_r, fhm, events)` |
| `CombatMath` | Damage formulas (static) | `magic_damage_range(int_stat, matk, spell_attack, mastery)`, `touch_damage(...)`, `apply_defense(...)`, `roll_crit(...)` |
| `SkillBook` / `Loadout` | Survivor skill definitions + owned skills, ranks and modifiers | `Loadout.add_skill(id)`, `rank(id)`, `stats(id) -> Dictionary` (resolved damage, cooldown, count, pierce, speed, range, size...) |
| `SkillRunner` | Auto-casting | `step(dt, world)`: cooldowns, targeting via `SpatialHash`, emits `cast` events, spawns projectiles or instant hits |
| `ExpCurve`, `RunProgression` | Survivor EXP curve, level, job, pending level-ups | `exp_to_next(level)`, `add_exp(n) -> int` levels gained |
| `JobTree` | Data-driven job advancement (canonical ids) | `advancements(job_id, level) -> Array`, `job(id) -> Dictionary` |
| `UpgradePool` | Data-driven upgrade eligibility and draws | `eligible(state) -> Array`, `roll_choices(state, rng, n) -> Array`, `apply(id, state)` |
| `SpawnDirector` | Stage pacing, spawn positions | `step(dt, world)`; spawns off-screen on floors reachable from the player's platform |
| `RunWorld` | Owns a run | `_init(setup)`, `step(dt, input)`, `events`, `time`, `kills`, `state` (PLAYING / CHOOSING / DEAD / CLEARED) |

### 4.4.1 Run setup (what `RunWorld` is built from)

The sim never reads files. `RunScene` (presentation) builds a setup Dictionary from the asset cache and `res://data`:

```gdscript
var setup := {
	"map_img": Dictionary,            # Map.wz/Map/Map1/104040000.img root (cache JSON)
	"physics_img": Dictionary,        # Map.wz/Physics.img root
	"mob_imgs": {100100: Dictionary}, # Mob.wz/<id>.img roots, info/link already followed by the loader
	"skill_imgs": {"000": Dictionary, "200": Dictionary, "210": Dictionary},  # Skill.wz/<book>.img roots
	"data": {"skills": {}, "upgrades": {}, "stages": {}, "balance": {}, "mobs": {}, "jobs_survivor": {},
		"jobs": {}, "exp_table": {}},   # parsed game/data/survivor/*.json and game/data/canonical/*.json
	"stage": "henesys_hg1",           # key in stages.json
	"seed": 12345,
	"view_size": Vector2(800, 600),   # logical view; RunWorld keeps a player-centred view rect for spawn logic
}
```

Tests build the same Dictionary from synthetic data. `scripts/core/data_repo.gd` loads the JSON files (outside sim).

### 4.4.2 Pause protocol

`RunWorld.state` is one of `PLAYING`, `CHOOSING_JOB`, `CHOOSING_UPGRADE`, `DEAD`, `CLEARED`. `step()` advances the
world only while `PLAYING`. When EXP crosses one or more levels, the world queues them. For each queued level it
first checks the job tree: if an advancement is offered at that level it enters `CHOOSING_JOB` and emits
`job_advance_pending`; otherwise (or after the job choice) it enters `CHOOSING_UPGRADE` and emits `choice_pending`.
The presentation layer shows the windows and calls back:

| Call | Effect |
|---|---|
| `apply_job(job_id)` | advance (emits `job_changed`), then continue to the upgrade choice for that level |
| `decline_job()` | stay, then continue to the upgrade choice |
| `apply_choice(card_id)` | apply the card (emits `upgrade_applied`), then the next queued level, else back to `PLAYING` |

Level-up effects and their short pause before the window are presentation-only.

### 4.4.3 Event schema

`RunWorld.events` is an `Array` of Dictionaries appended during `step()` (and during the calls above) and cleared by
the presentation after it drains them. `mob`, `proj`, `pickup` are **sim slot indices** (valid only for the frame);
`mob_id`, `skill_id`, `item_id`, `job_id` are **original MapleStory ids**; `skill` is the survivor skill key from
`skills.json`; visual fields are **WZ paths** into the asset cache.

| type | fields |
|---|---|
| `cast` | `skill`, `skill_id`, `level`, `pos`, `facing`, `action` (body stance to play when standing, e.g. `"swingO1"`), `effect` (WZ path of the caster effect or `""`) |
| `mob_spawned` | `mob`, `mob_id`, `pos`, `elite` |
| `mob_hit` | `mob`, `mob_id`, `damage` (int), `crit`, `pos` (where to draw the number: mob head), `hit_visual` (WZ path or `""`), `skill` |
| `mob_died` | `mob`, `mob_id`, `pos`, `exp`, `elite` |
| `player_hit` | `damage` (int), `mp_absorbed` (int), `dir` (-1/1), `pos` |
| `player_jump` | `pos` |
| `player_died` | `pos` |
| `pickup_spawned` | `pickup`, `item_id`, `pos` |
| `pickup_collected` | `pickup`, `item_id`, `exp`, `pos` |
| `level_up` | `level` |
| `job_advance_pending` | `options`: `[{job_id, name, available, reason}]` |
| `job_changed` | `job_id`, `name` |
| `choice_pending` | `cards`: `[{id, kind, name, desc, icon, rank, max_rank, skill}]` |
| `upgrade_applied` | `id`, `rank` |
| `skill_learned` | `skill`, `skill_id` |
| `burst` | `count` (a spawn burst started) |
| `stage_cleared` | `time` |

Swarm visuals are read from state, not events: `MobSwarm` arrays (`kind` -> `RunWorld.mob_kinds[kind].id`, `state`,
`state_t`, `facing`, `alpha`, `x`, `y`), `ProjectileSystem` arrays (`active`, `x`, `y`, `vx`, `vy`, `visual` ->
`RunWorld.visual_paths[visual]`, `rotate`), `PickupSystem` arrays (`active`, `x`, `y`, `item_id`), and
`RunWorld.player` / `RunWorld.player_state` (`hp`, `mp`, `max_hp`, `max_mp`, `exp`, `level`, `job_id`,
`invincible_t`, `action`, `action_t`, `dead`).

### 4.4.4 Survivor data files (`game/data/survivor/`)

| File | Contents |
|---|---|
| `skills.json` | survivor behaviour per skill key: canonical `skill_id`, `book`, job, kind (projectile / instant / passive), cooldown, range, speed, count, pierce, rank -> canonical level map, visuals (WZ paths), sounds |
| `upgrades.json` | upgrade cards (`GAME_DESIGN.md` §8) |
| `stages.json` | stage key -> map id, duration, pacing keyframes, pools, bursts, elites |
| `balance.json` | EXP curve, player base stats and growth per job, invincibility, knockback, magnet, contact damage scale, mob speed factor |
| `mobs.json` | per-mob survivor overrides (EXP drop item id, HP/speed multipliers, `can_jump` override) |
| `jobs.json` | which canonical jobs are playable and what advancing grants |

### 4.5 Presentation (`game/scripts/render`, `ui`, `audio`, `run`)

| Piece | Approach |
|---|---|
| `MapRenderer` | Backgrounds (types 0-7, parallax `x + cam_cx*rx/100`, tiling by `cx/cy`, auto-scroll `rx*5 px/s`, `a`, `f`, front backs) redrawn per frame; static tiles/objs per layer recorded once in a `_draw()` command list; animated objs as canvas items. Draw order: non-front backs -> layers 0..7 (objs by `z`, then tiles by canvas `z`, then actors standing on that layer) -> front backs. |
| `AvatarRenderer` | Composites body/arm/head/face/hair/coat/pants/shoes(/weapon) per frame using `map` anchors (navel, neck, hand, brow) and `Base.wz/zmap.img` order. Mirrors for facing. |
| `MobRenderer` | One RenderingServer canvas item per live mob slot (no Nodes), region-of-atlas per frame, alpha for `a0/a1` fades. |
| `FxRenderer` | Pooled one-shot WZ animations (skill hit, level-up, job change) and projectiles. |
| `DamageNumbers` | `Effect.wz/BasicEff.img` digit sets: first digit large set, rest small; 400 ms hold then 600 ms fade + 30 px rise (tier B). |
| `Hud` | `UI.wz/StatusBar.img` bar (800x71), gauges, `Basic.img/LevelNo` digits, timer, kill count. |
| Windows | Level-up choice, job advancement, pause, results: built from `UI.wz` window frames and buttons, skill icons from `Skill.wz`, text from `String.wz`. |
| `Camera` | Follows the player with smoothing (tier C), clamped to `MapBounds`, positions rounded to whole pixels. |

Logical resolution 800x600 (v83's native size and the width of `StatusBar.img/base/backgrnd`), `stretch/mode=viewport`,
`aspect=expand`, `scale_mode=integer`, nearest filtering: on wider windows the player sees more of the map at the same
pixel size, never a stretched sprite.

## 5. Data architecture

| Layer | Where | Examples | Rule |
|---|---|---|---|
| Canonical, from WZ | asset cache (read at runtime) | mob stats, frame delays/origins/hitboxes, Physics.img, skill level tables, map geometry, names | Never copied into the repo, never edited |
| Canonical, not in WZ | `game/data/canonical/` | EXP table, job tree (ids, advancement levels) | Facts with a `_source` note |
| Survivor design | `game/data/survivor/` | skill behaviour, upgrades, stages and waves, balance multipliers, per-mob overrides | All tuning happens here |
| Asset selection | `game/data/asset_manifest.json` | maps, mobs, character parts, UI/effect/sound images to import | Grows with content |

## 6. Performance architecture

Budget at 60 FPS (16.7 ms) on the dev PC, target 300 mobs at < 5 ms total frame CPU, with a path to 1000+:

- Sim in packed arrays, one loop per system, no per-entity Nodes; fixed 1/60 s ticks with at most 4 catch-up ticks.
- Broad phase: uniform `SpatialHash` (64 px cells) rebuilt every tick by counting sort.
- Rendering: atlas pages per WZ image (same-type mobs share a texture so draws batch), RenderingServer canvas items for
  swarms, static map layers recorded once.
- Pools for projectiles, pickups, damage numbers and effects; no allocation in steady state.
- `scripts/bench.sh` runs the sim headless at fixed mob counts and records µs/tick; `scripts/playtest.sh` records real
  frame times in a window. Results go in `docs/IMPLEMENTATION_PLAN.md` "Performance log".
- If GDScript becomes the bottleneck past ~1000 mobs, the mob/projectile inner loops move to a Rust GDExtension
  behind the same `MobSwarm`/`ProjectileSystem` API.

## 7. Offline guarantees

- No networking API is used by the game or the importer; enforced by `tests/unit/test_offline.gd` (source scan of
  `game/` for network classes) and the importer's `no_network_deps` test (Cargo.lock scan).
- The importer is a local process reading local files; the game launches it with `OS.execute_with_pipe`/`OS.create_process`.
- Settings and saves are local files under the user data folder.
- Verified by running the game with networking disabled (see `docs/IMPLEMENTATION_PLAN.md` acceptance checks).

## 8. Licensing and assets

- Our code: original. Godot (MIT) notices ship with exports. Rust crates are permissive (MIT/Apache/Zlib); the list is
  in `THIRD_PARTY_NOTICES.md`.
- Cosmic (AGPL-3.0) and the AGPL/GPL/MPL clients: facts and prose descriptions only, never code. Where a constant comes
  from them it is labelled with its tier and source in `docs/GAME_DESIGN.md`.
- Nexon's assets: the player supplies their own v83 install; the cache lives in their user folder; nothing proprietary
  is committed, bundled or uploaded. Screenshots of the running game are kept in the gitignored `evidence/` folder.

## 9. Known unknowns (tracked in `docs/RESEARCH.md` §6)

The real client's physics integrator and timestep, mob speed-stat conversion, projectile speeds, hit-stun and death
fade timing, climb speed, camera smoothing, and the touch-damage formula are not recoverable from data or clean
sources. Each is implemented as a labelled, data-driven constant so it can be corrected when better evidence appears.
