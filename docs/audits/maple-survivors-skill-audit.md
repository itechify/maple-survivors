# Maple Survivors: skill-driven game audit

Audit of commit `a68e74f` (main, "Spec #226: one job entry per advancement, then a weapon specialization page"), clean
working tree, 2026-10-21. Read-only: no source, data, assets, tests, settings or existing documentation were changed.
Diagnostic output lives in the gitignored `evidence/skill-audit/` (logs, summaries, screenshots, specialist reports) and
`_scratch/` (probes, private project mirrors).

Method: the installed [gamedev skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) were routed with
their `router` skill, then five independent specialist audits (architecture, gameplay, performance, feel/UX,
testing/persistence) ran in parallel on GPT-6.1-Sol (High). Each specialist read its assigned `SKILL.md` files in full
before applying them. A sixth GPT-6.1-Sol (High) agent then adversarially challenged the findings that most affect
priorities. The lead ran all standard verification centrally, inspected screenshots by eye, investigated the anomalies
found along the way, and consolidated. The specialist reports and their shared brief are copied beside this document in
[`skill-audit-reports/`](skill-audit-reports/) (text only). They hold the full reproduction, impact and acceptance
detail for every finding. Logs, screenshots and probe scripts they cite (`evidence/skill-audit/…`, `_scratch/audit-*/…`)
exist only in the auditing worktree's gitignored folders and are not part of the repository.

---

## 1. Executive summary

**Overall assessment: a technically strong, unusually well-tested game whose main risks are at the edges, not the
core.** The architecture the skills would push back on (a pure deterministic simulation, Physics.img movement instead of
`CharacterBody2D`, struct-of-arrays swarms drawn through RenderingServer) held up under every skill applied. These are
the right choices for this game and should not change. Gameplay is deterministic: the same seed produced
byte-identical records. The full suite passes with the real asset cache (2,225 tests, 0 failed, 0 skipped). The
presentation is faithful to v83, and performance has 2-3x headroom at 60 Hz with 200-340 mobs.

The weaknesses sit in four places:

1. **Save safety at the boundaries.** The core `SaveData` transaction is careful, but two compositions around it can
   lose a player's characters. An invalid imported save can wipe the only good backup on the next save (MS-01). Two
   sessions (two desktop instances or two browser tabs) silently overwrite each other (MS-02).
2. **QA drift on main.** Two of the three end-to-end flow-driver scenarios fail at HEAD (`rounds`, `economy`). The game
   is right in both cases; the driver's expectations went stale after the #222 auto-equip and Lv70 third-job notices
   (MS-04). The test runner also reports success for an empty selection and counts a helper as 189 tests (MS-13). The
   regression net is therefore weaker than its green numbers suggest.
3. **Early-run difficulty for a fresh character.** In the regression smoke, 11 of 12 runs died and only one cleared.
   Five of the six fresh Henesys runs died, three of them between 4:19 and 4:56. The bot's two deaths at 4:19 and 4:34
   came as Beginners, before the Lv10 first job. The likely trigger is the first elite (HP ×8, damage ×1.5) at 4:00, arriving alongside a
   crowd-cap increase (MS-03). Balance is reserved for #77, so this audit records it rather than tuning it. Players will
   feel it before anything else.
4. **Small correctness defects with seeded reproductions.** Gear swaps refill MP (MS-05). A leftward wall-clipped charge
   hits behind the player (MS-06). The finale can still kill the player after the objective is met (MS-07). The stale
   "Not enough MP" cue shows over death and over a full-MP level-up (MS-24). F3 rebinding is silently dead in a round
   (MS-10).

No Critical issue survived the adversarial challenge. Three specialists' "Critical" ratings were recalibrated: the two
save-loss paths to High, the importer panic to Medium.

**Highest-return first move:** make save import transactional and never rotate an invalid primary over the last good
backup (MS-01). It is the only path to permanent data loss reachable through a shipped UI feature (web Import save).
The fix is small and fully testable with synthetic saves.

---

## 2. Skill coverage matrix

