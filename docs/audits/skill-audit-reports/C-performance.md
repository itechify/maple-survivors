# Domain C — performance and scalability audit

Audited revision: `a68e74f`, 2026-10-21. Read-only audit; no source, data, settings or save changes.

**Verdict:** the measured desktop workloads have comfortable headroom for 60 FPS at p95/p99. There is no evidence supporting a replacement of the packed simulation, pools, atlas rendering or RenderingServer approach. Two actionable defects concern profiling fidelity and first-use victory loading; a third finding concerns qualifying performance captures. No High/Critical finding. These conclusions do not certify the current release export, browser build, every class, Dark Cave, or a continuous multi-round session.

## 1. Skills read and applied

All assigned SKILL.md files were read in full from the project skill installation, not the worktree. Exact files:

1. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/performance-optimization/SKILL.md`
2. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/performance-optimization/references/profiling-and-budgets.md`
3. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-gdscript/SKILL.md`
4. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-gdscript/references/annotations-and-typing.md`
5. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/physics-tuning/SKILL.md`
6. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/physics-tuning/references/timestep-and-ccd.md`
7. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-animation/SKILL.md`
8. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-animation/references/animation-tree-and-tween.md`
9. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-export/SKILL.md`
10. `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/godot-export/references/presets-and-cli.md`

Application:

- **performance-optimization:** measure before recommending, define the 16.7 ms budget, qualify workload/build/contenders, inspect allocations and caching, and avoid inferring GPU or allocation causes from a total frame percentile.
- **godot-gdscript:** inspect typed hot-loop state, lifecycle, callbacks, container construction and the profiler's duplicated tick implementation.
- **physics-tuning:** inspect the custom 60 Hz accumulator, catch-up limit and visual sampling. The pure simulation supplies its own fixed timestep; the skill's `_physics_process`/engine body examples are not a reason to move it to Godot physics or retune MapleStory movement.
- **godot-animation:** inspect custom SpriteAnim/SpritePool timing and command reuse. AnimationPlayer/AnimationTree replacement is inapplicable to this WZ renderer; its animation clock and ownership principles remain useful.
- **godot-export:** distinguish editor/debug-binary measurements from release exports; account for the intentional single-threaded browser preset and browser frame pacing.

## 2. Scope and evidence

### Read coverage

- Binding `evidence/skill-audit/reports/COMMON_BRIEF.md`; `AGENTS.md`; `docs/agents/issue-tracker.md`.
- `docs/ARCHITECTURE.md` simulation/presentation contracts, movement details, sections 6 and 10.4/Web profile; `docs/IMPLEMENTATION_PLAN.md` entire Performance log; `docs/ASSET_PIPELINE.md` cache/runtime contract; `docs/RESEARCH.md`, especially section 6; `GLOSSARY.md`; ADRs 0004/0005.
- Relevant `docs/GAME_DESIGN.md` headings/records for performance history, swarms, unexpired drops, class/Final Attack rules and constants; stage density/boss schedules in `game/data/survivor/stages.json`. No balance changes or candidate tuning.
- `game/scripts/run/run_scene.gd`: setup/warmup, fixed ticks, event handling, layer rendering, end presentation, automation and timing aggregation.
- Assets: `asset_library.gd`, `wz_img.gd`, `sprite_anim.gd`; render: `sprite_pool.gd`, `mob_renderer.gd`, `projectile_renderer.gd`, `pickup_renderer.gd`, `damage_numbers.gd`, `fx_renderer.gd`, relevant `avatar_renderer.gd` and `map_renderer.gd` paths.
- Simulation: relevant `run_world.gd`, `mob_swarm.gd`, `spatial_hash.gd`, `skill_runner.gd`, `projectile_system.gd`, `pickup_system.gd`, `spawn_director.gd` hot paths; benchmarks/profiler and relevant deterministic fixtures/tests.
- Build/runtime context: `scripts/{godot,run,playtest,bench,export}.sh`, `game/{project.godot,export_presets.cfg}`, bootstrap/settings/flow paths. No network code introduced.
- Read-only `gh issue list --repo itechify/maple-survivors --state all --limit 300`; `gh issue view 146`, `147` including comments, and `224`. #146's original pickup hypothesis was disproved by profiling; #147's web shutdown warning is explicitly wontfix. No matching issue for the profiler drift or clear-asset warmup was identified. No issue writes.

### Measurement context and command status

Hardware supplied by lead: Ryzen 7 7800X3D, RTX 4070 SUPER, 3440x1440 display at 164 Hz. Captures/probes use a **1600x1200 window**, 800x600 logical view, Godot 4.7.2 Compatibility/OpenGL 3.3, NVIDIA 610.88. This is not a native-fullscreen 3440x1440 performance result.

The source runs invoke the editor executable as a standalone game/headless tool, **not the editor UI and not a release export**. Probes confirm `OS.is_debug_build() == true`. Speed is 1 / Engine.time_scale 1 for the reported rendering probes. The standard x4 visual runs are not interchangeable with these measurements.

I started no Godot process before `PERF_DONE` existed. Every extra timing below is **CONTENDED**: the lead continued fixture captures/verification on the same machine. Probe files/logs are exclusively under `_scratch/audit-C/`. The isolated project was prepared with `ISOLATE=audit-C`; direct runs used that mirror. The cache environment was explicitly `MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit` for corrected measurements; no shared-cache import or save write occurred.

| Check | Status / exit | Evidence and qualification |
|---|---|---|
| Lead original three uncapped playtests | Process passed, rc 0; **requested workload not reached** | `perf/{density_hg_s2026,finale_hg_s2026,density_tree_s2026}/summary.json`; all died in warp, zero rendered sim ticks, zero 100+/200+ frames |
| Lead `bench.sh run 300 1000`, twice | Passed, rc 0 | `logs/bench_run_{1,2}.log`; real and synthetic rows present |
| Lead `bench.sh world 300 1000` | Passed, rc 0 | `logs/bench_world_1.log`; no lost mobs |
| Lead replacement F/P fixture density | Passed, rc 0; **CONTENDED** | `perf/density_hg_s2026_fixture_fp/`; PLAYING at 780 s, 10,800 rendered sim ticks, 289 max alive |
| Lead replacement Fighter fixture density | Passed, rc 0; **CONTENDED** | `perf/density_hg_s2026_fixture_fighter/`; PLAYING at 780 s, 10,800 ticks, 221 max alive |
| Lead replacement F/P fixture finale | Passed, rc 0; **CONTENDED** | `perf/finale_hg_s2026_fixture_fp/`; CLEARED at907.833s, 4070 rendered sim ticks, max337; clears before17:00 |
| Lead per-system profiles, default / job110 | Process passed, rc0; **not production-equivalent**, C-1 | `logs/profile_hg_2026_{default,job110}.log`; both use physical Final Attack and the stale copied tick |
| Additional `bench.sh run 2000 --statuses` | Passed, rc 0; **synthetic only**, real row skipped | `_scratch/audit-C/bench2000_1.log`; the first Bash environment invocation failed to resolve the real cache; do not count this as a real-cache test |
| Corrected direct `bench_run.gd -- 2000 --statuses`, twice | Passed, rc 0; **CONTENDED** | `_scratch/audit-C/bench2000_{2,3}.log`; both real/synthetic rows present |
| Synthetic summary aggregation probe | Passed, rc 0; **CONTENDED** | `summary_probe.gd` / `.log`; 10k–80k samples, three repetitions each; first Bash CLI attempt could not locate the absolute script (rc 1), corrected direct PowerShell invocation passed |
| Real-rendering god-mode Fighter finale probe, twice | Passed, rc 0; **CONTENDED, diagnostic workload** | `runtime_probe.gd`, `runtime_probe_{1,2}.log`; seed 2026, forced job 110, warp 895, uncapped x1; real boss fights, no diagnostic boss damage; three bosses dead and choices finished at 910.483 s |
| Synthetic normal-vs-profiled tick probe | Passed execution, rc 0; **parity failed** | `profile_parity_probe.gd` / `.log`; deterministic follow-up differs, C-1 |
| Cold/warm clear-art probe, three repetitions | Passed, rc 0; **CONTENDED** | `clear_load_probe.gd` / `.log`; real private-cache assets, windowed Windows renderer, C-2 |
| Screenshots inspected by eye | Passed for inspected files | Original three `final.png` images: tombstones at04:19 /00:47, matching failed warp coverage; replacement F/P `t720.png`: real239-mob combat; replacement finale `t900.png`: Blue Mushmom and322 mobs; `clear.png`: victory art at15:07 |
| Lead cargo with real WZ / node tests | Passed per logs, rc0; not duplicated | Cargo:44 unit,18 wasm, two one-test integration groups pass; node51 pass,0 skipped after correcting an initial directory-argument invocation (rc1) to the documented glob |
| Full Godot suite / balance | Not duplicated; pending lead at report preparation | `CHECKS_DONE` not present; no claim of passing, and no SKIP treated as evidence |
| Current Windows release/browser runtime, continuous 17-minute memory timeline, multiple-round memory | Not executed / pending lead | No current export was available for target-runtime profiling during this audit; browser numbers below are from docs only |

Direct tool command used for corrected probes (substitute the script/log name):

```powershell
$env:MAPLE_SURVIVORS_CACHE='C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit'
$env:ISOLATE='audit-C'
& 'C:/Users/itech/AppData/Local/MisoStory/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe' `
  --path '_scratch/godot_runs/audit-C/game' `
  --script 'C:/Users/itech/.t3/worktrees/maple-survivors/t3-eb28f480/_scratch/audit-C/runtime_probe.gd'
