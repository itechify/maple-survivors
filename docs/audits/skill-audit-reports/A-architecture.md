# A — Architecture and code quality audit

Audited HEAD `a68e74f`. Audit only: no implementation or balance changes. Seven findings: five Medium, two Low; no Critical or High defect established. Source inspection and synthetic probes establish the mechanisms below; they do not establish an observed visual complaint or a measured production memory/performance regression.

## 1. Skills read and application

All six assigned SKILL.md files were read in full from the installed project skills directory, not the worktree skill directory:

- `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-gdscript/SKILL.md` — typed boundaries, lifecycle, return types and warning settings. Also read `references/annotations-and-typing.md`.
- `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-nodes-scenes/SKILL.md` — scene ownership, deferred replacement, deletion versus removal/reparenting, autoload roles. Also read `references/tree-and-instancing.md`.
- `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-signals-groups/SKILL.md` — parent wiring, Callable lifetime, one-shot callbacks and intentional direct owner-to-component calls. Also read `references/signal-patterns.md`.
- `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-resources/SKILL.md` — shared resource mutation, cache ownership, pure content data and stable UIDs. Also read `references/resource-patterns.md`.
- `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-physics/SKILL.md` — applied narrowly to collision bounds and the distinction between discrete and swept checks. Its body/layer/mask/Jolt recommendations do not apply: this project deliberately uses custom deterministic 2D geometry. No replacement with Godot bodies is proposed.
- `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/physics-tuning/SKILL.md` — fixed timestep, catch-up bounds and render interpolation. Also read `references/timestep-and-ccd.md`. Movement constants and the two movement substeps are preserved.

The custom JSON cache and survivor JSON are valid deliberate data interfaces. The resources skill is not grounds for converting them to `.tres`, nor are the scene skills grounds for adding an entity Node per mob/projectile.

## 2. Scope, evidence and check status

### Source and documentation

Read `COMMON_BRIEF.md` in full first and the repository `AGENTS.md`; consulted architecture contracts 4.1–4.5, movement/data/performance sections and web measurement context; GAME_DESIGN movement, moving attacks and relevant provenance; ASSET_PIPELINE cache format/runtime consumption; IMPLEMENTATION_PLAN performance log; RESEARCH §6; ADRs 0001–0005; GLOSSARY and issue-tracker guidance.

Inspected the four autoloads, bootstrap/scene switching, RunScene and FreeMarket, window stack and inventory wiring; all direct RenderingServer item allocation/free sites; SpritePool, DamageNumbers, MobRenderer, ProjectileRenderer, PickupRenderer, PetRenderer, FxRenderer, CameraRig, and map/avatar renderer ownership. Reviewed RunWorld orchestration, player/stat/equipment/hit/reward portions and the assigned swarm/director/runner/upgrade/bot modules; foothold, player-motion, ladder, portal and spatial-hash math; DataRepo merging, cached WZ objects and relevant synthetic/real-cache test contracts. This was not a line-by-line proof of every skill's gameplay semantics.

| Check | Status / result |
|---|---|
| Initial HEAD/status | Passed: `a68e74f`, initially clean. Final source status also clean. |
| Six skills plus five references listed above | Passed: read in full. |
| `rg` for nodes/Input/Time/files/autoloads in sim | Passed: broad scan found only explanatory comments mentioning presentation services; no executable forbidden dependency found. No `load`/`preload` dependency on presentation discovered. |
| All `canvas_item_create` / `free_rid` under scripts | Passed ownership inspection: allocation occurs only in SpritePool and DamageNumbers; see strengths below. |
| `git log --stat`, `--numstat`, `git log -S` | Passed, exit 0: churn, origin of frame retention/projectile age tracking and charge clipping checked. |
| `gh issue list --repo itechify/maple-survivors --state all --limit 300` | Passed, exit 0; reviewed issue titles, then bodies of #190, #146, #46 and #77. Only #46/#77 open. Findings below were not identified as an existing open task. |
| Focused `render_reparent spatial_hash footholds` tests | Passed: 21 tests, 0 failed, 0 skipped, 3 files. Correctly isolated repeat: `_scratch/audit-A/focused-isolated-tests.log`; exit 0. |
| Synthetic architecture probe | Passed execution, exit 0: `_scratch/audit-A/probe.gd`, `_scratch/audit-A/probe.log`. Confirmed charge clipping, slot animation age, fixed/render cadence, flight-clock drift, telemetry retention, and world release. |
| Full tests/importer/node/balance/playtests/exports | Not executed by this auditor; owned by the lead. No duplicate standard verification and no balance seeds consumed. |
| High-refresh visual check / multi-stage memory plateau / repeated real menu-flow teardown | Not executed here; no visual or peak-memory conclusion inferred from headless output. |

