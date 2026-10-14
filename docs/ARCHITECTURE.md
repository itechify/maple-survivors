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
| `Settings` | `scripts/core/settings.gd` | `user://settings.cfg`: WZ root, volumes, window scale, fill-window view mode, frame cap (`[display] max_fps`: vsync on and `Engine.max_fps` = the display's refresh rate by default, `--vsync=off` uncaps), key bindings (rebound actions applied to the `InputMap`) |
| `Sfx` | `scripts/audio/audio_service.gd` | BGM player with fade, pooled SFX players |
| `Flow` | `scripts/core/scene_flow.gd` | Scene flow of 4.1: swaps main.tscn's child (`goto_title`, `goto_stage_select`, `goto_import`, `start_run`, `finish_run` -> results + best result in `SaveData`), `--run=<stage>` command line |

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
| `FootholdMap` | Foothold geometry and queries | `static from_wz(map_img)`, `static from_segments(list)`, `count()`, `is_wall(i)`, `is_floor(i)`, `y_at(i, x)`, `find_below(x, y, ignore := -1) -> int`, `next_of(i)`, `prev_of(i)`, `bounds() -> Rect2`, `platform_of(i)`, `platform_count()`, `platform_span(p) -> Vector2` (min x, max x), `walk_blocked(p, xa, xb) -> bool` (a wall stands across p between the two), packed arrays `x1 y1 x2 y2 layer group prev next`, flags `cant_through forbid_fall_down` |
| `MapBounds` | Camera/world limits | `static from_map(map_img, fhm) -> Rect2`: `info/VR*` if present, else `miniMap` rect, else foothold bbox (top -300, bottom +100) |
| `LadderSet` | Ladders and ropes | `static from_wz(map_img)`, `static from_list(list)`, `find_grab(x, y, reach) -> int`, arrays `x y1 y2 is_ladder uf page` |
| `MoveInput` | One tick of player intent | `left right up down jump_pressed jump_held` |
| `PlayerMotion` | Player movement per Physics.img | `_init(constants)`, `place(pos, fhm)`, `step(dt, input, fhm, ladders, bounds) -> int` (event flags), `knockback(dir)`, fields `pos vel fh ladder facing state speed_stat jump_stat`, `stance() -> String` |
| `NavGraph` | Platform graph for mob pathing | `static build(fhm, opts)`, `route(from_p, to_p) -> int` (edge index, fewest edges), `edge(e) -> Dictionary` (`kind` drop/jump, `from_p`, `to_p`, `x_from`, `x_to`), `reachable(a, b)`; travel-cost field toward a point: `prepare_target(to_p, tx, also_p := -1)`, then `route_cost(p, x) -> float` (px, INF = no way), `best_edge(p, x) -> int`, arrays `cost`, `take` (per edge) |
| `MobKind` | One mob type: canonical WZ stats + survivor overrides + animation timing needed by the sim | `static from_wz(mob_img, id, overrides)`, fields `id name level max_hp exp pad pdd mad mdd speed_stat move_speed can_jump hitbox die_time hit_time pushed body_attack elem_attr` |
| `MobSwarm` | All mobs, struct-of-arrays with free list | `_init(capacity)`, `spawn(kind, x, y, fh, hp) -> int`, `despawn(i)`, `step(dt, ctx)`, `apply_hit(i, dmg, dir) -> bool`, `alive_count()`, `static low_platform(fhm, target, tp, reach_y)`, packed arrays `kind x y vx vy hp max_hp state state_t fh platform facing anim_t route_len` |
| `SpatialHash` | Broad phase for mobs | `_init(cell)`, `rebuild(xs, ys, active)`, `query_rect(r, out) -> int`, `query_radius(c, r, out) -> int` |
| `ProjectileSystem` | Shots in flight (pooled SoA) | `spawn(spec) -> int`, `step(dt, swarm, hash, events)`, per-shot pierce and already-hit list |
| `PickupSystem` | EXP drops (pooled SoA) | `spawn(pos, exp, item_id)`, `step(dt, player_pos, magnet_r, fhm, events)` |
| `CombatMath` | Damage formulas (static) | `magic_damage_range(int_stat, matk, spell_attack, mastery)`, `touch_damage(...)`, `apply_defense(...)`, `roll_crit(...)` |
| `SkillBook` / `Loadout` | Survivor skill definitions + owned skills, ranks and modifiers | `Loadout.add_skill(id)`, `rank(id)`, `stats(id) -> Dictionary` (resolved damage, cooldown, count, pierce, speed, range, size...) |
| `SkillRunner` | Auto-casting | `step(dt, world)`: cooldowns, targeting via `SpatialHash`, emits `cast` events, spawns projectiles or instant hits |
| `ExpCurve`, `RunProgression` | Survivor EXP curve, level, job, pending level-ups | `exp_to_next(level)`, `add_exp(n) -> int` levels gained |
| `JobTree` | Data-driven job advancement (canonical ids) | `advancements(job_id, level) -> Array`, `job(id) -> Dictionary` |
| `UpgradePool` | Data-driven upgrade eligibility and draws | `eligible(state) -> Array`, `roll_choices(state, rng, n) -> Array`, `apply(id, state)` |
| `SpawnDirector` | Stage pacing, spawn positions, relocation | `step(dt, world)`, `pick_spawn(world, k, side := 0) -> Vector3`, `screen_rect(world) -> Rect2` (what spawns stay out of: the view + `margin`, + `trail_margin` behind a moving player); spawns off-screen, first on the floors beside the view, preferring points whose way to the player (NavGraph travel cost) is at most `prefer_route` px longer than the walk in from the view's side, never where a wall across a platform stands anywhere on the way; moves off-screen mobs that stall, are far or cannot reach the player to a point ahead of the player (`relocated`) |
| `RunWorld` | Owns a run | `_init(setup)`, `step(dt, input)`, `events`, `time`, `kills`, `state` (PLAYING / CHOOSING / DEAD / CLEARED) |
| `BotInput` | The autoplay bot (RunScene `autoplay`/`autopick`, the full-run tests, `scripts/balance.sh`, the benchmarks): kites, collects drops, climbs to drops above, picks jobs and cards | `decide(world, memo) -> MoveInput`, `auto_choose(world, first_card := false)`, `pick_card_for(world, cards)`, `pick_job(options)` |

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
	"view_size": Vector2(800, 600),   # the live logical view, get_viewport().get_visible_rect().size (800x600 on 4:3,
	                                  # 1066x600 on 16:9, more with fill_window; see 4.5); RunWorld keeps a
	                                  # player-centred view rect of this size for spawn logic
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
| `mob_spawned` | `mob`, `mob_id`, `pos`, `elite`, `relocated_from` (the slot the mob had when SpawnDirector relocated it, -1 for a new spawn) |
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
| `choice_pending` | `cards`: `[{id, kind, name, desc, icon, rank, max_rank, skill, skill_name, skill_level, skill_level_next, skill_changes}]`; `skill_changes` maps canonical fields (`mad`, `mastery`, `mpCon`, `fixdamage`) to `{before: int, after: int}` for rank cards, `{}` otherwise; mastery is the displayed percent |
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
| `skills.json` | survivor behaviour per skill key: canonical `skill_id`, `book`, job, kind (projectile / instant / passive), cooldown, range, speed, count, pierce, rank -> canonical level map, `level_ranks` (rank reached at a character level), visuals (WZ paths), sounds |
| `upgrades.json` | upgrade cards (`GAME_DESIGN.md` §8), `power` flags and the `pity` rule |
| `stages.json` | stage key -> map id, duration, pacing keyframes, pools, bursts, elites, per-stage `spawn` overrides, `exp_mult`, stage-card `note` |
| `balance.json` | EXP curve, player base stats (incl. cast origin / `cast_forward`) and growth per job, invincibility, knockback, magnet, drops (incl. `lifetime`), spawning (incl. `band_y`, `prefer_route`, `stall_time`, `trail_margin`), contact damage scale, mob speed factor |
| `mobs.json` | per-mob survivor overrides (EXP drop item id, HP/speed multipliers, `can_jump` override) |
| `jobs.json` | which canonical jobs are playable and what advancing grants (MP, skills learned at once, the next draw's guarantee) |

### 4.4.5 World-movement details (`FootholdMap` ... `SpatialHash`)

What the table above leaves open; the class doc comments have the rest.

- **Footholds:** `x1 < x2` floor (landed on from above), `x1 == x2` wall, `x1 > x2` ceiling (stops upward motion).
- **`MobSwarm.step(dt, ctx)`**, `ctx` keys: `fhm` (required); `nav` = `NavGraph.build(fhm, {"can_jump": false})` for
  mobs whose `MobKind.can_jump` is false; `nav_jump` = `NavGraph.build(fhm, {"can_jump": true})` (default `nav`);
  `target` (player position); `target_fh` (player foothold, -1 = the floor below `target`); `bounds` (MapBounds rect);
  `speed_mult` (stage speed multiplier, default 1); `physics` (PhysicsConstants, default v83). Build both graphs with
  the same `gravity` / `fall_speed` / `jump_speed` as `physics`. `MobSwarm.kinds` is `RunWorld.mob_kinds`; edits to a
  kind apply from the next step.
- **`MobSwarm` state:** `state` is `STAND 0`, `MOVE 1`, `JUMP 2` (airborne: hop, drop or fall), `HIT 3`, `DIE 4`,
  `FREE 5`. `active[i]` is 1 for live mobs (not DIE/FREE): the `SpatialHash.rebuild` and targeting mask. `alpha` is the
  regen fade-in 0..1. `state_t` counts seconds in the state; `anim_t` restarts when the shown stance changes.
  `facing` is -1 left (the WZ default orientation of mob sprites) or 1 right; the player starts facing 1.
- **`NavGraph`:** `edge(e)` also has `lo`/`hi` (takeoff range) and `vx`. A drop lands on its `to_p` at every mob speed
  (`NavGraph.drop_landing` replays MobSwarm's step-off; this holds when MapBounds contains the foothold box and
  `step` runs at the graph's `dt`, 1/60). Jump arcs are checked against walls and ceilings when the graph is built.
  A wall standing inside a platform (not at its ends) is not modelled: mobs stop at it, the graph routes past it;
  SpawnDirector never spawns (or relocates a mob) where such a wall stands anywhere on the point's way to the player
  (`FootholdMap.walk_blocked` on each platform of the way, following `best_edge` onto the player's platform, where the
  last stretch ends at the player's x; on 100010000 the hill's faces cross the ground chain, so a mob dropping onto the
  ground outside the faces would walk into one while the player is between them). A mob stopped at such a wall (it
  has not moved `stall_progress` px) keeps counting toward `stall_time` even on screen and is relocated as soon as it
  is off screen; the player walking up to it shortens its way but is not its progress. Mobs steer by the travel-cost field, not by `route()`: `prepare_target(to_p, tx, also_p)` prices
  every edge from its `take` x to the point (to_p, tx) (walks in px + `edge_cost` per drop/hop, the final walk to tx
  included; a straight-up hop's `take` is the point of its range nearest to where the route goes on, and the mob takes
  off there); it is rebuilt when to_p/also_p change or tx moves `target_step` px. MobSwarm keeps a chosen edge until
  another is `route_hysteresis` px cheaper and writes the remaining cost to `route_len`; `also_p` is the floor right
  below a player on a low step (`MobSwarm.low_platform`, `reach_y`), where walkers count as arrived.
- **`PlayerMotion`:** `place(pos, fhm)` stands the player on a floor only when one is within 1 px below `pos`, else the
  player falls; to start standing at a spawn portal, place at `fhm.y_at(fhm.find_below(x, y), x)`. `step()` returns
  `EV_JUMP 1`, `EV_LAND 2`, `EV_DOWN_JUMP 4`, `EV_GRAB 8`, `EV_LADDER_EXIT 16`, `EV_WALK_OFF 32`, `EV_WALL 64`,
  `EV_FELL_OUT 128` (fell below the bounds; put back on the nearest floor).

### 4.4.6 Run details (`ProjectileSystem` ... `RunWorld`)

What the tables above leave open; the class doc comments have the rest.

- **Ids:** `Loadout.add_skill/rank/stats` take the survivor skill key (`"three_snails"`); `SkillBook.skill_id(key)` gives
  the canonical id. Canonical numbers are read per level from `setup.skill_imgs[book].skill[<7-digit id>].level`.
- **`RunWorld` extras:** `drain_events()` (returns and clears `events`), `emit(type, fields)`, `state_name()`,
  `pending_jobs` / `pending_cards` (the open window), `spawn_mob(kind, pos, fh, hp_mult, elite)`,
  `relocate_mob(i, pos, fh) -> int` (SpawnDirector relocation: frees the slot and spawns the same kind at pos with the
  mob's HP, max HP and elite flag, fading in, and emits `mob_spawned` with `relocated_from` = i; returns the new slot,
  which is usually the same one), `player_platform()`, `player_low_platform()` (the floor right below a player on a low step), `mob_elite` (per
  slot, for name tags), `kills`, `damage_dealt`, `view`, `warnings`, `god` (tests/benchmarks only). `player_state` also
  has `exp_next`. The calls of 4.4.2 return `bool` (false and no change when not on offer). A relocated mob's
  `mob_spawned` carries the usual fields; the presentation treats it like a new mob (its slot may be the one it had);
  tools that follow a mob across relocations (`balance_run.gd`'s stale share) use `relocated_from`.
- **Event details:** `player_hit.damage` is the whole hit (the number shown), `mp_absorbed` the part Magic Guard paid
  with MP. `choice_pending` card `rank` is the rank the card gives when taken (1 = new); `max_rank` 0 = unlimited;
  `skill_name` is the card's skill's name ("" without a skill), `skill_level` its canonical level now (0 = not owned)
  and `skill_level_next` its canonical level once the card is taken (0 unless the card learns or ranks the skill; the
  level-up window shows "Skill Lv. 2 → 3" for a skill_rank card, whose own rank is not the skill's level).
  The run's starting skill emits `skill_learned` before the first `step()`.
- **`ProjectileSystem`:** `rng` (combat stream), `paths` (= `RunWorld.visual_paths`), `bounds`; `step()` fills
  `kills` (mob slots killed this tick) and RunWorld turns them into `mob_died` + an EXP drop, like instant hits.
- **`PickupSystem`:** `step()` returns the EXP collected this tick; past `max_active` drops `spawn()` merges into the
  nearest drop and sets `merged` (no `pickup_spawned` then). With `lifetime` > 0 an uncollected drop expires silently
  (no event; `expired`, `expired_exp`) after fading out; renderers read `alpha(i)`.
- **`UpgradePool`:** `state` is the `RunWorld`; `apply()` also emits `upgrade_applied` (+ `skill_learned`). Card
  `effects` op `add` sums, `mul` compounds per rank, `heal` restores a fraction of max HP/MP.
- **Job window:** opens at a queued level whenever an option is available, and once at exactly the tier's first
  advancement level even when none is (Magician at 30 sees 210/220/230 as unavailable once).

### 4.5 Presentation (`game/scripts/render`, `ui`, `audio`, `run`)

| Piece | Approach |
|---|---|
| `MapRenderer` | Backgrounds (types 0-7, parallax `x + cam_cx*rx/100`, tiling by `cx/cy`, auto-scroll `rx*5 px/s`, `a`, `f`, front backs) redrawn per frame; static tiles/objs per layer recorded once in a `_draw()` command list; animated objs as canvas items. Draw order: non-front backs -> layers 0..7 (objs by `z`, then tiles by canvas `z`, then actors standing on that layer) -> front backs. |
| `AvatarRenderer` | Composites body/arm/head/face/hair/coat/pants/shoes(/weapon) per frame using `map` anchors (navel, neck, hand, brow) and `Base.wz/zmap.img` order. Mirrors for facing. |
| `MobRenderer` | One RenderingServer canvas item per live mob slot (no Nodes), region-of-atlas per frame, alpha for `a0/a1` fades. One renderer per foothold layer (`only_layer` + `update_slot_layers`) to draw mobs inside `actor_layer(L)`. |
| `NameTags` | Elite name tags under mobs (`RunWorld.mob_elite`), drawn like v83's code-drawn default name tag. |
| `FxRenderer` | Pooled one-shot WZ animations (skill hit, level-up, job change) and projectiles. |
| `DamageNumbers` | `Effect.wz/BasicEff.img` digit sets: first digit large set, rest small; 400 ms hold then 600 ms fade + 30 px rise (tier B). |
| `Hud` | `UI.wz/StatusBar.img` bar (800x71), gauges, `Basic.img/LevelNo` digits, timer, kill count, "+N EXP" system messages (`show_exp`). |
| Windows | Level-up choice (`LevelUpWindow`), job advancement (`JobAdvanceWindow`), pause (`PauseMenu`): `MapleWindow` Controls built from `UI.wz` art, skill icons from `Skill.wz`, text from `String.wz`; `RunScene` hosts them in a CanvasLayer (layer 10) and holds its tick loop while one is open. Title, stage select, results and import are scenes under `scenes/ui/`. |
| `Camera` | Follows the player with smoothing (tier C), clamped to `MapBounds`, positions rounded to whole pixels. |

Logical resolution 800x600 (v83's native size and the width of `StatusBar.img/base/backgrnd`), `stretch/mode=viewport`,
`aspect=expand`, `scale_mode=integer`, nearest filtering: on wider windows the player sees more of the map at the same
pixel size, never a stretched sprite (1920x1080: 1066x600 at 1x with black bars). The logical view size therefore
varies; read it live (`get_viewport().get_visible_rect().size`), never assume 800x600. `Settings` adjusts two cases:
a window smaller than 800x600 on either axis is scaled down (fractional) instead of cropped, and the opt-in
`[display] fill_window` grows the view to window / s at the same integer scale s instead of showing bars
(`GameSettings.fit_size`: 3440x1440 -> 1720x720 at 2x, 1920x1080 -> 1920x1080 at 1x; much more map on screen, so it is
off by default).

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
  frame times in a window (`summary.json`: percentiles overall, per run minute and for frames with 100+/200+ mobs;
  `--warp=<s>` fast-forwards the sim to the late game first). Results go in `docs/IMPLEMENTATION_PLAN.md`
  "Performance log".
- If GDScript becomes the bottleneck past ~1000 mobs, the mob/projectile inner loops move to a Rust GDExtension
  behind the same `MobSwarm`/`ProjectileSystem` API.

## 7. Offline guarantees

- No networking API is used by the game or the importer; enforced by `tests/unit/test_offline.gd` (scan of every
  script, scene, resource, config and `project.godot` under `game/` for network classes, nodes and settings) and the
  importer's `no_network_deps` (Cargo.lock scan) and `no_network_src` (`std::net`/socket types in its sources) tests.
- The importer is a local process reading local files; the game launches it with `OS.execute_with_pipe`/`OS.create_process`.
- Settings and saves are local files under the user data folder.
- Verified by process-level socket snapshots during a 15:00 playtest and of the exported build (0 TCP connections,
  0 UDP endpoints, no child process other than the local importer; `docs/IMPLEMENTATION_PLAN.md` acceptance checks).
  A run with the network adapter disabled has not been done.

## 8. Licensing and assets

- Our code: original. Godot (MIT) notices ship with exports: `scripts/export.sh` writes `GODOT_LICENSES.txt` (the
  engine's licence, its bundled components and their licence texts, from the engine itself), `WZIMPORT_LICENSES.txt`
  (every crate's licence files) and copies `THIRD_PARTY_NOTICES.md` next to the exe. Rust crates are permissive
  (MIT/Apache/Zlib); the list is in `THIRD_PARTY_NOTICES.md`.
- Cosmic (AGPL-3.0) and the AGPL/GPL/MPL clients: facts and prose descriptions only, never code. Where a constant comes
  from them it is labelled with its tier and source in `docs/GAME_DESIGN.md`.
- Nexon's assets: the player supplies their own v83 install; the cache lives in their user folder; nothing proprietary
  is committed, bundled or uploaded. Screenshots of the running game are kept in the gitignored `evidence/` folder.

## 9. Known unknowns (tracked in `docs/RESEARCH.md` §6)

The real client's physics integrator and timestep, mob speed-stat conversion, projectile speeds, hit-stun and death
fade timing, climb speed, camera smoothing, and the touch-damage formula are not recoverable from data or clean
sources. Each is implemented as a labelled, data-driven constant so it can be corrected when better evidence appears.