```

Use `--headless` for the summary/parity/benchmark probes. Timings include the existing instrumentation; they are not profiler-free GPU measurements.

### Numbers and comparison limits

Lead quiet-phase benchmarks, microseconds per tick:

| Workload | 300 | 1000 | Cost ratio for 3.333x mobs |
|---|---:|---:|---:|
| Run, synthetic, run 1 / run 2 | 942.1 / 910.2 | 3047.8 / 2944.9 | 3.24x / 3.24x |
| Run, Henesys, run 1 / run 2 | 1586.3 / 1561.0 | 3901.5 / 3822.0 | 2.46x / 2.45x |
| World, synthetic | 594.1 | 1772.7 | 2.98x |
| World, Henesys | 673.0 | 2073.1 | 3.08x |

This shows approximately linear or sublinear empirical growth over these two counts, **not a proof for all target distributions/projectile counts**. There is no observed quadratic blow-up here. Real-map world costs at 1000: movement 1249.5 us, hash 346.2 us, 20 queries 477.4 us. Run benchmarks have only 0.3–1.0 live projectiles and few drops, and their MP-short fractions differ by cell; they do not stress a dense projectile storm or large long-lived loot field.

CONTENDED 2000-mob, all-slowed/poisoned/every-third-frozen run probes: synthetic **7520.7 / 7177.9 us**, Henesys **8477.0 / 8218.4 us** (4.6% / 3.1% spread). Initial synthetic-only result was 6716.9 us, showing why these cannot establish a precise regression. Different statuses/workloads prevent direct slope comparison against the unstatused 300/1000 benchmark. Headless tick results say nothing about a 2000-mob full rendered frame.

Uncapped rendered timings, milliseconds unless marked otherwise:

| Workload | Max alive | p50 / p95 / p99 / max | RunScene work p95 | Sim us/tick |
|---|---:|---|---:|---:|
| Lead F/P fixture, 10:00–13:00, CONTENDED | 289 | 3.847 / 7.321 / 8.952 / 31.132 | 4.053 | 1187.3 |
| Lead Fighter fixture, 10:00–13:00, CONTENDED | 221 | 2.440 / 4.782 / 6.439 / 35.569 | 2.202 | 840.5 |
| Lead F/P fixture finale, 14:00–15:07.833 + clear hold, CONTENDED | 337 | 3.670 / 6.390 / 8.000 / 71.988 | 3.795 | 1213.3 |
| God-mode Fighter, 14:55–15:10.483 + clear hold, probe 1, CONTENDED | 334 | 3.307 / 6.387 / 9.462 / 32.566 | 3.043 | 1367.5 |
| Same deterministic Fighter workload, probe 2, CONTENDED | 334 | 3.083 / 6.003 / 8.985 / 23.994 | 2.913 | 1305.1 |

F/P 200+ population: **32,950 frames**, p95 7.384, p99 9.014 ms. Fighter fixture: **5162 frames**, p95 5.344, p99 7.061. The finale probes have **4989 / 5368 frames with 200+**, with all-frame and 200+ percentiles identical; both yield 5924 kills, Lv53, three bosses dead, `missing: []`. Max alive also includes the first warmup frames; recorded minute maxima are 330/332. Repeat finale p95 differs by about 6%, max by 36%, so maxima are especially noise-sensitive.

The lead's replacement F/P finale adds **16,279 frames, all200+**: minute14 mean314/max331, p95/p99 **6.464/8.108ms**; minute15 mean327/max331, **5.832/7.080ms**. Its **71.988ms maximum is in minute14**, before the third boss at15:00; that max cannot be attributed to third-boss arrival or the eventual clear. There is no per-frame trace to distinguish other boss activity, loading, scheduling or capture effects. This tail needs timestamped validation rather than a guessed optimisation. As with the diagnostic Fighter, an early legitimate clear is valid finale evidence, not proof of a continuous17-minute soak.

These desktop p95/p99 values satisfy **60 Hz = 16.67 ms**, with roughly 1.8–2.8x p99 headroom in these workloads. They do **not** guarantee maintaining the display's **164 Hz = 6.10 ms** refresh in every dense frame. Vsync-capped frame_ms around 6.1 ms measures pacing, not execution cost; it must not be read as an improvement over a 3 ms uncapped frame. `frame_work_us` covers RunScene's own callback, not all engine/UI/render-thread/GPU work. No GPU timer was collected, so I do not label the current game CPU-bound or GPU-bound, or claim the architecture's separate <5 ms *total frame CPU* target is proven.

Historical comparison:

- `docs/IMPLEMENTATION_PLAN.md:140`: a25697e, seed 2026 fresh Magician, max274, 200+ p95 **3.070**, p99 **3.662**, max **25.346** ms. The original current seed-2026 captures have **zero** 200+ frames, so no comparison is valid. The replacement carried F/P/Fighter characters, different level/skills/loot, content revision and contention also prevent a controlled before/after comparison.
- #224 rows (`docs/IMPLEMENTATION_PLAN.md:92`): seed5 forced F/P, max273, 200+ after p95 **3.06/3.11** ms. Same nominal 1600x1200/x1/uncapped framework; different seed, starting character/content and contention. Current F/P p95 7.384 is a useful baseline to investigate, **not evidence that #224 or a particular code path regressed**.
- #146 rows (`docs/IMPLEMENTATION_PLAN.md:139`): after real-map 300-mob bench **1024 us** versus today's **1561–1586 us**, about 52–55% higher. New class/combat code, dates and runtime context differ; no old checkout was executed. The measurable present cost remains 1.56–1.59 ms/tick. A current-vs-base isolated comparison is needed before filing a regression attribution.
- Browser **docs only** (`docs/ARCHITECTURE.md:1284`): #146 after build b0a17c5, seed5 13:00–15:00, max339: web **4.0/6.7/9.7/20.8 ms**, desktop **2.26/3.58/4.39/15.7**, sim **1252/836 us**; peak wasm heap286 MiB. Older seed2026 web p95/p99 15.3/27.4 belongs to pre-fix content and is not the current result. No current Windows/browser multiplier can be inferred from these older paired runs.

## 3. Strengths worth preserving

- **Simulation scaling is already good:** the 300→1000 benchmarks above show no superlinear explosion. Packed SoA state, pooled slots and the counting-sort hash (`game/scripts/sim/spatial_hash.gd:53`) fit the stated architecture and need no speculative replacement.
- **One RID per sprite is not one Node per sprite:** `MobRenderer` uses SpritePool. `sprite_pool.gd:84` clears/re-records texture geometry only when the `SpriteFrame` reference changes; transform, alpha and visibility calls are also conditional. Atlas pages are shared. A claim that every mob clears/redraws its texture command every render frame would be false.
- **Animation work is bounded:** `sprite_anim.gd:124` uses binary search over frame start times. MobRenderer flattens kind/state animation lookups; projectile/pickup renderers cache animations/icons. Damage-number commands are recorded at spawn and their existing RIDs are moved/faded; FxRenderer returns slots to a free list. Avatar composition redraws on changed animation state/frame. No evidence supports introducing per-entity AnimationPlayers or AnimatedSprite2Ds.
- **Setup warms substantial content:** `run_scene.gd:860` iterates every definition in the merged skill book, every rank, character-level art thresholds, ball/hit/effect/burst art, playable instructors, held/grant weapon pages; `:906` covers scheduled bosses, enabled MobSkill art, attack art, boss bar and ordinary attack art/sounds. This is much broader than warming only the starting Magician.
- **Existing #146 optimisation is retained:** `skill_runner.gd:197` uses lightweight target admission before building full target lists; `run_world.gd:912` fills live defenses in one pass. `test_tick_cost_identity.gd` guards events/state with a deterministic digest. Do not resurrect #146's rejected assumption that pickups were the dominant cost.
- **Lifetimes are explicitly owned:** SpritePool frees RIDs on PREDELETE; DamageNumbers frees its own/effect RIDs. Effects use WeakRef for followers. Pool high-water capacity is reuse, not proof of a leak.
- **The four-tick cap protects responsiveness:** `run_scene.gd:535–554` runs fixed DT steps then discards excess backlog down to at most DT when the budget is exhausted. This intentionally trades elapsed game time for bounded work during sustained stalls; it does not integrate one large unstable timestep.

### Fixed timestep, speed and interpolation assessment

At x1, at most **4/60 = 0.0667 game seconds** can advance per rendered frame. If a machine sustains 10 rendered FPS and the accumulator is continually saturated, the game advances about **0.667 game seconds per real second**; at 5 FPS, about **0.333**. A single 200 ms stall processes at most 66.7 ms immediately and retains at most one tick, dropping the rest. It cannot later fully catch up to wall time. At speed k, Engine.time_scale scales delta by k and the budget is 4k; maximum advancement is k times those values. The relative saturation boundary remains approximately 15 FPS, apart from engine delta delivery/other pauses.

This is intentional and **not a defect**. Render/FX clocks receive the scaled frame delta while sim advancement can discard backlog, so visual/sim clock agreement under severe stalls needs a low-FPS observation before changing anything. Player/mob positions are rendered from rounded current tick positions (`run_scene.gd:1664`, `mob_renderer.gd:182`); no previous/current transform interpolation was found in those paths. At 164 Hz this repeats 60 Hz samples. A still screenshot cannot establish objectionable movement jitter, and the owner explicitly values the existing MapleStory feel. No interpolation or movement retuning is recommended without side-by-side moving evidence.

### Long-session and allocation assessment

- The finale probes simulate to 15:10.483 but render only the last 15.483 sim seconds plus clear hold. They are **not** a continuous 17-minute presentation/memory soak.
- Probe2 static-memory monitor rose **447,439,973→462,375,235 bytes** (~426.7→441.0 MiB), pages **82→90**, objects **4716→5197**, orphan nodes **0 throughout**. Late combat sample at909.85s was457,943,057 bytes with pages89, followed by clear/page90. This is consistent with deferred art, renderer pools and telemetry warming; without a teardown/re-entry plateau test it neither proves nor disproves a leak. Raw runtime logs show no ObjectDB/orphan warnings. Benchmark wrapper suppresses some leak lines (`scripts/bench.sh:43`), so its silence is not independent leak evidence.
- Hot-path container allocations exist: event dictionaries plus new drain arrays (`run_world.gd:682–693`), ready-skill list/sort closure (`skill_runner.gd:171–193`), target arrays/closures (`run_world.gd:1290–1378`), status-view Array/Dictionary (`run_scene.gd:1628–1660`), damage digit layouts at spawn, and some per-frame player-name arrays. Packed buffer growth occurs on pool expansion; hash cursor duplication is per tick. The architecture's phrase “no allocation in steady state” is too absolute as a description. **No allocation trace ties these to the observed maxima; no hot-loop rewrite is recommended from inspection alone.** Do not call them managed-GC pauses without evidence.
- Timing collection is always invoked (`run_scene.gd:398–409`, `:2050–2075`), regardless of overlay/perf option. Four retained per-frame arrays use about **16 payload bytes/frame**, plus recent-window arrays and container overhead. At164FPS for17min this is ~2.55 MiB of payload per RunScene; pools/telemetry are discarded with scene ownership. This is bounded by round duration/frame count in practice, not evidence of runaway cross-round growth.
- A suspected quadratic per-minute PackedArray append cost was **rejected by measurement**: `_perf_by_minute` single-minute synthetic groups of10k/20k/40k/80k samples took median **2.275/4.900/9.812/19.456 ms** across three repetitions each, approximately linear. This is end-summary work, not a per-frame function. No recommendation to replace packed arrays follows.

## 4. Findings

### C-1 — Per-system profiler no longer executes the production tick

- **Category / severity:** developer tooling / **Medium**.
- **Finding type:** **Confirmed bug** (profiling correctness; not a measured gameplay slowdown).
- **Evidence:** `game/tools/profile_run.gd:156–210` manually reproduces the tick. It omits production `_play_final_attacks()` (`game/scripts/sim/run_world.gd:908`), omits `_ctx["hidden"]` (`:886`), and calls `projectiles.step` without current `_live_pdd` (`profile_run.gd:193` versus `run_world.gd:905`). Its header promises equivalent order/output. `_scratch/audit-C/profile_parity_probe.gd` constructs two identical synthetic seeded worlds, queues one guaranteed Final Attack, and takes one fixed1/60 tick through each path. Log: normal **queue1→0, one final_attack event**; profiled **queue1→1, zero final_attack events**. Exit0 means the probe ran, not parity passed.
- **Skills applied:** performance-optimization, “representative reproducible workload before optimising” and “measure the real bottleneck”; godot-gdscript, typed callback/state lifecycle inspection. A profiler that omits a combat system measures another workload.
- **Late lead evidence:** `logs/profile_hg_2026_default.log` ends as job120 with `final_attack_bw`; `profile_hg_2026_job110.log` learns `final_attack_sword_fighter`. They report1108.2/1045.8us per copied tick, with swarm/director about22–24% each, runner13–15%, pickups2–4%. These are **measurements of the divergent profiler workload**, not a trustworthy production subsystem breakdown; no optimisation is recommended from those shares. The default Page's Threaten is also relevant to omitted livePDD.
- **Impact:** class profiles can undercount/omit follow-up work, keep an unprocessed queue and change ensuing kills, drops and targets. Hidden behavior and live physical-defense handling can diverge too. This undermines future optimisation decisions despite correct normal gameplay.
- **Recommended improvement:** restore exact production tick parity and add a deterministic identity test covering Final Attack, Hidden and a physical projectile against altered PDD. Prefer timing boundaries around shared production stages, or make the copied loop's parity a required test; preserve a clock-free sim API.
- **Effort:** **M**. **Confidence:** **Confirmed** for missing follow-up; other omissions confirmed by source but not separately reproduced.
- **Acceptance:** normal and instrumented paths produce identical ordered events, RNG/state/queues and totals over seeded fixed ticks for those mechanics; timings add no RNG calls. Existing #146 identity test remains green.
- **False positive if:** the profiler were explicitly a restricted Mage-only approximate workload. Checked: it accepts `--job=<id>`, claims same simulation, and the synthetic differential fails. It is not a restricted replacement simulation by contract.
- **Known/intentional check:** read #146 and its comments, architecture10.4 and #181 tests. #146 historically predates physical-job additions; no intentional instruction to omit their runtime work was found. Do not use this to invalidate the historical pre-physical #146 measurement.

### C-2 — Victory art is still decoded on the first clear

- **Category / severity:** presentation hitch / **Low**.
- **Finding type:** **measured performance issue** (small, bounded transition cost; timings CONTENDED).
- **Evidence:** `run_scene.gd:1393–1401` first asks `library.find_anim(FX_CLEAR)` and `_sound(SND_CLEAR)` in the clear event. `_warm_ui`/`_warm_stage` (`:860–961`) do not warm these two constants. Atlas load is synchronous through `asset_library.gd:_load_page` and `wz_img.gd:load_page`. In three fresh-library repetitions on Windows, `_scratch/audit-C/clear_load_probe.log` measured animation first-use **10,488 /11,150 /10,296 us**, cached **3/3/2 us**; sound first-use **352/411/326 us**, cached **2/3/3 us**. The real finale repeat at910.483s recorded a **23,796 us draw interval** when the clear began and loaded one additional page (89→90); summary max23.994ms. No screenshots were requested in this probe.
- **Skills applied:** performance-optimization, prewarm measured first-use costs rather than pooling/replacing everything; godot-animation, cache sprite animation data outside live transitions; godot-gdscript, inspect synchronous event callback cost.
- **Impact:** a one-time visible hitch when victory art appears on a cold session. This does not impair steady-state combat, and the sim has already cleared. The measured asset work explains a portion of this transition frame, not every millisecond or all observed maxima.
- **Recommended improvement:** add these existing clear animation/sound paths to setup warmup. Keep the same art, timing, renderer and gameplay. Do not turn this into an asynchronous loader rewrite.
- **Effort:** **S**. **Confidence:** **Confirmed** synchronous first-use cost; **Likely** contribution to the complete23.8ms clear interval.
- **Acceptance:** on a fresh process/cache-in-memory state, setup has cached FX_CLEAR/SND_CLEAR; triggering clear loads no new atlas/audio resource for these paths. Repeated uncapped cold clears show reduced transition work; check screenshot appearance unchanged. A unit test can assert cache coverage without a hard microsecond threshold.
- **False positive if:** another earlier screen always preloads this art. Checked: a tool one-off is a supported path and both real probe processes loaded the extra page at clear. A warm same-process subsequent clear may avoid it, which is precisely the first-use scope.
- **Known/intentional check:** architecture6 explicitly calls for avoiding first-use decode; #224/performance history and #146 do not list a victory hitch as intentional. Death art, other late-loaded pages and status cues are separate unvalidated candidates, not bundled into this finding.

### C-3 — Successful playtest exit does not qualify a density performance sample

- **Category / severity:** performance verification / **Low**.
- **Finding type:** **maintainability risk**.
- **Evidence:** `scripts/playtest.sh:65–85` checks for a summary and prints it; it has no performance-workload assertion. `run_scene.gd:1367–1379` intentionally preserves death during warp. Lead `pipeline.log` records rc0 for all three original windows, yet Henesys ends at **259.383s, max30**, Tree at **47.517s, max25**, `ticks:0`, and all 100+/200+ sample counts zero. The original frame p95 values1.40–1.79ms and sim0.0 are valid death-presentation measurements, **not a fast dense sim**. Screenshots visually confirm tombstones. Later fixture captures repair part of this audit's missing evidence but do not prevent the same mistake next time.
- **Skills applied:** performance-optimization, define target/reproduction and compare representative scenes; godot-export, distinguish process/export success from target runtime acceptance.
- **Impact:** an automated/manual perf review could falsely accept a large apparent speedup when the bot simply died before the measurement window. Particularly relevant because the docs already note that seed2026 no longer survives the old late-game recipe.
- **Recommended improvement:** a small opt-in performance qualification wrapper/mode requiring the expected `warped_to`, positive timed ticks and a minimum number of frames in the intended density/window. Report zero-sample sim/density results as unavailable in that mode. Preserve ordinary playtest success on a valid death and preserve #143's warp handling.
- **Effort:** **S**. **Confidence:** **Confirmed** evidence gap; not a gameplay bug.
- **Acceptance:** the original three artifacts fail/are marked unqualified under the opt-in perf check; normal death playtests remain valid; a live fixture capture with positive ticks/density passes. No balance/survival tuning is required.
- **False positive if:** every perf consumer already enforces these predicates externally. Checked: this audit's pipeline accepts rc0 and emits PERF_DONE despite no workload coverage; no qualification is in the playtest wrapper inspected. An external consumer not present here could already protect itself.
- **Known/intentional check:** #143 intentionally fixes death-inside-warp termination, and architecture10.4 documents seed2026's changed survival. Those are preserved; the issue is measurement interpretation/guarding, not dying or returning a summary.

## 5. Considered and rejected

- “Replace packed arrays/pools with Nodes, MultiMesh or Rust now”: rejected; current benchmarks/frame tails do not justify it.
- “Every mob clears/redraws its canvas commands every frame”: false; SpritePool records only on frame change and caches transform/modulate/visibility.
- “300→1000 scaling is quadratic”: unsupported; empirical ratios2.45–3.24x for3.33x population, with workload caveats above.
- “The original new1.5ms p95 beat old3.07ms density”: false comparison; new samples had zero dense active frames.
- “4-tick clamp loses time, therefore bug”: intentional response cap; explain slowdown, preserve fixed DT.
- “No interpolation requires CharacterBody2D / physics retuning”: rejected; custom MapleStory sim and owner feel are binding. Visible jitter needs motion evidence.
- “Drops should expire/merge/cap for speed”: rejected; owner decisions and #146 comments forbid using that shortcut, and no current pickup-dominance measurement exists.
- “C#-style GC caused these maxima”: unsupported; no allocation/engine trace. Container construction is visible, causal timing is not.
- “Per-minute summary uses quadratic packed-array copies”: rejected by linear synthetic probe.
- “Memory increased15MB in a short probe, therefore leak”: unsupported; new atlas pages/pool warming and telemetry coexist, orphans stay0; no multi-round plateau measurement.
- “2000-mob headless8.2ms implies2000 rendered mobs at60FPS”: false; rendering not included.
- “Current web runs at old pre-#146 p99~30ms”: false; historical content and repaired bottleneck must remain distinguished.
- Web WorkerThreadPool Group warning: already #147/wontfix engine shutdown noise; not a new leak finding.
- Add browser threads/COOP headers: rejected; single-threaded Pages deployment is ADR0004, not an optimisation oversight.

## 6. Unverified hypotheses and missing validation

1. **Other first-use assets / coverage of every job:** warmup covers all ball/hit/effect/burst ranks, but status `mob` art (`mob_renderer.gd:40,219`), weapon afterimages, changing ammo visuals, equipment-drop pages and death/clear paths are not all enumerated there. Probe pages rose82→87 before the first sampled draw and87→89 at895.517s. That latter interval was only7.653ms; page growth by itself is not a defect. Validate with loaded-page/path timestamps across each physical line and boss before extending warmup. Do not add all possible art indiscriminately and inflate startup memory.
2. **Max-frame causes:** original tombstone-only maxima3.089/6.921/2.416ms do not sample live combat. Replacement F/P/Fighter maxima31.132/35.569ms lack a stored event/asset/memory/GPU timeline; the screenshot capture path skips two timing samples (`run_scene.gd:2044–2055`), but this does not identify every remaining hitch. No screenshot operations occurred in my finale probe; it still had>16.7ms intervals with no page-count change. Probe2's largest final transition correlates with clear/page load, but other stalls may be scheduling, other work or the display driver. Collect top slow-frame timestamps plus work/sim/casts/pages and CPU/GPU trace to resolve; no confident “boss arrival / job change / GC” attribution from percentiles alone.
3. **Current release/browser performance:** exports use `--export-release` by default (`scripts/export.sh:36`), but these measured source/debug builds. Run the same qualified fixture/window in a release exe and current Chrome/Firefox export before promising low-end/web targets. Browser rAF is capped unless the browser itself is uncapped; `--vsync=off` alone is not sufficient there.
4. **17:00 continuous and across-round memory:** sample process private bytes, Godot memory/object/orphan counts, page count and pool high-water marks from title through two rounds and back. Revisit already-loaded maps/classes and test plateau after scene free. Engine heap retained capacity or a finite content cache is not a leak unless continued growth is demonstrated.
5. **Dark Cave:** more complex attacks/roster may cost more, but no current uncapped density capture was available at report preparation. The lead's x4 visual run can validate appearance, not a like-for-like x1 performance baseline.
6. **Projectile/drop/effect-heavy worst cases:** supplied benches have near-zero shots/drops on real-map rows. The lead F/P screenshot does demonstrate340 lying drops with239 mobs at12:00, but no subsystem split attributes their cost. A deterministic stress fixture with realistic status effects, physical multi-hit skills and ranged Final Attack would quantify this without changing production data.
7. **Normal-play timing overhead:** retained samples/recent-array slicing run even without perf overlay. Measure identical workload with/without collection in an allowed experiment before proposing gating/buffering changes. Current code inspection alone does not establish a material cost.

## 7. Small independently implementable backlog

1. **Restore profiler identity (C-1).** Load performance-optimization and godot-gdscript. Add deterministic normal/instrumented tick equivalence covering queued Final Attack, Hidden and live PDD; include shared production stages or a tested updated profiler loop. Acceptance: identical event/state/RNG/queue digests, no gameplay change.
2. **Warm victory assets (C-2).** Load performance-optimization, godot-animation, godot-gdscript. Warm the two existing clear paths during setup, verify no clear-time page/audio first use, cold/warm timings and unchanged screenshot. No broad loader replacement.
3. **Qualify perf artifacts (C-3).** Load performance-optimization and godot-export. Add an opt-in verifier for reached window/density/tick counts/build metadata. Acceptance: early-death samples are unqualified while normal playtest behavior stays unchanged; qualified fixture sample passes.
4. **Record slow-frame context, then decide on further work.** Load performance-optimization and godot-export. Retain a bounded handful of worst frames with sim time/alive/work/page count and resource-load markers; pair a qualified release desktop/browser capture and a memory plateau probe. Acceptance: every over-budget top frame is timestamped, artifacts state build/hardware/contention, and unsupported optimisation hypotheses are explicitly rejected. This is validation work, not permission to tune balance or replace working hot paths.

Only the report and disposable `_scratch/audit-C/` probes/logs were authored. No implementation, commit, issue write, balance run, package installation, or standard-suite duplication was performed.