Runtime coordination: `evidence/skill-audit/PERF_DONE` existed when runtime work began. Later inspection found it absent, so no additional runtime work was started. These probes measure correctness/counts, not uncontended timing. A blank/absent sentinel is not interpreted as a verification pass.

Containment disclosure: the first focused-test launch set environment variables in PowerShell, but this machine's Windows `bash.exe` is WSL and did not forward them. Its import generated 31 previously untracked `.gd.uid` sidecars in the source tree. They were removed and `git status --short` verified clean. The corrected run sets variables inside Bash and uses `_scratch/godot_runs/audit-A/game`, scratch XDG user data, and an explicit existing Godot binary. A wrapper lookup under scratch XDG attempted an editor download before the explicit binary was supplied; that attempt was stopped. One first probe failed to parse because `weakref()` inference triggered the existing Variant-inference error setting; the scratch probe was explicitly typed and rerun successfully. These were audit setup failures, not game defects. The Windows save, settings and shared cache were not written. Corrected synthetic probes did not need proprietary assets.

Representative corrected invocation (the existing Linux binary is needed because the default Windows launcher selects WSL):

```bash
MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit \
ISOLATE=audit-A \
XDG_DATA_HOME=/mnt/c/Users/itech/.t3/worktrees/maple-survivors/t3-eb28f480/_scratch/audit-A/user \
GODOT=/home/itech/.local/share/MapleSurvivors/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64 \
bash scripts/test.sh render_reparent spatial_hash footholds
```

The probe uses the same environment, `--headless --path _scratch/godot_runs/audit-A/game --script <absolute scratch probe path>`. It uses existing synthetic fixtures and does not save a playable character.

## 3. Strengths worth preserving

- **The sim boundary holds.** RunWorld takes plain setup data and fixed ticks, and `drain_events()` replaces the pending list (`run_world.gd:682`). Rendering and UI consume data or use public commands. The observed presentation writes are documented seams: live view size, live ALERT settings, and the hub's deterministic scroll seed (`run_scene.gd:532,799`; `free_market.gd:411,452`). Inventory actions go through RunWorld, not arbitrary equipment dictionary edits.
- **RID ownership distinguishes tree membership from object lifetime.** SpritePool allocates at `sprite_pool.gd:55`, frees at PREDELETE (`:28`) or `free_all()` (`:119`), and clears its list to prevent a second free. DamageNumbers owns both child effect and number RIDs (`damage_numbers.gd:232,234`) and frees effects before their parents (`:57–76`). There are no extra unmatched item allocations in run/render. Reparent tests pass for pooled effects, damage numbers, mobs and projectiles. Do not move this cleanup into `_exit_tree`: actors intentionally move between layer containers.
- **Scene ownership is direct and understandable.** Main remains the Flow host (`main.gd:21`); `_swap_now` removes and queues the outgoing scene before adding the new child (`scene_flow.gd:530`). Children own windows/renderers; the four autoloads are genuine global services. FreeMarket has a separate movement model and a map-less inventory world, rather than advancing hidden combat.
- **The normal signal/timer paths have lifetime owners.** The choice-window cleanup timer connects directly to `window.queue_free` (`run_scene.gd:1502`); the screenshot callback is one-shot (`:2034`); the timeout callback targets the RunScene (`:1926`); the hub's notice tween is created on its owning Node (`free_market.gd:333`). Fx follow targets are weak references (`fx_renderer.gd:69,163`). Ordinary bound callbacks did not retain the synthetic world: probe `WORLD_RELEASED=true` after scene deletion.
- **Audio is bounded and shared resources are protected.** AudioService has two BGM players and 16 pooled voices (`audio_service.gd:12,35–48`). BGM duplicates the cached stream before enabling looping (`:65`), avoiding mutation of a shared cached sound. Surviving audio nodes across a scene change is intentional service ownership, not a per-round Node leak.
- **Content duplication is mostly data, not repeated class implementations.** DataRepo has explicit ordered merge rules and duplicate/unknown-line tests (`data_repo.gd:35–210`; `test_data_repo_lines.gd`). SkillBook caches family requirements; Loadout resolves shared mechanics; SkillRunner dispatches behavior rules shared across lines. Mastery/Booster/Final Attack variants are appropriately entries, not five class-specific caster implementations.
- **Type discipline is already strong at function boundaries.** A multiline-signature scan over sim/run/core found zero missing return annotations and zero `var name = ...` declarations. The project's 32 warning suppressions under scripts are specifically `integer_division`, consistent with item-ID arithmetic, rather than blanket unsafe-access suppression. Event dictionaries have exhaustive shape/type scenario tests (`test_run_events.gd:23–109,386`). JSON integer casts are visible at IDs, indexes and discrete stats; no concrete float-key defect established.
- **Custom collision already uses the right techniques.** ProjectileSystem uses swept segment/box entry and broad-phase padding (`projectile_system.gd:179–264`), not endpoint-only bullet collision. Footholds distinguish floors, walls and ceilings; player motion substeps, drop-through platform exclusion, bounds and ladder metadata are explicit. The focused foothold/spatial tests pass without SKIPs.

