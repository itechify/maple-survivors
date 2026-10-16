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

Auto-actions share `RunWorld.can_cast()`: it rejects non-PLAYING/dead runs and `PlayerMotion.ST_LADDER` (ropes and
ladders). `SkillRunner.step()` counts cooldowns before checking this gate; active effects and passives remain
independent of new casting. A ready skill can cast on the tick movement leaves the climbing state.
Manual Esc pause leaves the sim state unchanged; RunScene stops its tick loop and freezes presentation. An open
in-run window (Stat, Skill, Menu popup) holds the run the same way.

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
| `FootholdMap` | Foothold geometry and queries | `static from_wz(map_img)`, `static from_segments(list)`, `count()`, `is_wall(i)`, `is_floor(i)`, `y_at(i, x)`, `find_below(x, y, ignore := -1) -> int`, `teleport_destination(origin, direction, distance, bounds) -> Dictionary` (`{pos, fh}` or `{}`), `next_of(i)`, `prev_of(i)`, `bounds() -> Rect2`, `platform_of(i)`, `platform_count()`, `platform_span(p) -> Vector2` (min x, max x), `walk_blocked(p, xa, xb) -> bool` (a wall stands across p between the two), packed arrays `x1 y1 x2 y2 layer group prev next`, flags `cant_through forbid_fall_down` |
| `MapBounds` | Camera/world limits | `static from_map(map_img, fhm) -> Rect2`: `info/VR*` if present, else `miniMap` rect, else foothold bbox (top -300, bottom +100) |
| `LadderSet` | Ladders and ropes | `static from_wz(map_img)`, `static from_list(list)`, `find_grab(x, y, reach) -> int`, arrays `x y1 y2 is_ladder uf page` |
| `PortalSet` | Same-map portal links and activation | `static from_wz(map_img, map_id, tuning)`, `step(dt, feet, up) -> Dictionary` (warp or `{}`), `static start_point(map_img, fhm, bounds, rng)` (a random `sp` portal dropped to the floor, else the widest platform's middle); `links` rows `{name, target, pos, target_pos}` use canonical portal points |
| `MoveInput` | One tick of player intent | `left right up down jump_pressed jump_held drink_hp drink_mp teleport_pressed teleport_held` (drink/teleport_pressed flags are presses; teleport_held requests delayed repeats) |
| `PlayerMotion` | Player movement per Physics.img | `_init(constants)`, `place(pos, fhm)`, `teleport_destination(direction, distance, fhm, bounds) -> Dictionary`, `step(dt, input, fhm, ladders, bounds) -> int` (event flags), `knockback(dir)`, fields `pos vel fh ladder facing state speed_stat jump_stat`, `stance() -> String` |
| `NavGraph` | Platform graph for mob pathing | `static build(fhm, opts)`, `route(from_p, to_p) -> int` (edge index, fewest edges), `edge(e) -> Dictionary` (`kind` drop/jump, `from_p`, `to_p`, `x_from`, `x_to`), `reachable(a, b)`; travel-cost field toward a point: `prepare_target(to_p, tx, also_p := -1)`, then `route_cost(p, x) -> float` (px, INF = no way), `best_edge(p, x) -> int`, arrays `cost`, `take` (per edge) |
| `MobKind` | One mob type: canonical WZ stats + survivor overrides + animation timing needed by the sim | `static from_wz(mob_img, id, overrides)`, fields `id name level max_hp exp pad pdd mad mdd speed_stat fly_speed_stat move_speed can_jump flies hitbox die_time hit_time pushed body_attack boss elem_attr` |
| `MobSwarm` | All mobs, struct-of-arrays with free list | `_init(capacity, kinds, tuning)`, `spawn(kind, x, y, fh, hp) -> int`, `despawn(i)`, `step(dt, ctx)`, `apply_hit(i, dmg, dir) -> bool`, `alive_count()`, accessors `pos(i)`, `is_live(i)`, `is_settled(i)` (live and fully faded in), `mob_kind(i)`, `live_in_rect(area)` (ascending slots), `static low_platform(fhm, target, tp, reach_y)`, packed arrays `kind x y vx vy hp max_hp state state_t fh platform facing anim_t route_len steady` |
| `SpatialHash` | Broad phase for mobs | `_init(cell)`, `rebuild(xs, ys, active)`, `query_rect(r, out) -> int`, `query_radius(c, r, out) -> int` |
| `ProjectileSystem` | Shots in flight (pooled SoA) | `spawn(spec) -> int`, `step(dt, swarm, hash, events, live_mdd := PackedFloat32Array(), physical_allowed := PackedByteArray())`, per-shot pierce and already-hit list; optional live defense/immunity arrays are indexed by target slot at impact |
| `PickupSystem` | EXP and potion drops (pooled SoA) | `spawn(pos, exp, item_id, player_pos := Vector2.ZERO)`, `spawn_potion(pos, count, item_id, potion_kind)`, `step(dt, player_pos, magnet_r, fhm, events)`, `active_count()`, `exp_count()` |
| `PotionInventory` | Unlimited HP/MP stock and canonical restore specs | `_init(tuning, item_info)`, `snapshot()`, `add(kind, count := 1)`, `consume(kind) -> Dictionary`; `collected`, `used` counters per kind |
| `CombatMath` | Damage formulas (static) | `magic_damage_range(...)`, `monster_hit(attack, magic, element, defense, rng, multiplier)`, `monster_damage(...)`, `miss_chance(avoid, accuracy)`, `roll_miss(...)`, `apply_defense(...)`, `roll_crit(...)` |
| `SkillBook` / `Loadout` | Survivor skill definitions + owned skills, ranks and modifiers | `Loadout.add_skill(id)`, `rank(id)`, `stats(id) -> Dictionary` (resolved damage, `mp_cost` from canonical `mpCon` or survivor override, cooldown, count, pierce, speed, range, size...) |
| `MobSkillRunner` | Scheduled canonical mob skills, delayed heals, summons, timed per-slot defense/immunity and player slow | `step(world)`, `defense_bonus(slot, magic, time)`, `slow_state(time)`, `immunity_state(slot, time)`, `summoned_alive(world, encounter)`, `resize`, `reset_slot`, `move_slot`; reads setup MobSkill/skill-list nodes and shares BossDirector action timing; named MobSkill ids `SKILL_PDD_UP_AREA` 112, `SKILL_MDD_UP_AREA` 113, `SKILL_HEAL_AREA` 114, `SKILL_SLOW` 126, `SKILL_WEAPON_IMMUNITY` 140, `SKILL_SUMMON` 200 (`SUPPORTED`); reads the world only through `RunWorld`/`MobSwarm` accessors (`swarm.pos`, `is_settled`, `live_in_rect`, `mob_kind`, `world.summoned_alive`, `spawn_offspring`, `refresh_player_speed`) |
| `BasicAttack` | Automatic physical weapon swing | `step(dt, world)` starts after skill priority, resolves the canonical facing afterimage box and body-frame impact, and hits one nearest living slot; a separate seeded stream chooses five stances; weapon facts come from `WeaponInfo` |
| `WeaponInfo` | Weapon-type facts (static, pure) read by `CombatMath`, `BasicAttack` and `DataRepo` | `type_of(id)` (id / 10000; `TYPE_ONE_HANDED_SWORD` 130), `swing_k(id, action)` (tier B k), `afterimage_name(info)` (canonical `info/afterImage`), `afterimage_img_path`, `afterimage_frame_path`, `hit_spark_path` (tier C spark family), `attack_interval(info)` (tier B, from `attackSpeed`), `sound_path(info)` (`info/sfx`) |
| `SkillRunner` | Auto-casting | `step(dt, world)` ticks cooldowns, checks `RunWorld.can_cast()`, then casts one affordable ready skill, oldest-ready first; `tick_cooldowns` and `cast_ready` are separate entry points; `fired_this_tick` reports any cast and `waiting_mp` feeds the persistent HUD cue |
| `PlayerBuffs` | Timed player effects, periodic healing and detached HUD snapshots | `has(skill)`, `start(skill, stats)`, `step(dt, events) -> int` (HP healing due), `effect_total(stat)`, `snapshot()` |
| `PlayerUpkeep` | The player's per-tick timers, owned as `RunWorld.upkeep`: buffs (steps `PlayerBuffs`), hit invincibility, the cast-stance hold and the `balance.regen` pulse clock; the world owns the pools and applies what it reports | `tick(dt, events) -> float` (buff healing due), `regen_pulses(dt) -> int`, `pulse_hp()`, `pulse_mp()`, `improved_mp_bonus(level, skill_level)`, `start_action`, fields `invincible_t cast_action cast_left action_airborne`, `DEFAULT_REGEN` |
| `ExpCurve`, `RunProgression` | Survivor EXP curve, level, job, pending level-ups | `exp_to_next(level)`, `add_exp(n) -> int` levels gained |
| `JobTree` | Data-driven job advancement (canonical ids) | `advancements(job_id, level) -> Array`, `job(id) -> Dictionary` |
| `UpgradePool` | Data-driven upgrade eligibility, normal and advancement draws | `eligible(state) -> Array`, `roll_choices(state, rng, n) -> Array`, `roll_advancement_choices(state, rng, n) -> Array`, `apply(id, state)` |
| `SpawnDirector` | Stage pacing, spawn positions, relocation | `step(dt, world)`, `pick_spawn(world, k, side := 0) -> Vector3` (x, y, foothold: -1 for flyer air points, -2 when no point is found), `screen_rect(world) -> Rect2` (what spawns stay out of: the view + `margin`, + `trail_margin` behind a moving player); ground spawns prefer short reachable routes; flyers sample off-screen air within map bounds; moves off-screen mobs that stall, are far or cannot reach the player to a point ahead of the player (`relocated`) |
| `StageRoster` | Which mob ids a stage needs | `static named_ids(stage)` (keyframe pools + boss ids), `static boss_extra_ids(boss_img, mob_skill_img)` (MobSkill 200 summons at each level the boss lists in `info/skill`, plus `info/revive`), `static mob_ids(stage, mob_imgs, mob_skill_img)` (both, ascending), `static list_ids(node)` (a WZ list node's ids in key order: summon levels, revive lists); used by `RunWorld` (mob kinds) and `DataRepo.build_setup` (two passes: named imgs, then derived ids) |
| `BossDirector` | Scheduled warnings, arrivals, pursuit teleports, shared action timing, deaths and completion | `step(world, dt := 0)`, `live_count()`, `all_dead()`, `normal_spawn_multiplier()`, `damage_multiplier(index)`, `can_act`, `begin_action`, `prepare_actions`, `action_snapshot`; public `entries` and lifecycle `records`, owned as `RunWorld.bosses` |
| `BossAttacks` | Selected canonical type-0 area and type-2 ball windups, effect timing and delayed impact | `step(world)`, `area_at(range_data, pos, facing)`; owned as `RunWorld.boss_attacks`, shares `BossDirector` action gate |
| `MobProjectileSystem` | Monster type-2 balls as pooled packed arrays, separate from player shots | `spawn(spec)`, `step(dt, world)`, `active_count()`; captured source/damage metadata, swept player collision through take_hit; same ProjectileRenderer drawing interface |
| `RunWorld` | Owns a run | `_init(setup)`, `step(dt, input)`, `events`, `time`, `kills`, `state` (PLAYING / CHOOSING_JOB / CHOOSING_UPGRADE / DEAD / CLEARED); TIMEOUT is a harness outcome while the sim remains PLAYING |
| `BotInput` | The autoplay bot (RunScene `autoplay`/`autopick`, the full-run tests, `scripts/balance.sh`, the benchmarks): kites, collects drops, climbs or uses same-map portals, picks jobs and cards | `decide(world, memo) -> MoveInput`, `auto_choose(world, first_card := false)`, `pick_card_for(world, cards)`, `pick_job(options)` |

Player projectile hit exclusion uses `MobSwarm.identity`, a packed 64-bit logical identity independent of the
reusable slot index and canonical mob-kind ID. Each fresh `MobSwarm.spawn` receives the next run-local identity;
pool growth preserves existing identities. `RunWorld.relocate_mob` retains the original logical identity while
moving its state. ProjectileSystem's packed 64-bit already-hit list remembers these identities, so a relocated
mob cannot be hit twice by the same shot, while an unrelated fresh mob reusing its slot remains hittable.
Events, spatial hashes, kill lists and other per-slot state still use slot indices; event schemas do not change.
This is engine bookkeeping (tier C), with no per-entity allocations and no balance/stat changes.

### 4.4.1 Run setup (what `RunWorld` is built from)

The sim never reads files. `RunScene` (presentation) builds a setup Dictionary from the asset cache and `res://data`:

```gdscript
var setup := {
	"map_img": Dictionary,            # Map.wz/Map/Map1/104040000.img root (cache JSON)
	"physics_img": Dictionary,        # Map.wz/Physics.img root
	"mob_imgs": {100100: Dictionary}, # Mob.wz/<id>.img roots, info/link already followed by the loader: every id of
	                                  # StageRoster.mob_ids (pools, bosses, and the bosses' canonical summon/revive ids)
	"skill_imgs": {"000": Dictionary, "200": Dictionary, "210": Dictionary},  # Skill.wz/<book>.img roots
	"equipment_info": {1040002: Dictionary, 1060002: Dictionary, 1072001: Dictionary,
		1302000: Dictionary, 1372005: Dictionary}, # canonical info of balance.player.equipment + every weapon_by_job
		                                       # weapon (DataRepo.starter_equipment_ids), keyed by original item id
	"body_img": Dictionary,           # Character.wz/00002000.img, exact stance frame delays
	"afterimage_imgs": {"swordOL": Dictionary, "mace": Dictionary}, # Character.wz/Afterimage roots the worn weapons'
	                                  # canonical info/afterImage names (WeaponInfo.afterimage_name)
	"mob_skill_img": Dictionary,      # Skill.wz/MobSkill.img root, including each skill's level tables
	"item_info": {2000000: Dictionary, 2000003: Dictionary}, # canonical Consume item nodes (info icons + spec) of
	                                  # DataRepo.potion_item_ids: balance.potions starters + the potion_tier ladders
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
`job_advance_pending`; otherwise (or after the job choice) it enters `CHOOSING_UPGRADE` and emits `choice_pending`
for every queued level. Accepted jobs add an advancement draw (`advancement: true`) before that normal draw; it preserves the queued level, includes every eligible new power skill of the exact job, and fills remaining places up to three with other new job skills. Normal draws return up to three distinct eligible current-job or job-neutral cards; if fewer
than three are available, they include one Power Elixir fallback alternative. An exhausted pool therefore
still opens a one-card window rather than consuming the level silently. The fallback is separate from the
weighted `upgrades.cards` pool in `upgrades.fallback`.
The presentation layer shows the windows and calls back:

| Call | Effect |
|---|---|
| `apply_job(job_id)` | advance (emits `job_changed`), open an extra advancement draw, then the normal upgrade choice for that level |
| `decline_job()` | stay, then continue to the upgrade choice |
| `apply_choice(card_id)` | apply the card (emits `upgrade_applied`), then the next queued level, else back to `PLAYING` |

Level-up effects and their short pause before the window are presentation-only. Boss bonus picks use
`CHOOSING_UPGRADE` with `RunWorld.choice_bonus` and `pending_bonus_choices`; they take priority over the level queue.
`apply_choice` consumes a bonus without changing the level or queue. Exhausted bonus draws offer Power Elixir
and still require a choice before clear.
The bonus window uses a "Boss Reward" title and omits the gained-level notice.

### 4.4.3 Event schema

`RunWorld.events` is an `Array` of Dictionaries appended during `step()` (and during the calls above) and cleared by
the presentation after it drains them. `mob`, `proj`, `pickup` are **sim slot indices** (valid only for the frame);
`mob_id`, `skill_id`, `item_id`, `job_id` are **original MapleStory ids**; `skill` is the survivor skill key from
`skills.json`; visual fields are **WZ paths** into the asset cache.

| type | fields |
|---|---|
| `cast` | `skill`, `skill_id`, `level`, `pos`, `facing`, `action` (body stance to play when standing, e.g. `"swingO1"`), `effect` (WZ path of the caster effect or `""`) |
| `boss_skill` | `mob`, `mob_id`, `skill_id`, `level` (ints), `pos` (boss feet Vector2), `facing` (int), `action`, `effect`, `player_effect`, `summon_effect`, `recipient_effect` (Strings; WZ paths or empty), `duration` (float seconds), `targets` (Array of int mob slots receiving buffs or summoned; empty for delayed heal); emitted at cast/stance/effect initiation, with delayed healing later reported as `mob_healed` |
| `basic_attack` | `phase` (String: `start` / `impact`), `weapon_id` (int), `action`, `facing` (int), `pos` (Vector2 feet), `afterimage`, `sound` (WZ paths), `hit_after`, `interval` (float seconds); start plays stance/sound, impact plays afterimage; a landed hit also emits `mob_hit` with `skill = "basic_attack"` |
| `mp_short` | `skill`, `skill_id`, `required_mp` (int), `mp` (available whole MP, int); once per eligible ready skill's waiting episode, including targetless buffs |
| `player_restored` | `stat` (`hp`/`mp`), `amount` (actual positive integer pool gain after capping), `skill` (key or empty), `pos` (player feet); emitted by `restore_player`, independent of legacy Recovery/potions |
| `buff_cast` | `skill`, `skill_id`, `level`, `duration` (float canonical seconds); also emits ordinary `cast` for stance, effect and sound |
| `buff_expired` | `skill`, `skill_id`; once when an active timer expires; a run ending first need not emit expiry |
| `buff_pulse` | `skill`, `skill_id`, `amount` (canonical integer healing due; the HP gain is clamped to max). Recovery's final pulse precedes its expiry; Guard/Armor have no pulses. |
| `mob_spawned` | `mob`, `mob_id`, `pos`, `elite`, `relocated_from` (the slot the mob had when SpawnDirector relocated it, -1 for a new spawn) |
| `mob_hit` | `mob`, `mob_id`, `damage` (int), `crit`, `pos` (where to draw the number: mob head), `hit_visual` (WZ path or `""`), `skill` |
| `mob_status_applied` | `mob`, `mob_id`, `status` (`slow`, `poison`, `freeze`), `duration` (float canonical seconds); reapplication emits again and refreshes |
| `mob_status_expired` | `mob`, `mob_id`, `status`; natural timer expiry only; death/release/relocation clears silently |
| `mob_died` | `mob`, `mob_id`, `pos`, `exp`, `elite` |
| `player_hit` | `damage` (int), `mp_absorbed` (int), `miss` (bool), `dir` (-1/1), `pos`, `mob` (source slot, -1 when unspecified), `mob_id` (source id, 0 when unspecified), `boss` (bool), `max_hp` (HP pool at hit time), `source_kind` (String: `touch`, `attack`, `projectile`, or `other` for a direct unspecified source). Whole damage/max_hp supports encounter metrics. A miss spends no HP/MP and gives no knockback/invincibility. |
| `player_jump` | `pos` |
| `portal_used` | `portal` (source `pn`, String), `target` (destination `pn`, String), `pos` (arrival feet, Vector2) |
| `player_died` | `pos` |
| `pickup_spawned` | `pickup`, `item_id`, `pos`, `kind` (exp/potion), `potion_kind` (hp/mp or empty), `count` (potion bundle; 0 for EXP) |
| `pickup_collected` | `pickup`, `item_id`, `exp`, `pos`, `kind`, `potion_kind`, `count` |
| `potion_used` | `kind` (hp/mp), `item_id`, `restored` (actual integer gain after clamping), `count` (remaining stock) |
| `potion_tier_up` | `kind` (hp/mp), `from_item_id`, `item_id` (new current item), `count` (stock preserved) |
| `level_up` | `level` |
| `job_advance_pending` | `options`: `[{job_id, name, available, reason}]` |
| `job_changed` | `job_id`, `name` |
| `choice_pending` | `bonus` (bool), `advancement` (bool; extra new-job draw, preserving the queued level), `cards`: `[{id, kind, name, desc, icon, tier, magnitude, rank_before, rank, max_rank, skill, skill_name, skill_level, skill_level_next, skill_level_max, skill_changes, skill_effect_stat, skill_mod_changes}]`; `skill_mod_changes` (skill_mod cards on an owned skill, `{}` otherwise) maps the effective values the card's steps change (`shots`/`targets`/`pierce`/`speed`/`range` whole numbers, `cooldown` seconds to two decimals, `area`/`damage`/`crit` percent) to `{before, after}`; the level-up window shows them and dresses skill cards with SkillText (GAME_DESIGN 8.2); `skill_level_max` is the skill's canonical level cap (0 without a skill; the window marks a learn at the cap MAX); `tier` is lowercase `normal/rare/epic/unique/legendary` after the headroom clamp; `magnitude` is granted ranks, modifier steps or starting skill rank. `rank_before/rank` are consumed card steps before/after (learn/potion cards consume one). `skill_effect_stat` is the skill's skills.json `buff.stat` (`hp` Recovery, `mp_guard` Magic Guard, `pdd` Armor, `speed` Nimble Feet, `""` otherwise; the level-up window labels `x` from it); `skill_changes` maps canonical fields (`mad`, `mastery`, `mpCon`, `fixdamage`, `time`, `x`, `pdd`, `cooltime`, `speed`) to `{before: int, after: int}` for rank cards, `{}` otherwise; mastery is the displayed percent. Improved MaxMP Increase instead exposes `max_mp_percent`, the survivor per-level percentage, never canonical MP growth |
| `upgrade_applied` | `id`, `rank`, `tier` (displayed Potential tier), `magnitude` (actual ranks/steps/starting rank) |
| `skill_learned` | `skill`, `skill_id` |
| `burst` | `count` (a spawn burst started) |
| `stage_cleared` | `time` |
| `boss_warning` | `boss_index` (schedule index), `mob_id`, `time` (warning tick) |
| `boss_spawned` | `boss_index`, `mob` (slot), `mob_id`, `pos`, `time` (arrival tick); also emits the ordinary `mob_spawned` event for rendering |
| `boss_died` | `boss_index`, `mob`, `mob_id`, `pos`, `time` (death tick); precedes the final clear decision |
| `boss_attack` | `boss_index`, `mob`, `mob_id`, `attack` (canonical stance, e.g. attack1), `phase` (`start` / `effect` / `impact`), `pos` (captured feet), `facing`, `area` (Rect2, captured world-space range), `time` (event tick), `impact_time` (absolute planned sim time), `effect`, `sound` (WZ paths, effect may be empty). Start holds the stance and plays sound; effect phase starts art; impact tests the current player position/grounded state. |
| `mob_projectile_spawned` | `proj`, `mob`, `mob_id`, `pos` (muzzle), `velocity` (Vector2 px/s), `range`, `speed` (float), `ball`, `hit` (WZ paths), `time` |
| `mob_projectile_hit` | `proj`, `mob`, `mob_id`, `pos` (swept contact), `hit` (WZ path), `facing`, `time`; emitted on first body contact even when invincibility/MISS prevents damage |
| `mob_healed` | `mob`, `mob_id`, `skill_id`, `level`, `amount` (actual restored HP after max clamp, int), `pos` (feet), `time` (resolution tick) |
| `mob_revives_spawned` | `boss_index`, `mob`, `mob_id` (dead source IDs), `pos` (source feet), `revives` (ordered Array of `{mob: int, mob_id: int}` living offspring), `time` (death tick); one event per canonical death list |
| `teleport` | `skill`, `skill_id`, `level`, `phase` (`departure`/`arrival`), `pos`, `facing`, `effect`; fixed world positions for the manual player blink |
| `boss_teleported` | `boss_index`, `mob` (current slot), `mob_id`, `pos` (arrival), `time`; also emits `mob_spawned` with relocation identity |


`RunWorld.bosses.records` has one row per stage boss: `{boss_index, mob_id, slot, warned, arrival, spawn_time,
death_time, dead, skipped, teleports}`. Times are -1 before arrival/death. `arrival` starts at the schedule
time; when no arrival point exists on the arrival tick it moves to now + `warning_time` and a fresh `boss_warning`
fires at once, so an arrival always follows its last warning by the warning lead. A boss whose mob img is
missing is never announced and is `skipped` at its arrival time (a `RunWorld.warnings` line; the harness reports
status `skipped`); `all_dead()` counts it as done, so it cannot block the clear. Pursuit bookkeeping also holds `stall`, `best_distance`,
`anchor`, `fading`, `fade_left`; action bookkeeping captures the spawned mob's logical `identity` for reuse checks.
`RunWorld.mob_boss[slot]` is the schedule index or -1 for an ordinary mob.
Bosses use `SpawnDirector.pick_player_platform` at the configured near-player distance, keep the regen fade,
and are exempt from ordinary recycling. Relocation preserves the schedule index and updates the record's slot.
Every scheduled boss slot sets `MobSwarm.steady` (kept through relocation, cleared by a fresh spawn), which blocks
stun/push whatever the kind's flags; canonical `MobKind.boss` and the survivor `no_flinch` override still block it for
any mob of that kind. `RunWorld.can_clear()` waits for every scheduled boss death, with the
duration rule retained for stages without bosses. Boss clears defer until all bonus and queued level choices finish.



Boss attacks and skills share `BossDirector.can_act(index, now)` and
`begin_action(index, action, seconds, facing, now)`. `prepare_actions(world)` advances its clock before swarm
movement; `action_snapshot(swarm)` returns per-slot `actions: PackedStringArray`, `times: PackedFloat32Array` and
`facings: PackedInt32Array`. This is a borrowed read-only view: subsequent refreshes update the same Dictionary and
packed buffers, resizing only when swarm capacity changes. Consumers needing history must duplicate it. Refreshes
clear the previous occupied boss slots before writing current overrides, and match the boss's logical mob identity
so a newly spawned entity in a reused slot cannot inherit a stance. A nonempty stance holds grounded movement
and facing (tier C); `MobRenderer` draws
that canonical stance once at its elapsed sim time, including its original frame origins. Expiry or death clears
the override. No per-boss Nodes or presentation clocks drive the action.
An intentional action hold resets the pursuit-stall clock; a fading boss cannot start another action.

`MobSkillRunner` selects optional `boss_skill.recipient_effect` from canonical `mob0` only when that node exists.
RunScene plays it on non-caster targets, with `summon_effect` retaining priority for summon arrivals. An absent
recipient burst leaves the caster effect and buff recipients unchanged: Dyle 112/L4 has no `mob0`, while 113/L2
does. The separate `mob` status icon is not a burst substitute. Nonempty paths still use normal asset lookup and
report missing required art; presentation never suppresses those warnings.

`stage.bosses[].attacks` selects canonical attack stances. `BossAttacks` handles `info/type = 0`, capturing area and
facing at windup, starting art at `effectAfter`, and resolving damage at `attackAfter` (milliseconds converted to
seconds). It reads attack-local PADamage/MADamage rather than contact attack and calls `take_hit` with
`source_kind = attack`. `attack_dmg_mult` is separate from contact `dmg_mult`; `attack_interval` is a survivor
start-to-start cadence because these attack nodes contain no interval. A canonical `jumpAttack` flag opts into
the tier-C airborne-at-impact dodge. Dead bosses cancel pending impacts. Attack frames/metadata remain as cached.

For type 2, `range/r` is the acquisition radius and travel range; `range/sp` is the mirrored muzzle offset.
At attackAfter, a ball aims at the player's current body centre and travels straight (tier C). The adopted unit
conversion is `bulletSpeed × 1000/600` px/s, equivalent to `r × 600/bulletSpeed` ms flight; this interpretation
is tier C, inspired by a later-client reference, not verified v83 client RE. WZ fields remain unchanged.
Balls store source attack/accuracy/multiplier independently of the live mob, expire at range, and use swept
segment-vs-player-body contact with a survivor collision radius. RunScene's separate `mob_shots` renderer uses
the existing batched ProjectileRenderer and `RunWorld.visual_paths`. No per-projectile Nodes are introduced.
MobSkill114 queues restoration at the caster's canonical effectAfter after the existing interval/HP/stance gate.
At resolution, every living mob in the canonical area regains the canonical x, clamped to its maximum (tier C:
y is unused, no RNG); dead casters cancel the queue.
The original mob0 animation starts at cast with its original blank lead-in; RunScene anchors heal pos0 at feet.
EffectAfter0 heals resolve on the casting tick after `boss_skill`; positive delays retain their queued resolution.
MobSkill140 is a timed self weapon-immunity status in packed per-slot expiry/path arrays. `physical_hit_allowed`
is checked at instant/basic impact and passed as a live mask to ProjectileSystem each tick. Immune physical
contact consumes the shot/pierce hit without a damage roll or `mob_hit`; magic ignores this mask. Launch time
does not decide immunity. Relocation transfers the status; fresh spawn resets it. The original repeat-marked
MobSkill140/level/8/mob icon is a pooled FxRenderer effect at the body top (tier C pos2 mapping), follows the
encounter's current slot, and stops at expiry/death. `RunScene.mob_status_effects()` exposes its draw model.
Scheduled King Slime's canonical info/boss remains absent; survivor `mobs.json.no_flinch` supplies stance immunity.
On scheduled death, the sorted canonical info/revive list spawns once on the source platform before rewards.
Offspring retain canonical stats, own ordinary slots and the dead encounter's summon ownership, and are not
additional scheduled bosses. Skill200's living limit applies to casts, not this unconditional death list.

`BossDirector.step(world, dt)` tracks route progress after movement: no route or no progress for 5 s starts fade-out,
then `relocate_mob` places the living boss about 250 px away on the player's platform, preserving HP and encounter
identity. `MobSwarm.fading_out` suspends movement/regen while the director drives alpha; arrival restarts normal
regen fade-in, harmless until opaque. Placement retries while no player platform point exists.
`balance.bosses` supplies stall/progress/fade/placement tuning. `rewards` defaults may be overridden by each entry:
`exp_mult`, `exp_drops`, `spread`, `potion_spread`, `potions` hp/mp counts, `bonus_choices`. The total is rounded
canonical boss EXP × reward multiplier, split with integer remainders conserved. Scheduled bosses bypass ordinary
EXP and random potion drops; bundles use the current stock item. Reward scattering has its own seeded RNG stream.



The ordinary spawn accumulator and burst count use `BossDirector.normal_spawn_multiplier()`. Elite scheduling
remains separate. A positive stage `post_duration_slope` extrapolates the final keyframe segment past its end,
the burst size past the stage duration (`burst_count_at`) and shortens the elite interval by the extrapolated rate
ratio (`elite_interval_at`); ordinary alive targets still obey `hard_cap`.

Swarm visuals are read from state, not events: `MobSwarm` arrays (`kind` -> `RunWorld.mob_kinds[kind].id`, `state`,
`state_t`, `facing`, `alpha`, `x`, `y`), `ProjectileSystem` arrays (`active`, `x`, `y`, `vx`, `vy`, `visual` ->
`RunWorld.visual_paths[visual]`, `rotate`), `PickupSystem` arrays (`active`, `x`, `y`, `item_id`), and
`RunWorld.player` / `RunWorld.player_state` (`hp`, `mp`, `mp_short` (bool, an eligible ready skill failed affordability), `max_hp`, `max_mp`, `exp`, `level`, `job_id`,
`str`, `dex`, `int`, `luk` (integer attributes), `pdd`, `mdd`, `avoid` (equipment-derived defense and avoidability),
`fortune` (survivor card-tier stat from `balance.player.fortune`, separate from LUK),
`invincible_t`, `action`, `action_t`, `dead`, plus detached `buffs`, `slow` and `potions` snapshots described below).
The snapshot's `pdd`/`mdd` are base equipment/stat defense; active Armor additions are applied by `hit_defense()`.

Player-inflicted monster statuses live in one `MobSwarm` status table: packed `status_left` (seconds left, doubles)
and `status_elapsed` (art clock), indexed `slot * STATUS_COUNT + status` with `SLOW`, `POISON`, `FREEZE`, plus
`slow_factor` and private poison pulse/damage/source arrays. `status_time(slot, status)` reads a timer. The shared entry
point is `apply_status(slot, name, params, events) -> bool` (`name` from `STATUS_NAMES`); `params` contains canonical
`time`, signed Slow `x`, or poison skill `level`, an optional survivor `skill` key and an optional `element` overriding
the status default (`STATUS_ELEMENTS`: Poison `S`, Freeze `I`). Bosses, and kinds whose Mob.wz digit for
the element is 1, 2 or 4 (`MobKind.resists_status`), reject it. `step` receives the current event list in
`ctx.events`, advances status timers after movement and emits poison `mob_hit` events; it visits only a compact
list of statused slots, and no status means no status pass at all. `RunWorld.damage_dealt` is a getter summing shots, instant hits and `swarm.poison_dealt`.
`has_statuses()` lets presentation skip status work. `can_act(slot)` (settled and not frozen) gates monster touch
damage as well as boss attacks/skills. Release, death and relocation clear these player-inflicted
statuses; the existing `MobSkillRunner` monster buffs still transfer on relocation. `MobRenderer` uses pooled cached
Slow/Poison art and status tints; frozen state/animation clocks do not advance, though a frozen airborne monster still
falls and a fading-in one keeps fading in.

`MobKind.elements` parses canonical `elem_attr` once; `element_multiplier(letter)` is case-insensitive and neutral
for absent elements. `undead` exposes the canonical flag. `Loadout.stats().element` comes from Skill.wz `elemAttr`;
shots retain it in a packed string array. Instant and projectile hits share `ProjectileSystem.roll_damage`'s final
element multiplier, including zero immunity before the normal minimum-one clamp.

### 4.4.4 Survivor data files (`game/data/survivor/`)

| File | Contents |
|---|---|
| `skills.json` | survivor behaviour per skill key: canonical `skill_id`, `book`, job, kind (projectile / instant / passive / buff), cooldown, range, speed, count, pierce, rank -> canonical level map, `level_ranks`, buff effect fields and canonical time/cooltime, survivor pulse interval and HP threshold, visuals and sounds |
| `upgrades.json` | upgrade cards (`GAME_DESIGN.md` §8), `power` flags and the `pity` rule |
| `stages.json` | stage key -> map id, duration, pacing keyframes, pools, bursts, elites, per-stage `spawn` overrides, `exp_mult`, stage-card `note`, scheduled `bosses` with time/mob_id/hp_mult/dmg_mult and `post_duration_slope`; summon/revive mob ids are never listed (StageRoster derives them from the boss imgs and MobSkill.img) |
| `balance.json` | EXP curve, player base attributes, automatic AP and job primary-stat rules, worn equipment ids and job weapons, cast origin / `cast_forward`, HP/MP growth and INT MP divisor per job, invincibility, knockback, magnet, drops (incl. `lifetime`), spawning (incl. `band_y`, `prefer_route`, `stall_time`, `trail_margin`), mob speed factor, `mob_motion` flyer bob amplitude/period passed to MobSwarm |
| `mobs.json` | per-mob survivor overrides (EXP drop item id, HP/speed multipliers, `can_jump` override) |
| `jobs.json` | which canonical jobs are playable and their Max MP bonuses; no skill grants, extra advancement draw |

`RunWorld` checks `PortalSet` before movement each PLAYING tick. Holding Up inside a same-map link's activation box
places the player at the destination minus the configured lift, resets velocity/ladder/down-jump state, and emits
`portal_used`; regular movement resumes on the next tick. The global portal cooldown advances only while PLAYING.
`RunScene` snaps the camera on that event without a sound or transition effect. Other-map exits are inert. Monsters
keep using `NavGraph` and never activate portals. `MapRenderer` draws type-2 exits with `portal/game/pv` and type-10
hidden sparkles with `portal/game/ph/default/portalContinue`; the Tree's type-1 hollows have no portal sprite.

### 4.4.5 World-movement details (`FootholdMap` ... `SpatialHash`)

What the table above leaves open; the class doc comments have the rest.

- **Footholds:** `x1 < x2` floor (landed on from above), `x1 == x2` wall, `x1 > x2` ceiling (stops upward motion).
- **`MobSwarm.step(dt, ctx)`**, `ctx` keys: `fhm` (required); `nav` = `NavGraph.build(fhm, {"can_jump": false})` for
  mobs whose `MobKind.can_jump` is false; `nav_jump` = `NavGraph.build(fhm, {"can_jump": true})` (default `nav`);
  `target` (player position); `target_fh` (player foothold, -1 = the floor below `target`); `bounds` (MapBounds rect);
  `speed_mult` (stage speed multiplier, default 1); `physics` (PhysicsConstants, default v83). Build both graphs with
  the same `gravity` / `fall_speed` / `jump_speed` as `physics`. `MobSwarm.kinds` is `RunWorld.mob_kinds`; edits to a
  kind apply from the next step.
- **Flyers:** `MobKind.flies` is inferred from the canonical `fly` stance; movement ignores footholds and NavGraph,
  uses `fly_speed_stat` through the survivor speed conversion, and stays within map bounds with a non-drifting bob.
  Flyer `fh` stays -1, including during death; `route_len` is the straight-line distance to the player. HIT pauses
  pursuit; DIE keeps the death sprite in the air until the canonical animation finishes. The same spawn HP
  multiplier and touch hit path apply to flyers and ground mobs.
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

`RunWorld.spend_mp(amount) -> bool` atomically pays a cost without changing the pool on failure. Regen is applied
in `balance.regen.interval` pulses (`PlayerUpkeep` keeps the clock; RunWorld applies each pulse to its pools): HP/MP
base amounts plus owned Improved MP Recovery's canonical level-scaled MP bonus. `hp_regen` / `mp_regen` modifiers add
to each pulse. Level growth calls `refresh_player_stats(false)` so larger maxima do not restore current pools;
explicit pool upgrades retain the normal granted-growth behavior.

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
  Narrow accessors for the components that act on the world (MobSkillRunner, BossAttacks, BasicAttack): `player_box()`,
  `player_body_center()`, `mob_img(id)`, `refresh_player_speed()`, `summoned_alive(owner)` and `spawn_offspring(source,
  center_x, ids, owner, max_count := -1)` (MobSkill 200 summons and info/revive offspring: the same symmetric
  `mob_skills.summon_spacing` spread on the source's platform, centred on the whole list). Its tick reads as
  `_step_player` (drinks, `_take_portal` or movement, view, `_tick_timers`), `_step_monsters`, `_step_player_attacks`,
  `_step_pickups`, touch, EXP, state snapshot, `_end_tick`; `_on_boss_kill` handles a scheduled boss's death.
- **Event details:** `player_hit.damage` is the whole hit (the number shown), `mp_absorbed` the part Magic Guard paid
  with MP. `player_hit.miss` renders the violet MISS and produces no hit expression or invincibility blink.
  `RunWorld.take_hit` takes attack, magic flag, element, source position and optional source fields `accuracy`,
  `elite`, `dmg_mult`, `mob`, `mob_id`, `boss`, `source_kind`. Only explicit elite/source multipliers scale damage; time keyframes
  never do. `player_hit.max_hp` is captured before any later level-up in that tick changes the pool.
  `choice_pending` card `rank` is the rank the card gives when taken (1 = new); `max_rank` 0 = unlimited;
  `skill_name` is the card's skill's name ("" without a skill), `skill_level` its canonical level now (0 = not owned)
  and `skill_level_next` its canonical level once the card is taken (0 unless the card learns or ranks the skill; the
  level-up window shows "Skill Lv. 2 → 3" for a skill_rank card, whose own rank is not the skill's level).
  The run's starting skill emits `skill_learned` before the first `step()`.
- **Player buffs:** `player_state.buffs` is an array of `{skill, skill_id, level, icon, remaining, duration,
  effect_stat, value}`. Duration/effect are snapshotted from canonical `time` and `x`/`pdd` at cast level; upgrading a
  rank affects the next cast. `skills.json` kind `buff` keeps its passive slot but joins SkillRunner's oldest-ready
  cast ordering, pays canonical `mpCon`, and casts without a target only while inactive. Buff timers advance before
  casting each tick, including on ropes. `fired_this_tick` covers buffs and keeps basic attacks out of that tick.
  `hit_defense()` adds active Armor PDD to equipment/stat defense; `magic_guard_ratio()` reads active Guard only.
  Expiry drops the effect immediately; an affordable, permitted recast may happen on that same tick. `HudBuffRow`
  draws canonical Skill.wz icons and whole-second remaining labels; the HUD signature updates on countdown changes.
  Rank previews add canonical `time`, `x`, `pdd` changes to MP cost and existing combat fields.
  Recovery also reads canonical `cooltime`; its `buff.hp_threshold` and `pulse_interval` are survivor rules.
  `RunWorld.can_start_buff(skill, stats)` checks the HP threshold before spending MP. Recovery's cooldown starts at
  cast time and keeps ticking during its HoT and while climbing. PlayerBuffs applies periodic intervals only inside
  the active duration, returns total healing due to the world, and emits the final pulse before expiry. The six
  5-second pulses over 30 seconds are a tier C interpretation of canonical `x`. Rank previews include `cooltime`,
  and Recovery's `x` is labelled HP per pulse rather than an absorption percentage.
  Nimble Feet reads canonical `speed`, `time`, `mpCon` and `cooltime`; its active speed points are added before
  the mob-skill slow multiplier. Speed refreshes immediately on cast and expiry. Its 60 s cooldown starts at
  cast, so the 4/8/12 s buff does not recast at expiry before that cooldown elapses. Improved MaxMP Increase is
  a passive with data-defined `per_level` feeding `max_mp_percent`: RunWorld multiplies its base MP plus job
  grant on every recompute, rounds once, and preserves current MP ratio on growth when this passive is owned.
  Ordinary level growth without the passive still grants no current MP.
- **`ProjectileSystem`:** `rng` (combat stream), `paths` (= `RunWorld.visual_paths`), `bounds`; `step()` fills
  `kills` (mob slots killed this tick) and RunWorld turns them into `mob_died` + an EXP drop, like instant hits.
- **`PickupSystem`:** `step()` returns the EXP collected this tick; at `max_active`, `spawn()` absorbs the drop farthest
  from the supplied player position and reuses its slot at the new death position, restarting the pop and age with
  the combined EXP. `merged` reports absorption, and `RunWorld` still emits `pickup_spawned`. With `lifetime` > 0 a drop expires silently
  (no event; `expired`, `expired_exp`) after fading out; renderers read `alpha(i)`.
  Potion slots have a separate kind and bundle count: they never expire, absorb EXP, or count toward `max_active`.
  Both kinds use the same pop, gravity and magnet motion. `collected_potions` reports hp/mp quantities collected this tick;
  `active_count()` includes all drops, while `exp_count()` preserves the balance harness's EXP-drop metric.
- **Potions:** `setup.item_info` maps original item IDs to canonical `Item.wz/Consume/0200.img` nodes loaded by
  `DataRepo.build_setup`. `player_state.potions` is `{hp: {item_id, count}, mp: {item_id, count}}`.
  `RunWorld.spawn_potion(kind, pos, count := 1)` emits a ground bundle (also the boss-reward seam);
  `drink_potion(kind) -> bool` consumes one and restores `spec.hp` or `spec.mp`, clamped to max. Empty stock is inert.
  Drink presses run before movement and casting, including on ropes; no cooldown applies.
  `balance.potions` selects starter IDs/counts, independent normal/elite per-kind drop chances and bot thresholds.
  Stage keyframes may override ordinary HP/MP rolls with `normal_hp_drop_chance` / `normal_mp_drop_chance`.
  Each endpoint uses that kind's global normal chance when missing, clamps to [0, 1], and interpolates linearly in
  run time; outside the frame range the nearest endpoint holds (no post-duration spawn ramp). Elite chances remain
  global; fixed boss bundles bypass both curves. An absent curve preserves the seeded ordinary drop sequence.
  `potions.collected` and `potions.used` feed per-kind balance/perf records. The HUD quickslot draws the stock snapshot's
  current canonical item icons, counts and keys.
- **Player-platform placement:** `SpawnDirector.pick_player_platform(world, min_distance := -1,
  preferred_distance := -1, allow_visible := false, side := 0) -> Vector3` returns (x, y, foothold), or z=-2 when no
  point is possible. It samples the current platform while avoiding walls and nearby points; normal placement is
  visible only when `player_platform_visible(world)` sees the whole platform inside the logical view. A preferred
  distance and visible override support boss relocations. `spawn.platform_share` (0.35) selects this path for ground
  placements before ordinary ring fallback; flyers retain off-screen air sampling. Every new mob fades in and deals
  no touch damage until alpha is 1.
- **`UpgradePool`:** `state` is the `RunWorld`; `apply()` also emits `upgrade_applied` (+ `skill_learned`). Card
  `effects` op `add` sums and `mul` compounds per rank. No card heals by percentage and no filler cards are injected.
  A `potion_tier` card has `potion_kind`, target `item_id`, `requires.min_level` and `requires.potions` mapping its kind
  to the required current item ID. This survivor data defines the whole ladder. Applying an eligible one-time tier
  calls `RunWorld.upgrade_potion(kind, item_id)` and preserves stock; the event and refreshed player state update the
  quickslot immediately. Future `spawn_potion` calls use the current ID, including boss bundles.
- **Job window:** opens at a queued level whenever an option is available, and once at exactly the tier's first
  advancement level even when none is (Magician at 30 sees 210/220/230 as unavailable once).

### 4.5 Presentation (`game/scripts/render`, `ui`, `audio`, `run`)

The headless `tools/balance_run.gd` advances the same fixed ticks with real-map setup and seeded card/movement
policies. Its record/aggregate contract and CLI are in AGENTS.md's Balance section: milestone reach counts,
completed versus censored boss fights, per-hit whole damage/max-HP fractions by boss/source, potion collection/use,
per-run MP-short ticks, and camper activation/arrival. A later affordable skill may cast during an MP-short tick.
TIMEOUT is a measurement cap, never a sim clear. Remaining potion stock, ordinary-versus-boss potion source counts,
offensive cast counts and aggregated Guard coverage are not separate recorded metrics. Monster balls retain captured source/damage after
caster death; their original mob slot may be reused, while captured mob ID/source position remain meaningful.
`PortalApproach` supplies the shared pure entrance-floor lookup, jump-graph approach, wall gate and movement input
for `BotInput` and the camper harness. Each caller retains its goal scoring and eligibility policy, including the
bot's additional entrance-floor activation-height check.
`buff_casts` is an additive harness diagnostic: event-observation time, skill/key ID, canonical level/duration,
and effect stat/value copied from the public cast snapshot. Normal runs drain after each fixed step, so this is
that cast tick; already-pending setup events are observed at the next drain. It adds no RNG calls or gameplay
changes. Earlier records lacking this field are unavailable observations, not zero casts. Hit MP absorption may
be clipped by available MP, so it is not a substitute for the canonical active effect or a coverage measure.
Legacy `cards_taken` strings prefix the card ID with the front queued level, or −1 when that queue is empty.
A bonus choice can have a positive prefix while levels remain queued. The field supplies neither a bonus flag
nor a choice timestamp, so it cannot isolate normal-choice acquisition timing.
The sensible `BotInput.card_score` reads optional `balance.potions.bot.tier_score` for potion-tier cards, falling back
to the legacy tier C score 52 when absent. Optional `balance.bot.card_scores` takes precedence for an individual card
ID. These replace the final score, with no job bonus added; an unlisted card retains its existing
scoring path. Random policy selects uniformly among offered cards with its own seeded RNG and never reads either
score setting. Both knobs are tier C survivor tuning.

| Piece | Approach |
|---|---|
| `MapRenderer` | Backgrounds (types 0-7, parallax `x + cam_cx*rx/100`, tiling by `cx/cy`, auto-scroll `rx*5 px/s`, `a`, `f`, front backs) redrawn per frame; static tiles/objs per layer recorded once in a `_draw()` command list; animated objs as canvas items. Draw order: non-front backs -> layers 0..7 (objs by `z`, then tiles by canvas `z`, then actors standing on that layer) -> front backs. |
| `AvatarRenderer` | Composites body/arm/head/face/hair/coat/pants/shoes(/weapon) per frame using `map` anchors (navel, neck, hand, brow) and `Base.wz/zmap.img` order. Mirrors for facing. |
| `MobRenderer` | One RenderingServer canvas item per live mob slot (no Nodes), region-of-atlas per frame, alpha for `a0/a1` fades. One renderer per foothold layer (`only_layer` + `update_slot_layers`) to draw mobs inside `actor_layer(L)`. |
| `NameTags` | Elite name tags under mobs (`RunWorld.mob_elite`), drawn like v83's code-drawn default name tag. |
| `FxRenderer` | Pooled one-shot WZ animations and repeating slow/immunity icons; `play_repeating`, `stop` and `place` follow sim status/expiration without per-entity Nodes. |
| `DamageNumbers` | `Effect.wz/BasicEff.img` digit sets: first digit large set, rest small; 400 ms hold then 600 ms fade + 30 px rise (tier B). |
| `Hud` | Hosts separate `HudStatusBar`, `HudCounters`, `HudSkills`, `HudMessages`, `HudPotionQuickslot`, `HudBuffRow` and `HudBossBar` widgets, all extending the one base `HudWidget` (a mouse-ignoring Control with its own state snapshot, the HUD fonts and the only copies of the WZ drawing helpers `_frame(path, report_missing)`, `_blit`, `_blit_rect`, `_text`, `_rank`). RunScene feeds potion stock/icons, buff icons with ceiling-second MM:SS labels, and live boss bars stacked below the timer. The one HUD control that takes the mouse is the status bar's Menu button (`Hud.menu_button`, a `WzButton` on `StatusBar.img/BtMenu`, process mode ALWAYS so it works while the HUD is frozen). |
| Windows | Level-up choice (`LevelUpWindow`), job advancement (`JobAdvanceWindow`), pause (`PauseMenu`): `MapleWindow` Controls built from `UI.wz` art, skill icons from `Skill.wz`, text from `String.wz`; `RunScene` hosts them in a CanvasLayer (layer 10) and holds its tick loop while one is open. In-run windows (Stat, Skill, the Menu popup; later Key Config, Options): `UiWindow` Controls (draggable, art-sized) in a `WindowStack` on CanvasLayer 11; a window kind is one `ui_windows.register(id, factory)` in `RunScene._build_ui_windows()`, after which its hotkey (`RunScene.WINDOW_HOTKEYS`) and Menu entry work; keys RunScene does not use itself go to the front window's `UiWindow.handle_key`. The Skill window draws a `SkillWindowModel` (plain data from the SkillBook, UpgradePool, Loadout ranks / mods / `card_ranks`, JobTree and SkillText; read-only). The tick loop also holds while the stack has a window, Esc closes the front one before the pause menu, and a choice window below sets `input_blocked`. Title, stage select, results and import are scenes under `scenes/ui/`. |
| `Camera` | Follows the player with smoothing (tier C), clamped to `MapBounds`, positions rounded to whole pixels. |

`RunScene.boss_bars()` builds presentation-only snapshots from live encounter records and swarm HP, independently
of the status/timer update signature. `HudBossBar.displayed()` exposes the same rows used by drawing, with original
mob id, name, HP/max HP, ratio, icon and gauge paths. The bar uses `UI.wz/UIWindow.img/MobGage` backgrounds,
`Mob/<id>` icons and `Gage/<hpTagColor>/0`, `Gage/<hpTagBgcolor>/1` strips. `mobs.json.boss_ui` supplies only missing
presentation metadata; the cache is untouched. A dead boss is omitted immediately, including when others remain.
`boss_warning` and `boss_spawned` map to keyed yellow encounter notices above the ordinary EXP queue (and above
the low-MP cue), so EXP churn cannot evict them. Arrival replaces that boss's warning, plays the canonical
`Effect.wz/BasicEff.img/Summoned` animation at its position, and requests an evidence screenshot when enabled.

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
- No first-use decoding mid-run: `RunScene._warm_ui` and `_warm_stage` load at setup the window art, every skill rank's
  art, the job weapon and job-change sounds, and every scheduled boss's stances, MobSkill/attack art, sounds, name and
  boss-bar art (a Mano MobSkill 112 effect first decoded at 5:11 cost a 110 ms frame before this).
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

The canonical `equipment_info` supplies physical `incPAD`, magic `incMAD`, weapon speed, `afterImage` and `sfx`.
`RunWorld.weapon_id()` selects the configured job weapon; `mob_defense(slot, magic)` reads live slot defense, and
`physical_hit_allowed(slot)` is the physical-immunity seam. Basic swings show their action while standing or airborne;
new skills retain standing-only action presentation. Neither action changes movement or locks it.

MobSkillRunner keeps defense amounts/expiry in packed per-slot arrays. New spawns reset status and
`mob_summon_owner` (encounter index, -1 for ordinary mobs); relocation transfers both status and summon ownership.
Only active owned slots count toward the canonical summon limit. `mob_defense(slot, magic)` combines immutable
kind defense with its live timed bonus. ProjectileSystem.step accepts an optional packed per-slot MDD snapshot,
so projectile damage resolves the defense present at impact; basic and instant hits read the same live seam.
`player_speed_stat()` composes upgrade speed with the timed slow. `player_state.slow` is `{skill_id: int,
remaining: float, multiplier: float, visual: String}` while active, otherwise `{}`. The presentation repeats slow
art in a pooled slot until the sim state expires; window pauses cannot consume its duration.