**Installation check.** All skills the brief named, and every skill selected below, are installed. They live, with
`skills-lock.json`, as **uncommitted** files in the main checkout (`C:\Users\itech\.t3\projects\maple-survivors\.agents\skills\`
and `.claude\skills\`), not in this worktree or in git. Agents working in other worktrees will not find them unless they
are committed or referenced by absolute path. One file the router references is **missing**: `router/SKILL.md` points
to `../docs/VERSION-SUPPORT.md`, which was not installed. It did not block routing: the engine version was read from
`project.godot` (Godot 4.7.2). No packages or skills were installed.

**Routing.** The router detected Godot (`game/project.godot`), which selects one engine skill set. It then classified
the request into disciplines (game-feel, game-ui-ux, camera, audio, physics, input, save, performance, AI, level
design) and one dominant genre template, `rpg` (stats, equipment, jobs). Survivors-like action is not a catalogue
genre; `roguelike` and `platformer` were loaded only for the narrow ideas that apply.

| Skill | Selected | Applied to (systems) | Why / limits | Findings it revealed |
|---|---|---|---|---|
| router | Yes (lead) | Engine/version detection, skill selection | Entry point | - |
| godot-gdscript | Yes (A, C) | Typing, lifecycle, hot-loop containers, warning policy | Core language | MS-22, MS-27, MS-11, MS-12 |
| godot-nodes-scenes | Yes (A) | Scene flow, autoload roles, pooled lifetimes | Scene/pool ownership | MS-27, MS-29 (A-5), MS-22 |
| godot-signals-groups | Yes (A) | Callable lifetimes, event ownership | Event-list design respected | MS-11 |
| godot-resources | Yes (A, E) | DataRepo, UIDs, save/settings formats | JSON saves kept (correct) | MS-31, MS-01, MS-28 |
| godot-physics | Yes (A) | Custom foothold/swept collision only | Body/layer advice N/A by design | MS-06 |
| physics-tuning | Yes (A, C, X) | Fixed tick, catch-up cap, render interpolation | Movement retuning excluded | MS-06, MS-11, MS-26 |
| godot-2d-movement | Yes (B) | Motion correctness review | `move_and_slide` recipes N/A | (none; strengths) |
| platformer | Limited (B) | Jump commitment, one-way platforms, reachability | Coyote time/jump buffer rejected (v83 fidelity) | (none) |
| game-ai | Yes (B) | Swarm routing, relocation, boss pursuit, sensible bot | FSM/BT not imposed on SoA swarm | MS-23 |
| rpg | Yes (B, X) | Stats, equipment, leveling, rewards, win/lose states | Dominant genre template | MS-05, MS-07, MS-08, MS-32, MS-33 |
| level-design | Yes (B) | Pacing curve, finale/critical path, reachability | No geometry changes | MS-03, MS-07, MS-08 |
| roguelike | Limited (B) | Run/profile split, resource stakes, seeded continuation | No grid/turn/permadeath conventions | MS-05, MS-30 |
| procedural-gen | Limited (B) | Seeded RNG streams, weighted card/drop tables | No generation conventions | MS-30, MS-32 |
| input-systems | Yes (B, D, X) | Action map, rebinding, prompts, keyboard access | No controller/touch scope (#87) | MS-10, MS-20, MS-34, MS-35 |
| game-feel | Yes (D) | Hits, numbers, pickups, rewards, death | No generic shake/hit-stop over v83 | MS-09, MS-24 |
| game-ui-ux | Yes (D) | HUD, windows, menus, focus, scaling, web shell | No restyle; v83 art kept | MS-19, MS-20, MS-24, MS-36 |
| godot-ui-control | Yes (D) | Window stack, focus, resize | Art-sized windows kept | MS-19, MS-20 |
| camera-systems | Yes (D) | CameraRig follow/dead zone/clamp/process order | Fundamentals sound | MS-26 (with physics-tuning) |
| audio-design | Yes (D) | Voice budget, cue priority, mix | No adaptive music demanded | MS-21 |
| godot-audio | Yes (D) | Buses, pooled players, web bus fix | Static bus layout kept | MS-21 |
| godot-animation | Yes (C, D) | SpriteAnim clocks, pooled FX, first-use art | AnimationTree N/A to WZ frames | MS-25, MS-29 (A-5) |
| create-game-assets | Limited (D) | Native-scale readability, provenance | No generation, scripts not run | MS-09 |
| save-systems | Yes (E, X) | SaveData, import/export, settings, migration | JSON + atomic write kept | MS-01, MS-02, MS-28 |
| godot-gdscript-headless-testing | Yes (E, X) | Runner exit codes, counts, CI, assertions | Existing runner kept | MS-04, MS-13, MS-37, MS-38 |
| performance-optimization | Yes (C, X) | Bench, uncapped captures, allocations, warmup | Measure first; no rewrites | MS-12, MS-25, MS-39 |
| godot-export | Yes (C, E) | Windows/web export, artifact guard, CI | Single-threaded web kept (ADR 0004) | MS-14, MS-15, MS-16, MS-17, MS-18 |

**Deliberately not selected:** `godot-tilemap` (maps are WZ footholds, there is no TileMapLayer); `godot-shaders` /
`shader-programming` (the project has no shaders); `godot-3d-essentials`, `godot-csharp`; `godot-multiplayer`
(offline-only is a hard rule); `ai-behavior-trees-utility-ai` (a BT runtime would fight the SoA swarm, and the bot is a
rule policy); `dialogue-systems` (NPC text is static instructor/shop lines); `card-game` (level-up cards are a draw
from an eligibility pool, not a deck); `tower-defense`, `fps-shooter`, `survival-crafting`, `puzzle`, `visual-novel`;
`steam-publish` / `itch-publish` (GitHub Pages and a Windows zip only); `game-jam`, `prototype-fast`; all
Unity/Unreal/Roblox/web-engine skills.

---

## 3. System-by-system findings

IDs `MS-nn` are the consolidated findings (section 6); the specialist IDs (A-1, B-1, ...) they came from are in
brackets. Final severities are after the adversarial challenge (report X).

### 3.1 Architecture and code quality (godot-gdscript, -nodes-scenes, -signals-groups, -resources, -physics, physics-tuning)

**Strengths (keep):**
- The sim boundary holds. A grep found no nodes, Input, Time, files or autoloads in `game/scripts/sim/`, and presentation
  writes are limited to documented seams.
- Every `canvas_item_create` has an owner that frees it (`sprite_pool.gd:28,55,119`, `damage_numbers.gd:57-76,232`), and
  reparent tests pass.
- Function boundaries are typed throughout; the scan found zero missing return types in sim/run/core.
- DataRepo merges per-line data with ordered rules and duplicate-ID tests.
- Projectiles use swept segment-versus-box collision, not endpoint tests.

**Findings:**
- **MS-06** [A-1] A leftward charge clipped by a wall moves the whole hit rectangle instead of shrinking it, so a mob
  *behind* the player is hit (`skill_runner.gd:469`). Confirmed by probe.
- **MS-11** [A-3] The Grenade burst plays on the presentation clock while damage lands on the sim clock. After a hitch
  or during a level-up hold, the blast shows before the damage (`run_scene.gd:589,1299-1312` vs `skill_runner.gd:510-534`).
- **MS-26** [A-4, D] The renderers draw raw 60 Hz tick state with no interpolation (`run_scene.gd:527-559,1664`;
  `mob_renderer.gd:175`), while `CameraRig` smooths every display frame (`camera_rig.gd:38-50`). The default frame cap
  is the display refresh (`settings.gd:388-400`; 164 Hz on the dev PC), so actors hold for uneven 2-3 frames under a
  continuously moving camera. The mechanism is confirmed; whether it is visible or objectionable needs a motion capture
  and the owner's judgement.
- **MS-22** [A-6] `run_world.gd` (2,630 lines, 99 commits) and `run_scene.gd` (2,146 lines, 82 commits) remain the
  intersection of unrelated changes. Recommended seams, only when next touched: a scene-owned telemetry recorder, and a
  pure hit-effects/follow-up module. No broad refactor.
- **MS-27** [A-2] Frame telemetry appends four arrays every frame even while paused or with the overlay off: about
  9 MiB/hour at 164 FPS, released with the scene (Low).
- **MS-29** [A-5] A projectile slot reused between two draws inherits the previous projectile's animation phase (Low).
- **MS-31** [A-7] `game/scripts/sim/potion_schedule.gd` is the only runtime script without a committed `.uid`.
  30 debug/test scripts also lack one. A fresh import dirties the tree; this happened during the audit (Low).

### 3.2 Gameplay systems and progression (game-ai, rpg, level-design, godot-2d-movement, platformer, input-systems, procedural-gen, roguelike)

**Strengths (keep):**
- Independent seeded RNG streams per system (`run_world.gd:394,1970`); same seed, same run (verified byte-identical).
- Boss-first deterministic targeting.
- A short-MP skill never blocks an affordable one.
- Swarm routing with stuck recovery and boss pursuit teleport, so the finale cannot become unreachable.
- An always-accepted Elixir filler, so no level-up is empty.
- A synthetic sweep reached all 283/283 card IDs across jobs, weapon families and rank states: no dead cards.
- No buy/sell scroll arbitrage.
- NX awarded only at boundaries.

**Findings:**
- **MS-03** (lead) The early-run difficulty spike before the first job; see section 5.
- **MS-05** [B-1] Taking off and re-wearing +MaxMP gear with a MaxMP passive refills MP while the Equip/Item windows
  hold the run. In the probe, MP went 10 → 179 in five swaps at sim time 0 (`run_world.gd:1165-1177,1668-1670`). The
  challenger reproduced it through the real double-click handlers.
- **MS-07** [B-4] After the last finale choice the world returns to PLAYING, and the next tick runs monsters and contact
  damage *before* the clear check (`run_world.gd:696-712,971-984`). A lethal hit can archive a death after the objective
  was met. Owner decision on precedence needed.
- **MS-08** [B-5] Final-boss ground rewards outside magnet range are forfeited when the round clears; only collected
  inventory carries. A payout policy is needed.
- **MS-23** [B-6] The sensible bot scores Gun Pirate / Gunslinger gear with Beginner weights (STR 6, DEX 3), because
  `equipment_weights` has no 500/510/520 entry (`bot_shop.gd:21-26`). This biases the #77 measurements.
- **MS-30** [B-2] The hub's scroll RNG is seeded two different ways: through stream 11 at build, and with the raw hash
  after an action (`free_market.gd:379-381` vs `:411`). The same saved state gives different next rolls live and after
  Continue (Low after challenge: there is no normal-UI foreknowledge).
- **MS-32** [B-3] A multi-level EXP batch allocates AP against the *final* level before each intermediate growth step,
  giving base MP 645 vs 648 over Lv20 → 28 (Low).
- **MS-33** [B-7] Bless's card and tooltip still say accuracy does nothing, but ACC feeds critical chance per ADR 0005
  (`skills/magician.json:319-320`; `loadout.gd:330`) (Low).
- **MS-40** [B-8] Warrior Final Attack/Booster cards count as "power" for pity draws; the Bowman equivalents do not.
  This is a policy decision for #77 (Low).

### 3.3 Performance and scalability (performance-optimization, godot-gdscript, physics-tuning, godot-animation, godot-export)

**Verdict: no performance problem.** Do not replace packed arrays, pooling or RenderingServer drawing. Measured
headroom at 60 Hz is 1.8-2.8x at p99 with 200-340 mobs. Sim cost grows sub-linearly to linearly from 300 to 1,000
mobs. Numbers are in section 4.3.

**Findings:**
- **MS-12** [C-1] `game/tools/profile_run.gd` replays a copied tick that omits Final Attack draining, Hidden and the
  live PDD argument (`profile_run.gd:156-210` vs `run_world.gd:886,905,908`). Its per-system shares for physical classes
  measure a different game.
- **MS-25** [C-2] The victory animation and sound are decoded on first clear. That costs about 10.5 ms of synchronous
  atlas load, and a 23.8 ms frame was measured at the clear (`run_scene.gd:1393-1401`; not in `_warm_ui` /
  `_warm_stage`) (Low).
- **MS-39** [C-3] `playtest.sh` reports success even when the bot dies before the measurement window. This audit's
  first three perf captures returned rc 0 with **zero** density frames. The documented late-game perf recipe (`--warp=600`,
  seed 2026) no longer reaches density on this build (Low).
- Bench drift: same-day medians, HEAD vs `b1e18d3` (#146 era), are +6% per tick on the real map and +9-15% synthetic.
  The step arrives with #151 physical combat. The documented 1,024 µs (#146) is not reproducible today
  (`b1e18d3` measures 1,449). This is not a regression to act on.

### 3.4 Game feel, visuals, audio and UX (game-feel, game-ui-ux, godot-ui-control, camera-systems, audio-design, godot-audio, godot-animation, input-systems, create-game-assets)

**Strengths (keep):**
- Current screenshots match v83 closely: map layering, avatars, the job and weapon dialogs with instructor portraits,
  the Free Market, and the "You died..." results book.
- Damage numbers, hit FX, job pillars, the CLEAR banner and pickup notices are all event-driven.
- Two-player crossfading BGM, 16 pooled SFX voices with per-frame coalescing, and a static bus layout that keeps the
  web-audio fix.
- The window stack pauses consistently; the Skill window has arrow/tab navigation.
- Crisp text (#224) reads well at 1600x1200.

**Findings (screenshots under `evidence/skill-audit/`):**
- **MS-09** [D-1] In crowds, outgoing damage-number columns cover the character. Worst case: Dark Cave
  `visual/dark_cave_s1_x4_fixture/t420.png`, where a 15-row column hides the Lv49 F/P completely. Also
  `perf/density_hg_s2026_fixture_fp/t720.png`, `t780.png`, and `perf/finale_hg_s2026_fixture_fp/t900.png`.
- **MS-24** [D-7 + lead] The red "Not enough MP" cue is stale in two situations:
  - Over the tombstone (`perf/density_hg_s2026/death_land.png`).
  - On a level-up window with **MP 25/25** (`visual/tree_s7_x4_windows/window_cards_3.png`). The HUD reads a cached
    `mp_short` (`hud_messages.gd:25-26`) that the level-up refill does not clear.
- **MS-10** [D-2] F3 can be bound to Stat/Skill/Equip/Item in Key Config, but `RunScene._unhandled_input` consumes F3
  for the perf overlay first (`run_scene.gd:424-430`).
- **MS-19** [D-4] Remembered window positions are restored verbatim and never re-clamped when the logical view
  shrinks, so a window can reopen off-screen (`window_stack.gd:45-50`). Esc still closes it.
- **MS-20** [D-5] Options, Key Config, the inventory/shop and the title utilities (web Export/Import save) are
  mouse-only (`ui_window.gd:46,74`; `wz_button.gd:60`; `title_button.gd:43`).
- **MS-21** [D-6] One 16-voice oldest-steal pool serves every sound, so swarm hit sounds can cut off potion, job,
  death or clear cues. Needs a voice-steal count before any change.
- **MS-34** [D-3] The Free Market header hard-codes "Up at the exit / Space: talk to a scroll NPC"
  (`free_market.gd:317`; visible in `flow/rounds/17_free_market_arrival.png`). It ignores WASD mode, rebinding and an
  unbound NPC Chat (Low).
- **MS-35** [D-8] The README controls table is stale: E is listed as the MP potion but is Equip; A/D and W/S are
  presented as always active; pause "quits to stage select"; window keys and Dash are missing (Low).
- **MS-36** [D-9] The web import screen's URL field and progress bar have no accessible names, tabs are not linked to
  their panels, and focus is not moved on screen changes (Low).
- **MS-26** (above) The judder mechanism on high-refresh displays.

### 3.5 Testing, persistence and distribution (godot-gdscript-headless-testing, save-systems, godot-export, godot-resources)

**Strengths (keep):**
- The runner rejects assertion, runtime and parse failures (verified by injection), and `ScriptErrorGuard` captures
  GDScript errors.
- #103 settings isolation is fixed.
- `SaveData` validates detached data, writes `.tmp` then `.bak`, recovers a missing primary, and commits memory only
  after a successful write. It has extensive migration/recovery tests.
- The importer has bounded directory/ZIP readers.
- CI pins Godot, verifies template checksums and locks wasm-bindgen to `Cargo.lock`.
- Export bundles every licence notice.

**Findings:**
- **MS-01** [E-2] **High.** The web shell accepts any JSON with the right top-level shape (`web/lib.js:352-378`). It
  copies the healthy save to `.bak`, then installs the candidate (`web/shell.js:637-650`). `SaveData` then preserves the
  invalid primary as `.bad` and starts empty (`save_data.gd:86-92`). The **next save copies the invalid primary over
  the good `.bak`** (`save_data.gd:376`). Reproduced: after `create_slot`, both primary and backup no longer hold the
  old characters.
- **MS-02** [E-1] **High.** `SaveData` writes its whole in-memory view without a revision or ownership check
  (`save_data.gd:60,332,354`). Two native instances can run at once (the challenger launched two), and two browser tabs
  share `/userfs`. A stale session overwrites the other's characters and account. Native is reproduced; the web case is
  supported by source but not browser-tested.
- **MS-04** (lead) **Medium.** Two of the three flow-driver QA scenarios fail at HEAD; see section 4.1.
- **MS-13** [E-6] `test_runner.gd:38` counts the inherited static `TestCase.test_dir` as a test in every file: 189 of
  the 2,225 "tests" contain no assertion. An empty filter or a missing directory returns `TESTS_PASSED` with 0 tests
  (`test_runner.gd:63,79`).
- **MS-14** [E-3] The importer accepts enormous canvas dimensions and panics with capacity overflow in the decoder
  (`property.rs:260`, `canvas.rs:13,81,115`). Web staging protects the previous cache. Native writes per file, so a
  failed import can leave a partially updated (repairable) cache (Medium after challenge).
- **MS-15** [E-4] Native folder imports auto-detect any WZ version up to 1000 (`archive.rs:74,119`); ZIP and wasm
  imports force v83 (`wzroot.rs:189`). A v95 install imports on desktop only.
- **MS-16** [E-5] Incremental re-import does not check audio files (`import.rs:254`). A deleted MP3 stays missing after
  a "successful" repair; only `--force` fixes it.
- **MS-17** [E-7] CI builds the web export but never boots it or a Windows build, and runs no flow-driver scenario.
  195 cache-gated tests SKIP there by design (9.6%).
- **MS-18** [E-8] `check_web_artifact.sh` blocks known name and signature shapes but has no shipping allowlist. A
  synthetic extra PNG and a ZIP containing a WZ entry passed.
- **MS-28** [E-11] Settings are saved in place with `cfg.save()`, with no temp/backup step, and callers drop the error
  (Low).
- **MS-37** [E-10] `assert_near` / `assert_between` accept NaN (Low).
- **MS-38** [E-9] The offline scan bans `OS.shell_open` but not `OS.execute` / `create_process`; an uncalled
  `OS.execute("curl")` passes. There is no current violation (Low).
- **MS-41** [E-12] `test_sharp_text.gd:159` calls `root.add_child()` while the root is busy, so the viewport never
  attaches. The test still passes, and engine `ERROR:` lines do not fail the run (Low).
- **MS-42** (lead) The debug scene script `game/scenes/debug/character_driver.gd:100` fails to parse
  (`var wand := …equipment.worn.weapon`: "Cannot infer the type"). It last changed in `0e8b216` (#235), and the export
  log reports it. The suite never loads debug drivers, so nothing caught it; it belongs with MS-04's QA drift. Fix it
  with an explicit type and add a cheap "every `scenes/debug/*.gd` parses" test (Low).

---

## 4. Baseline verification and performance measurements

### 4.1 Environment and test results

Environment: Windows 11 (10.0.26200), Ryzen 7 7800X3D, 31.1 GiB RAM, RTX 4070 SUPER (driver 32.0.16.1088,
3440x1440 at 164 Hz) plus Radeon iGPU (2560x1440 at 143 Hz). Godot 4.7.2.stable.official.ed1daf0bf (editor binary,
debug build), Compatibility/OpenGL 3.3; cargo/rustc 1.99.0; Node 24.21.0; wasm-bindgen 0.2.105; export templates
4.7.2 (Windows and web_nothreads). Real v83 WZ data was present. A **private asset cache** was imported from the
current manifest, because the shared cache predates the 2026-10-19 manifest change: 1,081 imgs, 0 errors, 24
already-documented `swingO2` UOL warnings, 16 s. Every Godot run used `ISOLATE` mirrors and that cache.

| Check | Command | Result | Notes |
|---|---|---|---|
| Godot unit/integration | `ISOLATE=audit-tests bash scripts/test.sh` (real cache) | **PASSED**: 2,225 passed, 0 failed, 0 skipped, 189 files, 758 s | 189 of the 2,225 are the assertion-free `test_dir` helper (MS-13). Two engine errors were logged without failing: `test_sharp_text` add_child, and 2 leaked dummy textures at exit. Without a cache (as in CI), about 195 methods would SKIP. |
| Importer | `cargo test` with `MAPLE_WZ_ROOT` set | **PASSED**: 64 (44 unit, 18 real-WZ, 2 guards) | In CI the 18 real-WZ tests return early and report ok. |
| Web shell | `node --test web/dev/test/*.test.mjs` | **PASSED**: 51/51 | The first invocation passed a directory by mistake (rc 1, the lead's error); re-run with the documented glob. |
| Determinism | Henesys bot, seeds 1/2/2026, run twice | **PASSED**: records byte-identical | |
| Balance smoke | `balance.sh 1 2 2026`, both stages × bot/random | **Ran**, rc 0 ×4, no crashes, `warnings: []`, `missing: []` | Outcomes in section 5.1. |
| Flow `full` | `flow_driver.tscn --scenario=full` | **PASSED** | Title → creation → run → level-ups → job and weapon pages → pause → death → results → Quit round → Continue → history. |
| Flow `rounds` | `--scenario=rounds` | **FAILED** (driver) | Tier 2 passes Lv70 and the game correctly shows the "Not in this build" third-job notice. The driver passes the bot's decline (`job_id -1`) into `_choose_job_ui` (`flow_driver.gd:426,2077`). The driver's 19 checks before that point passed (tier-1 clear, Free Market, Save & quit, tier-2 entry, Quit round and replay); only the Free Market arrival shot was inspected by eye. |
| Flow `economy` | `--scenario=economy` | **FAILED** (driver) | 3 checks expect both drops in the Equip tab, but #222 now auto-equips the Metal Gear ("Equipped Metal Gear" in `10_economy_picked_up.png`). The other 40 checks passed, including Save & quit → Continue restoring mesos, hat and inventory. |
| Visual playtests | 5 × `playtest.sh` at x4 | Ran, rc 0, `missing: []` | Section 5.2. |
| Windows/web export | `export.sh`, `export.sh --web` | See 4.4 | |

Not executed:
- An exported-build browser session or browser performance.
- A two-tab browser persistence test.
- A run with the network adapter disabled.
- Listening tests and a high-refresh motion capture.
- Keyboard-only and screen-reader passes.
- **The other documented flow-driver scenarios**: `title`, `import`, `windows`, `skill`, `keys`, `skill_weapon`,
  `skill_warrior`, `warrior`, `warrior2`, `pirate`, `bowman`, `thief`, `inventory`, `scrolls`, `shops`, `botshop`,
  `cash_shop`, `cash_equip`, `account`. Only `full`, `rounds` and `economy` were run.

None of these is implied by the results above. Two of the three scenarios that were run had gone stale after merges,
so the rest should be presumed unverified on HEAD.

### 4.2 Balance regression smoke (seeds 1/2/2026; no tuning, no held-out seeds)

| Stage / policy | Seed 1 | Seed 2 | Seed 2026 | Previous (#232, 2026-10-18) |
|---|---|---|---|---|
| Henesys / bot | **CLEARED** 15:58, Lv44, F/P (210) | DEAD 4:34, Lv8, Beginner | DEAD 4:19, Lv7, Beginner | D 5:40 / 7:35 / 5:23 (Lv 11/13/11) |
| Henesys / random | DEAD 9:16, Lv27 | DEAD 10:02, Lv25 | DEAD 4:56, Lv9 | D 7:31 / 5:25 / 5:16 |
| Tree / bot | DEAD 9:04, Lv21 | DEAD 16:10, Lv29 | DEAD 0:48, Lv1 | D 2:09 / 1:04 / 0:52 |
| Tree / random | DEAD 9:29, Lv18 | DEAD 2:56, Lv6 | DEAD 0:48, Lv1 | (same as bot) |

Seeded records changed as expected after the #225/#235/#226 merges reshuffled draws on job stream 8. #235 already
recorded the seed 2/2026 Beginner deaths and relaxed the `test_full_run` guard to Lv10 on 1 of 3 runs. Tree remains
owner-deferred. Henesys bot seed 1 is the first natural clear in the recent smokes. Per AGENTS.md these results are
recorded here, not appended to `GAME_DESIGN.md` 4.2: this audit may not edit existing docs.

### 4.3 Performance (uncapped `--vsync=off`, 1600x1200 window, 800x600 logical, editor/debug binary)

| Workload | Max mobs | frame p50 / p95 / p99 / max (ms) | 200+ mob frames: p95 / p99 | Sim µs/tick |
|---|---|---|---|---|
| Henesys s2026, Lv38 F/P fixture, 10:00-13:00 (contended) | 289 | 3.85 / 7.32 / 8.95 / 31.1 | 7.38 / 9.01 (32,950 frames) | 1,187 |
| Henesys s2026, Lv34 Fighter fixture, 10:00-13:00 (contended) | 221 | 2.44 / 4.78 / 6.44 / 35.6 | 5.34 / 7.06 (5,162) | 841 |
| Henesys finale, F/P fixture, 14:00 → clear 15:07 (contended) | 337 | 3.67 / 6.39 / 8.00 / 72.0 | (all frames 200+) | 1,213 |
| God-mode Fighter finale probe ×2 (specialist C, contended) | 334 | 3.1-3.3 / 6.0-6.4 / 9.0-9.5 / 24-33 | same | 1,305-1,368 |

The fixture captures overlapped some specialist probes, so treat them as upper bounds. The 72 ms maximum came in
minute 14, before the third boss, and is not attributed to anything: no per-frame trace exists (MS-39). The
like-for-like comparisons in the docs (fresh seed-2026 Magician, 200+ p95 3.07 ms) cannot be repeated on this build
because that bot now dies at 4:19. The fixture runs carry stronger builds with more drops and FX, so their higher p95
is **not** evidence of a regression.

Headless `bench.sh` on a quiet machine (µs/tick, medians of 3 alternated rounds):

| Commit | Synthetic 300 | Synthetic 1000 | Real map 300 | Real map 1000 |
|---|---|---|---|---|
| `b1e18d3` (#146 era) | 832 | 2,510 | 1,449 | 3,602 |
| `b6af314` (#151 physical combat) | 905 | 2,808 | 1,500 | 3,682 |
| `d1cdb16` (#167) | 897 | 2,900 | 1,577 | 3,747 |
| `0e8b216` (playtest-3) | 900 | 2,912 | 1,530 | 3,691 |
| `2f778db` (#225) | 949 | 2,980 | 1,545 | 3,776 |
| **`a68e74f` HEAD** | 909 | 2,876 | 1,542 | 3,816 |

`bench_world`, real map: 673 µs at 300 mobs and 2,073 at 1,000 (step 1,250, hash 346, queries 477). 1,000 mobs costs
2.5-3.2x the 300-mob cost for 3.3x the mobs, so growth is sub-linear to linear. A contended 2,000-mob all-statused
run costs about 8.2-8.5 ms per tick. Browser figures are only in the docs (#146, ARCHITECTURE 10.4: web
p50/p95/p99 4.0/6.7/9.7 ms vs desktop 2.3/3.6/4.4 ms) and were not re-measured.

### 4.4 Exports

| Check | Result |
|---|---|
| `ISOLATE=audit-export EXPORT_DIR=… bash scripts/export.sh` (Windows, release) | **Built**, rc 0, 40 s: `MapleSurvivors.exe` (116 MB), `wzimport.exe`, `GODOT_LICENSES.txt`, `WZIMPORT_LICENSES.txt`, `ARIMO_OFL.txt`, `THIRD_PARTY_NOTICES.md`. The log has one `SCRIPT ERROR`: the debug-only `res://scenes/debug/character_driver.gd:100` fails to parse (MS-42). |
| Exported exe smoke (`--run=henesys_hg1 --seed=2026 --autoplay --speed=4 --quit-after=120 --perf`) | **Ran**, rc 0. Reached the round and wrote a summary from the private cache. Capped at 164 Hz: frame p50/p95/p99 6.09/6.91/7.20 ms; one **110.8 ms** maximum frame (unattributed; section 10). |
| `bash scripts/export.sh --web` (+ wasm importer, `check_web_artifact.sh`) | **Built**, rc 0, 49 s. `[check_web_artifact] ok … (27 files, no WZ data or cache-shaped files)`. Licence files present. |
| Browser boot / import / persistence of that export | **Not executed** (no browser session in this audit). |

---

## 5. Gameplay and visual observations

### 5.1 The early run is the experience bottleneck (MS-03)

- Henesys schedules its first elite at **240 s** (HP ×8, EXP ×5, damage ×1.5;
  `stages.json` `henesys_hg1.elites.first`). At the same time the 4:00 keyframe raises `max_alive` from 12 to 20 and the
  rate from 0.6 to 1.0.
- The bot reaches Lv10, and with it the first job, at about 4:25-4:35. In the seed-2 bot record, hits per minute for
  minutes 0-3 were `[1,0,0,0]`. The character stood at full HP 148/148 at 4:00 (`visual/hg_s2_x4_job110/t240.png`).
  It then drank all 14 HP potions between 249 s and 269 s and died at 274 s, still a Beginner, in a crowd of about 20
  (`death_fall.png`).
- Seed 2026 died the same way at 4:19 (Lv7), and random-policy seed 2026 at 4:56. A forced Hunter made the job but sat
  at 5:00 with **MP 5/132**, zero blue potions and "Not enough MP" (`visual/hg_s1_x4_job310/t300.png`), then died at
  6:11.
- Skills applied: level-design (the tension curve puts the first spike before the first reward/power beat), rpg (the
  power spike from the first job should precede the first gate), game-feel (death without a readable cause).
- This is a **pacing observation for #77, not a tuning proposal**. The bot is not a human player, n = 3 per cell, and
  the owner balances by personal playtest. Recommended action: a short human playtest of 3-5 fresh Henesys runs to
  confirm whether the 4:00 elite is the decisive spike, and feed that into #77's triage. Confidence: Likely.

### 5.2 Visual run notes (screenshots inspected by eye)

- **Henesys and Tree, early game:** clean, readable and faithful. The level-up card window (`window_cards_3.png`) shows
  real skill cards with rarity bands and clear before/after numbers. The job pillar and the Bowman advancement look
  right (`job_300.png`). The Free Market arrival notice, the "+475 NX" message and the NPC labels are clear.
- **Crowds (200-340 mobs):**
  - Silhouettes and drops stay legible, and the CLEAR banner reads over the crowd.
  - Outgoing damage-number columns are the loudest element and can bury the player (MS-09). In Dark Cave the column
    above the player reaches about 15 digits tall.
  - Drop carpets of 340-390 items line every platform (`t420.png`). Per the owner's rule they never expire; their
    density is a readability topic for the owner, not a defect.
- **Dark Cave (Lv38 F/P fixture):** died at 10:39 at Lv56 after one boss, at **MP 0/2,369** with zero blue potions
  and "Not enough MP" (`boss_windup_1_attack1.png`). The tier is untuned by design (#77). The screen shows a large black
  band below the lowest floor. Whether the v83 client framed this map the same way is unverified (section 10).
- **Results, dialogs and the hub** (`flow/full/21_results_death.png`, `13_full_job_weapon_page.png`,
  `flow/rounds/17_free_market_arrival.png`): authentic v83 UI art, consistent typography, no layout breakage.
  "Spear" without a gift detail on the weapon page is intentional: the item is named "Spear" (`job_advance_window.gd:383`).

---

## 6. Prioritized findings

Severity is after the challenge. Effort: S < 1 day, M 1-3 days, L > 3 days. Confidence: C = Confirmed (reproduced),
L = Likely, V = Needs validation. Types: Bug = confirmed bug; Perf = measured performance issue; Maint =
maintainability risk; UX = UX concern; Prop = proposed improvement.

| ID | Title | Area | Sev. | Type | Conf. | Effort | Skills | Source |
|---|---|---|---|---|---|---|---|---|
| MS-01 | Invalid imported save erases the only good backup on next save | Persistence | **High** | Bug | C | M | save-systems, godot-resources | E-2, X |
| MS-02 | Concurrent sessions (2 instances / 2 tabs) overwrite each other's saves | Persistence | **High** | Bug | C native / L web | M | save-systems, godot-export | E-1, X |
| MS-03 | Fresh characters hit a lethal spike (first elite 4:00) before the Lv10 job | Gameplay | **High** (impact) | UX / Prop (#77) | L | S to validate | level-design, rpg, game-feel | lead |
| MS-04 | Flow-driver `rounds` and `economy` QA fail on main (stale driver after #222 / Lv70) | Testing | Medium | Bug (test) | C | S | headless-testing | lead |
| MS-05 | MaxMP gear swaps refill MP while windows hold the run | Gameplay | Medium | Bug | C | S | rpg, roguelike | B-1, X |
| MS-06 | Leftward wall-clipped charge hits behind the player | Combat | Medium | Bug | C | S | godot-physics, physics-tuning | A-1, X |
| MS-07 | Finale: a lethal tick can follow the last answered choice | Gameplay | Medium | Bug / owner decision | C | S-M | rpg, level-design | B-4, X |
| MS-08 | Final-boss loot outside magnet range is forfeited at clear | Gameplay | Medium | Prop | C | M | rpg, level-design, roguelike | B-5 |
| MS-09 | Damage-number columns bury the character in crowds | Feel/UX | Medium | UX | C (stills) | M | game-feel, create-game-assets | D-1, lead |
| MS-10 | F3 bindable to a window action but intercepted in rounds | Input | Medium | Bug | C | S | input-systems | D-2, X |
| MS-11 | Grenade burst on the presentation clock, damage on the sim clock | Presentation | Medium | Bug | C | M | physics-tuning, godot-signals-groups | A-3 |
| MS-12 | `profile_run.gd` no longer replays the production tick | Tooling | Medium | Bug (tool) | C | M | performance-optimization | C-1, X |
| MS-13 | Runner: empty selection passes; helper counted as 189 tests | Testing | Medium | Bug (test) | C | S | headless-testing | E-6, X |
| MS-14 | Importer panics on huge canvas dimensions | Importer | Medium | Bug | C | M | godot-export, headless-testing | E-3, X |
| MS-15 | Native folder import accepts non-v83 WZ (ZIP/web reject it) | Importer | Medium | Bug | C | S-M | godot-export | E-4 |
| MS-16 | Incremental re-import never repairs missing audio | Importer | Medium | Bug | C | M | godot-export | E-5 |
| MS-17 | CI never boots the exported build or runs flow scenarios | CI | Medium | Prop | C (gap) | M | godot-export, headless-testing | E-7 |
| MS-18 | Web artifact guard lacks a shipping allowlist | Distribution | Medium | Maint | C | S-M | godot-export | E-8 |
| MS-19 | Remembered window position can reopen off-screen after resize | UI | Medium | Bug | C (source) | S | game-ui-ux, godot-ui-control | D-4 |
| MS-20 | Options/Key Config/inventory/shop/web utilities are mouse-only | UI/Access | Medium | Prop | C | M | input-systems, godot-ui-control | D-5 |
| MS-21 | One oldest-steal SFX pool for routine and critical cues | Audio | Medium | Maint | V | M | audio-design, godot-audio | D-6 |
| MS-22 | RunWorld/RunScene concentrate unrelated responsibilities and churn | Architecture | Medium | Maint | C | M (per seam) | godot-nodes-scenes | A-6 |
| MS-23 | Gun Pirate/Gunslinger bot gear uses Beginner (STR) weights | Bot / #77 | Medium | Maint | C | S | game-ai, rpg | B-6 |
| MS-24 | "Not enough MP" cue stale over death and with full MP at level-up | HUD | Low-Med | Bug | C (screens) | S | game-feel, game-ui-ux | D-7, lead |
| MS-25 | Victory art/sound decoded on first clear (~10.5 ms) | Perf | Low | Perf | C | S | performance-optimization, godot-animation | C-2 |
| MS-26 | No render interpolation at 164 Hz (actors step, camera glides) | Feel | Low (validate) | UX | V | M | physics-tuning, camera-systems | A-4, D, X |
| MS-27 | Frame telemetry grows while paused (~9 MiB/h) | Memory | Low | Bug | C | S | performance-optimization | A-2, X |
| MS-28 | Settings saved in place, errors ignored | Persistence | Low | Maint | C (path) | S-M | save-systems | E-11 |
| MS-29 | Reused projectile slot inherits animation phase | Presentation | Low | Bug | C | S-M | godot-nodes-scenes | A-5 |
| MS-30 | Hub scroll RNG seeded differently after Continue | Economy | Low | Bug | C | S | procedural-gen, save-systems | B-2, X |
| MS-31 | `potion_schedule.gd.uid` (and 30 test/debug `.uid`s) not committed | Hygiene | Low | Maint | C | S | godot-resources | A-7 |
| MS-32 | Batch EXP uses the final level for intermediate AP | Progression | Low | Bug | C | M | rpg | B-3, X |
| MS-33 | Bless text says accuracy does nothing | Text | Low | Bug | C | S | rpg | B-7 |
| MS-34 | Free Market hint hard-codes Space/Up | Input | Low | Bug | C | S | input-systems | D-3, X |
| MS-35 | README controls table is stale | Docs | Low | Bug | C | S | input-systems | D-8, X |
| MS-36 | Web import screen accessibility semantics incomplete | Web UI | Low | UX | C (markup) | S | game-ui-ux | D-9 |
| MS-37 | `assert_near`/`assert_between` accept NaN | Testing | Low | Bug (test) | C | S | headless-testing | E-10, X |
| MS-38 | Offline scan misses `OS.execute`/`create_process` | Offline | Low | Maint | C | S-M | headless-testing, godot-export | E-9 |
| MS-39 | `playtest.sh` cannot tell a perf capture that never reached density | Perf tooling | Low | Maint | C | S | performance-optimization | C-3 |
| MS-40 | "Power" card classification differs Warrior vs Bowman | Cards / #77 | Low | Prop | V | S | rpg, procedural-gen | B-8 |
| MS-41 | Sharp-text test fixture never attaches, still passes | Testing | Low | Bug (test) | C | S | headless-testing | E-12 |
| MS-42 | Debug `character_driver.gd` no longer parses (since `0e8b216`) | Tooling | Low | Bug (tool) | C | S | godot-gdscript, headless-testing | lead (export log) |

### 6.1 Finding details: evidence, impact, recommendation, acceptance

Each block lists evidence, impact, the recommended change and the acceptance test. Full reproductions are in the
cited specialist report sections; probes are under `_scratch/audit-{A,B,C,E,X}/`.

**MS-01 Invalid imported save erases the only good backup.**
- Evidence: `web/lib.js:352-378`, `web/shell.js:637-650`, `save_data.gd:69-72,86-92,345,376`. Reproduction:
  `_scratch/audit-E/persistence_probe.log` and `_scratch/audit-X/challenge_probe.log`. Import
  `{"format":2,"best":{},"runs":{},"slots":[{},null,null],"history":[]}`, restart, create a character: neither primary
  nor `.bak` holds the old save any more.
- Impact: web Import save (a shipped feature) can turn a hand-edited, damaged-but-valid-JSON or old-schema backup into
  permanent loss of every character and the NX account.
- Recommendation: validate fully before promotion (stage the candidate, have the game validate it, then promote), or
  roll back to the retained healthy backup on rejection. Never rotate an invalid primary over the last valid recovery
  copy. Do not add a second, drifting validator in JS.
- Acceptance: synthetic malformed slot/account/history and future-format candidates leave the previous primary and
  backup bytes intact across a restart and a following successful save; valid saves still round-trip
  (`test_save_data.gd`, `web/dev/test`).

**MS-02 Concurrent sessions overwrite each other's saves.**
- Evidence: `save_data.gd:60-108,332-385`. Two native instances ran together (`_scratch/audit-X/two-instances.log`);
  `web/idbfs.js:5-17,36` shares one store across tabs.
- Impact: a second window or tab silently deletes characters or purchases. The first stale write still leaves a good
  `.bak`; a second removes it.
- Recommendation: one writer per user-data store. Use an exclusive lock file on desktop, and a Web Locks or
  BroadcastChannel ownership check in `web/` before the engine mounts. Add a clear "already open" screen.
  Alternatively, a save revision check that refuses stale writes. Neither adds networking or JavaScriptBridge.
- Acceptance: a synthetic two-session test either preserves session A's character or reports a conflict; a two-tab
  disposable-origin test covers takeover with no lost records.

**MS-03 Early-run spike before the first job.**
- Evidence: section 5.1.
- Recommendation: no data change in a feature ticket. Run a short human validation (3-5 fresh Henesys runs, F3
  overlay on, note the time and cause of death) and attach the result to #77. If confirmed, #77 can weigh the first-elite
  time against the Lv10 milestone. A cheap diagnostic, not tuning, is a `balance.sh` per-run "killer" field
  (elite/boss/ordinary) so smokes show causes.
- Acceptance: #77 triage contains the human observations and the smoke's cause-of-death breakdown.

**MS-04 Flow-driver QA fails on main.**
- Evidence: `logs/flow_rounds.log` (`job -1 is missing from ["Dragon Knight"]`, `flow_driver.gd:426,2077`) and
  `logs/flow_economy.log` (three checks at `flow_driver.gd:3050,3071` and the tooltip check that follows; auto-equip
  per #222).
- Impact: the only end-to-end checks of tier transitions, the Free Market, Continue and the economy loop are red, so
  later regressions in those paths will be invisible.
- Recommendation:
  - In `_warp_round`, answer `job_id -1` through the window's OK/"Not now." path.
  - Update `economy` to expect one auto-equipped item plus one inventory item, matching #222.
  - In the same task, rerun the ~19 scenarios this audit did not run (section 4.1), because 2 of the 3 it did run were
    stale.
  - Rerun all scenarios before merging spec branches.
- Acceptance: every documented scenario prints PASSED on HEAD with fresh shot directories.

**MS-05 MaxMP swap refills MP.**
- Evidence: `run_world.gd:1165-1177,1668-1670`; `_scratch/audit-B/probe.log` `MP_EQUIP_LOOP`; the challenger's
  real-handler probe.
- Recommendation: let equipment changes clamp only, and keep ratio preservation for passive-rank growth (#41).
- Acceptance: repeated low-MP swaps never raise current MP; passive learning still preserves the ratio.

**MS-06 Charge clipping.**
- Evidence: `skill_runner.gd:455-472`; `_scratch/audit-A/probe.log` `CHARGE`.
- Recommendation: rebuild the clipped rect from its endpoints (keep the right edge when clipping the left).
- Acceptance: the existing wall tests plus a rear-mob case at x=675 and its mirror; movement unchanged.

**MS-07 / MS-08 Finale settlement.**
- Evidence: `run_world.gd:696-712,971-984,1021-1046,2314-2361`; `_scratch/audit-B/probe.log` `FINALE_TRANSITION`,
  `FINALE_LOOT`.
- Recommendation: the owner decides objective precedence. The suggestion is to settle the clear as soon as the last
  mandatory choice is answered, and to transfer or auto-collect the final boss's own reward drops exactly once.
- Acceptance: deterministic lethal-contact and pending-ball cases at the last answer give the agreed outcome; distant
  final kills pay the agreed reward once.

**MS-09 Damage-number congestion.**
- Evidence: the screenshots in section 3.4; `damage_numbers.gd:33-39,190`.
- Recommendation: a presentation-only density policy, such as a per-screen-region cap on outgoing stacks or an option
  for fewer outgoing numbers. Incoming damage and boss cues stay protected; original digits and timings stay at
  ordinary density.
- Acceptance: same-seed A/B at 200-300 mobs keeps the character, incoming damage and a windup identifiable; sim bytes
  identical; owner preference decides the default.

**MS-10 F3 conflict.**
- Evidence: `key_config_window.gd:34`, `key_bindings.gd:89,154`, `run_scene.gd:424-430`.
- Recommendation: reserve F3 as a fixed key, shown as such in Key Config, or let user bindings win.
- Acceptance: a dispatch-level test through `_unhandled_input`.

**MS-11 Grenade clocks.**
- Recommendation: drive the burst from a sim landing event, or from sim-consumed time.
- Acceptance: a 0.5 s hitch and a level-up hold never show the blast before the damage; speed 1/4/8 the same; damage
  and RNG bytes unchanged.

**MS-12 Profiler drift.**
- Recommendation: time the production stages directly, or add a parity test of the copied loop (Final Attack queue,
  Hidden, live PDD).
- Acceptance: identical events, state and RNG digests between the normal and instrumented paths.

**MS-13 Runner accounting.**
- Recommendation: skip inherited/static helpers in discovery, and fail on zero selected files or methods.
- Acceptance: three declared methods report three; an unmatched filter returns non-zero; failure injection is still
  rejected.

**MS-14 / MS-15 / MS-16 Importer robustness.**
- Recommendation: checked dimension arithmetic plus per-canvas and aggregate decode budgets returning `WzError`;
  enforce v83 at the folder import boundary; record and verify MP3/WAV payloads in the up-to-date check and in web
  completeness.
- Acceptance: synthetic oversized, overflow and deep-property fixtures (`testutil.rs`) return errors on native and wasm
  without huge allocations; v95 fails every import path; deleting an MP3 and re-importing restores it.

**MS-17 / MS-18 CI and artifact guard.**
- Recommendation: a no-WZ browser smoke on the exported artifact (boot to the import UI, synthetic save
  export/import/restart, console errors fatal); a Windows export startup smoke; an explicit shipping-file allowlist in
  `check_web_artifact.sh`.
- Acceptance: a planted extra PNG or ZIP fails the checker; the smoke fails on a broken worker or IDBFS.

**MS-19 / MS-20 Windows and keyboard.**
- Recommendation: clamp restored and open window positions on view-size changes; add keyboard focus to Options and Key
  Config first, then inventory, shop and the title utilities, using the SkillWindow model.
- Acceptance: a WindowStack shrink test keeps the title bar reachable; a keyboard-only remap and save/cancel works.

**MS-21 SFX priority.**
- Recommendation: first count steals by role in a dense fixture run, then add a small priority reserve only if
  important cues are being cut.
- Acceptance: the steal counts are recorded, and the voice cap and static buses are unchanged.

**MS-22 Coordinator seams.**
- Recommendation: extract the telemetry recorder together with MS-27; extract the hit-effects/follow-up module the
  next time MP Eater, Final Attack, Drain or Steal changes.
- Acceptance: the public APIs and same-seed event bytes are unchanged.

**MS-23 Gun bot weights.**
- Recommendation: resolve equipment weights by weapon path and branch (DEX for gun and Gunslinger).
- Acceptance: a direction test only; the numbers belong to #77.

**MS-24 Stale MP cue.**
- Evidence: `hud_messages.gd:25-26`; `run_world.gd:2609`; the screenshots in 3.4.
- Recommendation: hide the cue when the run is dead, cleared or ending, and refresh `mp_short` after level-up refills.
- Acceptance: death and full-MP level-up screenshots without the cue; the living MP-wait cue still shows.

**Low items, MS-25 to MS-42.** Each is a single focused change with its acceptance listed in section 9; the full
evidence is in the specialist report named in the "Source" column (`skill-audit-reports/`).

---

## 7. Top 10 highest-value improvements

Ranked by player benefit, correctness and risk reduction relative to cost.

1. **MS-01 Transactional save import** (High, M): closes the only UI-reachable path to permanent loss.
2. **MS-04 + MS-13 Restore the regression net** (S + S): fix the two stale flow-driver scenarios and make the runner
   fail on empty selections and stop counting helpers. Every later fix depends on these being trustworthy.
3. **MS-02 Single writer per save store** (High, M): stops silent character loss from a second window or tab.
4. **MS-03 Validate the 4:00 spike with human play, feed #77** (S): the largest player-experience lever, handled without
   tuning in a feature ticket.
5. **MS-05 MaxMP swap exploit** (S): a free-resource loop that undermines the MP economy the owner designed.
6. **MS-24 + MS-10 + MS-34 + MS-35 Truthful prompts bundle** (4 × S): the stale MP cue, F3, the hub hint and the
   README. Players stop being told wrong things.
7. **MS-09 Damage-number density policy** (M): the clearest crowd-readability improvement in the screenshots, and
   presentation-only.
8. **MS-07 / MS-08 Finale settlement** (S-M after an owner decision): protects the most emotionally important moment
   of a round.
9. **MS-06 Charge clipping** (S): a contract violation in combat, with a ready-made reproduction.
10. **MS-14 / MS-15 / MS-16 Importer hardening** (M): first-run robustness for every new player, with web parity.

## 8. Quick wins vs larger initiatives

**Quick wins (S, independent, low risk):** MS-04, MS-13, MS-37, MS-41 (test infrastructure); MS-05, MS-06, MS-33,
MS-30 (sim correctness); MS-24, MS-10, MS-34, MS-35 (prompts and docs); MS-25 (warm the clear art); MS-31 (commit the
`.uid` files); MS-39 (opt-in perf qualification); MS-23 (gun weight direction); MS-19 (window clamping).

**Larger initiatives (M+, need design or owner input):**
- MS-01 and MS-02 (save transactions and single writer, desktop and web).
- MS-03 → #77 (balance pass).
- MS-07 / MS-08 (finale settlement policy).
- MS-09 (number density option).
- MS-20 (keyboard access across windows).
- MS-14 / MS-15 / MS-16 (importer budgets and parity).
- MS-17 / MS-18 (target smokes and allowlist in CI).
- MS-22 (seams, opportunistically).
- MS-26 (an interpolation prototype, only if a motion capture shows judder the owner dislikes).

## 9. Recommended implementation sequence and backlog

Each task is small and independently mergeable. "Load" lists the skills to read before implementing (paths under the
installed skill root). Gameplay changes need a seeded test; visual changes need an `evidence/` screenshot (AGENTS.md).

**Wave 1: trustworthy verification (do first, so everything after is provable).**

| # | Task | Acceptance | Load |
|---|---|---|---|
| 1 | Fix `rounds`: answer a decline (`job_id -1`) through OK/"Not now." in `_warp_round` | `rounds` PASSED on HEAD | godot-gdscript-headless-testing |
| 2 | Fix `economy` for #222 auto-equip (one worn plus one inventory item) | `economy` PASSED on HEAD | godot-gdscript-headless-testing |
| 3 | Runner: exclude inherited/static helpers; zero files or methods → non-zero exit | 3 declared = 3 reported; bad filter rc ≠ 0 | godot-gdscript-headless-testing |
| 4 | Reject NaN/inf in `assert_near`/`assert_between` | NaN fails; finite boundaries unchanged | godot-gdscript-headless-testing |
| 5 | Attach the sharp-text viewport under the test scene (or drop the attach) | No busy-parent ERROR in the suite log | godot-gdscript-headless-testing |
| 6 | Opt-in perf qualification in `playtest.sh` (`warped_to`, ticks > 0, N frames at 200+) | Early-death captures marked unqualified | performance-optimization |
| 7 | `profile_run.gd` parity test (Final Attack, Hidden, live PDD) | Identical event/state digests | performance-optimization |
| 7a | Fix `character_driver.gd:100` typing; add a test that every `scenes/debug/*.gd` and `tools/*.gd` parses | Export log free of SCRIPT ERROR; the new test fails on a planted parse error | godot-gdscript, godot-gdscript-headless-testing |

**Wave 2: save safety.**

| # | Task | Acceptance | Load |
|---|---|---|---|
| 8 | Stage and fully validate imported saves; never rotate an invalid primary over a valid `.bak` | Old bytes survive invalid import + restart + next save | save-systems, godot-resources |
| 9 | Desktop single-instance lock on the user-data dir, with an "already running" message | Second instance refuses to write | save-systems, godot-export |
| 10 | Web single-tab ownership (Web Locks/BroadcastChannel in `web/`), with takeover | Two-tab synthetic test loses nothing | save-systems, godot-export |
| 11 | Atomic settings write (temp + backup) and surface failures | Unwritable path keeps old prefs and reports it | save-systems |

**Wave 3: gameplay correctness (each with a seeded deterministic test).**

| # | Task | Acceptance | Load |
|---|---|---|---|
| 12 | Equipment MaxMP change clamps only | Swap loop gains 0 MP; #41 ratio kept | rpg |
| 13 | Charge clip keeps the far edge | Rear mob at x=675 not hit; mirror case | godot-physics, physics-tuning |
| 14 | Hub scroll RNG uses one derivation | Same next roll live and after rebuild | procedural-gen, save-systems |
| 15 | Per-level AP before each intermediate growth step | Batch = stepwise base MP | rpg |
| 16 | Bless text: ACC contributes to crit | Card and tooltip match `Loadout.stats` | rpg |
| 17 | Gun/Gunslinger bot weights by path (direction only) | DEX preferred for guns, STR for knuckles | game-ai, rpg |
| 18 | Owner decision, then finale settlement (precedence + final-boss payout) | Lethal tick at last answer gives the agreed outcome; payout exactly once | rpg, level-design |

**Wave 4: feel, prompts and UI.**

| # | Task | Acceptance | Load |
|---|---|---|---|
| 19 | Hide the MP cue on death/clear and refresh it after level-up refill | Screenshots: tombstone and full-MP level-up without the cue | game-feel, game-ui-ux |
| 20 | F3 reserved (shown in Key Config) or user binding wins | Dispatch-level test | input-systems |
| 21 | Free Market hint from live action labels | Hint follows WASD/rebind/unbound | input-systems |
| 22 | README controls table matches InputMap and GAME_DESIGN 2 | Every default verified | input-systems |
| 23 | Warm FX_CLEAR / SND_CLEAR at setup | No page load at clear | performance-optimization, godot-animation |
| 24 | Clamp windows on view resize | Shrink test keeps the title bar reachable | game-ui-ux, godot-ui-control |
| 25 | Keyboard focus for Options and Key Config (then inventory/shop/title utilities) | Keyboard-only remap/volume/save | input-systems, godot-ui-control |
| 26 | Prototype the damage-number density policy behind an option | Same-seed A/B screenshots; owner decides | game-feel, create-game-assets |
| 27 | Web import a11y (labels, tab/panel ids, focus on screen change) | Accessibility snapshot names the controls | game-ui-ux |

**Wave 5: importer, distribution, structure.**

| # | Task | Acceptance | Load |
|---|---|---|---|
| 28 | Canvas size budgets and checked arithmetic → `WzError` | Oversized fixtures error on native and wasm | godot-export |
| 29 | v83 enforced for folder imports | v95 rejected on every path | godot-export |
| 30 | Audio payloads in up-to-date/completeness checks | Deleted MP3/WAV repaired | godot-export |
| 31 | Shipping allowlist in `check_web_artifact.sh` | Planted PNG/ZIP rejected | godot-export |
| 32 | CI: browser boot + synthetic save smoke; Windows startup smoke | Smoke fails on broken worker/IDBFS | godot-export, godot-gdscript-headless-testing |
| 33 | Offline scan covers `OS.execute`/`create_process` with an importer allowlist | Synthetic `curl` call rejected | godot-gdscript-headless-testing |
| 34 | Commit the missing `.uid` sidecars | Clean import leaves the tree clean | godot-resources |
| 35 | Bounded telemetry recorder (also the first RunScene seam) | Paused retention constant; summaries unchanged | godot-nodes-scenes, performance-optimization |
| 36 | Projectile draw generation (fresh animation on slot reuse) | Same-slot reuse restarts the animation | godot-nodes-scenes |
| 37 | Grenade burst from sim landing | Hitch/level-up never shows the blast early | physics-tuning, godot-signals-groups |
| 38 | SFX steal counters by role (instrument first) | Counts recorded in a dense run | audio-design, godot-audio |
| 39 | Validate MS-26: record the same movement at 60 and 164 Hz (walk, ladder, knockback, portal); prototype presentation-only interpolation only if the owner sees judder | Owner decision recorded; if adopted, same-seed sim bytes unchanged and no interpolation across teleports or slot reuse | physics-tuning, camera-systems |
| 40 | MS-40 for #77: decide and document which offensive passives/buffs count as "power" per line; encode it in a data test | Written rule plus a data-level test; draw changes only with owner approval | rpg, procedural-gen |

## 10. Areas requiring additional verification

- **High-refresh motion (MS-26):** record 60 vs 164 Hz movement (walk, ladder, knockback, portal) and get the owner's
  judgement before any interpolation work. The mechanism is confirmed; visibility is not.
- **Browser behaviour:** two-tab persistence (MS-02), IndexedDB eviction, the exported-build boot, and current browser
  frame times. None was run in this audit; web numbers come from the docs.
- **Early spike cause (MS-03):** human runs, plus a cause-of-death breakdown per smoke.
- **Audio (MS-21):** listening on speakers and headphones through title → map → boss → Free Market, and voice-steal
  counts in a dense run.
- **Dark Cave framing:** the black band below the lowest floor (`visual/dark_cave_s1_x4_fixture/t420.png`). Compare
  against a v83 reference capture before treating camera bounds or `ANCHOR_Y` as a defect.
- **Frame-time tail:** 24-72 ms maxima in dense uncapped runs, and one 110.8 ms frame in the exported release exe's
  2-minute smoke, have no attribution. Record the top-N slow frames with
  sim time, page loads and alive count before optimizing anything.
- **Release build:** all perf numbers are from the debug editor binary; a release-export capture of the same fixture
  window is still owed.
- **Asset memory across rounds:** title → Henesys → hub → Dark Cave → title, repeated, to see whether retained
  textures plateau.
- **Keyboard-only and screen-reader passes** of the menus and the web shell.
- **The ~19 flow-driver scenarios not run here** (listed in 4.1), presumed unverified on HEAD.
- **Camper/rope exploits** on the current class set: historical camper samples predate the physical classes.

---

## 11. Final recommendation

**Three improvements most likely to improve the player experience:**
1. **Make the opening minutes survivable and readable** (MS-03 → #77, validated by human play first). Half of the
   fresh Henesys smoke runs end between 4:19 and 4:56, before or right at the first job, the moment the game is
   supposed to open up.
2. **Make the finale and crowds legible and fair**: finale settlement (MS-07 / MS-08) and a damage-number density
   policy (MS-09) that keeps the character and threats visible at 200-340 mobs.
3. **Stop telling players wrong things**: the stale "Not enough MP" cue, F3 rebinding, the Free Market hint and the
   README (MS-24, MS-10, MS-34, MS-35), plus the MaxMP swap loop (MS-05) that quietly breaks the MP economy.

**Three improvements most likely to improve technical quality:**
1. **Save safety**: transactional import and a single writer per store (MS-01, MS-02).
2. **A regression net that can't silently go green**: green flow scenarios on main, a runner that rejects empty or
   helper-inflated runs, and target smokes in CI (MS-04, MS-13, MS-17).
3. **Importer robustness and parity**: decode budgets, v83 enforcement on every path, audio repair (MS-14, MS-15,
   MS-16).

**Single highest-return first task: MS-01, transactional save import.** It is the one path to permanent loss of every
character and the NX account that a shipped UI feature can reach. The fix is contained (`web/shell.js` +
`save_data.gd` rotation rule), and synthetic saves can prove it. Do it right after the one-hour Wave 1 fixes that make
the result verifiable.

---

## Appendix A: audit integrity and disclosures

- **Tree state.** The worktree was clean at the start and at the end (`git status --short` empty), apart from this new
  file. One specialist's first test launch went through WSL `bash`, which dropped the environment variables and
  generated 31 untracked `.gd.uid` files in `game/`. The agent removed them immediately and verified a clean tree. No
  tracked file was ever modified.
- **Network.** One specialist's scratch-XDG launcher attempted a Godot editor download before an explicit binary was
  supplied; it was stopped. No game or importer code made network requests.
- **User data.** The real `save.json` and `settings.cfg` hashes were recorded before the audit
  (`evidence/skill-audit/env/user_files_before.sha256`) and re-checked after (Appendix B). The shared asset cache was
  not written; all runs used `cache-skill-audit`.
- **Perf phase 1.** The first three uncapped captures returned rc 0 but died in the warp, so they contained no density
  frames. They were replaced by fixture captures, which overlapped some specialist probes and are labelled contended
  (MS-39 came from this).
- **Pipeline script.** It was edited while running, which caused one bash parse error after the checks phase. It was
  re-run from a frozen copy; no step was skipped silently.
- **Balance and seeds.** No balance data was changed, no tuning candidates were run, and only seeds 1/2/2026 were used.
- **Model.** Every subagent was GPT-6.1-Sol (High), per the brief.
- **Unchallenged findings.** MS-03, MS-04, MS-24's living-state extension and MS-42 were found by the lead after the
  challenge round and were not independently challenged. MS-04 and MS-42 are proven by logs. MS-03's cause (the 4:00
  elite) rests on keyframe timing and potion-drain timing; the balance records carry no elite-specific fields, so it
  stays "Likely".

## Appendix B: evidence index

`evidence/skill-audit/`:
- `env/`: environment, import log, user-file hashes.
- `pipeline.log`: every step with its exit code.
- `logs/`: test suite, cargo, node, bench, benchcmp, profile, flow, export.
- `perf/`: uncapped captures with summaries and screenshots.
- `balance/`: smoke records, summaries, and the determinism repeat.
- `visual/`: x4 playtests.
- `flow/{full,rounds,economy}/`: flow-driver shots.
- `reports/`: the common brief and the A-E and X specialist reports.

User-file check after the whole pipeline: the SHA-256 of `%APPDATA%\MapleSurvivors\save.json` and `settings.cfg` is
unchanged (`env/user_files_before.sha256` = `env/user_files_after.sha256`). The shared cache's `cache.json` still
carries its 2026-10-18 08:12 timestamp. Final `git status --short`: only `?? docs/audits/`.