## 4. Findings

### A-1 — Leftward charge wall clipping enlarges the rear of the hit area

- **Category / severity:** Collision correctness — **Medium**.
- **Finding type / confidence:** Confirmed bug / **Confirmed**.
- **Evidence:** `game/scripts/sim/skill_runner.gd:455–472`, especially `:469`, changes `path.position.x` to the wall for a leftward charge while retaining `path.size.x`. In Rect2 that moves both edges; it does not preserve the original right edge. Rightward clipping sets `path.end.x` and correctly changes width.
- **Reproduction:** `_scratch/audit-A/probe.gd` reuses `test_moving_attacks.gd`'s synthetic skill: player x=600, flat ground, wall x=580, toward/during distance=300, attack box [-60,40]. Near target x=590 chooses a leftward cast; another mob is at x=675, behind the character and outside the original sweep's right edge x=640. The player stops at x=580.01, but `hits=[0,1]`, including the rear mob. The proper clipped sweep is approximately [580,640]; the current one extends approximately [580,700]. Log: `_scratch/audit-A/probe.log`, `CHARGE`.
- **Skills applied:** `godot-physics` collision geometry/correct contact boundaries; `physics-tuning` swept-volume validation and testing both directions, adapted to this custom solver.
- **Impact:** A terrain-limited Brawler charge can damage enemies outside the intended swept path. The player movement itself stops correctly; this is a hit-area calculation defect.
- **Recommended improvement:** Preserve the old right edge while moving the left edge: compute clipped endpoints and rebuild the Rect2/width. Leave displacement distance, foothold movement and all balance values unchanged.
- **Effort:** S.
- **Regression / acceptance:** Add the reproduction alongside the existing left/right wall tests; rear x=675 must not be hit, near x=590 must be hit, and player position must remain x=580.01. Also mirror it rightward and preserve open-ground charge behavior.
- **False positive if:** Charges deliberately extend their rear reach when blocked by walls. Checked: the resolver contract and #190 explicitly restrict hits to the swept path; existing tests exclude beyond-path mobs, but do not test this rear expansion.
- **Known/intentional check:** GAME_DESIGN §7.13, #190 body, existing `test_a_charge_never_hits_a_mob_just_past_the_wall_that_stopped_it`. `git log -S 'path.position.x = maxf'` traces it to `a1e6a05` (#168). Not the deliberate movement feel or a known Tree balance issue.

### A-2 — Ordinary paused play keeps an unbounded full-frame telemetry history

