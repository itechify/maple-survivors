# Architecture

Status: Phase 0 decision record (2026-10-13). Evidence lives in `docs/RESEARCH.md` and the full investigator reports in
`docs/research/`.

## 1. Goal and constraints

Make a single-player Vampire-Survivors-style game that looks, sounds and moves like MapleStory v83 (GMS, Feb 2010
build), using the original assets, with a different combat and progression loop. Hard constraints from the brief:

- Fully offline: no server, no localhost sockets, no database, no account, no Java process. (The web build, section
  10, adds one narrow exception in its page shell, outside `game/`: section 7.)
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

`main.tscn` (bootstrap) -> `ImportScreen` (only when the cache is missing) -> `TitleScreen` -> `CharacterSelect` ->
`StageSelect` (map select for this character's next tier) -> `RunScene` (one round). Non-final clears carry the
character to the Free Market hub, whose out00 exit opens the next tier's map select;
death/final-tier victory -> `ResultsScreen` -> `CharacterSelect`.
There is no Retry. Three living slots support create, continue, confirmed delete and ended-run history.

The title is the game's own, not the v83 login scene: the key art `game/assets/branding/title.png` (the project's
original art, committed; logo baked in) is also the boot splash (`application/boot_splash`, stretch Cover), so start-up
runs straight into it, and Start opens character select. `KeyArt` draws it on the title and import screens; its
buttons are `TitleButton`s drawn from code. The emblem is `game/icon.png` (window) and `game/icon.ico` (Windows exe,
`application/modify_resources`); the web shell ships the favicons, `site.webmanifest` and `title.jpg` from `web/`.
Character select and creation keep the v83 MapLogin backdrop (`LoginBackdrop`).