- **Category / severity:** Memory/lifetime — **Medium**.
- **Finding type / confidence:** Confirmed bug (unbounded retention of optional diagnostic samples) / **Confirmed**.
- **Evidence:** `game/scripts/run/run_scene.gd:397–406` calls `_record_frame` every process frame. `:2050–2059` appends to `_frame_ms`, `_present_us`, `_frame_t`, `_frame_alive` after warmup regardless of `_perf_on`, autoplay, output requests or `paused`. Only the two-second overlay lists are trimmed (`:2060–2069`). The four retained arrays are 16 raw bytes per recorded frame.
- **Reproduction:** Probe sets `paused=true`, leaves `_perf_on=false`, calls `_record_frame` 10,060 times: `retained_frames=10000 raw_array_bytes=160000`. These are actual array lengths, not estimated process-memory readings. At 164 FPS their raw payload alone is about 9.0 MiB per wall-clock hour, including an indefinitely open pause/options window; uncapped rendering increases it. It is released when the RunScene is deleted.
- **Skills applied:** `godot-nodes-scenes` per-scene state lifetime; `godot-resources` explicit retention ownership; `godot-gdscript` lifecycle-driven updates.
- **Impact:** A player leaving a paused round open consumes growing memory for diagnostics they did not enable. Tool summaries also duplicate/sort accumulated samples (`:1950`), creating a transient extra allocation. No OOM was reproduced.
- **Recommended improvement:** Separate bounded overlay samples from full recording. Retain complete history only for explicitly requested automation/perf output; use bounded samples or per-minute aggregates otherwise. F3 should remain useful when enabled mid-round.
- **Effort:** S–M.
- **Regression / acceptance:** With perf/output off, a long synthetic paused-frame loop must retain bounded samples. With explicit recording on, preserve current summary fields and percentile/minute/crowd grouping behavior. Samples should be released at scene deletion.
- **False positive if:** Full-frame diagnostics are an unconditional product requirement for all play sessions. Checked: docs describe automation/perf output and F3, not persistent full-history collection while ordinary play is paused.
- **Known/intentional check:** Architecture §6, RunScene options/header and performance logs; #146 concerns a different sim hot path. `git log -S '_frame_ms.append'` traces retention to `209be82`. Do not confuse these arrays with the intentional non-expiring EXP drops.

### A-3 — Grenade flight visuals can finish while their simulated flight is still pending

- **Category / severity:** Fixed-tick/presentation correctness — **Medium**.
- **Finding type / confidence:** Confirmed bug / **Confirmed** for the clock mismatch; player-visible frequency needs visual validation.
- **Evidence:** RunScene caps catch-up and discards excess accumulated time (`run_scene.gd:535–557`) but passes the full frame delta to `_present` (`:589`). `_update_throws` adds that full delta and plays the Grenade burst when the visual duration elapses (`:1299–1312`). Simulation flight time is decremented only by actual fixed ticks (`skill_runner.gd:510–534`). The visual also advances while a choice holds the world, since `held` only represents manual pause/nonmodal windows, not the CHOOSING state.
- **Reproduction:** Probe schedules a 0.2-second sim flight and its matching throw visual, then supplies a 0.5-second frame at speed 1. Only 4 ticks (0.0666667 seconds) run. The real throw-update method plays one burst and removes the visual; sim flight remains with 0.1333333 seconds left. Log: `HITCH` / `THROW_HITCH` in `_scratch/audit-A/probe.log`. The FX sink is synthetic so this establishes scheduling, not rendered pixels.
- **Skills applied:** `physics-tuning` fixed accumulator versus render time; `godot-signals-groups` communicate authoritative completion through events instead of independently inferring it.
- **Impact:** The blast can appear before damage lands, or a Grenade can visually land during a level-up choice while its actual damage waits. Ordinary final-attack ammo is expressly visual-only and is a different contract.
- **Recommended improvement:** Keep the catch-up cap. Anchor gameplay-bearing flight progress to consumed sim time/cast timestamps, and preferably emit a Grenade landing event to trigger the burst. Use presentation interpolation only between those authoritative timestamps. Cosmetic level-up/window animations can retain their existing clocks.
- **Effort:** M.
- **Regression / acceptance:** A 0.5-second hitch and a CHOOSING pause must not trigger the Grenade blast before the sim landing. Check speed 1/4/8 with the same cast/landing ticks; preserve existing damage/RNG results. Final-attack visual-only flights should retain their intended immediate-damage semantics.
- **False positive if:** Grenade burst art is intentionally independent of damage timing. Checked: `_on_skill_thrown`'s contract explicitly says the sim strikes at the same moment; GAME_DESIGN §7.20 and the flight event fields describe that relationship.
- **Known/intentional check:** The four-tick cap is intentional; it is not the finding. GAME_DESIGN §7.20, #192 naming and architecture event schema checked. No request to retune movement or catch up all lost wall time.

### A-4 — Actors render raw 60 Hz positions at a higher display cadence

- **Category / severity:** Presentation smoothness — **Medium**.
- **Finding type / confidence:** UX concern / **Confirmed** absence of interpolation; perceptual severity needs validation.
- **Evidence:** `_acc` is used only to schedule ticks (`run_scene.gd:527–559`), not as a render fraction. Player position is assigned from `p.pos.round()` (`:1664`); mobs use `roundf(xs[i]), roundf(ys[i])` (`mob_renderer.gd:175`), projectiles do the same (`projectile_renderer.gd:63`), and FreeMarket draws `motion.player.pos.round()` (`free_market.gd:550`). Camera smoothing is independent exponential follow; it does not interpolate actors.
- **Reproduction:** Synthetic RunScene subclass preserves the actual accumulator and samples player draw positions over 164 equal render frames: 59 fixed ticks over the floating-point frame interval and 105 repeated adjacent rounded positions. This demonstrates sample-and-hold, not a new 59 Hz timing defect. Architecture §10.4 reports a 164 Hz development display in its prior measurement session; current monitor refresh was not independently measured here.
- **Skills applied:** `physics-tuning` core guidance to interpolate visual state between fixed ticks, while leaving physics and movement constants fixed.
- **Impact:** At a display cadence around 164 Hz, movement positions persist for an uneven roughly 2–3 displayed frames per tick, even when frame CPU cost is low. Animation clocks/camera can move on intervening frames, producing a cadence mismatch. A screenshot or p95 number alone cannot prove or disprove the perceptual effect.
- **Recommended improvement:** Evaluate a presentation-only previous/current position snapshot and `_acc / DT` interpolation for actors and their attached tags/effects, rounding the final visual positions. Reset interpolation on portals, teleport, spawn/slot reuse, scene changes and pause transitions. Do not enable a Godot physics interpolation setting and assume it covers custom RenderingServer items/custom ticks.
- **Effort:** M.
- **Regression / acceptance:** Compare motion recordings at 60, 120, 144 and 164/165 Hz; actor/tag attachment and pixel alignment must remain correct. Same seed/input/tick stream must retain identical sim events and endpoints. No interpolation across teleports or distinct entities reusing a slot. Obtain the owner's visual judgement before making it default.
- **False positive if:** Intentional v83-style pixel cadence is preferred to smoother high-refresh motion. The source mechanism is certain, but this preference was not resolved by the brief; mark the visual decision as pending rather than claiming an observed player complaint.
- **Known/intentional check:** GAME_DESIGN §3 fixed step, architecture §4.5 pixel snapping/camera and §10.4 refresh context. The custom solver, 60 Hz integration and pixel-art snapping are intentional and stay intact.

### A-5 — Projectile slot reuse can inherit a previous projectile's animation phase

- **Category / severity:** Pool lifecycle/presentation correctness — **Low**.
- **Finding type / confidence:** Confirmed bug / **Confirmed**.
- **Evidence:** `projectile_renderer.gd:45–53` resets `_age` only if the renderer observed an inactive slot or a changed visual. `projectile_system.gd:114–172` can despawn and respawn the same slot between presentation samples. RunScene can execute several ticks before `_present` (`run_scene.gd:538–554`), especially at speed >1 or after a slow frame. There is no projectile spawn generation in the draw contract.
- **Reproduction:** Probe draws an actual ProjectileSystem slot with the synthetic mob move animation, advances its renderer clock to 0.2 seconds, despawns it and spawns a new shot with the same visual before the next draw. The new shot gets slot 0 and `_age[0]=0.2100000083`, rather than restarting at zero. Log: `PROJECTILE` in `_scratch/audit-A/probe.log`.
- **Skills applied:** `godot-nodes-scenes` pooled lifetime/reset correctness; `godot-gdscript` explicit state ownership across updates.
- **Impact:** A new multi-frame projectile can start partway through its animation or alpha cycle. Damage and shot position remain simulated correctly. Single-frame projectile art hides the symptom.
- **Recommended improvement:** Supply a monotonically changing spawn generation or authoritative projectile age in the packed draw data. Reset renderer clocks on generation changes; do not add per-projectile Nodes. The same issue should be checked for the mob-projectile source accepted by this shared renderer.
- **Effort:** S–M.
- **Regression / acceptance:** Cover same-slot/same-visual reuse without an intermediate inactive draw; new animation starts at zero. Existing projectile animation, reparent and rotation tests remain passing, and damage/RNG results are unchanged.
- **False positive if:** Every visual is a phase-invariant one-frame loop or shot phases are intentionally continuous across entities. Checked: renderer header promises restart for a new active projectile, and it accepts arbitrary multi-frame SpriteAnim. Not all visuals have that invariant.
- **Known/intentional check:** Renderer/test contracts and original age bookkeeping (`git log -S '_was_visual'`: `154072f`) reviewed. Mob identity tracking already demonstrates the project's distinction between slot and entity; the mob pool is not the same bug.