`SceneFlow` owns the active slot and the round loop ([ADR 0001](adr/0001-run-of-rounds-with-one-character.md),
ADR 0006, #286): character select opens the character's Free Market, whose out00 opens map select (every stage of
every unlocked tier), `start_round` launches a round **without writing anything**, and `finish_run(summary, character,
ending)` is the one exit of a persistent round (clear, death, and Quit round with `ending` "quit"): it saves the
outgoing character, the best, the run count, the NX and one history entry in a single `SaveData.finish_round` write and
shows the results screen, whose button returns to the hub. `RunScene.configure` accepts `options.character` as a
snapshot Dictionary or the tool JSON-file path. The coordinator's header documents #70's small character-screen calls.
`RunWorld.character_snapshot()` is always available (no choice can block it) and is where a clear unlocks the next tier.
On clear, RunWorld first settles every collectible ground drop and every resulting choice (4.4.2); `stage_cleared`
is emitted only after that settlement. RunScene takes the outgoing snapshot after the clear presentation hold.
`FreeMarket` uses `FreeMarketMotion` (PlayerMotion, FootholdMap, LadderSet and PortalSet) without a RunWorld;
there are no combat, spawning, drop or round-clock systems. MapRenderer/CameraRig draw the map and AvatarRenderer
draws CharacterSnapshot.look with the character's worn equipment. A status bar displays full HP and identity, while
PauseMenu's boundary mode offers Save & quit without the round-loss warning. NPC stand animations use canonical
life positions/facing and remain inert, including Maple TV (drawn despite its v83 hide flag, per #71). The four scroll
NPCs (#111, `survivor/shops.json`) stand on the floor beside them and are the only NPCs that can be talked to: NPC Chat
(Space) next to one, or a double-click, opens its `ShopWindow` in the hub's window stack (`FreeMarket.open_shop`),
trading through the map-less RunWorld (`shop_stock`, `buy_scroll`, `sell_item`, `sell_scrolls` over the pure `Shop`
module) and saving the slot at once.
`--run` calls `start_run`, an independent one-off with no save writes.

The `flow_driver.tscn` `redesign` scenario exercises these boundaries through injected signboard, creation (name, look,
Job page), Free Market walk, map select (a locked tier refused), level-up window, double-click equip, pause, deletion and
History input. It warps real fixed simulation ticks through combat (invulnerable, with diagnostic boss hits after each map
timer), plays the real CLEAR/fade/arrival presentation of the three maps, and reloads the evidence-only save from disk to
check that a clear unlocks tier 2 and that a death keeps the loot and the unlock. It checks presentation and flow only;
natural outcomes belong to balance smokes (AGENTS.md "Flow driver").

### 4.2 Autoloads

| Autoload | Script | Role |
|---|---|---|
| `Assets` | `scripts/assets/asset_library.gd` | Locates the cache, loads/caches img JSON (`WzImg`), atlas page textures, sounds; builds `SpriteAnim` frame lists |
| `Settings` | `scripts/core/settings.gd` | `user://settings.cfg`: WZ root, volumes, window scale, fill-window view mode, frame cap (`[display] max_fps`: vsync on and `Engine.max_fps` = the display's refresh rate by default, `--vsync=off` uncaps), key bindings (rebound actions applied to the `InputMap`), HP ALERT levels (`[alert]`; persistent rounds only, #121) |
| `Sfx` | `scripts/audio/audio_service.gd` | BGM player with fade, pooled SFX players |
| `Flow` | `scripts/core/scene_flow.gd` | Scene flow of 4.1: swaps main.tscn's child; character slots, the Free Market home, map select over the unlocked tiers, standalone rounds (no saved round); tool-only `start_run` (`--run`) bypasses persistence |

Everything else is owned by the scene that uses it.

`SaveData` owns local `user://save.json`, format 3: `best`, `runs`, three nullable `slots`, and `history`, plus an
optional `account: {nx, owned}` (spec #34; absent = an empty account). A finished round's `nx_awarded` is credited
inside the same atomic write as the round's slot, best and history entry.
A slot is `{name, created, rounds_played, character}`; `character` is the validated format-3 `CharacterSnapshot`
(job, look, equipment, scrolls, mesos, cash, pet, `tiers_unlocked`). There is no phase, tier cursor, stage or seed: a
round is never saved. The caller supplies dates and seeds.

`slot(index)`, `slots` and `history` return detached copies. `create_slot(snapshot)` returns the first free index
(or -1, with `last_error`); `update_slot(index, snapshot)` saves the hub's changes and returns `Error`.
`finish_round(index, snapshot, ending, date, round_summary)` (`ending` cleared/died/quit) stores the character the round
left, counts the round for its stage's best and run count, credits its NX and appends
`{name, job_id, job_name, stage, level, ending, date}` in one write; the character is never removed.
`delete_slot(index, date)` frees the slot and appends a `deleted` entry. A format-2 file's living characters move to the
history on load as `retired` entries (name, job, the level and stage they had) and the file is rewritten as format 3;
its bests, counts, history and account are kept. Older history entries keep their `tiers_cleared` / `rounds_played`.
The legacy `record`, `best_for`, `runs_for`, `is_better` and presentation helpers retain their existing behavior;
tool-only one-off rounds skip every persistence call.

Format 1 converts on load and writes back with empty slots/history, retaining playable-stage bests/counts.
Malformed or unsupported saves are copied to `.bad`, `.bad.1`, etc.; preservation failure blocks writes. A valid
`.bak` recovers a missing **or rejected** primary; only when neither validates does the save start empty.
Writes validate all characters, preserve full-precision JSON numbers, flush/close `.tmp`, copy a previously
validated primary to `.bak`, then replace the primary. A rejected primary is never rotated over the backup.
Saving unchanged state leaves both committed byte sequences alone. In-memory mutations commit only after success.
Godot 4.7.2's [Windows rename implementation](https://github.com/godotengine/godot/blob/ed1daf0bf/drivers/windows/dir_access_windows.cpp#L288-L327)
removes the destination before moving the source, so a missing primary recovers the last complete `.bak` on load.
A leftover `.tmp` is never loaded as a committed save. Tests use process-private paths, including backups.

The default persistent `SaveData` acquires a desktop single-writer lease **before loading, migrating, recovering or
writing**. Atomic creation of the sibling `save.json.lock` directory grants ownership; a uniquely named `.owner`
file records a random session id and `renewed_at` wall-clock timestamp. SceneFlow's always-processing Timer renews
every **5 real seconds**, independently of pause and gameplay speed; writes renew before staging, before touching
committed bytes, before promotion and after success (including unchanged saves). **30 seconds** without renewal
permits takeover (tier C safety constants, not v83 facts). No process is launched or queried. Clock reads stay in
core/ and tests inject the clock; simulation remains deterministic. System clock rollback can delay stale recovery.
A live lease blocks the second session with `ERR_ALREADY_IN_USE`; the existing v83 Notice tells the player to close
the other window or wait 30 seconds after it stops responding, then retry from the title. Retry constructs a fresh
SaveData and reloads committed state. A session waking after takeover becomes permanently read-only and shows the
same Notice; it cannot reacquire ownership with its old in-memory state, even after the new owner exits.
Each renewal publishes a new unique generation before retiring its previous marker; stale cleanup removes only the
expired generation it inspected. Ambiguous ownership or unknown debris fails closed. Clean tree exit and SaveData
destruction remove only their own marker, never the replacement's marker. Empty/partially written locks from an
interrupted acquisition also expire after 30 seconds (file modification time is the fallback for partial markers).
Persistent writers use session-specific `.tmp.<session>` files so a resumed old writer cannot truncate or remove
its replacement's staging file. Leftover temporary files are never loaded. The lock is a directory so creation is
exclusive on Windows as well as POSIX; a normally opened file would not provide exclusivity in GDScript.
Custom SaveData paths are unguarded unless explicitly opted in (`SaveData.new(path, true)`, for synthetic ownership
tests). Tool-only `--run`, headless tools, balance/bench/playtest and injected `flow_driver` saves never acquire the
real-save lock. Web ownership is held by the shell for the whole storage lifecycle, below, rather than by game code.

`GameSettings` also writes through a flushed/closed `.tmp`, backs up a parseable primary to `.bak`, then renames.
A missing or malformed primary reads the backup without writing during load; corrupt bytes are never rotated over
that backup. Unrelated ConfigFile sections and InputMap/default-binding semantics remain unchanged. `save_settings`
returns its `Error`, records `last_error` and emits `save_failed(error)` for every failed setter persistence attempt.
The live values still apply to the session. Options displays "Not saved" in its footer; Key Config keeps its draft
open with that message and emits neither `saved` nor close until persistence succeeds. Tests clean all three
process-private config siblings, retaining #103's isolation from the player's real preferences.

Auto-actions share `RunWorld.can_cast()`: it rejects non-PLAYING/dead runs and `PlayerMotion.ST_LADDER` (ropes and
ladders). `SkillRunner.step()` counts cooldowns before checking this gate; active effects and passives remain
independent of new casting. A ready skill can cast on the tick movement leaves the climbing state.
Manual Esc pause leaves the sim state unchanged; RunScene stops its tick loop and freezes presentation. An open
in-run window (Stat, Skill, Menu popup) holds the run the same way.

### 4.3 Simulation / presentation split

A round is a `RunWorld` (`scripts/sim/run_world.gd`), a pure object advanced in **fixed 1/60 s ticks** by `RunScene`'s
accumulator. It never touches nodes, input, time or files. Each tick it consumes a `MoveInput` and appends events
(`{"type": "mob_hit", ...}`) to `RunWorld.events`. The presentation layer drains the events every frame to spawn damage
numbers, hit effects and sounds, and reads the struct-of-arrays state directly to draw mobs, projectiles and pickups.

Benefits: every gameplay rule is testable headless with a seeded RNG; the presentation can be swapped (debug view,
recording) without changing the rules; and a full simulated run can be benchmarked without rendering.
`RunWorld.step` optionally calls `after_stage(name)` at its production stage boundaries (`STEP_PARTS`); observers
must be read-only and draw no RNG. `profile_run.gd` supplies the external clock and reports those coarse stages,
including Final Attack inside player attacks. It no longer maintains a separate copy of tick orchestration.

### 4.4 Module contracts (sim core, `game/scripts/sim/`)

All classes are `RefCounted` with `class_name`. Coordinates are MapleStory world pixels (x right, y down, the same as
Godot 2D). Time is seconds (WZ `delay` ms are converted on load). `fh` = foothold index (not the WZ id), `-1` = none.

| Class | Responsibility | Key API |
|---|---|---|
| `PhysicsConstants` | Map.wz/Physics.img values | `static from_wz(physics_img: Dictionary)`, `static v83_defaults()`, fields `walk_force`, `walk_speed`, `walk_drag`, `slip_force`, `slip_speed`, `float_drag1`, `float_drag2`, `float_coefficient`, `swim_*`, `fly_*`, `gravity_acc`, `fall_speed`, `jump_speed`, `max_friction`, `min_friction`, `fly_jump_dec` |
| `FootholdMap` | Foothold geometry and queries | `static from_wz(map_img)`, `static from_segments(list)`, `count()`, `is_wall(i)`, `is_floor(i)`, `y_at(i, x)`, `find_below(x, y, ignore := -1) -> int`, `teleport_destination(origin, direction, distance, bounds, from_p := -1) -> Dictionary` (`{pos, fh}` or `{}`), `wall_hit(xa, ya, xb, yb, p := -1) -> int`, `wall_applies(w, p) -> bool`, `next_of(i)`, `prev_of(i)`, `bounds() -> Rect2`, `platform_of(i)`, `platform_count()`, `platform_span(p) -> Vector2` (min x, max x), `walk_blocked(p, xa, xb) -> bool` (a wall stands across p between the two), packed arrays `x1 y1 x2 y2 layer group prev next`, flags `cant_through forbid_fall_down` |
| `MapBounds` | Camera/world limits | `static from_map(map_img, fhm) -> Rect2`: `info/VR*` if present, else `miniMap` rect, else foothold bbox (top -300, bottom +100) |
| `LadderSet` | Ladders and ropes | `static from_wz(map_img)`, `static from_list(list)`, `find_grab(x, y, reach) -> int`, arrays `x y1 y2 is_ladder uf page` |
| `PortalSet` | Same-map portal links and activation | `static from_wz(map_img, map_id, tuning)`, `step(dt, feet, up) -> Dictionary` (warp or `{}`), `static start_point(map_img, fhm, bounds, rng)` (a random `sp` portal dropped to the floor, else the widest platform's middle), `static start_point_away_from(map_img, fhm, bounds, rng, from)` (Banish, #256: the same with the `sp` nearest `from` left out when there are two or more); `links` rows `{name, target, pos, target_pos}` use canonical portal points |
| `MoveInput` | One tick of player intent | `left right up down jump_pressed jump_held drink_hp skills_pressed skills_held` (drink flags and `skills_pressed` are presses; `skills_held` requests repeats; both are skill-key id -> true maps, set with `press_skill(id)` / `hold_skill(id)`, read with `skill_pressed(id)` / `skill_held(id)` / `skill_requested(id)`; ids are the manual skills' `skill_key`, "teleport" and "dash") |
| `PlayerMotion` | Player movement per Physics.img | `_init(constants)`, `place(pos, fhm)`, `teleport_destination(direction, distance, fhm, bounds) -> Dictionary`, `step(dt, input, fhm, ladders, bounds) -> int` (event flags), `knockback(dir)`, fields `pos vel fh ladder facing state speed_stat jump_stat`, `stance() -> String` |
| `NavGraph` | Platform graph for mob pathing | `static build(fhm, opts)`, `route(from_p, to_p) -> int` (edge index, fewest edges), `edge(e) -> Dictionary` (`kind` drop/jump, `from_p`, `to_p`, `x_from`, `x_to`), `reachable(a, b)`; travel-cost field toward a point: `prepare_target(to_p, tx, also_p := -1)`, then `route_cost(p, x) -> float` (px, INF = no way), `best_edge(p, x) -> int`, arrays `cost`, `take` (per edge) |
| `MobKind` | One mob type: canonical WZ stats + survivor overrides + animation timing needed by the sim | `static from_wz(mob_img, id, overrides)`, fields `id name level max_hp exp pad pdd mad mdd speed_stat fly_speed_stat move_speed can_jump flies hitbox die_time hit_time pushed body_attack boss elem_attr` |
| `MobSwarm` | All mobs, struct-of-arrays with free list | `_init(capacity, kinds, tuning)`, `spawn(kind, x, y, fh, hp) -> int`, `despawn(i)`, `step(dt, ctx)`, `apply_hit(i, dmg, dir) -> bool`, `alive_count()`, accessors `pos(i)`, `is_live(i)`, `is_settled(i)` (live and fully faded in), `mob_kind(i)`, `live_in_rect(area)` (ascending slots), `static low_platform(fhm, target, tp, reach_y)`, packed arrays `kind x y vx vy hp max_hp state state_t fh platform facing anim_t route_len steady` |
| `SpatialHash` | Broad phase for mobs | `_init(cell)`, `rebuild(xs, ys, active)`, `query_rect(r, out) -> int`, `query_radius(c, r, out) -> int` |
| `ProjectileSystem` | Shots in flight (pooled SoA) | `spawn(spec) -> int`, `step(dt, swarm, hash, events, live_mdd := PackedFloat32Array(), physical_allowed := PackedByteArray(), on_hit := Callable(), live_pdd := PackedFloat32Array())`, per-shot pierce and already-hit list; live defense/immunity arrays are indexed by target slot at impact |
| `PickupSystem` | EXP, meso and equipment drops (pooled SoA) | `spawn(pos, exp, item_id, player_pos := Vector2.ZERO)`, `spawn_meso(pos, amount)`, `spawn_equipment(pos, instance)`, `step(dt, player_pos, magnet_r, fhm, events, equip_room := -1)`, `active_count()`, `exp_count()` |
| `PotionInventory` | Unlimited HP with independent cooldowns and canonical restore specs | `item_id(kind)`, `cooldown_left`, `cooldown_total(kind)`, `is_ready(kind)`, `tick(dt)`, `snapshot()`, `upgrade(kind, item_id)` (keeps cooldown), `consume(kind, by_pet := false)`; `used`, `pet_used` drink counters |
| `PotionSchedule` | Level schedule of automatic potion upgrades (static, pure; `balance.potions.schedule`, spec #225) | `steps(balance)` (valid steps sorted by level), `due(schedule, level, current) -> Array` (re-scanned each time: no applied-step state, never a downgrade), `items(balance)`, `notice_text(from_name, to_name)`; `RunWorld.apply_potion_schedule(level, announce)` applies the due steps through `PotionInventory.upgrade` at each level-up (with a `potion_tier_up` event) and silently when a snapshot is restored |
| `CombatMath` | Damage formulas (static) | `magic_damage_range(...)`, `monster_hit(attack, magic, element, defense, rng, multiplier)`, `monster_damage(...)`, `miss_chance(avoid, accuracy)`, `roll_miss(...)`, `apply_defense(...)`, `roll_crit(...)` |
| `SkillBook` / `Loadout` | Survivor skill definitions, owned skills and ranks | `add_skill`, `rank`, `stats` (damage, cooldown, count, pierce, speed, range, size; no MP cost), `clone` for previews; weapons do not gate skills |
| `MobSkillRunner` | Scheduled canonical mob skills, delayed heals, summons, timed per-slot defense/attack/immunity, player slow and Banish | `step(world)`, `defense_bonus(slot, magic, time)`, `attack_multiplier(slot, time)`, `slow_state(time)`, `immunity_state(slot, time)`, `summoned_alive(world, encounter)`, `resize`, `reset_slot`, `move_slot`; reads setup MobSkill/skill-list nodes and shares BossDirector action timing; named MobSkill ids `SKILL_ATTACK_UP` 100, `SKILL_ATTACK_UP_AREA` 110, `SKILL_PDD_UP_AREA` 112, `SKILL_MDD_UP_AREA` 113, `SKILL_HEAL_AREA` 114, `SKILL_SLOW` 126, `SKILL_BANISH` 129, `SKILL_WEAPON_IMMUNITY` 140, `SKILL_SUMMON` 200 (`SUPPORTED`); a boss entry's optional `skill_intervals` (`{"<skill id>": seconds}`, read through `world.bosses.skill_interval`) replaces that skill's WZ `interval` (#256); the Banish notice is the boss's survivor `mobs.json` `banish_message` (read from `world.data`); reads the world only through `RunWorld`/`MobSwarm` accessors (`swarm.pos`, `is_settled`, `live_in_rect`, `mob_kind`, `world.summoned_alive`, `spawn_offspring`, `refresh_player_speed`, `banish_player`) |
| `WeaponReach` | The held weapon's swing reach (#284 removed the automatic basic attack) | `reach(world)` (the farthest edge of the held weapon's canonical afterimage boxes, the punch box bare-handed) and `envelope(world)` (their union), read by `weapon_reach` skills and Final Attack spread; `action_spec(weapon, info, action)` is one stance's box, timing and effect paths (the weapon gallery) |
| `Ammo` | Endless ammo of the ranged basic attack (static, pure; `survivor/ammo.json`) | `item_for(ammo, family, job_id, level, jobs)` (start ammo, or the highest reached step of a branch schedule), `projectile(ammo, family)`, `noun`, `notice(noun, name)`, `item_ids(ammo)`, `img_path(id)`, `bullet_path(id)`; `RunWorld.ammo_id()` / `ammo_attack()` / `ammo_tooltip(weapon)` derive the current ammo (never saved) |
| `WeaponInfo` | Weapon facts (static, pure) read by combat and presentation | `type_of(id)`, `family(id)`, `family_of_skill_code(code)`, `is_two_handed(id)`, `attack_kind(action)` (swing/stab/shoot/empty), `basic_actions(id)` (the family's basic-attack stances), `basic_kind(id, action)` (ranged families always shoot), `is_ranged(id)`, `ranged_box(id)`, `stand_stance(info)` / `walk_stance(info)` (PlayerMotion and AvatarRenderer play the held weapon's stances), `physical_formula(id, job)` (swing/stab multipliers and primary/secondary stats; tier B except wand/staff/bare fallback), `afterimage_name(info)`, `afterimage_img_path`, `afterimage_frame_path`, `hit_spark_path`, `attack_interval(info)`, `sound_path(info)` |
| `SkillRunner` | Auto-casting | `step(dt, world)` ticks cooldowns, checks `RunWorld.can_cast()`, then casts one affordable ready skill, oldest-ready first; `tick_cooldowns` and `cast_ready` are separate entry points; `fired_this_tick` reports any cast and `waiting_mp` feeds the persistent HUD cue; `cooldown_totals` (cooldown set at each skill's last cast) and `is_waiting_mp(key)` feed `RunWorld.skill_readiness`; static `count_meaning` (shots / targets), `strike_count` and `restart_cooldown` are the one definition of those rules for card previews and the Skill window |
| `PlayerMeter` | Round-owned M1 counter (`RunWorld.meter`, #299) | `gain(event, events)`, `admits(definition)`, `begin_cast(world, key, stats)`, `landed(receipt, events)`, `preferred(world, ready)`, `snapshot()`; job data configures capacity/gain/bonus, skill data configures finishers. Shared cast receipts deduplicate delayed hits; map transfer preserves the counter. HudMeter consumes value-change events. Schema: GAME_DESIGN 7.34. |
| `PlayerSummons` | Map-local player allies owned by `SkillRunner.summons` (#291) | `spawn(world, resolved_stats)`, `step(dt, world)`, `clear()`, `living_count()`; packed position/lifetime/facing/animation/windup state, cold cast snapshots; reads canonical summon attack info through SkillBook, hits through RunWorld; `clear_pending()` removes allies on transfer. `PlayerSummonRenderer` draws the pool through one SpritePool without entity Nodes. Definition schema: GAME_DESIGN 7.32. |
| `PlayerBuffs` | Timed player effects, periodic healing and detached HUD snapshots | `has(skill)`, `start(skill, stats)`, `step(dt, events) -> int` (HP healing due), `effect_total(stat)`, `snapshot()` |
| `PlayerUpkeep` | The player's per-tick timers, owned as `RunWorld.upkeep`: buffs (steps `PlayerBuffs`), hit invincibility, the cast-stance hold and the `balance.regen` pulse clock; the world owns the pools and applies what it reports | `tick(dt, events) -> float` (buff healing due), `regen_pulses(dt) -> int`, `pulse_hp()`, `pulse_mp()`, `start_action`, `land_hit(boss_skill) -> float` (starts the hit window a landed hit earns and steps the #88 shrinking chain), static `bypasses_window(source) -> bool` (boss skill attack/ball), fields `invincible_t hit_step since_hit cast_action cast_left action_airborne` (`hit_step`/`since_hit` are per-round chain state, not saved with the character), `DEFAULT_REGEN`, `DEFAULT_HIT_WINDOW` (balance.hit_window: `lengths`, `chain_gap`, `reset_after`) |
| `ExpCurve`, `RunProgression` | Survivor EXP curve, level, job, pending level-ups | `exp_to_next(level)`, `add_exp(n) -> int` levels gained |
| `JobTree` | Canonical jobs with survivor pools and flags | `playable_jobs`, `skill_pool`, `start_skills`, `creation_weapon`, `job_error`, `parse_job`, `put_job`, `lineage`, `job`; presentation/tools use `DataRepo.jobs(data)` |
| `UpgradePool` | Pool-based eligibility and seeded draws | `eligible(state)`, `roll_choices(state, rng, n)`, `apply(id, state)`; active new/rank/Mastery cards roll rarity, common passives do not |
| `SpawnDirector` | Stage pacing, spawn positions, relocation | `step(dt, world)`, `pick_spawn(world, k, side := 0) -> Vector3` (x, y, foothold: -1 for flyer air points, -2 when no point is found), `screen_rect(world) -> Rect2` (what spawns stay out of: the view + `margin`, + `trail_margin` behind a moving player); ground spawns prefer short reachable routes; flyers sample off-screen air within map bounds; moves off-screen mobs that stall, are far or cannot reach the player to a point ahead of the player (`relocated`) |
| `StageRoster` | Which mob ids a stage needs | `static named_ids(stage)` (keyframe pools + boss ids), `static boss_extra_ids(boss_img, mob_skill_img)` (MobSkill 200 summons at each level the boss lists in `info/skill`, plus `info/revive`), `static mob_ids(stage, mob_imgs, mob_skill_img)` (both, ascending), `static list_ids(node)` (a WZ list node's ids in key order: summon levels, revive lists); used by `RunWorld` (mob kinds) and `DataRepo.build_setup` (two passes: named imgs, then derived ids) |
| `BossDirector` | Scheduled warnings, arrivals, pursuit teleports, shared action timing, deaths and completion | `step(world, dt := 0)`, `live_count()`, `all_dead()`, `normal_spawn_multiplier()`, `damage_multiplier(index)`, `skill_interval(index, skill_id, fallback)` (an entry's `skill_intervals` override, else `fallback`), `can_act`, `begin_action`, `prepare_actions`, `action_snapshot`; public `entries` and lifecycle `records`, owned as `RunWorld.bosses` |
| `BossAttacks` | Scheduled bosses' selected canonical attacks (`stage.maps[].boss.attacks`), cadence and scaling | `step(world)`, `area_at(range_data, pos, facing)`; owned as `RunWorld.boss_attacks`, shares `BossDirector` action gate; the windup/impact code is `MobAttacks`' static half |
| `MobAttacks` | The shared canonical type 0/1/2 attack code (`plan`, `service`, `emit`, `area_at`) and ordinary mobs' attacks (#76) | `step(world, dt)`, `reset_slot`, `move_slot`, `resize`, `wait_left(slot)`, static `attack_names(img)`, `first_wait(interval, identity)`; owned as `RunWorld.mob_attacks`; per-slot waits in a packed array, pending windups keyed by slot and checked against the swarm identity |
| `MobActions` | Ordinary mobs' authored attack stances per slot in packed arrays, and the composed per-slot action view | `begin`, `busy`, `reset_slot`, `resize`, `view(boss_view, bosses, swarm, now)`; owned as `RunWorld.mob_actions`; `RunWorld.mob_action_view()` is what MobSwarm and MobRenderer read |
| `MobProjectileSystem` | Monster type-2 balls as pooled packed arrays, separate from player shots | `spawn(spec)`, `step(dt, world)`, `active_count()`; captured source/damage metadata, swept player collision through take_hit; an ordinary ball that `RunWorld.hit_window_blocks(source)` turns away is not consumed and flies on (spec #88), while boss balls ignore the window; same ProjectileRenderer drawing interface |
| `RunWorld` | Owns one deterministic round across its maps | `_init(setup)`, `step(dt, input)`, `events`, `time`, `kills`, `state` (PLAYING / CHOOSING_UPGRADE / DEAD / CLEARED); `job_id()` the character's fixed job, written only by `set_job(job_id)` (#284: once at construction from the character, `setup.job` or `JobTree.default_job()`; tests call it to stand other lines); TIMEOUT is a harness outcome while the sim remains PLAYING; `skill_readiness(key) -> {left, total}` is the HUD's per-skill cooldown sweep data (Teleport: its repeat timer); `read_skill_cooldowns(left, total)` writes the same for every owned skill into the caller's reused Packed arrays (the HUD's allocation-free per-frame feed) |
| `BotInput` | The autoplay bot (RunScene `autoplay`/`autopick`, the full-run tests, `scripts/balance.sh`, the benchmarks): kites (melee builds close to their attack reach instead, #162: `SkillRunner.reach_of`), collects drops, climbs or uses same-map portals, picks cards | `decide(world, memo) -> MoveInput`, `auto_choose(world, first_card := false)`, `pick_card_for(world, cards)` |
| `BotShop` | What the bots do with equipment and mesos (spec #33, #112), beside `BotInput`: wears the best item it owns, and plans and applies one Free Market visit through RunWorld's equip/shop API. Used by `balance_run.gd` (mid-round and between `--tier` rounds), RunScene's autoplay and `FreeMarket.bot_shop` | `auto_equip(world) -> int`, `equip_trigger(events)`, `plan(character, stock, facts, policy, rng) -> {sell, steps}`, `visit(world, policy, rng) -> record`, `character_of / stock_of / facts_of(world)` |

Player projectile hit exclusion uses `MobSwarm.identity`, a packed 64-bit logical identity independent of the
reusable slot index and canonical mob-kind ID. Each fresh `MobSwarm.spawn` receives the next run-local identity;
pool growth preserves existing identities. `RunWorld.relocate_mob` retains the original logical identity while
moving its state. ProjectileSystem's packed 64-bit already-hit list remembers these identities, so a relocated
mob cannot be hit twice by the same shot, while an unrelated fresh mob reusing its slot remains hittable.
Events, spatial hashes, kill lists and other per-slot state still use slot indices; event schemas do not change.
This is engine bookkeeping (tier C), with no per-entity allocations and no balance/stat changes.

### Map transfer within a round (#241)

`RunWorld` remains one world and one set of seeded streams per round. `map_index` is zero-based,
`current_map_id()` retains the v83 id, `map_entered_at` is total round time at entry and `map_times` retains each
reached map's entry seconds (starting `[0.0]`). `time` never resets. `curve_time()` is
`map_index * map_seconds + (time - map_entered_at)`; every SpawnDirector clock uses it. BossDirector arms only
the current map's boss at entry + 300 s, retaining `map_index`/`map_id` on every lifecycle record. StagePools
resolves current-map life weights/exclusions or an explicit pool; curve pools stop selecting keyframes at 300 s.

On an intermediate boss death, RunWorld freezes combat, sweeps all drops once using the finale rules, removes
ordinary mobs without drops or kill credit and resolves the existing choice queue. Once answered it sets
`transfer_pending` and emits `map_cleared`. While pending, `step()` does nothing and time stays frozen.
`advance_map()` loads the next prepared map root, draws a random `sp` arrival on existing spawn stream 2, rebuilds
map state, records entry time, clears boss-inflicted statuses and emits `map_entered`. The last map uses normal
finale settlement. No stream is renumbered; stream 7 stays reserved.

| Per-round state retained at transfer | Per-map state rebuilt or cleared |
|---|---|
| HP, level/EXP/job/AP, loadout, buffs, Hidden, auto-cast timers, skill/manual and potion cooldowns, equipment/inventory, mesos, pet, RNG streams, time, kills/damage, boss history and aggregate counters | Footholds, bounds, ladders, navigation, portals, spatial hash, mobs, projectiles (player and monster), pickups, attacks/actions, per-slot statuses and motion; boss-inflicted player statuses clear |

SpawnDirector retains round counters and scheduling clocks while selecting the new map's pool. Cooldowns and buffs
remain on their deterministic clocks through the frozen transfer; HP do not refill. Headless drivers advance
immediately. RunScene holds the CLEAR notice, fades out, draws one black frame, advances, reloads map/camera/mob
layers/actors/BGM, fades in and shows the destination name. Pause/in-run windows hold the presentation clock.
The bot's navigation memo clears on arrival. There is no live-world save at a map transfer: Continue always
reconstructs map 1 from the existing round-boundary character and seed (ADR 0001).

Balance records carry `map_times`, `ended_map: {index, id}` and `boss_fights[].map_index/map_id`. The playtest
`summary.json` includes `map_times` and `ended_map` both at its root and within `summary`; RunScene's existing
map_id/map_name/street_name fields identify the ending map. SUMMARY counts deaths by one-based map number and
reports entry seconds for maps 2 and 3 with observation counts. Legacy records contribute no invented map data.
`flow_driver --scenario=redesign` exercises the real map transitions and the hub; diagnostic invulnerability and post-timer
boss hits make this flow evidence rather than balance evidence.

### 4.4.1 Run setup (what `RunWorld` is built from)

The sim never reads files. `RunScene` (presentation) builds a setup Dictionary from the asset cache and `res://data`:

```gdscript
var setup := {
	"map_img": Dictionary,            # first map root (cache JSON), compatibility alias of map_imgs[0]
	"map_imgs": [Dictionary, Dictionary, Dictionary], # index-aligned stage.maps roots, loaded once
	"physics_img": Dictionary,        # Map.wz/Physics.img root
	"mob_imgs": {100100: Dictionary}, # Mob.wz/<id>.img roots, info/link already followed by the loader: every id of
	                                  # StageRoster.mob_ids (pools, bosses, and the bosses' canonical summon/revive ids)
	"skill_imgs": {"000": Dictionary, "200": Dictionary, "210": Dictionary},  # Skill.wz/<book>.img roots
	"equipment_info": {1040002: Dictionary, 1060002: Dictionary, 1072001: Dictionary,
		1302000: Dictionary, 1372005: Dictionary}, # canonical Character.wz info of Equipment.DEFAULT_OUTFIT, the
		                                       # weapon_grants wand, every MakeCharInfo top/bottom/shoes/weapon and
		                                       # every item setup.character holds (DataRepo.starter_equipment_ids),
		                                       # keyed by original item id; req*, attackSpeed, afterImage, sfx
	"body_img": Dictionary,           # Character.wz/00002000.img, exact stance frame delays
	"afterimage_imgs": {"swordOL": Dictionary, "mace": Dictionary}, # Character.wz/Afterimage roots the worn weapons'
	                                  # canonical info/afterImage names (WeaponInfo.afterimage_name)
	"mob_skill_img": Dictionary,      # Skill.wz/MobSkill.img root, including each skill's level tables
	"item_info": {2000000: Dictionary, 2000003: Dictionary}, # canonical Consume item nodes (info icons + spec) of
	                                  # DataRepo.potion_item_ids: starting item ids + the potions.schedule items
	"data": {"skills": {}, "upgrades": {}, "stages": {}, "balance": {}, "mobs": {}, "jobs_survivor": {},
		"jobs": {}, "exp_table": {}},   # parsed game/data/survivor/*.json and game/data/canonical/*.json
	"stage": "henesys",           # key in stages.json
	"seed": 12345,
	"view_size": Vector2(800, 600),   # the live logical view, get_viewport().get_visible_rect().size (800x600 on 4:3,
	                                  # 1066x600 on 16:9, more with fill_window; see 4.5); RunWorld keeps a
	                                  # player-centred view rect of this size for spawn logic
	"character": Dictionary,          # optional CharacterSnapshot (see 4.5); its `cash` ({slot: id}) and `pet` (species)
	                                  # are what the character wants to wear / bring out
	"account": {"owned": [1002469, 5000000]},  # optional (spec #34): the account's owned cash item ids, absent = an
	                                  # empty account; `nx` is never part of the setup, only the save credits it
	"alert": {"hp": 0.3},  # optional: HP ALERT fractions the pet's auto potions follow, absent = 0
}
```

The account reaches the sim only as plain data: `setup.account.owned` filters `character.cash` and `character.pet` to what
the account owns (`CashCatalog.resolve`), and the result is `RunWorld.worn_cash`, `RunWorld.pet` and, with a pet out,
a `PetSystem`. Fortune from cash slots is computed live (`RunWorld.cash_fortune`, added to `player_state.fortune`) and never
written back to the character. Where `account` and `alert` come from: a persistent round (`SceneFlow._resume_round`)
passes `SaveData.account` and the settings' ALERT levels; a tool round (`RunScene` `options.account`, from
`--account=<json>` through `AccountFile.load_file`/`apply`) uses the file's `owned`/`cash`/`pet`/`alert` and ignores
its `nx`. Without either, the setup has no `account`, nothing is worn and no pet exists, which keeps every record
byte-identical to a round without the feature.

The money side lives outside the sim. A finished round's summary carries `nx_awarded` (`NxAward`, from `bosses_killed` and
`levels_gained` and `balance.nx_award`); `SceneFlow` credits it to `SaveData.account` in the same atomic write as the
clear's round-boundary snapshot or the death/victory run archive, and only for persistent rounds. The Cash Shop
(`scenes/ui/cash_shop.gd`, rules in `scripts/core/cash_shop.gd`) and the Equip window's Cash tab and Pet page edit
`account.owned` (buy) and the slot's `character.cash` / `character.pet` (wear, bring out) and save at once.

Tests build the same Dictionary from synthetic data. `scripts/core/data_repo.gd` loads the JSON files (outside sim).

### 4.4.2 Pause protocol

`RunWorld.state` is one of `PLAYING`, `CHOOSING_UPGRADE`, `DEAD`, `CLEARED`. `step()` advances the
world only while `PLAYING`. When EXP crosses one or more levels, the world queues them. For each queued level it
enters `CHOOSING_UPGRADE` and emits `choice_pending` (there is no job advancement, #284). Draws return up to three
distinct eligible cards of the character's job line (`UpgradePool.on_line`); if fewer
than three are available, they include one Power Elixir fallback alternative. An exhausted pool therefore
still opens a one-card window rather than consuming the level silently. The fallback is separate from the
weighted `upgrades.cards` pool in `upgrades.fallback`.
The presentation layer shows the windows and calls back:

| Call | Effect |
|---|---|
| `apply_choice(card_id)` | apply the card (emits `upgrade_applied`), then the next queued level, else settle a completed objective or return to `PLAYING` |

Level-up effects and their short pause before the window are presentation-only. Boss bonus picks use
`CHOOSING_UPGRADE` with `RunWorld.choice_bonus` and `pending_bonus_choices`; they take priority over the level queue.
`apply_choice` consumes a bonus without changing the level or queue. Exhausted bonus draws offer Power Elixir
and still require a choice before clear.
The bonus window uses a "Boss Reward" title and omits the gained-level notice.

Tier C owner finale policy (2026-10-21, MS-07/MS-08): after the last mandatory answer, an already completed objective
settles synchronously, before any further `step()` can advance combat or time. `PickupSystem.collect_all(events,
equip_room)` collects remaining drops in ascending pool-slot order without motion/expiry, using the same accounting,
`pickup_collected` events and despawn path as `step()`. RunWorld credits them through its ordinary meso,
equipment and auto-wear paths, then feeds their EXP through `_gain_exp` and the existing choice queue.
Auto-wear that frees inventory room triggers another sweep pass without advancing time. These choices
keep the sim frozen; their final answer retries settlement (including equipment spilled by job grants), then enters
`CLEARED` and emits one `stage_cleared`. Equipment without inventory room retains the ordinary blocked-on-ground
rule and notice; it does not stall clear. Death during the active combat tick still takes priority over settlement.
The duration fallback for bossless stages also waits for all choices. Warp mode drains terminal events emitted by
auto-choice calls even when no subsequent sim step runs.

### 4.4.3 Event schema

`RunWorld.events` is an `Array` of Dictionaries appended during `step()` (and during the calls above) and cleared by
the presentation after it drains them. `mob`, `proj`, `pickup` are **sim slot indices** (valid only for the frame);
`mob_id`, `skill_id`, `item_id`, `job_id` are **original MapleStory ids**; `skill` is the survivor skill key from
`skills.json`; visual fields are **WZ paths** into the asset cache.

| type | fields |
|---|---|
| `skill_ground` | `skill`, `pos`, `box`, `effect`, `duration`: anchored area art |
| `summon_spawn` | `skill`, `slot`: new player ally |
| `summon_attack` | `skill`, `slot`, `pos`: ally attack animation |
| `cast` | `skill`, `skill_id`, `level`, `pos`, `facing`, `action` (body stance to play when standing, e.g. `"swingO1"`), `effect` (WZ path of the caster effect or `""`) |
| `boss_skill` | `mob`, `mob_id`, `skill_id`, `level` (ints), `pos` (boss feet Vector2), `facing` (int), `action`, `effect`, `player_effect`, `summon_effect`, `recipient_effect` (Strings; WZ paths or empty), `duration` (float seconds), `targets` (Array of int mob slots receiving buffs or summoned; empty for delayed heal); emitted at cast/stance/effect initiation, with delayed healing later reported as `mob_healed` |
| `player_banished` | `mob`, `mob_id`, `skill_id`, `level` (ints), `from`, `pos` (the character's feet before and after, Vector2), `effect` (WZ path of the `affected` art or `""`), `message` (notice text or `""`); a boss's Banish (MobSkill 129, #256) moved the character to a random `sp` portal of the current map; emitted before that cast's `boss_skill`, after the pet's `pet_teleported` when a pet is out |
| `player_restored` | `stat` (`hp`/`mp`), `amount` (actual positive integer pool gain after capping), `skill` (key or empty), `pos` (player feet); emitted by `restore_player`, independent of legacy Recovery/potions |
| `final_attack` | `skill`, `skill_id`, `level`, `mob` (the original target's slot), `pos`, `facing`, `action` (the skill's stance), `effect` (WZ path or `""`); emitted just before the follow-up's own `mob_hit` (skill = the Final Attack key; #161) |
| `buff_cast` | `skill`, `skill_id`, `level`, `duration` (float canonical seconds); also emits ordinary `cast` for stance, effect and sound |
| `buff_expired` | `skill`, `skill_id`; once when an active timer expires (or a buff ends early: Oak Barrel above its `end_hp_above`); a run ending first need not emit expiry |
| `buff_failed` | `skill`, `skill_id`, `level` (#194); a buff cast with a `fail_chance` (Oak Barrel) whose roll failed: nothing started, cooldown was paid, the accompanying `cast` event has `effect` `""` |
| `buff_pulse` | `skill`, `skill_id`, `amount` (canonical integer healing due; the HP gain is clamped to max). Recovery's final pulse precedes its expiry; Guard/Armor have no pulses. |
| `mob_spawned` | `mob`, `mob_id`, `pos`, `elite`, `relocated_from` (the slot the mob had when SpawnDirector relocated it, -1 for a new spawn) |
| `mob_hit` | `mob`, `mob_id`, `damage` (int), `crit`, `pos` (where to draw the number: mob head), `hit_visual` (WZ path or `""`), `skill` |
| `mob_status_applied` | `mob`, `mob_id`, `status` (`slow`, `poison`, `freeze`, `threatened`, `stun`), `duration` (float canonical seconds); reapplication emits again and refreshes |
| `mob_status_expired` | `mob`, `mob_id`, `status`; natural timer expiry only; death/release/relocation clears silently |
| `mob_died` | `mob`, `mob_id`, `pos`, `exp`, `elite` |
| `player_hit` | `damage` (int), `miss` (bool), `dir` (-1/1), `pos`, `mob` (source slot, -1 when unspecified), `mob_id` (source id, 0 when unspecified), `boss` (bool), `max_hp` (HP pool at hit time), `source_kind` (String: `touch`, `attack`, `projectile`, or `other` for a direct unspecified source). Whole damage/max_hp supports encounter metrics. A miss spends no HP and gives no knockback/invincibility. |
| `player_jump` | `pos` |
| `portal_used` | `portal` (source `pn`, String), `target` (destination `pn`, String), `pos` (arrival feet, Vector2) |
| `player_died` | `pos` |
| `pickup_spawned` | `pickup`, `item_id`, `pos`, `kind` (exp/meso/equip), `potion_kind` (empty compatibility field), `count` (meso amount; 1 for equipment, whose `item_id` is the equipment id; 0 for EXP) |
| `pickup_collected` | `pickup`, `item_id`, `exp`, `pos`, `kind` (exp/meso/equip), `potion_kind` (empty compatibility field), `count` (meso amount; 1 for equipment), `collector` (`player`, including the finale sweep, or `pet` when the pet's pickup radius or VAC took it; credited the same, mesos and equipment included) |
| `pickup_blocked` | `pickup`, `item_id`, `pos`, `reason` (`inventory_full`): an equipment drop meets a full Equip tab during magnet pickup or finale settlement; once per approach (or settlement attempt until room changes), the drop stays on the ground |
| `potion_used` | `kind` (hp/mp), `item_id`, `restored` (actual integer gain after clamping); no `count` |
| `pet_potion_used` | same fields as `potion_used`, for the pet's Auto HP Potion Pouch drinks (counted apart from the player's) |
| `pet_teleported` | `from`, `pos` (the pet's feet): it jumped to the player; a renderer snaps instead of interpolating |
| `potion_tier_up` | `kind` (hp/mp), `from_item_id`, `item_id` (new current item; cooldown preserved): one per `potions.schedule` step applied at a level-up (never on a snapshot load). `RunScene` shows "Your Red Potions are now Orange Potions." from the String.wz item names |
| `ammo_upgraded` | `family` (bow/crossbow/claw/gun), `from_item_id`, `item_id` (the new ammo, Item.wz id), `level` (character level): the held ranged weapon's endless ammo moved to a higher tier (#155) on a level-up or on advancing into the branch; a weapon swap and the first computation are silent. On a level-up it comes before `level_up` (the caster refresh runs inside the level-up). `RunScene` shows "Your throwing stars are now Ilbi Throwing-Stars" |
| `skill_thrown` | `skill`, `skill_id`, `from` (the hand), `to` (the aim point, the target mob's body centre), `seconds` (the flight), `ball` (the flight art path), `burst` (the blast art path): a Gunslinger Grenade (cast rule `cluster`, #192) left the hand on the cast tick. `RunScene` records that tick's world time, loops the ball indefinitely until landing, and interpolates its arc inside consumed sim ticks; hitches and choice holds cannot complete it |
| `skill_landed` | `skill`, `cast_time` (float, authoritative throw tick; together they identify the flight), `pos` (captured aim point, Vector2), `effect` (captured burst art path): emitted immediately before Grenade damage resolution, including when no targets remain. Stops the matching ball and starts the blast; damage/RNG ordering is unchanged |
| `skill_impact` | `skill`, `pos` (struck mob's feet before hits), `effect` (blast art path): an opt-in projectile impact blast (#200), followed by ordinary `mob_hit` events for the primary and splash targets. `RunScene` plays the effect at the captured position |
| `ammo_shot` | `skill`, `from` (hand), `to` (target body centre), `seconds` (distance / current ammo speed), `ball` (current ammo sprite path), `rotate` (bool): a presentation-only ranged Final Attack flight (#200). Damage already lands during this tick on stream 12; the visual follows a straight line using pooled effects and cannot hit again |
| `level_up` | `level` |
| `choice_pending` | `bonus`, `cards`: card id, kind/category, skill, rank step, mapped WZ levels, rarity bonus and before/after previews; active Mastery grants only a diminished bonus, common passives always stay Normal |
| `upgrade_applied` | `id`, `rank`, `tier` (displayed Potential tier), `magnitude` (actual ranks/steps/starting rank) |
| `skill_learned` | `skill`, `skill_id` |
| `burst` | `count` (a spawn burst started) |
| `stage_cleared` | `time`; emitted once after objective, sweep and all mandatory choices finish, possibly directly inside `apply_choice`; follows the sweep's ordinary pickup/level/job/card events and admits no later combat tick |
| `boss_warning` | `boss_index` (schedule index), `mob_id`, `time` (warning tick) |
| `boss_spawned` | `boss_index`, `mob` (slot), `mob_id`, `pos`, `time` (arrival tick); also emits the ordinary `mob_spawned` event for rendering |
| `boss_died` | `boss_index`, `mob`, `mob_id`, `pos`, `time` (death tick); precedes the final clear decision |
| `boss_attack` | `boss_index`, `mob`, `mob_id`, `attack` (canonical stance, e.g. attack1), `phase` (`start` / `effect` / `impact`), `pos` (captured feet), `facing`, `area` (Rect2, captured world-space range), `time` (event tick), `impact_time` (absolute planned sim time), `effect`, `sound` (WZ paths, effect may be empty). Start holds the stance and plays sound; effect phase starts art; impact tests the current player position/grounded state. |
| `mob_attack` | An ordinary (non-boss) mob's attack (#76): the `boss_attack` fields without `boss_index`, same phases (`start` / `effect` / `impact` / `hit`). `hit` (the hit art) is not emitted when the hit window turns the attack away at impact (#144, tier C); no `player_hit` either. A rolled MISS still emits `hit` |
| `mob_projectile_spawned` | `proj`, `mob`, `mob_id`, `pos` (muzzle), `velocity` (Vector2 px/s), `range`, `speed` (float), `ball`, `hit` (WZ paths), `time` |
| `mob_projectile_hit` | `proj`, `mob`, `mob_id`, `pos` (swept contact), `hit` (WZ path), `facing`, `time`; emitted on first body contact that consumes the ball, also when a MISS prevents damage; not emitted (and the ball flies on) when the hit window blocks an ordinary ball, `RunWorld.hit_window_blocks(source)`; boss balls ignore the window |
| `mob_healed` | `mob`, `mob_id`, `skill_id`, `level`, `amount` (actual restored HP after max clamp, int), `pos` (feet), `time` (resolution tick) |
| `mob_revives_spawned` | `boss_index`, `mob`, `mob_id` (dead source IDs), `pos` (source feet), `revives` (ordered Array of `{mob: int, mob_id: int}` living offspring), `time` (death tick); one event per canonical death list |
| `equipment_changed` | `action` (`equip`, `unequip`, `discard`, `grant`, `pickup`, `auto_equip`), `slot` (equip slot, `""` for a discard), `item_id`; after the derived stats were refreshed; the presentation redraws the worn look. Emitted by `equip_item`, `unequip_item`, `discard_item`, a job's weapon grant in `change_job` (the Magician's wand, a weapon path's weapon, a second job's branch weapon; #157) and an equipment pickup (`slot` `""`, `item_id` the new item); a pickup whose slot is empty and whose requirements are met is followed at once by `auto_equip` (`slot` the worn slot, `Equipment.auto_wear_error`, #222) |
| `teleport` | `skill`, `skill_id`, `level`, `phase` (`departure`/`arrival`), `pos`, `facing`, `effect`; fixed world positions for the manual player blink |
| `boss_teleported` | `boss_index`, `mob` (current slot), `mob_id`, `pos` (arrival), `time`; also emits `mob_spawned` with relocation identity |

ADR 0006 #288 extends each choice card with `card_kind` (including `mastery`), `slots` (display summary),
`skill_rank_before` (survivor rank, distinct from canonical `skill_level`) and `rarity_bonus` (empty or
`{id, text, counter, effects: [{stat, op, value}]}`). `skill_mod_changes` also previews rarity effects on new/rank/Mastery
cards. Pool-active new/rank magnitude is always 1; at rank 8 Mastery reuses the rank-card id with magnitude 0 (a Normal Mastery carries the shared `mastery_damage` bonus, +5% damage).
The rolled active rarity is preserved; passive rarity is Normal. Bonus repeat counters live in the round loadout's
`card_ranks` under `bonus:<skill>:<bonus-id>`; schema and diminishing rules are in GAME_DESIGN 8.



`RunWorld.bosses.records` has one row per stage boss: `{boss_index, mob_id, map_index, map_id, slot, warned, arrival, spawn_time,
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
duration rule retained for stages without bosses. Clears defer until all bonus and queued level choices finish,
then sweep ground drops and resolve any additional choices without another combat tick (4.4.2).



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

`stage.maps[].boss.attacks` selects canonical attack stances. `BossAttacks` handles `info/type = 0`, capturing area and
facing at windup, starting art at `effectAfter`, and resolving damage at `attackAfter` (milliseconds converted to
seconds). It reads attack-local PADamage/MADamage rather than contact attack and calls `take_hit` with
`source_kind = attack`. `attack_dmg_mult` is separate from contact `dmg_mult`; `attack_interval` is a survivor
start-to-start cadence because these attack nodes contain no interval. A canonical `jumpAttack` flag opts into
the tier-C airborne-at-impact dodge. Dead bosses cancel pending impacts. Attack frames/metadata remain as cached.
An explicit `magic=1` also selects magic damage, falling back to mob MADamage when no local attack value exists.
Effects and impacts have separate completion flags: an effectAfter later than attackAfter is preserved once.
The `boss_attack` hit phase carries the canonical hit path in `effect` at the character's current feet.

**Shared mob attack path (#76).** The windup/impact code above lives in `MobAttacks` as static functions
(`plan`, `service`, `emit`, `area_at`); `BossAttacks` keeps only the boss loop (which attacks, `attack_interval`,
`attack_dmg_mult`, the BossDirector action gate). `MobAttacks.step` runs the same code for ordinary mobs: every kind
whose Mob.wz img lists `attackN` with type 0, 1 or 2 (scheduled-boss kinds and slots with `mob_boss >= 0` excluded)
tries its attacks in canonical order and starts the first whose range admits the character. A slot's wait (packed
`_wait`) counts down only while the mob can act (fully faded in, not frozen) with its feet inside `RunWorld.view`;
the first wait is 50-100% of the interval by the golden-ratio fraction of the swarm identity (`first_wait`, tier C),
later waits the full `balance.mob_attacks` interval. A start also needs the mob grounded and not busy. Pending
windups are keyed by slot and carry the swarm identity; a dead, reused or relocated slot drops its windup. Hits use
`source_kind = mob_attack` (balls from ordinary mobs too, through MobProjectileSystem's `ordinary` flag), `boss =
false`, the elite flag, and `dmg_mult` from `balance.mob_attacks.mobs[id]`; events are `mob_attack`. Ordinary
stances live in `MobActions` (packed per-slot arrays); `RunWorld.mob_action_view()` composes them with
`BossDirector.action_snapshot` for MobSwarm (hold ground/facing) and MobRenderer, and returns the boss snapshot
itself while no ordinary stance is live. Ordinary mobs cast no mob skills: character statuses come only from bosses
(owner, #76), so `MobSkillRunner` runs scheduled bosses only. Per-slot waits and stances reset in `spawn_mob` and move
(waits) or reset (stances, windups) in `relocate_mob`.

Type 1 is a targeted direct strike (tier C, not verified v83 RE): acquisition checks the character body centre
within `range/r` of the mirrored `range/sp`. Once admitted, the single character is locked; `attackAfter`
resolves through normal take_hit regardless of escape or jumping, without a projectile or second range test.
Death/fade cancellation, defence, avoid, invincibility and Magic Guard still apply. The canonical effect plays
at the caster at effectAfter, the hit art at the character on impact. Details: `docs/research/dark-cave-boss-attacks.md`.

For type 2, `range/r` is the acquisition radius and travel range; `range/sp` is the mirrored muzzle offset.
At attackAfter, a ball aims at the player's current body centre and travels straight (tier C). The adopted unit
conversion is `bulletSpeed × 1000/600` px/s, equivalent to `r × 600/bulletSpeed` ms flight; this interpretation
is tier C, inspired by a later-client reference, not verified v83 client RE. WZ fields remain unchanged.
Absent/nonpositive bulletSpeed uses `balance.mob_projectiles.default_speed` (320 px/s, tier C) instead.
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
`exp_mult`, `exp_drops`, `spread`, `bonus_choices`. The total is rounded
canonical boss EXP × reward multiplier, split with integer remainders conserved. Scheduled bosses bypass ordinary
EXP rolls. Bosses drop two guaranteed equipment items; no potion drops exist (spec #237). Reward scattering has its own seeded RNG stream.



The ordinary spawn accumulator and burst count use `BossDirector.normal_spawn_multiplier()`. Elite scheduling
remains separate. A positive stage `post_duration_slope` extrapolates the final keyframe segment past its end,
the burst size past the stage duration (`burst_count_at`) and shortens the elite interval by the extrapolated rate
ratio (`elite_interval_at`); ordinary alive targets still obey `hard_cap`.

Swarm visuals are read from state, not events: `MobSwarm` arrays (`kind` -> `RunWorld.mob_kinds[kind].id`, `state`,
`state_t`, `facing`, `alpha`, `x`, `y`), `ProjectileSystem` arrays (`active`, `x`, `y`, `vx`, `vy`, `visual` ->
`RunWorld.visual_paths[visual]`, `rotate`, `generation`), `PickupSystem` arrays (`active`, `x`, `y`, `item_id`), and
`RunWorld.player` / `RunWorld.player_state` (`hp`, `max_hp`, `exp`, `level`, `job_id`,
`str`, `dex`, `int`, `luk` (integer attributes), `pdd`, `mdd`, `avoid` (equipment-derived defense and avoidability),
`fortune` (survivor card-tier stat from `balance.player.fortune`, separate from LUK),
`invincible_t`, `action`, `action_t`, `dead`, plus detached `buffs`, `slow` and `potions` snapshots described below).
The snapshot's `pdd`/`mdd` are base equipment/stat defense; active Armor additions are applied by `hit_defense()`.
Both player and monster projectile pools expose packed int64 `generation`, incremented on each slot spawn. The shared
renderer restarts a slot's animation when its generation changes, even if despawn/respawn happened between draws.

Player-inflicted monster statuses live in one `MobSwarm` status table: packed `status_left` (seconds left, doubles)
and `status_elapsed` (art clock), indexed `slot * STATUS_COUNT + status` with `SLOW = 0`, `POISON = 1`, `FREEZE = 2`,
`THREATENED = 3` (Page Threaten, #183) and `STUN = 4` (#187), `STATUS_COUNT = 5`, plus `slow_factor`, the Threaten cut arrays `threat_pad`/`threat_pdd` (read through
`threatened_pad`/`threatened_pdd`, applied in `RunWorld.mob_weapon_attack` (touch and `MobAttacks._impact`), `RunWorld.mob_defense` and the
bulk `lower_threatened_pdd`) and private poison pulse/damage/source arrays. The `crowd` cast rule takes its status from
the skill's `cast.status` (`SkillRunner.crowd_status`, "slow" by default; `MobSwarm.can_crowd_cast`); Threaten has no
`prop`, so it draws no random number and RNG stream 13, reserved for spec #165, stays unused. `status_time(slot, status)` reads a timer. The shared entry
point is `apply_status(slot, name, params, events) -> bool` (`name` from `STATUS_NAMES`); `params` contains canonical
`time`, signed Slow `x` (Threaten: signed `x` PAD and `y` WDEF), or poison skill `level`, an optional survivor `skill` key and an optional `element` overriding
the status default (`STATUS_ELEMENTS`: Poison `S`, Freeze `I`, Threatened none). Stun ignores even a supplied element;
bosses reject every status. Other statuses fail when the Mob.wz element digit is 1, 2 or 4 (`MobKind.resists_status`). `step` receives the current event list in
`ctx.events`, advances status timers after movement and emits poison `mob_hit` events; it visits only a compact
list of statused slots, and no status means no status pass at all. `RunWorld.damage_dealt` is a getter summing shots, instant hits and `swarm.poison_dealt`.
`has_statuses()` lets presentation skip status work. `can_act(slot)` (settled, not frozen or stunned) gates monster touch
damage as well as boss attacks/skills. Release, death and relocation clear these player-inflicted
statuses; the existing `MobSkillRunner` monster buffs still transfer on relocation. `MobRenderer` uses pooled cached
Slow/Poison/Threaten/Stun art and status tints; frozen state/animation clocks do not advance, though a frozen airborne monster still
falls and a fading-in one keeps fading in. Stunned monsters stand without moving or flinching, keep their animation clocks,
and fall straight down when airborne; a refresh keeps the longer remaining duration.

Disorder (#210) reuses Threatened with additive crowd parameters: `cast.box` (WZ-shaped lt/rb) and `cast.mob_count`
are Loadout fallbacks only when their canonical fields are absent. After a successful application, `cast.interrupt`
calls `MobAttacks.interrupt(world, slot)` to remove a pre-impact pending attack and reset its MobActions stance,
preserving the existing per-slot wait. No status or player-state fields are added. A crowd skill's optional `hit`
art emits `skill_mob_effect {skill, mob, pos, effect}`; RunScene plays it once without damage numbers or mob hit sounds.
Threaten has no interrupt flag or hit art, so its events and behavior are unchanged. GAME_DESIGN 7.22.

`MobKind.elements` parses canonical `elem_attr` once; `element_multiplier(letter)` is case-insensitive and neutral
for absent elements. `undead` exposes the canonical flag. `Loadout.stats().element` comes from Skill.wz `elemAttr`;
shots retain it in a packed string array. Instant and projectile hits share `ProjectileSystem.roll_damage`'s final
element multiplier, including zero immunity before the normal minimum-one clamp.

### 4.4.4 Survivor data files (`game/data/survivor/`)

ADR 0006 removes weapon paths and advancement. `balance.player.ap` has one row per job; lookup follows
canonical lineage to the nearest configured ancestor. The held weapon never selects an AP row.
`Loadout.stats` defaults projectile `count` to canonical `bulletCount`, and `range` to canonical `range`, when their
survivor overrides are absent. For a box cast, optional `cast.around:true` mirrors its far horizontal edge across the
player while retaining canonical height (Somersault Kick; tier C). `RunWorld.pirate_rng` owns stream 16; stream
13 belongs to Threaten (no v83 prop, so unused); 14 remains reserved for Bowman; stream 15 is `RunWorld.thief_rng`
(#207), used only for Steal success (#214). Stream 17 is `RunWorld.banish_rng` (#256), used only for Banish's
destination portal draw. Existing stream initialization and other draws are unchanged.
Bandit attacks add `steal: {chance_field: "prop"}` to the instant skill definition. A damaging-hit listener rolls
stream15 before damage/kill resolution, then calls `RunWorld.drop_mob_loot(m, true)` and marks `MobSwarm.stolen`
(PackedByteArray). This is not a status: boss immunity does not apply. Logical relocation preserves it, fresh spawns
reset it. `drop_mob_loot(m)` retains ordinary death meso/equipment rolls; its single-item variant uses the ordinary
equipment chance and job/held-family pool, with a normal meso bundle fallback. Content draws stay on streams9/10.

| File | Contents |
|---|---|
| `skills.json` + `skills/<line>.json` | survivor behaviour per skill key (line fragments, see below): canonical `skill_id`, `book`, job, kind (projectile / instant / passive / buff), cooldown, range, speed, count, pierce, rank -> canonical level map, `level_ranks`, buff effect fields and canonical time/cooltime, survivor pulse interval and HP threshold, optional `weapon_families` (family names or `["any"]`; overrides the Skill.wz `weapon` requirement, GAME_DESIGN section 7), visuals and sounds |
| `upgrades.json` + `upgrades/<line>.json` | upgrade cards (`GAME_DESIGN.md` §8, in the line fragments), `power` flags, the `pity` rule, rarity, magnitudes and the fallback Elixir (base) |
| `equipment_drops.json` + `equipment_drops/<line>.json` | the drop rules (chance, boss drops, boss_top_parts; base) and the eligible equipment ids (fragments) |
| `scrolls.json` + `scrolls/<line>.json` | the scroll roster: item slot -> family -> rate -> item id (fragments) |
| `shops.json` + `shops/<line>.json` | the Free Market scroll NPCs, prices and talk range (base) and the weapon-priced slots (fragments) |
| `stages.json` | region stage key -> ordered `maps` (map_id, pool rule, boss with relative time/mob_id/hp_mult/dmg_mult), `map_seconds`, duration, pacing keyframes, bursts, elites, `spawn`, `exp_mult`, note and `post_duration_slope`; no top-level map_id/bosses. StagePools derives life pools; StageRoster derives boss summon/revive ids |
| `balance.json` | EXP curve, player base attributes, automatic AP and job primary-stat rules, worn equipment ids and job weapons, cast origin / `cast_forward`, HP growth per job, the shrinking `hit_window`, knockback, magnet, drops (incl. `lifetime`), spawning (incl. `band_y`, `prefer_route`, `stall_time`, `trail_margin`), mob speed factor, `mob_motion` flyer bob amplitude/period passed to MobSwarm |
| `mobs.json` | per-mob survivor overrides (EXP drop item id, HP/speed multipliers, `can_jump` override) |
| `jobs.json` | Playable jobs, fixed starting and mobility skills, active skill pools, allowed weapon families and creation weapon |
| `ammo.json` | endless ammo (#155): per ranged weapon family the starting ammo item, its notice noun and projectile numbers, and the specialist branches' level schedules (`Ammo`; the setup key `ammo_info` carries the Item.wz incPAD of every ammo item, `DataRepo.ammo_info`) |
| `cash_items.json` | the Cash Shop catalog (id, kind equip / pet / pet_upgrade, NX price, Commodity SN, prerequisites) and the tier C Fortune each cash slot adds (`CashCatalog`, spec #34); the account and the worn items reach a round as setup keys `account` / `alert` and the CharacterSnapshot `cash` / `pet` keys |

**Job-line fragments.** The five files above that name `<line>.json` are a base file (`_doc` and the job-neutral, non-entry config) plus one fragment per job line in a directory beside it (`survivor/skills/magician.json`). `DataRepo.load_all` returns the merged result under the same `setup.data` keys as before, so nothing downstream knows about the split. The fragments are probed by name, in the fixed order `DataRepo.LINES` = common (job-neutral), beginner, warrior, magician, bowman, thief, pirate (job-line id order after common), then the class lines in the order their specs landed (hero, #296); the order is job-line order, not file-name order, because it decides the order of the merged cards that the level-up roll walks, and `test_data_repo_lines` fails on a file in a fragment directory that is not named after a line. Merge rules (`DataRepo.SPLIT`): `skills` entries are concatenated by key; `cards` and `weapon_slots` are concatenated in line order; `equipment_drops.items` are concatenated and sorted ascending; `scrolls.families` merge per slot, so a later line can add families to an armour slot another file started. A repeated skill key, card `id`, item id, weapon slot or slot+family across files is an error in the `errors` list of `load_all` and the first value is kept; `_`-prefixed keys of a fragment (its `_doc`, notes) are never merged and never overwrite the base. Placement: skills by Skill.wz book (000 beginner, 2xx magician), cards by their skill (none = common, book 000 = beginner, else the skill's line), equipment ids by canonical `reqJob` (0 = common armour, a Magician bit or any wand/staff = magician, the Warrior bit with the sword/axe/blunt/spear/polearm weapons and shields = warrior; weapons and shields never take reqJob 0, so a Beginner's drops stay as they were), armour scrolls in common, wand/staff scrolls in magician and the sword/axe/blunt/two-handed/spear/polearm/shield scrolls in warrior (`weapon_slots` in `shops/<line>.json`). A weapon drops only from the job's `weapon_families` (`EquipmentDrops.family_allows`). **A class spec adds its line** (Warrior, Bowman, Thief, Pirate, Hero) by creating its own `<name>/<line>.json` files, never by editing another line's file (see "Adding a class line" below); an export ships them through `data/survivor/*/*.json` in the `include_filter` of `game/export_presets.cfg`. Tools that deep-merge a patch (`balance_run.gd --patch`) work on the merged data.

**Adding a class line (the Hero convention, #296 H2 #298; every later class spec copies it).** A class spec gets one *line*, named after the class (`hero`, later `paladin`, `darkknight`, ...), however many jobs of the Adventurer job-line (Warrior 1, Magician 2, ...) it touches, so Hero, Paladin and Dark Knight no longer all edit `warrior.json`. The checklist, in order:

1. **Append the name to `DataRepo.LINES`** (the end of the array, never in the middle: the order is the merge order, so appending leaves the merged output of every earlier line, and every recorded oracle byte, unchanged). Class lines come after `pirate` in the order their specs landed.
2. **Create the per-line files**, each next to its base file, each with a `_doc` saying which spec owns it:
   - `game/data/survivor/jobs/<line>.json`: the class's job entries (`{"jobs": {"<id>": {starting_skill, mobility_skill, skill_pool, weapon_families, creation_weapon, playable, ...}}}`). A new job starts with `"playable": false`; only the ticket that makes the class selectable flips it.
   - `game/data/survivor/skills/<line>.json`: the line's skill definitions (`{"skills": {...}}`); an empty `{}` skeleton at first, so the ticket that defines each skill appends its own entries (separate tickets append to separate regions of the file to keep merges trivial). A skill key a job names before it is defined is inert: undefined skills are never offered or learned.
   - `game/data/asset_manifest.d/<line>.json`: the line's WZ images (`docs/ASSET_PIPELINE.md` 4.1), owned by the class's asset ticket.
   - `upgrades/<line>.json`, `equipment_drops/<line>.json`, `scrolls/<line>.json` and `shops/<line>.json` only when the class has entries for them (Hero adds none: its swords and axes are in the Warrior drop list and are filtered by `weapon_families`, its armour and shields drop by the Warrior class bit).
3. **Add the job's single-row tables** in the shared files, which are not split: `balance.player.ap["<id>"]` (the auto-AP row; `balance.growth` is looked up through the lineage, so a Warrior-line job inherits the `100` HP row), and per-job flags such as `survivor/jobs.json` `default_job` stay in the base file.
4. **Never make the class selectable by accident.** `JobTree.default_job()` reads `survivor/jobs.json` `default_job` (212, tier C) while that job is playable, and falls back to the first playable job only when the pin is absent or unplayable. A second playable job therefore changes no tool run, test or oracle that names no job; the new class is always chosen explicitly (`--job=<id>`, the creation Job page).
5. **Tests.** `test_data_repo_lines` pins the `LINES` order and fails on any file in a fragment directory that is not named after a line; add the line's own data test (Hero: `test_hero_data`) for the entry fields, AP row, default job and drop families.

Equipment drops no longer read the character's level or held weapon (#292): `stages.json` `drop_bands` gives each tier a
`reqLevel` band, `survivor/jobs/<line>.json` lists each exact job's `weapon_families` (`JobTree.weapon_families`), and
`EquipmentDrops` takes both as arguments. A shield or armour piece is eligible by canonical `reqJob` alone.

`RunWorld` checks `PortalSet` before movement each PLAYING tick. Holding Up inside a same-map link's activation box
places the player at the destination minus the configured lift, resets velocity/ladder/down-jump state, and emits
`portal_used`; regular movement resumes on the next tick. The global portal cooldown advances only while PLAYING.
`RunScene` snaps the camera on that event without a sound or transition effect. Other-map exits are inert. Monsters
keep using `NavGraph` and never activate portals. `MapRenderer` draws type-2 exits with `portal/game/pv` and type-10
hidden sparkles with `portal/game/ph/default/portalContinue`; the Tree's type-1 hollows have no portal sprite.

### 4.4.5 World-movement details (`FootholdMap` ... `SpatialHash`)

What the table above leaves open; the class doc comments have the rest.

- **Footholds:** `x1 < x2` floor (landed on from above), `x1 == x2` wall, `x1 > x2` ceiling (stops upward motion).
  A wall stops only bodies of the platforms it belongs to (`FootholdMap.wall_applies(w, p)`: same foothold group as
  one of p's floors, linked to one of them, group 0 or cantThrough); `wall_hit(..., p)` takes the mover's platform
  (the one it stands on, or last stood on while airborne: `PlayerMotion.wall_platform`, `MobSwarm.platform`;
  `NavGraph.drop_landing` / jump arcs pass the takeoff platform), `-1` counts every wall. `floor_wall`,
  `walk_blocked`, `slide_along` and the platform-end flags use the floor's own platform.
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
  last stretch ends at the player's x; where two faces of the ground's own structure cross the ground chain, a mob
  dropping onto the ground outside the faces would walk into one while the player is between them). A mob stopped at
  such a wall (it
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

Regeneration runs in fixed `balance.regen.interval` pulses through `PlayerUpkeep`; only HP exists.
Level growth allocates AP for each gained level, refreshes maximum HP, then applies the configured HP refill.
Equipment refreshes derived stats without granting a refill. `periodic_recovery` skills retain independent clocks
for HP recovery. There are no MP costs, regeneration, conversion, alerts or absorption fields (ADR 0006).

What the tables above leave open; the class doc comments have the rest.

Damage-to-heal attacks (#213 Drain) declare `damage_heal: {percent_field, max_hp_fraction, target_max_hp}`.
The shared hit listener reads the canonical percentage at the hit's launch level, caps the whole-point gain
by the optional fraction of character MaxHP and the target slot's MaxHP, then uses `restore_player("hp", ...)`.
It runs before kill resolution for instant and projectile lines, so lethal and piercing hits use the same path.
No additional packed projectile field, RNG stream, event or snapshot field is needed.

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
  Narrow accessors for the components that act on the world (MobSkillRunner, BossAttacks): `player_box()`,
  `player_body_center()`, `mob_img(id)`, `refresh_player_speed()`, `summoned_alive(owner)` and `spawn_offspring(source,
  center_x, ids, owner, max_count := -1)` (MobSkill 200 summons and info/revive offspring: the same symmetric
  `mob_skills.summon_spacing` spread on the source's platform, centred on the whole list). Its tick reads as
  `_step_player` (drinks, `_take_portal` or movement, view, `_tick_timers`), `_step_monsters`, `_step_player_attacks`,
  `_step_pickups`, touch, EXP, state snapshot, `_end_tick`; `_on_boss_kill` handles a scheduled boss's death.
- **Event details:** `player_hit.damage` is whole HP damage; there is no MP absorption.

- **Hidden and morph (#194, GAME_DESIGN 7.18):** a buff whose snapshot has `hidden` (from `buff.hidden`) makes
  `RunWorld.is_hidden()` true; `player_state.hidden` and `player_state.morph` (the Morph.wz id of the first morphing
  buff, 0 for the plain avatar, always 0 once dead) feed the presentation. Mobs, bosses, mob skills and balls read
  `is_hidden()` (MobSwarm `ctx.hidden`, MobAttacks, MobProjectileSystem, MobSkillRunner, BossDirector, SpawnDirector,
  `take_hit`, `_touch`), the player's attacks read it too (SkillRunner). `RunScene` passes `morph` to
  `AvatarRenderer.set_morph`.
- **Player buffs:** `player_state.buffs` is an array of `{skill, skill_id, level, icon, remaining, duration,
  effect_stat, value}` (plus `hidden`, `morph`, `end_hp_above` since #194). Duration/effect are snapshotted from canonical `time` and `x`/`pdd` at cast level; upgrading a
  rank affects the next cast. `skills.json` kind `buff` keeps its passive slot but joins SkillRunner's oldest-ready
  cast ordering, pays canonical `mpCon`, and casts without a target only while inactive. Buff timers advance before
  casting each tick, including on ropes. `fired_this_tick` covers buffs and keeps basic attacks out of that tick.
  `hit_defense()` adds active Armor PDD to equipment/stat defense; `magic_guard_ratio()` reads active Guard only.
  Expiry drops the effect immediately; an affordable, permitted recast may happen on that same tick. `HudBuffRow`
  draws canonical Skill.wz icons and whole-second remaining labels; the HUD signature updates on countdown changes.
  Rank previews add canonical `time`, `x`, `pdd` changes to existing combat fields.
  Recovery also reads canonical `cooltime`; its `buff.hp_threshold` and `pulse_interval` are survivor rules.
  `RunWorld.can_start_buff(skill, stats)` checks the HP threshold before casting. Recovery's cooldown starts at
  cast time and keeps ticking during its HoT and while climbing. PlayerBuffs applies periodic intervals only inside
  the active duration, returns total healing due to the world, and emits the final pulse before expiry. The six
  5-second pulses over 30 seconds are a tier C interpretation of canonical `x`. Rank previews include `cooltime`,
  and Recovery's `x` is labelled HP per pulse rather than an absorption percentage.
  Nimble Feet reads canonical `speed`, `time` and `cooltime`; its active speed points are added before
  the mob-skill slow multiplier. Speed refreshes immediately on cast and expiry. Its 60 s cooldown starts at
  cast, so the 4/8/12 s buff does not recast at expiry before that cooldown elapses.
- **`ProjectileSystem`:** `rng` (combat stream), `paths` (= `RunWorld.visual_paths`), `bounds`; `step()` fills
  `kills` (mob slots killed this tick) and RunWorld turns them into `mob_died` + an EXP drop, like instant hits.
  Shots capture `damage_type`, `damage_pct`, `player_level`, `crit_damage_bonus` and pre-defence bounds in packed
  arrays; target level and live PDD/MDD are read at each impact. `roll_damage` is shared with `RunWorld.hit_mob`;
  physical bounds take level-gap/PDD reduction before rolling and skill%, magic keeps its existing MDD rule,
  and fixed damage ignores defence. `hit_mob(m, stats, visual, hit_rng := null)` defaults to combat stream 1;
  Final Attack supplies stream 12 for both the damage and crit rolls (stream 5 is reserved since #284).
- **Physical caster (#153):** `Loadout` exposes `str_stat`, `dex_stat`, `luk_stat`, `watk`, `acc`, `weapon_id`,
  `weapon_family`, `job_id`, `mastery` (fraction, default .10), `crit_bonus` (chance), `crit_damage_bonus`
  (skill-percentage points). `clone()` copies these; changed inputs invalidate `version`. `RunWorld._refresh_caster`
  is their assembly point, refreshed on stats/equipment changes, buff start and after buff timers each tick.
  `weapon_attack(ranged := false)` returns worn incPAD plus buff `watk`, plus the current ammo's incPAD when `ranged` (#155; `_refresh_caster` feeds `watk` with `ranged` for a held bow, crossbow, claw or gun). The ranged basic attack's shots roll on stream 5 through `ProjectileSystem.alt_rng` (spawn key `alt_rng`).
  Accuracy uses `CombatMath.base_accuracy(dex, luk, jobs.lineage(job))` plus equipment and active buffs.
  `Loadout.stats()` adds `damage_type` (fixed/magic/physical/none), `attack_kind` (swing/stab/shoot/empty),
  `defense` (pdd/mdd/none), `damage_pct` (canonical physical skill% / 100, otherwise 1), `player_level` and
  `crit_damage_bonus`, retaining `magic` and `damage_min/max`. Physical bounds include survivor damage modifiers
  but precede defence and skill%; fixed/magic bounds retain their existing meaning. Optional survivor
  `physical_formula: {primary, secondary, max_mult, min_mult, ignore_mastery}` overrides the weapon row
  (Lucky Seven; 6.1 of GAME_DESIGN). #161 feeds mastery and crit passive inputs here.
- **Shared passives, buffs and Final Attack (#161):** `RunWorld._refresh_caster` is the one place that turns owned
  passives into caster fields. `Loadout.passive_total(stat)` / `passive_best(stat)` read every effect of a skill's
  `passive` (the legacy `stat` + `field`/`per_level`, plus an optional `effects: [{stat, field | per_level}]` list) and skip
  skills outside the job pool. Stats: `mastery` (canonical N, fraction
  (10 + 5N)%, best wins), `acc` (summed into `Loadout.acc`), `crit_chance` (percent, summed into `crit_bonus`),
  `crit_damage` (total crit percent; `crit_damage_bonus` is the part above 100, best wins) and `max_hp_per_level`
  (added to the base HP at each `_on_level_up`, so it persists in the snapshot's `base_hp`). A buff `effects` entry may
  carry `scale` (the Boosters' negative speed steps use `-1`; Rage's WZ pdd is already negative and takes none); `watk` buff totals already feed `weapon_attack()`. Final Attack is a
  passive skill with `final_attack: {chance_field}`, `damage: "physical"` and an `action`: the hit listener
  `RunWorld._final_attack_hit` rolls `prop` on RNG stream 12 (`final_rng`) after a damaging physical line of a matching
  family (hit dicts now carry `damage_type`, from `hit_mob` and ProjectileSystem), queues the target, and
  `_play_final_attacks` runs at the end of `_step_player_attacks`: `final_attack` event, then one `hit_mob(slot,
  loadout.stats(key), …, final_rng)` (damage, crit and the proc all on stream 12). Follow-ups never trigger follow-ups,
  and a target the trigger killed gets none. Spread (#181): the Final Attack
  skill's `count` (base 1, +1 per Spread card step) is the number of monsters one follow-up strikes;
  `RunWorld._spread_targets` adds the extra ones around the struck target with no RNG (GAME_DESIGN 7.9).
- **Shield slot (#158).** `"shield"` is the last of `Equipment.SLOTS` (Character.wz Shield, category 109). The worn map
  key is optional, so snapshots from before the slot load and save back unchanged (no format bump).
  `Equipment.displaced_slots(worn, id)` names what wearing an item moves back to the Equip tab: an overall's top and
  bottom, and a two-handed weapon (`WeaponInfo.is_two_handed`: weapon type 140 and up) and a shield each other. A swap
  the full tab cannot hold is refused (`inventory_full`, "You can't get anymore items."), and
  `Equipment.validation_error` rejects a snapshot that wears both.
- **Attack speed (#160).** `WeaponInfo.speed_factor(base, boost)` is 1.0 without a Booster. `RunWorld.attack_speed_boost()`
  sums the running buffs' `attack_speed` effect (`PlayerBuffs.effect_total_where`); `_refresh_caster` feeds `Loadout.weapon_speed` / `speed_steps`,
  `Loadout.stats()` multiplies a damaging skill's `action_time` and `cooldown` by `speed_factor`, and
  `WeaponReach.action_spec(..., boost)` plus `player_state.action_scale` shorten the swing and the avatar's frames.
- **Weapon-bound casts and HP cost (#163).** `SkillRunner` has two more cast rules beside `nearest` / `box` / `crowd`:
  `weapon_reach` (the nearest mob inside `WeaponReach.envelope(world)`, the union of the held weapon's afterimage boxes)
  and `range_around` (up to `mob_count` mobs whose body centre is within the canonical `range`); `reach_of` and
  `strike_count` are their shared definitions. A skill with `"action": "weapon"` plays `WeaponInfo.skill_action(weapon)`
  (the first weapon stance), which also picks the swing/stab multiplier. `Loadout.stats().hp_cost` (canonical
  `hpCon`) is paid at cast time: `cast_ready` skips a skill `RunWorld.can_pay_hp` refuses (HP must stay above 0) and
  `RunWorld.spend_hp` pays it.
- **Melee behaviour cards (#208).** `Loadout.stats().attack_count` applies skill modifiers to canonical `attackCount`;
  target count remains separate. `SkillRunner.weapon_envelope(stats, world)` scales a copy of
  `WeaponReach.envelope(world)` by the skill's existing `area` modifier on both axes. Admission uses that box; `reach_of` scales the weapon reach by the same area for the bot. The cached
  envelope is never mutated. `UpgradePool` previews `attack_count` as whole hits alongside the existing percent
  `area` preview; the level-up window labels them Hits and Reach. No snapshot schema or RNG stream changes.
- **Self casts:** the generic self-cast rule requires no monster; MP conversion was removed by ADR 0006.

- **Weapon paths and grants** (#226) are gone (#284): no job grants or records a weapon; drops still follow the
  held family (`EquipmentDrops.family_allows`, stream 10) until #292.
- **`PickupSystem`:** `step()` returns the EXP collected this tick; at `max_active`, `spawn()` absorbs the drop farthest
  from the supplied player position and reuses its slot at the new death position, restarting the pop and age with
  the combined EXP. `merged` reports absorption, and `RunWorld` still emits `pickup_spawned`. With `lifetime` > 0 a drop expires silently
  (no event; `expired`, `expired_exp`) after fading out; renderers read `alpha(i)`.
  Potion pickup kinds 1 and 2 are reserved but unused (spec #237); no potion bundles or collection accounting remain.
  `active_count()` includes all drops, while `exp_count()` preserves the balance harness's EXP-drop metric.
  **Mesos (#107):** kind `MESO` = 3 (`EQUIP` = 4 is #109, below) with `meso[i]` = the amount; `spawn_meso(pos, amount)`
  picks the coin sprite item from the amount (`MesoDrops.sprite_item`: <50 bronze 09000000, 50-99 gold 09000001, 100-999
  bundle 09000002, 1000+ bag 09000003). They never expire, merge or count toward `max_active`. A collected
  one adds its amount to `step_mesos` (this step; RunWorld adds it to `mesos`) and `collected_mesos` (the round's total),
  and its `pickup_collected` / `pickup_spawned` events carry `kind` `"meso"` with the amount in `count`.
- **Mesos:** `MesoDrops` (pure statics) holds the brackets, `amount_range(level, listed, fallback)` and `roll(rng, span,
  mult)` (uniform in [min, max), times the multiplier). A kill rolls `balance.mesos.chance` on its own RNG stream (9,
  `meso_rng`), then the amount from `mobs.json` `mesos` (or the level fallback) x `balance.mesos.mult`;
  a scheduled boss's death drops `balance.mesos.boss_drops` bundles with no chance roll. `RunWorld.spawn_meso(pos, amount)`
  is the public seam; `RunWorld.mesos` is the carried total (snapshot format 2). PickupRenderer animates the coins
  (`AssetLibrary.meso_frame_path`: `Item.wz/Special/0900.img/<id>/iconRaw/0..3`, 100 ms a frame); RunScene sums the frame's
  collected mesos into one "You have gained mesos (+N)" message. The balance record carries `mesos_earned` per round.
- **Equipment drops (#109):** kind `EQUIP` = 4; `spawn_equipment(pos, instance)` keeps the Equipment instance in
  `equip_instance[i]` (a plain Array beside the Packed arrays; `item_id` is the equipment id, drawn from its
  `Character.wz/.../info/iconRaw`). Equipment never expires, merges or counts toward `max_active`. `step(..., equip_room)`
  takes how many items the Equip tab still holds (RunWorld passes `inventory_slots() - inventory.size()`, -1 = unlimited):
  a collected drop is appended to `collected_equipment` (RunWorld puts it in `equipment.inventory`, emits
  `equipment_changed` action `pickup`, counts `equips_collected`, then wears it at once through `equip` with action
  `auto_equip` when its slot is empty and its job class admits it, #222). With room 0 a drop is not magnetised (one already flying
  falls back to the floor) and `pickup_blocked` is emitted once each time the player comes within magnet range; it is picked
  up as soon as room appears. `EquipmentDrops` (pure statics: `eligible`, `pick`, `pick_boss`) filters
  `survivor/equipment_drops/<line>.json` `items` (ids only; reqLevel, reqJob and stats come from `setup.equipment_info`, which
  `DataRepo.starter_equipment_ids` extends with the list) by the character's job (`Equipment.job_allows`), the job's weapon
  families and the `reqLevel` band of the stage's tier (`RunWorld.drop_band()`, uniform inside it); `Equipment.create_drop(id, info, rng)` rolls the v83 random stats. A kill rolls
  `equipment_drops.chance` on its own RNG stream (10, `equip_rng`); a scheduled boss's death drops
  `equipment_drops.boss_drops` item(s) from the top third of the band with no chance roll. `RunWorld.spawn_equipment` is the public
  seam; RunScene shows "You have gained an item (name)" and "You can't get anymore items." through the HUD message queue.
  The balance record carries `equips_dropped` and `equips_collected` per round.
- **Potions (spec #237):** setup.item_info maps original item ids to canonical Consume nodes. Each kind in
  player_state.potions exposes {item_id, cooldown_left, cooldown_total}, with seconds remaining and total, no stock.
  drink_potion(kind) restores canonical spec.hp/spec.mp and starts the kind's shared player/pet cooldown;
  rejected presses emit nothing. RunWorld ticks it once per playing sim tick before manual drinks and casting, including
  on ropes. Windows freeze sim time; upgrading preserves the timer. used and pet_used count drinks separately.
  No potion pickup kinds, spawns, rolls or collections remain; stream 7 is reserved. The schedule derives tiers from
  starter ids plus level on load, ignoring legacy stock; neither potion stock nor cooldowns are saved.
- **Player-platform placement:** `SpawnDirector.pick_player_platform(world, min_distance := -1,
  preferred_distance := -1, allow_visible := false, side := 0) -> Vector3` returns (x, y, foothold), or z=-2 when no
  point is possible. It samples the current platform while avoiding walls and nearby points; normal placement is
  visible only when `player_platform_visible(world)` sees the whole platform inside the logical view. A preferred
  distance and visible override support boss relocations. `spawn.platform_share` (0.35) selects this path for ground
  placements before ordinary ring fallback; flyers retain off-screen air sampling. Every new mob fades in and deals
  no touch damage until alpha is 1.
- **`UpgradePool`:** `state` is the `RunWorld`; `apply()` also emits `upgrade_applied` (+ `skill_learned`). Card
  `effects` op `add` sums and `mul` compounds per rank. No card heals by percentage and no filler cards are injected.
  There are no job-neutral cards (spec #225): the Magnet and `potion_tier` cards are gone (`upgrades/common.json` keeps an
  empty `cards` list) and the Power Elixir `fallback` is the only filler, offered alone when no card is eligible.
  Potion tiers come from `PotionSchedule` instead: `RunWorld.apply_potion_schedule` calls `upgrade_potion(kind, item_id)`
  per due step and preserves the remaining cooldown; the event and refreshed player state update the quickslot immediately.
  `CharacterSnapshot.migrate` drops `magnet` and the
  removed potion cards from `card_ranks` (and the `magnet` modifier from `player_mods`) on load.
- **Job selection:** fixed at character creation; there is no advancement window.

### 4.5 Presentation (`game/scripts/render`, `ui`, `audio`, `run`)

`RunScene` owns a `RunFrameRecorder` for frame samples. Full history is retained only when configure options request
`perf`, `quit_after` or `shots_dir`; automated summaries keep their warmup, screenshot exclusions, percentile and
minute/crowd grouping semantics. Ordinary play keeps only the last two seconds, capped at 2048 samples even if frame
deltas are zero. F3 reads this bounded window immediately when toggled mid-round and does not enable full recording.

`RunWorld` accepts an optional `setup.character` `CharacterSnapshot` (format 3; tool files of format 1 and 2 migrate on
load) and exposes `character_snapshot()`. The schema, and the one list of what a character keeps, is in
`scripts/sim/character_snapshot.gd`: job, look, worn equipment and inventory (`scripts/sim/equipment.gd` instances),
scroll stacks, mesos, cash, pet and unlocked tiers; never level, EXP, skills, cards, AP or HP. Every world starts at Lv1.
RunWorld owns the live equipment: UI and bots change it
only through `equip_item`, `unequip_item` and `discard_item` (see the RunWorld header); a character without a
snapshot wears `Equipment.DEFAULT_OUTFIT`. `SceneFlow.new_character` makes the creation choices and the job's creation
weapon worn equipment. Each new world computes full HP and creates
fresh map systems, timers, buffs and statuses. Snapshot reads during any pending level/reward
choice push an error, return empty in release and assert in debug. With no character the original setup/event
path is retained. The sim does no file I/O: `DataRepo.load_character` validates the explicit tool JSON file for
RunScene's `options.character` path and `tools/balance_run.gd --character=<abs path>`.

The headless `tools/balance_run.gd` advances the same fixed ticks with real-map setup and seeded card/movement
policies. Its record/aggregate contract and CLI are in AGENTS.md's Balance section: milestone reach counts,
completed versus censored boss fights, per-hit whole damage/max-HP fractions by boss/source, player `potions_used`,
per-drink restoration/waste in `potion_uses`, separate `pet.potions_used`,
and camper activation/arrival.
TIMEOUT is a measurement cap, never a sim clear. Potion metrics describe unlimited drinks on cooldown (spec #237).
Offensive cast counts and aggregated Guard coverage are not separate recorded metrics. Monster balls retain captured source/damage after
caster death; their original mob slot may be reused, while captured mob ID/source position remain meaningful.
`PortalApproach` supplies the shared pure entrance-floor lookup, jump-graph approach, wall gate and movement input
for `BotInput` and the camper harness. Each caller retains its goal scoring and eligibility policy, including the
bot's additional entrance-floor activation-height check.
`buff_casts` is an additive harness diagnostic: event-observation time, skill/key ID, canonical level/duration,
and effect stat/value copied from the public cast snapshot. Normal runs drain after each fixed step, so this is
that cast tick; already-pending setup events are observed at the next drain. It adds no RNG calls or gameplay
changes. Earlier records lacking this field are unavailable observations, not zero casts.
Legacy `cards_taken` strings prefix the card ID with the front queued level, or −1 when that queue is empty.
A bonus choice can have a positive prefix while levels remain queued. The field supplies neither a bonus flag
nor a choice timestamp, so it cannot isolate normal-choice acquisition timing.
The sensible `BotInput.card_score` reads optional `balance.bot.card_scores`, which takes precedence for an individual
card ID (potions are no longer cards, spec #225, so there is no potion-tier score). Such a score replaces the final
score, with no job bonus added; an unlisted card retains its existing scoring path. Random policy selects uniformly
among offered cards with its own seeded RNG and never reads the score setting. The knob is tier C survivor tuning.

| Piece | Approach |
|---|---|
| `MapRenderer` | Backgrounds (types 0-7, parallax `x + cam_cx*rx/100`, tiling by `cx/cy`, auto-scroll `rx*5 px/s`, `a`, `f`, front backs) redrawn per frame; static tiles/objs per layer recorded once in a `_draw()` command list; animated objs as canvas items. Draw order: non-front backs -> layers 0..7 (objs by `z`, then tiles by canvas `z`, then actors standing on that layer) -> front backs. |
| `AvatarRenderer` | Composites body/arm/head/face/hair/coat/pants/shoes(/weapon) per frame using `map` anchors (navel, neck, hand, brow) and `Base.wz/zmap.img` order. Mirrors for facing. A morph (`set_morph`, #194) replaces every part with one frame of `Morph.wz/<id>.img` for the matching action. Draws `look.cash` over the outfit (face accessories by expression, weapon covers by weapon type, `vslot` hiding through `smap.img`, an overall replacing top and bottom) through the pure helpers in `AvatarLayers`. |
| `MobRenderer` | One RenderingServer canvas item per live mob slot (no Nodes), region-of-atlas per frame, alpha for `a0/a1` fades. One renderer per foothold layer (`only_layer` + `update_slot_layers`) to draw mobs inside `actor_layer(L)`. |
| `NameTags` | Elite name tags under mobs (`RunWorld.mob_elite`), drawn like v83's code-drawn default name tag. |
| `FxRenderer` | Pooled one-shot WZ animations and repeating slow/immunity icons; `play_repeating`, `stop` and `place` follow sim status/expiration without per-entity Nodes. |
| `DamageNumbers` | `Effect.wz/BasicEff.img` digit sets: first digit large set, rest small; 400 ms hold then 600 ms fade + 30 px rise (tier B). |
| `Hud` | Hosts separate `HudStatusBar`, `HudCounters`, `HudSkills`, `HudMessages`, `HudQuickSlot`, `HudBuffRow` and `HudBossBar` widgets, all extending the one base `HudWidget` (a mouse-ignoring Control with its own state snapshot, the HUD fonts and the only copies of the WZ drawing helpers `_frame(path, report_missing)`, `_blit`, `_blit_rect`, `_text`, `_rank`). `HudSkills` draws each cooling icon's clockwise sweep (one polygon per icon, filled into a reused array by the shared static `CooldownSweep.sweep_polygon(left, total, rect, out)`); RunScene feeds its snapshot (icons, ranks, key labels) when the HUD signature changes and the cooldowns every frame through `set_cooldowns` from reused buffers, which redraws only when a sweep step changes. Key labels are cached and re-read on `Settings.changed` (`RunScene.watch_settings`, `GameSettings.action_label`). RunScene feeds potion icons and independent cooldown sweeps through reused HP buffers, buff icons with ceiling-second MM:SS labels, and live boss bars stacked below the timer. `HudQuickSlot` is the v83 quick slot: a pure `cells()` model (8 cells in a fixed order; icons from `KeyActionArt`, the table the Key Config window also uses; captions from `GameSettings.first_key_label`, current potion items without stock counts, the learned movement skill from `run_info.movement_skill`), re-read on `Settings.changed` and display only. The HUD controls that take the mouse are the status bar's Menu button (`Hud.menu_button`, a `WzButton` on `StatusBar.img/BtMenu`) and the quick slot's collapse button (`Hud.quick_slot_button`, `QuickSlotD` / `QuickSlot`; `RunScene.toggle_quick_slot` stores the state in `GameSettings.quick_slot_collapsed`, `[hud] quick_slot_collapsed`), both with process mode ALWAYS so they work while the HUD is frozen. |
| Windows | Level-up choice (`LevelUpWindow`), pause (`PauseMenu`): `MapleWindow` Controls built from `UI.wz` art, skill icons from `Skill.wz`, text from `String.wz`; `RunScene` hosts them in a CanvasLayer (layer 10) and holds its tick loop while one is open. In-run windows (Stat, Skill, the Menu popup, Key Config, Options): `UiWindow` Controls (draggable, art-sized) in a `WindowStack` on CanvasLayer 11; a window kind is one `ui_windows.register(id, factory)` in `RunScene._build_ui_windows()`, after which its hotkey (`RunScene.WINDOW_HOTKEYS`) and Menu entry work; keys RunScene does not use itself go to the front window's `UiWindow.handle_key`. The Skill window draws a `SkillWindowModel` (plain data from the SkillBook, UpgradePool, Loadout ranks / mods / `card_ranks`, JobTree and SkillText; read-only). The Equip and Item windows (#108; `InventoryWindow` base: the v83 double-click / drag protocol, `ItemTooltip`, `DropConfirm` on `Basic.img/YesNo`) show and change the character only through a RunWorld (`equip_item`, `unequip_item`, `discard_item`, `discard_scrolls`, and `use_scroll` for a scroll dragged from the Use tab onto a worn item, resolved by the pure `Scrolls` module on RNG stream 11) and read their plain data through `InventoryModel`; `RunScene._on_item_action` maps the world's `equipment_changed` and `scroll_used` at once (the Enchant effect is an `EnchantFx` layer above the windows, unfrozen while the run is held). The Free Market hosts the same stack (`FreeMarket.ui_windows`) over `FreeMarket.inventory`, a map-less RunWorld of the saved character whose `character_snapshot()` is written back into the save slot after every change. The tick loop also holds while the stack has a window, Esc closes the front one before the pause menu, and a choice window below sets `input_blocked`. Key Config edits a `KeyBindings` draft (`scripts/core/key_bindings.gd`, no scene) that OK writes through `Settings.set_bindings`; Options calls the `Settings` setters directly; both also open from the pause menu (`RunScene.PAUSE_WINDOWS`). Title, character select/creation, map select, the Cash Shop (`cash_shop.gd`, opened by `SceneFlow.goto_cash_shop(origin)` from map select or the Free Market; rules in `scripts/core/cash_shop.gd`), results and import are scenes under `scenes/ui/`; in the Free Market the pause menu is Resume / Save & quit only (`PauseMenu.boundary_mode`). |
| `Camera` | Follows the player with smoothing (tier C), clamped to `MapBounds`, positions rounded to whole pixels. |

`RunScene` holds `map_cleared` at the sim's `transfer_pending` boundary while the original party-quest CLEAR effect
plays, then fades out. After one fully black frame it calls `advance_map()`, replaces the map-owned world subtree
(freeing the old mob/drop/projectile/effect canvas pools), updates and snaps the existing camera to the arrival portal and
starts the destination BGM. Fade-in completes before another simulation tick; the destination's street/map name
uses the round title style. HUD and window layers survive. Pause and in-run windows hold the entire presentation
clock and Resume continues the same phase, including at black; choices during the frozen sweep work as before.
The ending-map summary follows `world.current_map_id()`. `--shots` adds one-based `map_N_cleared`, `map_N_enter`,
`map_N_fade` and `map_N_black` captures (the final map uses the existing finale instead of another transfer).

`RunScene.boss_bars()` builds presentation-only snapshots from live encounter records and swarm HP, independently
of the status/timer update signature. `HudBossBar.displayed()` exposes the same rows used by drawing, with original
mob id, name, HP/max HP, ratio, icon and gauge paths. The bar uses `UI.wz/UIWindow.img/MobGage` backgrounds,
`Mob/<id>` icons and `Gage/<hpTagColor>/0`, `Gage/<hpTagBgcolor>/1` strips. `mobs.json.boss_ui` supplies only missing
presentation metadata; the cache is untouched. A dead boss is omitted immediately, including when others remain.
`boss_warning` and `boss_spawned` map to keyed yellow encounter notices above the ordinary EXP queue (and above
the low-HP cue), so EXP churn cannot evict them. Arrival replaces that boss's warning, plays the canonical
`Effect.wz/BasicEff.img/Summoned` animation at its position, and requests an evidence screenshot when enabled.

Logical resolution 800x600 (v83's native size and the width of `StatusBar.img/base/backgrnd`), `stretch/mode=canvas_items`
(since #224; was `viewport`, see "Fonts and sharp text" below), `aspect=expand`, `scale_mode=integer`, nearest
filtering: on wider windows the player sees more of the map at the same pixel size, never a stretched sprite (1920x1080: 1066x600 at 1x with black bars). The logical view size therefore
varies; read it live (`get_viewport().get_visible_rect().size`), never assume 800x600. `Settings` adjusts two cases:
a window smaller than 800x600 on either axis is scaled down (fractional) instead of cropped, and the opt-in
`[display] fill_window` grows the view to window / s at the same integer scale s instead of showing bars
(`GameSettings.fit_size`: 3440x1440 -> 1720x720 at 2x, 1920x1080 -> 1920x1080 at 1x; much more map on screen, so it is
off by default).

#### Fonts and sharp text (`MapleText`, `MapleFonts`, `PixelDraw`; #224, 2026-10-18)

All font text goes through `MapleText` (12 / 11 px, line heights 15 / 13, positions floored to logical pixels) and
`MapleFonts` (the system Arial, Tahoma, Dotum as a `SystemFont`, else the bundled Arimo; see 10 "Web profile"). Until
#224 the window used `stretch/mode=viewport`: everything, text included, was drawn into an 800x600 (or expanded)
texture and scaled up with nearest, so on a 1440p screen text was 12 px glyphs doubled into blocks. Now the window uses
`stretch/mode=canvas_items` with the same base size, aspect, integer scale, nearest filter and 2D transform/vertex
snapping: canvas items are drawn straight into the window at its own pixel size through the stretch transform, and
Godot oversamples fonts by that scale, so glyphs are rasterised at window pixels while every metric stays logical.

- **Metrics are frozen.** Font metrics do not depend on the oversampling (`Font.get_string_size` takes no scale), and
  the two metric-moving settings stay fixed for both antialiasing variants: hinting normal, subpixel positioning off.
  Checked windowed at 2x in both stretch modes (same widths, wraps and ascents for a set of strings) and pinned by
  `test_sharp_text.gd` (recorded Arimo widths at 12 / 11 px, regular and bold; the game font's widths and a wrap; AA
  never changes a width). Sibling UI code keeps laying out with `MapleText.width` / `wrap` in logical px.
- **Antialiasing is one constant**, `MapleFonts.ANTIALIASED` (tier C; false: the owner chose crisp from the A/B screenshots, PR #235, 2026-10-19): false =
  crisp hinted glyphs without antialiasing (default, closest to v83), true = grayscale. `MapleText.font`,
  `HudWidget.make_font` / `Hud.make_font` and the Arimo fallback all go through `MapleFonts`. No settings toggle.
- **Sprites stay pixel-identical.** Node transforms are snapped per item in logical units, so sprites, map tiles and
  moving mobs at fractional positions land on the same pixels as before (measured: `map_viewer` with 40 moving mobs,
  `ui_gallery` windows, flow_driver Item / Equip / Stat windows, before vs after at 2x and in fill-window: only text
  pixels differ, plus map layers animated in real time). Three draw kinds would change and are handled: a 1 px
  `draw_rect(r, c, false)` became one window pixel thin, so `PixelDraw.outline` fills the logical pixels the old
  render lit (GL compatibility footprint: top row above the rect, left column outside, right and bottom inside); a
  texture drawn smaller than its art (the HUD's 24 px skill icons from 32 px art) would sample more texels, so
  `PixelDraw.blit_scaled` copies the texels the old render picked (texel floor((i + 0.5) * src / dst)) as unscaled
  runs (also the stage-select mob portraits); and 1 px lines on whole coordinates (`draw_line(.., 1.0)`, a
  `draw_rect(r, c, false, 1.0)` along whole edges) would straddle two logical rows at 2x, so `PixelDraw.hline` / `vline` /
  `edge_outline` fill the row or column the old render lit (tooltip separators, the stage-select and results dividers). Not reproduced: sprites
  drawn rotated (arrows, bullets and a few skill projectiles that turn to their direction, `ProjectileRenderer`; the
  rotated "Run history" label is text) and diagonal edges inside a `_draw` (the cooldown sweep, the Skill
  window's star-tab glyph, the cash shop's check tick) are rasterised at window pixels, i.e. slightly finer edges than the 800x600 render had.
- **Every display mode.** Integer 2x / 3x and fill-window (`GameSettings.fit_size`) keep their logical view sizes and
  integer scale; text is drawn at s x its size. Below 800x600 the fractional downscale now samples each sprite at the
  window's pixels instead of shrinking the finished 800x600 frame, and text is rasterised at the reduced size (legible
  instead of nearest-dropped rows).
- **Captures are window-sized.** `get_viewport().get_texture().get_image()` now holds the window's pixels (1600x1200 at
  2x), so playtest and driver screenshots show the sharp text. Crops in logical coordinates go through
  `GameSettings.capture_rect` (capture size / view size; letterbox bars are not in a capture); debug contact sheets that must stay at logical size use
  `GameSettings.capture_logical`. `main.gd` and `map_viewer` take tool-only `--size=WxH` (and main `--fill`) to
  capture a 2x or fill-window view on any screen.
- **Web.** The same project setting applies; the canvas is the tab's CSS size times `devicePixelRatio`
  (`html/canvas_resize_policy=2`), so a HiDPI browser gets window-resolution text too. Checked in Chrome (`web/dev/perf_run.mjs`) at a 1600x1200
  viewport and at an 800x600 viewport with devicePixelRatio 2 (canvas 1600x1200, 2x text).
- **Alternatives rejected.** A native-resolution text overlay on top of the 800x600 viewport cannot keep z-order: a
  window, tooltip or dragged icon drawn over another window's text would no longer cover it, and every `_draw` that
  mixes art and text would have to split. Per-font oversampling alone does nothing in viewport mode (glyphs still land
  in the 800x600 texture). Rendering only the world into an 800x600 SubViewport under a canvas_items root would also
  keep rotated projectiles blocky, but it splits RunScene, FreeMarket, the login backdrop and every debug scene, and
  leaves world text (name tags) low-res unless lifted out; the measured difference it would remove (rotated sprites)
  is small, so the global switch is the simpler choice.
- **Performance.** Canvas items are drawn at window resolution (4x the fill at 2x) instead of 800x600 plus one blit;
  frame time is in `docs/IMPLEMENTATION_PLAN.md` "Performance log" (#224).

## 5. Data architecture

| Layer | Where | Examples | Rule |
|---|---|---|---|
| Canonical, from WZ | asset cache (read at runtime) | mob stats, frame delays/origins/hitboxes, Physics.img, skill level tables, map geometry, names | Never copied into the repo, never edited |
| Canonical, not in WZ | `game/data/canonical/` | EXP table, job tree (ids, advancement levels) | Facts with a `_source` note |
| Survivor design | `game/data/survivor/` | skill behaviour, upgrades, stages and waves, balance multipliers, per-mob overrides | All tuning happens here |
| Asset selection | `game/data/asset_manifest.json` + `asset_manifest.d/<line>.json` | maps, mobs, character parts, UI/effect/sound images to import | Grows with content |

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
  script, scene, resource, config and `project.godot` under `game/` for network classes, nodes and settings, and for
  `JavaScriptBridge`) and the importer's `no_network_deps` (Cargo.lock scan) and `no_network_src`
  (`std::net`/socket types in its sources) tests. This holds for every build, the web build included: `game/` has
  no networking and no JavaScript, and `tools/wzimport/` has no network code (it may carry wasm-bindgen bindings and a
  Node test harness); both compile the same for desktop and web.
- On desktop the importer is a local process reading local files; the game launches it with
  `OS.execute_with_pipe`/`OS.create_process`.
- Settings and saves are local files under the user data folder (in a browser: `user://` in the page's IndexedDB).
- **What the web shell may fetch (ADR 0004).** The shell in `web/` is the only shipped code that makes requests, and
  only two kinds: (1) the static bundle it was served with (`index.js`, `index.wasm`, `index.pck`, its own scripts,
  `asset_manifest.json` and the licence files), and (2) when the player types a folder or `.zip` address into the
  import screen, requests to that address: a `HEAD` / `GET Range: bytes=0-0` probe, then ranged or whole-file reads
  for the import. Nothing is hard-coded: the repo, the site and the docs name no source or mirror, there is no
  default address, no analytics, no service worker and no telemetry, and a folder or `.zip` import from the player's
  disk makes no request at all. The player's files are read in the page and never uploaded. The importer's browser
  readers (`Blob`, HTTP `Range`) live in `web/` as host callbacks, so the Rust side stays free of network code.
- Developer tooling outside `game/` that uses the network ships in no build: `scripts/godot.sh` and
  `scripts/godot_templates.sh` (the pinned Godot editor and web templates), the CI workflow, and the localhost test
  servers in `web/dev/`.
- Verified by process-level socket snapshots during a 15:00 playtest and of the exported build (0 TCP connections,
  0 UDP endpoints, no child process other than the local importer; `docs/IMPLEMENTATION_PLAN.md` acceptance checks).
  A run with the network adapter disabled has not been done.

## 8. Licensing and assets

- Our code: original. Godot (MIT) notices ship with exports (the web build too: the four notice files sit beside
  `index.html` and are linked from the import screen): `scripts/export.sh` writes `GODOT_LICENSES.txt` (the
  engine's licence, its bundled components and their licence texts, from the engine itself), `WZIMPORT_LICENSES.txt`
  (every crate's licence files), `ARIMO_OFL.txt` (the bundled font's licence) and copies `THIRD_PARTY_NOTICES.md` next to the exe. Rust crates are permissive
  (MIT/Apache/Zlib); the list is in `THIRD_PARTY_NOTICES.md`.
- Cosmic (AGPL-3.0) and the AGPL/GPL/MPL clients: facts and prose descriptions only, never code. Where a constant comes
  from them it is labelled with its tier and source in `docs/GAME_DESIGN.md`.
- Nexon's assets: the player supplies their own v83 install; the cache lives in their user folder; nothing proprietary
  is committed, bundled or uploaded. Screenshots of the running game are kept in the gitignored `evidence/` folder.

## 9. Known unknowns (tracked in `docs/RESEARCH.md` §6)

The real client's physics integrator and timestep, mob speed-stat conversion, projectile speeds, hit-stun and death
fade timing, climb speed, camera smoothing, and the touch-damage formula are not recoverable from data or clean
sources. Each is implemented as a labelled, data-driven constant so it can be corrected when better evidence appears.

Worn equipment instances supply every `inc*` stat (W.ATT summed over all worn items); the canonical `equipment_info`
supplies requirements, weapon speed, `afterImage` and `sfx`. `RunWorld.weapon_id()` is the worn weapon (0 means a
bare-handed punch, `WeaponReach.BARE_HANDS`); `mob_defense(slot, magic)` reads live slot defense, and
`physical_hit_allowed(slot)` is the physical-immunity seam. Basic swings show their action while standing or airborne;
new skills retain standing-only action presentation. Neither action changes movement or locks it.

MobSkillRunner keeps defense amounts/expiry and Attack Up expiry in packed per-slot arrays. New spawns reset status and
`mob_summon_owner` (encounter index, -1 for ordinary mobs); relocation transfers both status and summon ownership.
Only active owned slots count toward the canonical summon limit. `mob_defense(slot, magic)` combines immutable
kind defense with its live timed bonus. ProjectileSystem.step accepts an optional packed per-slot MDD snapshot,
so projectile damage resolves the defense present at impact; basic and instant hits read the same live seam.
`player_speed_stat()` composes upgrade speed with the timed slow. `player_state.slow` is `{skill_id: int,
remaining: float, multiplier: float, visual: String}` while active, otherwise `{}`. The presentation repeats slow
art in a pooled slot until the sim state expires; window pauses cannot consume its duration.

## 10. Web build

The web build (spec #130, ADR 0004) is the "Web" preset of `game/export_presets.cfg`: single-threaded
(`variant/thread_support=false`, template `web_nothreads_*`), GL Compatibility, no GDExtension, no PWA, and the same
`include_filter`/`exclude_filter` as desktop (`tests/unit/test_export_presets.gd` holds this). Its shell is
`web/index.html` through `html/custom_html_shell="res://../web/index.html"`: FileAccess turns `res://` into the
project folder, so the shell stays beside `game/` without staging, and an ISOLATE mirror gets a copy of `web/` beside
its `game/`.

- **Templates:** the official 4.7.2 `web_nothreads_debug.zip` and `web_nothreads_release.zip`, installed by
  `bash scripts/godot_templates.sh install-web` (downloads the official templates archive, checks its SHA-512 against
  the release's `SHA512-SUMS.txt`, unpacks only those two into the editor's templates folder:
  `%APPDATA%/Godot/export_templates/4.7.2.stable` on Windows, `~/.local/share/godot/export_templates/4.7.2.stable`
  on Linux; `godot_templates.sh dir` prints it).
- **Export:** `ISOLATE=<name> bash scripts/export.sh --web [--debug]` writes the whole site to `game/export/web/`
  (`index.{html,js,wasm,pck}`: wasm 39.5 MB, pck 1.2 MB, plus everything of section 10.3). `node web/dev/serve.mjs
  game/export/web` serves it on 127.0.0.1:8060 with `application/wasm`, plus `web/dev/` at `/dev/`.
- **Dev cache injection (never exported):** `http://127.0.0.1:8060/dev/inject.html` copies a desktop-built cache
  folder straight into the IndexedDB database behind `user://` (`web/idbfs.js` documents the record format). The
  import screen of section 10.2 replaces it for players.
- **`user://` on web:** `OS.get_user_data_dir()` is `/userfs/MapleSurvivors` (Godot's web OS returns
  `/userfs/<custom_user_dir_name>`), so the cache is `/userfs/MapleSurvivors/asset_cache/v83`; the game prints that as
  its cache root. `/userfs` is Emscripten IDBFS: IndexedDB database `/userfs`, store `FILE_DATA`, keys are absolute
  paths. The whole tree is read into memory when the engine starts. The engine writes it back after any frame in which
  a file under `/userfs` was closed for writing or removed, and always once more on quit, before `onExit`.
- **Quitting on web:** in Godot 4.7.2, if an `AudioStreamPlayer` still holds a sample playback at shutdown,
  `Main::cleanup` throws (`SampleNode._pause` reads the AudioContext that was already closed) and `onExit` never runs.
  The final IndexedDB sync has already happened by then. Stopping every `AudioStreamPlayer` and pausing the tree
  before `get_tree().quit()` gives a clean exit (verified in a scratch build). This sequence is binding for every web
  quit (`WebHandoff.quit`); the shell also treats the post-quit `currentTime` TypeError as an exit (section 10.2), and
  the importer's zip reader uses no temporary storage (docs/ASSET_PIPELINE.md 2.3).
- **Audio buses come from `game/default_bus_layout.tres`, never from `AudioServer.add_bus` (2026-10-17):** web
  audio plays as Web Audio "samples", and the engine mirrors every bus into a JS bus graph. In Godot 4.7.2 appending a
  bus at runtime breaks that mirror: `AudioServer.add_bus` passes position -1 to the web driver, and the JS
  `Bus.addAt(-1)` / `Bus.move` (`splice(toIndex - 1)`) put the new bus in the wrong slot, so later index-based calls hit
  the wrong buses. `AudioService` used to add BGM and SFX at startup; that left the JS order SFX, BGM, Master, sends
  forming a cycle Master -> SFX -> BGM -> Master and nothing connected to the AudioContext destination, so the web
  build was silent while every sample still started (measured RMS 0 at the destination in Chrome; desktop mixes in
  C++ and was fine). A layout resource goes through `set_bus_layout`, which only appends buses in order. The
  `AudioService._ensure_buses` fallback is still there for a missing layout, counted in `buses_added_at_runtime`
  (`test_assets_audio_settings.gd` requires 0). Measured after the fix: RMS 0.07-0.11 mean on the title and in a
  Henesys round, and a context suspended at boot starts when the player first clicks or presses a key.
- **Arguments:** command-line user args reach `OS.get_cmdline_user_args()` through the engine config `args` after
  `--`; `web/index.html` maps `?arg=<value>` query parameters to them. The web templates are built without path
  overrides: a scene path on the command line (e.g. `res://scenes/debug/flow_driver.tscn`) aborts the engine.

### 10.1 Spike measurements (#131, 2026-10-17)

Setup: dev PC (Ryzen 7 7800X3D, RTX 4070 SUPER, display at 60 Hz in this session); installed Chrome 155.0.8059.40,
headed and driven by Playwright with a 1600x1200 viewport; release export of the #131 branch. The runs match the
desktop playtests: `--run=henesys_hg1 --seed=2026 --autoplay --autopick --speed=1 --warp=<s> --perf`. The simulation
is bit-identical to desktop: kills, levels, alive counts and the death time agree at every checkpoint.
"Uncapped" means Chrome with `--disable-gpu-vsync --disable-frame-rate-limit` plus the game's `--vsync=off`. Web frame
times come in 0.1 ms steps, the browser's timer resolution without cross-origin isolation.

| Window (run time) | Mobs (minute means / max) | Web frame ms p50 / p95 / p99 / max | Desktop exe frame ms p50 / p95 / p99 / max | Sim µs/tick web / desktop |
|---|---|---|---|---|
| uncapped 10:00-13:00 | 201-269 / 290 | 3.3 / 6.2 / 7.9 / 33.3 | 1.86 / 3.46 / 4.93 / 18.3 | 1659 / 1207 |
| uncapped 13:00-15:07 (death) | 292-341 / 341 | 3.7 / 8.7 / 10.9 / 83.7 | 2.01 / 5.33 / 6.91 / 17.0 | 3929 / 2849 |
| capped 60 Hz 13:00-15:00 | 292-339 / 340 | 16.7 / 16.8 / 16.8 / 21.5 (work p95 6.8 ms) | not run | 3732 / not run |

1. **Frame time:** see the table. 60 FPS holds at 330-341 mobs: the capped run played all 7,200 ticks of its 120 s in
   7,081 recorded frames (frames right after a screenshot are not recorded, and fewer than 2% ran a catch-up tick),
   with p99 16.8 ms and no frame over 21.5 ms; and the uncapped p95 of 8.7 ms leaves half of the 16.7 ms budget. 400 mobs were not
   reached because in this seed the bot dies at 15:07 on both platforms. Henesys' alive cap is not a flat 330
   (`stages.json`, `SpawnDirector.max_alive_at`): its `max_alive` keyframe curve reaches 330 at 15:00 and, past that last
   keyframe, keeps rising at a quarter of its previous slope (`post_duration_slope` 0.25: 0.125 mobs/s, about 345 by
   17:00). Bursts may go past the curve up to `hard_cap` 400, and elites spawn while fewer than 400 are alive; boss
   summons (MobSkill 200) and revives are bounded by their canonical summon limit and revive list, not by `hard_cap`.
2. **Sim:** 1.38x desktop: 3.9 ms/tick at about 340 mobs, 1.7 ms at 200-290.
3. **Peak wasm heap:** 178 MiB in a `--run` session with 200-341 mobs; it stops growing during the warp. The title
   screen alone takes the heap to 339 MiB, and the heap never shrinks, so a full title-to-round session peaks at 339
   MiB or more. Measuring the full flow needs menu input on web, which is left to the QA ticket. Chrome's
   `usedJSHeapSize` peaks at 330-340 MiB in rounds (it swings between about 235 and 330 MiB, which is GC churn with no
   visible frame cost) and 604 MiB on the title. Whether that figure counts the typed arrays holding the in-memory
   IDBFS copy of the 157 MiB cache was not checked.
4. **Max texture size:** WebGL2 `MAX_TEXTURE_SIZE` is 16384 (ANGLE D3D11). The largest cache page is 2493x340
   (`Map.wz/Back/grassySoil.img.0.png`), followed by 2048 px pages, so nothing comes close.
5. **Rendering against desktop:** compared by eye on the same frames (`evidence/spec130/t131/`). Maps, mobs, skills,
   the CanvasGroup invincibility blink, HUD, title and overlay match desktop. Text drawn with the `SystemFont` (Arial)
   falls back to Godot's built-in font, visible on "Re-import WZ data", names and the overlay. This is expected; a
   bundled font is the web profile ticket's job. Audio plays through Web Audio samples (AudioContext `running`; the
   output was not measured then and was silent until the bus fix above), and
   Godot resumes it on the first key or click. Under Playwright the context starts without a gesture, so the click
   requirement could not be reproduced. Every run reported `missing: []`. Quitting hits the shutdown error above.

**Verdict: pass.** In Chrome the game holds the desktop bar (60 FPS at 330-400 mobs on the dev PC) at the 330-341 mobs
it reaches, with no engine or presentation change. On web the sim costs about 1.4x desktop and frame time about
1.6-1.8x.

### 10.2 Web shell and the shell-game protocol (#133)

The shell is `web/index.html` (Godot's custom HTML shell, placeholders filled at export) plus files that must sit
beside it in the export: `shell.css`, `shell.js` (page logic), `lib.js` (pure helpers, unit-tested with
`node --test web/dev/test/*.test.mjs`), `idbfs.js` (reads and writes the `/userfs` IndexedDB), `import_worker.js` (module
worker), `wzimport.js` + `wzimport_bg.wasm` (the importer, `scripts/build_wasm.sh`), `asset_manifest.json`
(`game/data/asset_manifest.json` merged with its `asset_manifest.d/*.json` fragments by `wzimport manifest`,
ASSET_PIPELINE 4.1; fetched same-origin), and the branding: `title.jpg` (the key art behind the loading overlay and the shell screens),
`favicon.ico`, `favicon-16x16.png`, `favicon-32x32.png`, `apple-touch-icon.png`, `android-chrome-192x192.png` (also the
emblem in the plate title bar), `android-chrome-512x512.png` and `site.webmanifest` (relative icon paths, for the Pages
subpath). The Web preset has `html/export_icon=false`, so Godot adds no icon links of its own.
`bash scripts/export.sh --web` copies them (`WASM_DIR=<dir>`
picks the wasm build, default `_scratch/wasm/`); `web/dev/` is never copied (section 10.3).

**Ownership.** Before reading shared IndexedDB or starting any engine/import worker, boot takes an exclusive
Web Lock named `maple-survivors-userfs` with `ifAvailable`. It holds that lock for the page lifetime, including
engine quit/restart and shell import/export screens. A second tab shows "already open in another tab" and a
Try again button. Close the owner tab, then retry: the browser releases ownership on exit/crash and the new tab
loads current storage. Overlapping retry clicks share one startup operation. There is no force-steal of a mounted
engine, heartbeat expiry or network coordination.
Browsers without Web Locks refuse to mount and explain the requirement (current browser on HTTPS/localhost).
The shell never releases a running engine's lock on visibility change or `pagehide`.

**Boot.** Once ownership is acquired, the shell reads `cache.json` and the record keys below `/userfs/MapleSurvivors/asset_cache/v83` from
IndexedDB and judges them against the bundled manifest. Valid: start the engine. Otherwise: the import screen. The
check is exact for what the manifest names and nothing else: every `imgs[]` entry, every `mapimgs` entry and the imgs
the `maps`/`mobs`/`character`/`items` ids resolve to (the formulas of `tools/wzimport/src/manifest.rs`), plus
`Map.wz/MapHelper.img` (`portal`) and `Sound.wz/Mob.img` (one sub-path per listed mob), must be listed in `cache.json`,
and the `paths` the index records for an img must cover the manifest's: an img cached whole covers any selection, a
partial one covers a request only when it holds that path or a shorter path above it (so a path added to the manifest,
or an img that went from a selection to the whole img, reads as incomplete); and for every img the index lists, its
`.json` and `.N.png` records must exist. Dependencies the importer derives by reading WZ data (map backs, tiles, objs,
mob links) are only caught by the second rule. A cache that fails is "incomplete":
- remembered source is a **URL**: the shell re-imports from it at once, automatically, and says so on screen;
- remembered source is a **folder or zip**: the import screen says what is missing and asks the player to pick it
  again. Where `showDirectoryPicker` exists the folder handle is kept in a separate IndexedDB (`maple-shell`, never
  `/userfs`), and a "Use ... again" button plus the browser's permission prompt replaces the picker.

Re-imports are complete imports (docs/ASSET_PIPELINE.md 2.4). The old cache is replaced only after the new one has
been read successfully.

**Import.** One source per import: a folder (`showDirectoryPicker`, else `<input webkitdirectory>`; a dropped folder
where the browser offers a handle), a zip (picker or drop) or a web address (a folder base URL or a `.zip` URL). The
work is in `import_worker.js` and never runs while an engine is mounted. For a URL the worker first probes: a
`Range: bytes=0-0` GET per file gives size and range support; the player sees the total size and that the download
comes straight from the host they named, and only then confirms. CORS refusals and unreachable hosts are told apart (a
`no-cors` HEAD) and get distinct messages. The URL is remembered in `localStorage`, with the kind and label of the last
source. Nothing the engine could sync lives in `/userfs` but the cache, saves and settings.

**Storage.** The worker deletes the old cache records, writes directory records and files straight into IndexedDB
`/userfs` (`idbfs.js`: batches of at most 50 records or 32 MiB) and `cache.json` last, so an interrupted import leaves no
`cache.json` and reads as "no cache". The footer never waits on the browser's permission prompt (#148): at boot
`navigator.storage.persisted()` is read without prompting and shown at once ("kept (persistent)", else "best effort";
"not confirmed by this browser" when the API is missing or throws), then `persist()` is asked in the background and a
grant upgrades the line (a refusal keeps best effort). The call after an import refreshes the usage figure and starts
no second request while one is pending. The toast at the first game start reports the immediate state. The decision
and the dedupe state machine are `createPersistence` / `storageStatus` in `web/lib.js`, covered by the Node tests.

**Console line at engine quit.** Every engine quit on the single-threaded web template logs `Pages in use exist at exit
in PagedAllocator: N16WorkerThreadPool5GroupE` from Godot itself (#147, closed wontfix). It is harmless: no game code
uses the thread pool, `onExit(0)` fires and the saves reach IndexedDB.

**Request marker (the protocol).** `user://web_request.json`, i.e. `/userfs/MapleSurvivors/web_request.json`:

```json
{"format": 1, "request": "reimport"}
```

`request` is one of `reimport` (show the import screen), `export_save` (download `user://save.json` as
`maple-survivors-save-YYYYMMDD-HHMMSS.json`, then restart the engine) or `import_save` (ask for a save file, validate it,
stage it as `save.json.import`, restart for full game validation). The game writes the file,
closes it in a normal frame, stops its audio players, pauses the tree and calls `get_tree().quit()` (the game side is the
web profile ticket, #134). When the engine exits the shell reads the marker from IndexedDB, deletes it, handles it and
starts a **new** `Engine` on a fresh canvas element. An unknown `request`, a wrong `format` or invalid JSON is logged,
deleted and ignored; no marker is a plain quit. Both end on a "The game has quit" screen with Play again. Exit is
detected from `onExit`, and also from a page error mentioning `currentTime` of null while an engine runs (Godot 4.7.2's
teardown after a quit with audio alive; the final IndexedDB sync has already happened by then).

Save import refuses, before writing anything, a file that is not JSON or lacks `SaveData`'s top-level shape (format 1
2 or 3; `best` and `runs` objects; formats 2 and 3: exactly 3 `slots` and a `history` array). The game still validates the
contents of the staged `.import` file before promotion. An invalid candidate is preserved as `.import.bad[.N]`
and consumed without touching the primary or `.bak`; no second nested validator lives in JavaScript. A valid
candidate goes through SaveData's normal temporary/backup write, then the staging file is removed. The shell's
toast says "staged", since it cannot claim validation succeeded before the game loads it. A failed promotion keeps
the prior in-memory state and staged file for recovery.
SaveData remains lazy: in the normal menu flow, Start opens the roster and consumes the candidate. Until that
first persistent-save use, Export save still downloads the committed primary, and the shell only claims "staged".

**Network.** The shell requests its own static bundle and, when the player enters an address, that address (`fetch`
for the probe, synchronous `XHR` with `Range` or a streamed whole-file download in the worker). Nothing else; `game/`
and `tools/wzimport/` stay offline (ADR 0004). `web/dev/serve_sources.mjs` is a localhost test host with range,
no-range and CORS-blocked modes; test addresses are always `http://127.0.0.1:<port>/...`.

### 10.3 Deploying the site (#135)

`bash scripts/export.sh --web` (see the header of the script) is the single path that makes the site; `game/export/web/`
is gitignored. It exports the Web preset, copies the shell files and `asset_manifest.json`, builds the wasm importer
(`scripts/build_wasm.sh`) and places it beside `index.html`, writes the licence files linked from the import screen
(`GODOT_LICENSES.txt`, `WZIMPORT_LICENSES.txt` including the wasm-only crates, `THIRD_PARTY_NOTICES.md` including the
font, `ARIMO_OFL.txt`) and finishes with `scripts/check_web_artifact.sh`: the build fails if a `.wz`, `.img`,
`*.img.json`, atlas `*.N.png`, `.mp3`/`.wav`, a `cache.json` or any file starting with the WZ signature (`PKG1`) is in
the folder, or if a file the site needs is missing (`web/dev/test/artifact_check.test.mjs` plants each shape).
`ISOLATE` and `EXPORT_DIR` work as for the Windows export. Everything is static, so the folder works on any static
host and under a sub-path such as `/maple-survivors/` (the shell uses relative URLs only).

The workflow `.github/workflows/pages.yml` ("Web build"): its `build` job runs on every pull request, on pushes to
`main` and on `workflow_dispatch`. It installs the pinned Godot 4.7.2 editor (`scripts/godot.sh`) and its web templates
(`scripts/godot_templates.sh install-web`), Rust with `wasm32-unknown-unknown` and the locked `wasm-bindgen-cli`, runs
`cargo test`, `node --test web/dev/test/*.test.mjs` and `bash scripts/test.sh`, then `export.sh --web` and the artifact
check again, and uploads `game/export/web` as the Pages artifact. Tests that need the real asset cache (or
`MAPLE_WZ_ROOT`) SKIP in CI because CI has no WZ data and never will; a SKIP proves nothing, and the log counts them.
The `deploy` job (`actions/deploy-pages`) runs only for pushes to `main` and `workflow_dispatch`, never for pull
requests, so a pull request proves the whole pipeline except the final publish. `workflow_dispatch` is only offered
for the copy of the workflow on the default branch.

CI runs on Linux with no asset cache and no Arial/Tahoma/Dotum, which found two test assumptions that Windows runs hide
(fixed in the tests only): `test_maple_text_wrap_and_ellipsize` now accepts the bundled-Arimo `FontVariation` as well as
a `SystemFont`, and `test_fresh_character_event_stream_matches_before_ticket_67` used a Windows-only 20-minute golden
because its event digest differed on Linux for seed 1 (16 of 72000 ticks). The cause (#142) was the digest's
serializer, not the simulation: `JSON.stringify` writes `Vector2` fields through float-to-text, which rounds exact
decimal ties differently per platform (`1090.8125` gives `.813` on Windows and `.812` on Linux). The digest now hashes
`var_to_bytes` of the drained events, never float text, and one golden is asserted on every platform for the full
20 minutes (same digest on Windows and Linux Godot 4.7.2). libm does differ across platforms (one `sin` in the flyer
bob, integer-exponent `pow` calls in upgrades), but none of it reaches the event stream today; replacing them with
deterministic approximations is out of scope. The #131 "wasm matches Windows" result in 10.1 compared checkpoints
(kills, levels, alive count, death time), not event bytes; the wasm build was not compared against the new golden.

**One-time owner setup:** repository Settings -> Pages -> Build and deployment -> Source: **GitHub Actions**. Until that
is set the `deploy` job fails (the `build` job and pull requests are unaffected). The site is then at
`https://itechify.github.io/maple-survivors/`. Out of scope by design: custom domains, analytics, a service worker and
offline caching of the page.

### 10.4 Browser QA measurements (#136, 2026-10-17)

What was tested: the artifact of `bash scripts/export.sh --web` on the integration branch (head f619dc4, with B2/B3:
equipment, shops, Cash Shop, pet), served by `web/dev/serve.mjs` on 127.0.0.1, not the deployed Pages site (the owner
enables Pages after merge; the deployed-URL pass is still to do). Dev PC as in 10.1; Chrome 155.0.8059.40 (installed,
headed) and Playwright's Firefox 157.0, both in fresh profiles, 1100x800 viewport for the menu flow. Same method and
flags as 10.1 (`--run=henesys_hg1 --seed=2026 --autoplay --autopick --speed=1 --warp=<s> --perf`, uncapped = Chrome
`--disable-gpu-vsync --disable-frame-rate-limit` plus `--vsync=off`). The display ran at **165 Hz** this session (rAF
164 Hz measured with no flags), so the "capped" run is capped at 6.1 ms per frame, not 16.7 ms.

| Window (run time) | Mobs (minute means / max) | Web frame ms p50 / p95 / p99 / max | Desktop exe frame ms p50 / p95 / p99 / max | Sim µs/tick web / desktop |
|---|---|---|---|---|
| uncapped 10:00-13:00 | 202-257 / 290 | 3.4 / 5.7 / 8.3 / 133 (one frame; next worst 15) | not re-run | 1260 / not re-run |
| uncapped 13:00-17:00 (alive at 17:00) | 285-355 / 356 | 4.5 / 15.3 / 27.4 / 75.3 | 2.3 / 8.6 / 12.1 / 45.6 | 5807 / 4274 |
| capped (165 Hz) 13:00-15:00 | 285-325 / 339 | 6.1 / 14.5 / 17.4 / 55.4 | not run | 4354 / not run |

Minutes 15 and 16 (342-356 mobs) on their own, uncapped: web p95 16.8 / 16.4 ms and p99 31.3 / 34.7 ms against desktop
p95 10.0 / 10.1 ms and p99 12.5 / 13.0 ms. Every run reported `missing: []`.

1. **What changed since 10.1.** With B2/B3 the same seed no longer dies at 15:07: the bot is alive at 17:00 with up to
   356 mobs. That is the alive cap working as designed (10.1 item 1): the curve is at about 345 by 17:00, and a burst
   or an elite adds the rest. The desktop sim costs 4274 µs/tick at 13:00-17:00 where 10.1
   measured 2849 at 292-341 mobs. The web/desktop ratio is unchanged (sim 1.36x here, 1.38x in 10.1; frame p95 1.8x,
   p99 2.3x).
2. **Verdict against the bar (60 FPS at 330-400 mobs): marginal.** Median and mean are comfortable (p50 4.2-4.6 ms,
   uncapped mean 6.5 ms), but at 340-356 mobs the p95 sits at the 16.7 ms budget and the p99 at 27-35 ms, so a 60 Hz
   display would drop frames in a few percent of frames from about 14:00. 10.1's p95 of 8.7 ms at the same mob counts
   no longer holds: desktop moved the same way (p95 5.3 -> 8.6 ms), so this is the merged content, not the web
   platform. 400 mobs is still not reached (356 maximum). Filed as its own issue; nothing was tuned here.
3. **Heap.** A `--run` session peaks at 286 MiB of wasm memory (10.1: 178 MiB). A real title -> character select -> round
   session holds 358 MiB right on the title screen and does not grow in the round (the heap never shrinks). Chrome's
   `usedJSHeapSize` is 358-370 MiB in rounds and 469 MiB on the title.
4. **Firefox.** The #131 black canvas was most likely Firefox's window occlusion tracking: the same build froze (black
   canvas, no frames, page calls hanging) while another window covered the headed Firefox window, and worked once the
   preference `widget.windows.window_occlusion_tracking.enabled=false` was set (in the QA driver only; nothing in the
   game or shell). With it the build renders and plays: folder and zip import (8-9 s), title, character creation, a
   round, Key Config, Options, fullscreen, pause, Continue after a reload, tier 2, death and history. Firefox frame
   times were not measured (one rAF probe at the title read about 35 callbacks per second; not investigated). Firefox
   also left the import screen's "Storage: checking..." line unresolved until its persistence permission prompt was
   answered (fixed in #148, see Storage in 10.2).

**#146 re-measure (2026-10-18).** The drop pool was not the cost. A per-system profile of the late round
(`game/tools/profile_run.gd`) found 110-150 drops lying (the bot collects them) and the pickup step at 2-3% of the tick.
More than half of the tick (51-56%) was SkillRunner rescanning targets on ticks where no ready skill could be paid for:
every ready skill built and sorted its target list only to fail the MP check. Another 14% went to the per-tick
projectile defense loop. Both now give the same answers with less work, and the sim output is unchanged (see
`test_tick_cost_identity.gd`). What is left is per-mob work: swarm movement, the director's recycling and the grid
rebuild.

Seed 2026 cannot be re-measured over this window on current main: since mob attacks (#145) and the hit window (#171)
its bot dies at 4:47, and none of seeds 1-12 is alive at 17:00 either (one clears at 15:15, the others die between 5:24
and 15:12). The rows below use **seed 5** (Cleric, Lv38, alive at 15:00, dies at 15:12) over 13:00-15:00, so they are not
comparable with the seed-2026 rows above. Base = b2ef00d (main before
#146), after = b0a17c5; each tree exported with `scripts/export.sh --web` and played the same day with the same flags:
`--run=henesys_hg1 --seed=5 --autoplay --autopick --speed=1 --warp=780 --perf --vsync=off --shot-every=30
--quit-after=900`, Chrome 155 headed and uncapped, real v83 data imported in-page from the folder, driven by
`web/dev/perf_run.mjs`. Desktop is `scripts/playtest.sh --seed=5 --speed=1 --warp=780 --minutes=15 --vsync=off`. The
dev PC's main display ran at 164 Hz (3440x1440; a second display at 143 Hz). Other agents' Godot test runs were active on
the machine at times during the session. Both trees play the same round: 2640 kills, Lv38, `missing: []`.

| Window (seed 5) | Mobs (minute means / max) | Build | Web frame ms p50 / p95 / p99 / max | Desktop frame ms p50 / p95 / p99 / max | Sim µs/tick web / desktop |
|---|---|---|---|---|---|
| uncapped 13:00-15:00 | 285-338 / 339 | base b2ef00d | 4.0 / 8.8 / 11.9 / 19.1 | 2.25 / 5.41 / 6.49 / 16.2 | 3166 / 2274 |
| uncapped 13:00-15:00 | 285-338 / 339 | after b0a17c5 | 4.0 / 6.7 / 9.7 / 20.8 | 2.26 / 3.58 / 4.39 / 15.7 | 1252 / 836 |

Minute 14 alone (338 mobs): web p95 / p99 9.3 / 12.5 ms before, 6.1 / 8.1 ms after; desktop 5.55 / 6.53 ms before,
3.42 / 4.14 ms after. Frame work p95 (RunScene's own work per frame): web 5.9 -> 3.2 ms, desktop 4.0 -> 1.9 ms. Peak wasm
heap 286 MiB in both. With seed 2026 gone, nothing here reaches 340-400 mobs, so the bar of 60 FPS at 330-400 mobs is
measured only up to 339 mobs: at 339 the web p99 is now 8-10 ms against the 16.7 ms budget.

### Web profile (#134)

Everything below is behind `WebProfile.is_web()` (`scripts/core/web_profile.gd`: `OS.has_feature("web")`, with a
`forced` override so unit tests can run the web branches on desktop). Desktop behaviour is unchanged. There is no
`JavaScriptBridge` and no JavaScript in `game/`: the game talks to the web shell (`web/`) with files and by quitting.

- **Cache location:** `AssetCachePaths.resolve_cache_root()` is always `<user data dir>/asset_cache/v83`, i.e.
  `/userfs/MapleSurvivors/asset_cache/v83`, where the shell writes it. The `MAPLE_SURVIVORS_CACHE` env var and the
  `cache_dir` / `wz_root` settings are skipped, and `resolve_wz_root()` is `""`. The pure rule is
  `AssetCachePaths.cache_root_for(web, env, configured, user_dir)`.
- **Hand-off (`scripts/core/web_handoff.gd`, `WebHandoff`):** the browser build cannot run `wzimport` or copy files, so
  the title's "Re-import WZ data", "Export save" and "Import save" (and the import screen's button when there is no
  cache) write the request marker and quit; the shell reads and deletes it after the engine exits, does the work and
  starts a new engine. Marker: `user://web_request.json` = `{"format":1,"request":"reimport"|"export_save"|"import_save"}`,
  written with `FileAccess` and closed in a normal frame (the engine syncs `/userfs` to IndexedDB after any frame in
  which a file was closed after writing, and once more on quit; nothing written during teardown arrives).
  `WebHandoff.quit_to_shell(tree, kind)` runs the BINDING sequence: flush `user://save.json` for the two save kinds
  (`Flow`'s `SaveData.save_file()`), write the marker, stop every `AudioStreamPlayer` under the root, set
  `tree.paused = true`, then `tree.quit()`. Without the audio stop and the pause Godot 4.7.2's web teardown throws on
  the closed AudioContext and `onExit` never fires (section 10 "Quitting on web"). `WebHandoff.exit_app(tree, code)` is
  the same quit without a marker, used on web by the tool quits (`--shot`, `--quit-after`, run launcher) so automated
  browser runs also end with `onExit`. Seams for tests: marker path, save and the final quit callable are parameters
  (`tests/unit/test_web_handoff.gd`).
- **Import screen:** on web it has no folder field, Browse or `FileDialog` and never reaches `OS.execute*`; one button
  hands over with `reimport` (the screen only shows when the cache is missing; the title goes straight to the marker).
- **Title:** no Quit (hidden; Esc does nothing there). Fullscreen, Export save and Import save lead the second button
  row, before Re-import WZ data.
- **Fonts (`MapleFonts`, `assets/fonts/arimo/`):** a browser has no system fonts, and a `SystemFont` with no match is
  drawn with Godot's built-in font whatever its `fallbacks` hold (checked on desktop with a font name that does not
  exist: same size as `ThemeDB.fallback_font`). `MapleFonts.make(names, weight)` therefore returns the bundled Arimo
  (a `FontVariation` of the variable `Arimo-Variable.ttf`, wght 400 / 700, same pixel settings as the SystemFont:
  `MapleFonts.ANTIALIASED` (#224), normal hinting, no subpixel positioning) when no system font exists for any of the names, and the
  `SystemFont` (Arial, Tahoma, Dotum) with Arimo in its `fallbacks` otherwise, so desktop keeps real Arial. Arimo is
  metric compatible with Arial. Licence: SIL OFL 1.1 (`assets/fonts/arimo/OFL.txt`, `THIRD_PARTY_NOTICES.md`;
  `scripts/export.sh` copies it to `ARIMO_OFL.txt` beside the exe). `MapleText.font`, `HudWidget.make_font` and
  `Hud.make_font` return `Font` now.
- **Display:** no window size/position calls (`window_scale` ignored) and no `Engine.max_fps` / vsync (the browser paces
  frames with requestAnimationFrame); the project's stretch (800x600 expand, integer scale, fractional below 800x600)
  is applied to the tab size by the existing `fit_viewport()` logic (`fill_window` keeps its default off, as on
  desktop). Godot emits no `size_changed` when a tab shrinks below the base size while the stretched view stays 800x600
  (seen in Chrome: 800x600 -> 640x480 kept a cropped 1x view), so on web `Settings._process` re-fits whenever
  `root.size` changed. The Options window shows a FULLSCREEN check box in place of the FRAME CAP row, and the title has a
  Fullscreen button; both call `GameSettings.toggle_fullscreen()` straight from the click (browsers only allow
  fullscreen inside an input handler) and read the state back from `window_get_mode()`, so leaving with Esc cannot
  desync them.
- **Keys:** Godot's web input calls `preventDefault()` on every key event of the focused canvas (the shell focuses it,
  `html/focus_canvas_on_start`), so Left Alt (Firefox/Chrome menu), Space, arrows, Tab and F5/F11/F12 should not
  trigger browser actions while the game has focus. Checked under Playwright's synthetic key events in Chrome and
  Firefox: every key above reached the page with `defaultPrevented` set and Alt jumps. Synthetic events do not run the
  browser's own accelerators (reload, fullscreen, developer tools), so the real-keyboard behaviour of F5/F11/F12 and of
  the Alt menu is left to a manual check in the QA ticket (#136). Keys a page cannot reliably take: F11 (browser fullscreen) and F12 (developer tools) are tinted "Web" and not
  bindable in the Key Config window (`KeyBindings.WEB_RESERVED`), and the window's strip notes that Ctrl+W / Ctrl+T /
  Ctrl+N always reach the browser. Esc leaves browser fullscreen before the game sees it (accepted).