### A-6 — The two coordinators remain a high-churn intersection of unrelated changes

- **Category / severity:** Architecture/change isolation — **Medium**.
- **Finding type / confidence:** Maintainability risk / **Confirmed** concentration; no refactor performance benefit claimed.
- **Evidence:** `run_world.gd` has 2,630 lines and 99 non-merge modifying commits; `run_scene.gd` has 2,146 lines and 82. Counts are whole-history file counts, not a measured change rate. Recent `git log --stat` examples: `b6af314` added/changed physical combat (+377/-… in RunWorld), `4ec2f0d` added Warrior effects, `a1e6a05` added Pirate behavior and throw presentation, `92d538c` added Steal, `12603fe` added Drain, and `a68e74f` changed advancement grants. The same RunWorld owns shop/inventory commands (`:1528–1694`), on-hit effects/follow-up scheduling (`:1765–1966`) and world orchestration (`:696–731`). RunScene additionally owns frame statistics and screenshots (`:1864–2146`), window protocols (`:1427–1585`) and event-to-art mapping (`:1045–1341`).
- **Skills applied:** `godot-nodes-scenes` single-purpose composition; `godot-signals-groups` explicit owner/component relationships and direct calls where ownership is clear; `godot-resources` pure-data boundaries.
- **Impact:** New content or tooling changes repeatedly edit the same owners and combine resource/lifetime, combat and automation concerns. This increases review scope and integration conflict risk. The risk is responsibility overlap plus demonstrated churn, not a line-count style limit.
- **Recommended improvement:** First extract the concrete cold-path telemetry/summary responsibility into a scene-owned recorder while addressing A-2. A useful subsequent sim seam, when hit mechanics next change, is a pure hit-effects/follow-up component for MP Eater/Final Attack/Drain/Steal, with explicit RNG/order inputs and outputs. Keep RunWorld as the public command facade and fixed-tick orchestrator. Do not split every function or introduce a global event bus. Existing PlayerUpkeep/InventoryWiring show this pattern already works here.
- **Effort:** M for either bounded extraction; L for a broad rewrite, which is not recommended.
- **Regression / acceptance:** Each extraction must be independently reviewable and preserve existing public RunWorld/RunScene APIs, same-seed event bytes, RNG stream order and terminal/pause behavior. For telemetry, preserve automation summary shape. A module should remove a coherent responsibility from the owner, not just relocate methods with an unrestricted back-reference to the entire scene/world.
- **False positive if:** These owners only orchestrate stable modules or rarely co-change. Checked: their headers and init/step helpers are good orchestration, but the cited long embedded behavior/tooling blocks and commit examples establish the additional responsibilities.
- **Known/intentional check:** Prior orchestration refactors `f668e65`, `408d944`, generic per-line plumbing `b2ef00d`, shared hit logic and InventoryWiring were considered. Preserve them. MobSwarm (1,019 lines/22 modifying commits), SpawnDirector (730/17), SkillRunner (686/25), UpgradePool (547/29), BotInput (600/25), SceneFlow (550/19) were inspected; their sizes alone do not justify more findings or broad cosmetic refactors.

### A-7 — PotionSchedule lacks its committed UID sidecar; the repository-wide premise needs narrowing

- **Category / severity:** Resource identity/repository hygiene — **Low**.
- **Finding type / confidence:** Proposed improvement / **Confirmed** absence.
- **Evidence:** `git ls-files game` shows 384 tracked `.gd` files and 31 without a tracked matching `.gd.uid`. Exactly **one under `game/scripts/`** is missing: `game/scripts/sim/potion_schedule.gd:1`. The other 30 are debug drivers/test fixtures/tests. Therefore it is the only missing production-runtime script sidecar, not the only missing sidecar in the whole project. A normal import generated the missing sidecars during the audit setup incident, confirming avoidable source-tree dirtiness.
- **Skills applied:** `godot-resources`, `resource-patterns.md` resource UIDs: editor-managed stable identity protects references through moves/renames.
- **Impact:** Current class-name/path-based references work; this is not a runtime crash or missing potion feature. Importing a fresh checkout produces an untracked sidecar, and its UID can vary between clean environments before it is committed.
- **Recommended improvement:** Generate and commit the runtime sidecar with the pinned Godot editor in a normal implementation task; consider the other 30 in the same explicit hygiene task. Do not hand-invent UID text during this audit.
- **Effort:** S.
- **Regression / acceptance:** A clean pinned-editor import must leave no new runtime `.gd.uid` file untracked. PotionSchedule remains discoverable and its existing unit tests pass. Verify tracked scene/path references resolve after any future move.
- **False positive if:** A documented policy intentionally omits UID sidecars for all class-name-only runtime scripts. Checked: other runtime scripts commit them; no such policy found. No current scene depends on an absent PotionSchedule UID.
- **Known/intentional check:** Tracked-file inventory, project/scene references and #225 PotionSchedule call sites checked. This finding corrects the broader hypothesis rather than repeating it as fact.

## 5. Considered and rejected

- **Replace packed mobs with reusable Enemy scenes:** rejected; contradicts the deliberate SoA/RenderingServer design and measured performance architecture.
- **Move custom physics into `_physics_process` or retune movement:** rejected; the accumulator already supplies fixed DT. Godot's default callback is not required for this deterministic simulation.
- **Four-tick cap itself is a bug:** rejected. At speed 1, a 0.5-second hitch advances 4 ticks and keeps at most DT remainder; this avoids a catch-up spiral by slowing sim time. At speed k, budget is 4k and Engine.time_scale is k, so normal nominal acceleration is supported. Below roughly 15 rendered frames/s, sustained discard/time dilation is expected; the cap is intentional. A-3 addresses a separate clock mismatch.
- **FreeMarket needs a RunWorld combat tick:** rejected; its separate movement/portal model is intentional. It uses a map-less world only for shared inventory/shop rules.
- **RID leak on layer reparent:** rejected by explicit deletion ownership and 21 focused passing tests. `_exit_tree` cleanup would introduce breakage.
- **Self-bound hit listeners necessarily leak RunWorld:** rejected; probe weak-reference check reports release after scene deletion. No persistent strong world back-reference was found in MobAttacks; it reads setup during construction.
- **All dynamic dictionaries should become Resources/typed classes:** rejected. Cache trees, schema-tested events, snapshot serialization and data-driven rule dispatch deliberately need flexible shapes. A typed snapshot at a stable boundary can be useful; conversion of every hot-loop value is not established as worthwhile.
- **GDScript warnings are all errors:** false. `project.godot` has no explicit `[debug]` warning policy. Godot 4.7.2 effective defaults measured in the scratch probe: untyped_declaration/unsafe_property_access/unsafe_method_access/unsafe_cast/unsafe_call_argument/return_value_discarded = 0; inference_on_variant = 2 (error). Enabling untyped-declaration checking appears inexpensive given the clean declaration scan, but unsafe-* as errors is not a cheap blanket change while deliberate dictionary/Object flows remain. Treat this as an incremental CI/editor improvement, not an existing player defect.
- **String keys in hot paths prove a bottleneck:** rejected; no isolated measurement established that. Kind arrays, animation lookup tables and SkillRunner stats already cache stable lookups. Preserve those optimizations and profile before replacing keys.
- **Per-job data duplication proves duplicated caster code:** rejected; common mechanics are shared. Different canonical IDs, WZ fields and tier-C behaviors are legitimate distinct data.
- **SpatialHash right/bottom exclusion is an off-by-one bug:** rejected; its documented Rect2 query contract excludes those edges, radius queries include exact radius, and focused tests pass. Collision narrow phases deliberately have their own contact rules.
- **All retained textures are leaks:** rejected. Assets' `_imgs/_anims/_frames/_sounds/_pages` retain visited content until `open()` clears them (`asset_library.gd:25–46`), and WzImg/frame objects also reference shared pages. This is a finite content high-water cache, not evidence of lost RIDs. Peak size across different stages/looks remains unmeasured.
- **Save history must be capped:** not established as a defect. `SaveData.end_run` appends history and serializes/copies it; retaining ended characters is a product feature. A long-history responsiveness budget needs evidence before changing retention.
- **Main screenshot await necessarily survives a destroyed screen:** rejected; its owner is the persistent bootstrap host, not the screen child. Other inspected timers/callbacks have their own Node owners. A minimized window's special `--shot` behavior was not exercised here.
- **Known Tree deaths, deferred balance and unresolved importer UOL warnings:** intentional/already known; no new tuning finding.

## 6. Unverified hypotheses and limits

- **Multi-stage asset high-water memory:** measure native retained texture bytes and wasm committed heap across title → multiple looks → Henesys → hub → Dark Cave → title, then repeat the same route. Repeated-route growth would be stronger leak evidence than a first-visit increase. Count images/pages/anims/sounds as well as memory; wasm heap commitment alone does not prove live retention. Do not add broad eviction before knowing the budget, because prewarming deliberately prevents first-use hitches.
- **Visible high-refresh stutter:** A-4 proves no interpolation, not objectionable appearance. Validate with a motion recording or high-refresh human play; static lead screenshots cannot settle it.
- **Pooled projectile phase symptom frequency:** A-5 proves the lifecycle gap with real pool/renderer code and synthetic multiframe art. A normal-play recording with a multiframe skill would establish how noticeable it is; one-frame bullets are unaffected.
- **Whole-session teardown plateau:** focused reparent tests and the weak world-release probe passed. A repeated real menu/hub/round window-flow with object/RID/texture counters was not performed. No claim that every lifecycle path is leak-free.
- **Warning policy:** consider enabling `untyped_declaration` as warning first in an isolated editor/CI parse, checking all UI/debug/tool scripts too. The declaration scan here covered sim/run/core and establishes a low migration-cost indication, not a complete warning-enabled build pass.
- **No quantitative bottleneck claim:** all local timings after PERF_DONE are potentially contended. This report uses counts and deterministic outcomes. Lead perf/standard verification outputs are not relabeled as checks performed by A.

## 7. Small independent backlog tasks

1. **Fix charge clipping (A-1).** Load godot-physics and physics-tuning. Preserve the original right edge when clipping the left edge; add the rear-target synthetic regression plus its mirror. Acceptance: exact movement unchanged; only out-of-sweep damage disappears.
2. **Bound ordinary frame telemetry (A-2; first useful A-6 seam).** Load godot-gdscript and godot-nodes-scenes. Separate a bounded overlay recorder from explicit full automation recording. Acceptance: paused ordinary play has constant retained sample count; explicit summaries keep existing fields/semantics.
3. **Tie Grenade presentation to sim landing (A-3).** Load physics-tuning and godot-signals-groups. Acceptance: hitch, level-up hold and speed 1/4/8 preserve visual-impact/damage ordering without altering sim damage or RNG.
4. **Track projectile draw generation (A-5).** Load godot-gdscript and godot-nodes-scenes. Acceptance: same-slot/same-visual replacement starts a fresh animation even between rendered frames; no per-shot Nodes.
5. **Prototype high-refresh actor interpolation (A-4).** Load physics-tuning. Acceptance: 60–165 Hz motion comparison with consistent tag/effect attachment, pixel alignment and discontinuity reset; identical sim digest. Owner visual judgement decides adoption.
6. **Commit missing generated UIDs (A-7).** Load godot-resources. Acceptance: clean pinned-editor import produces no new untracked runtime sidecar; assess the 30 debug/test sidecars explicitly in the same task.

Keep future hit-effects extraction separate from these correctness fixes and undertake it when that responsibility next changes. No balance pass, movement retuning, broad scene rewrite or blanket unsafe-warning conversion is needed for these tasks.
