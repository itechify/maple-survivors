# X — Adversarial challenge

Revision `a68e74f`, 2026-10-21. Read COMMON_BRIEF.md first, in full, then all five specialist reports. This is an audit, with no implementation, tuning, commits, issue writes or performance measurements. No Critical rating survives my likelihood/recovery calibration. Two conditional save-loss paths remain High; this does not refute their ability to lose data.

## Scope, skills and evidence ledger

Read the following complete skill files under `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/`:

- `save-systems/SKILL.md` and `save-systems/references/versioning-and-migration.md`: validate before promotion, preserve last-good state, migration and rollback; E-1/E-2/E-3 and the additional-defect search.
- `rpg/SKILL.md`: reversible equipment modifiers, permanent level growth and terminal combat states; B-1/B-3/B-4.
- `physics-tuning/SKILL.md`: swept bounds, fixed-step/render distinction and verification by feel; A-1/A-4. Generic engine-body and movement-tuning advice is inapplicable.
- `input-systems/SKILL.md`: conflict detection and prompts that follow mappings; D-2/D-3/D-8.
- `godot-gdscript-headless-testing/SKILL.md`: meaningful counts, invalid numeric assertions and exit status; E-6/E-10.
- `performance-optimization/SKILL.md`: representative workloads and separate measured problems from hypotheses; C-1/A-2/A-4. No timings were collected or compared by X.

Also read `C:/Users/itech/.agents/skills/{code-review,diagnosing-bugs}/SKILL.md` while selecting the workflow. Neither was applied: this is a whole-snapshot adversarial audit, not a fixed-diff two-agent review or an implementation/debugging assignment. No child agents were started.

Consulted AGENTS.md, GLOSSARY.md, Architecture save/pause/presentation/web contracts, Asset Pipeline portable/native output contracts, GAME_DESIGN controls/clear/growth/equipment rules, and ADRs 0001/0004/0005. The intentional-decision exclusions remain binding. The lead's full-suite, Rust, Node, smoke and determinism results are accepted as supplied; they were not duplicated. The supplied same-day HEAD-versus-b1e18d3 comparison supersedes any claim of a 50% regression from the historical 1024 us number; it establishes approximately 7–10% today, with no attribution here.

Commands below ran from the repo root. `G` means `C:/Users/itech/AppData/Local/MisoStory/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe`; `P` means `_scratch/godot_runs/audit-X/game`; `S` means this repo's absolute `_scratch/audit-X/` path. Every Godot invocation used `MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit` and `ISOLATE=audit-X`. PERF_DONE existed before execution. Mirror-only Settings, SaveData and TestCase default paths were redirected into S; no real save/settings were opened by those defaults. The cache was read only.

| Ref | Command/check and result |
|---|---|
| Q | `gh issue list --repo itechify/maple-survivors --state all --limit 300 --json number,title,state`, exit 0; saved as `S/issues.json`. `gh issue view N --repo itechify/maple-survivors`, exit 0 for N=19,20,41,68,87,105,106,111,132,133,146; bodies in `S/issue-N.txt`. No matching open defect; only #46/#77 open. |
| R | Focused `rg`/source reads, exit 0 when matched; no-match searches exit 1. No documented single-instance contract found in README, AGENTS, architecture or ADRs. Issue inventory was checked for each finding, with relevant closed issues named below. |
| U | `G --headless --path P --script S/challenge_probe.gd`, exit 0, `S/challenge_probe.log`. Real inventory double-click handlers, held RunScene accumulator, F3 dispatch, NaN helpers, SaveData recovery and real-cache EXP facts. Presentation callbacks are suppressed; this is a UI-handler integration probe, not an OS-driven visual playtest. |
| B | `G --headless --path P --script S/specialist_B_probe.gd`, exit 0; `S/specialist_B_probe.log`. Unmodified copy of B's synthetic probe: MP, scroll seeding, batch growth and finale reproduced. Seed 1 only. |
| A | `G --headless --path P --script S/specialist_A_probe.gd`, exit 0; `S/specialist_A_probe.log`. Copy of A's probe: charge, telemetry counts and sample cadence reproduced. No elapsed-time measurements used. |
| C | `G --headless --path P --script S/profile_parity_probe.gd`, exit 0; `S/profile_parity_probe.log`. Copy of C's one-tick state/event comparison; internal timer results discarded. |
| Z | `G --headless --path P res://tests/test_runner.tscn -- zz_no_such_test_audit_X`, exit 0; `S/empty_selection.log`: zero tests/files, TESTS_PASSED. |
| I | Two simultaneous `G --headless --path P --max-fps 30 --quit-after 100` launches using hidden Start-Process, both main scenes alive together, both exit 0. `S/two-instances.log`, `S/instance-{A,B}.log/.err`. They used redirected scratch save/settings. Each reports two ObjectDB exit leaks; no timing conclusion. |

Probe setup disclosure: the first mirror-only path-redirection expression produced a malformed constant. The editor import returned 0 despite parse errors (`S/import.log`); it is not a successful validation result. Replaced those three mirror files from source and corrected the scratch path substitutions before all authoritative runs above, which report no SCRIPT ERROR. An initial I invocation failed to capture child exit codes; the repeated I invocation explicitly retained process handles and recorded both 0. Early read commands guessed two file paths incorrectly; corrected paths were inspected. These are audit harness errors, not new product findings.

## Challenged findings

### 1. B-1 — Paused MP equipment loop

**Verdict: CONFIRMED-DOWNGRADE to Medium. Recommended severity: Medium.** A repeatable resource exploit exists, but it requires a learned Magician MaxMP passive, positive-MP gear, spare inventory capacity and intentional repeated swaps; it is not an automatic failure in ordinary bot play.

- Evidence: `game/scripts/sim/run_world.gd:1169` ratio-increases MP without consulting `grant_growth`; removal merely clamps, and `:1668–1670` recomputes on equipment changes. `equip_window.gd:190,354`, `item_window.gd:116,137`, and `inventory_window.gd:183–196` expose the actual double-click route. `run_scene.gd:463` permits opening Equip/Item from a live round, and `:533–559` holds ticks while either is open.
- U opens both real windows via `toggle_window`, double-clicks their slot cells five times with +10 MP synthetic gear: `10 → 14.5661770273`, `time=0`, `held=true`, hat worn again. B reproduces +100 MP `10 → 179.3182`. Neither depends on an inaccessible direct call alone.
- Trigger: open E/I while alive, take off the MP item, double-click it in Item, repeat. The manual Esc-pause flag remains false; the inspection windows themselves hold the round. Opening Equip *over* the Esc pause menu is blocked, which does not close the exploit.
- Limits: zero MP remains zero; positive MP increases toward the reduced maximum, rather than guaranteeing the larger equipped maximum becomes full. The bot only scores/equips items after events (`run_scene.gd:550–551`, BotShop); it does not cycle them by hand. A player can reach it; normal smoke bots do not demonstrate abuse.
- Known/intentional: Q #41 explicitly intends ratio preservation when the passive's maximum grows; #105 introduces gear. The asymmetric remove/reapply cycle is not a documented replenishment feature. Preserve passive-growth policy while making reversible equipment changes non-generative. Skill: RPG reversible modifiers.

### 2. E-1 — Concurrent sessions lose updates

**Verdict: CONFIRMED-DOWNGRADE to High. Recommended severity: High.** Losing characters/account progress is serious, but requires overlapping writers to the same store; a single ordinary session is unaffected.

- Evidence: `save_data.gd:60–108,332–385` loads one detached whole-save view and later writes it without a revision/ownership check. U: A creates TabOne; stale B writes its account; disk slots become empty. A second B write removes TabOne from `.bak` too. The first stale write alone still leaves a recoverable healthy `.bak`; E's report should acknowledge that recovery window.
- I proves the actual native main scene permits two concurrent processes. `game/project.godot:10–11` gives both the same MapleSurvivors user directory; main/Flow have no guard. The OS does not prevent the second launch in this environment.
- Trigger: launch twice, load character selection/play in both, then save/create/buy/end a run in each from stale views. Merely opening two title screens without loading/mutating saves is insufficient.
- Web: two tabs of the same origin/profile share `/userfs` (`web/idbfs.js:5–17,36`). Shell's `session`/worker ownership (`shell.js:478` onward) is page-local; IndexedDB `onblocked` only addresses version upgrades. An ordinary same-version second tab is not excluded. Two-tab save/cache loss is strongly supported by source, but **not independently browser-reproduced by X**; retain that qualification, especially for cache interference.
- Known/intentional: Q #68 excludes cloud/multiple save files, not concurrent local process protection; #133 assumes the engine has quit before shell writes. Neither documents one app/tab as an enforced user contract. Recommend one writer per store or stale-write refusal. Skill: save-systems authority/last-good recovery.

### 3. E-2 — Invalid imported save destroys retained recovery

**Verdict: CONFIRMED-DOWNGRADE to High. Recommended severity: High.** Real eventual data loss survives the backup challenge, with a less common damaged/edited/schema-incompatible import trigger than the Critical wording suggests.

- Exact path: `web/lib.js:352–378` validates JSON/top-level shape, accepting a format-2 file with `slots:[{},null,null]`. `web/shell.js:637–650` copies the healthy current primary to `save.json.bak`, then installs the candidate and restarts. It creates no separate immutable shell backup or automatic download of the prior save.
- `save_data.gd:69–72` tries `.bak` only when the primary is missing. A present semantically invalid candidate fails `_valid_file` (`:284` onward), is copied to `.bad` (`:345`), and starts with empty slots. Successful preservation clears the write block. The next valid mutation copies the *invalid primary* over `.bak` at `:376`, then replaces the primary.
- U reproduces the composed path in a scratch file: rejection leaves `bak_good=true`; ordinary `create_slot(NewSave)` succeeds and then both `primary_good=false` and `bak_good=false`. E's JS acceptance/source and `S/challenge_probe.log` support the whole sequence; no live IDBFS import was exercised.
- Trigger: import structurally plausible but invalid nested character/account/history JSON, then create a new character or otherwise save. An untouched export from the same working build is not expected to trigger it; random truncation usually fails JSON and is refused. Hand editing, valid-JSON damage or incompatible historical content can. The healthy `.bak` survives until the next save and is manually recoverable during that interval; a separately downloaded healthy export also remains available if the player made one.
- Known/intentional: #133 only requires refusing invalid JSON; #68 deliberately preserves corruption and starts empty. Architecture `:140–147` describes these choices. Their combination loses last-good recovery; it is not an unimplemented original acceptance criterion. Recommend stage/full validation or rollback before promotion. Skill: save-systems validation/rollback.

### 4. E-3 — Oversized canvas panic

**Verdict: CONFIRMED-DOWNGRADE to Medium. Recommended severity: Medium.** This is malformed local-input robustness/re-import disruption, not a demonstrated exploitable game/session crash or save loss.

- Evidence: `property.rs:260–275` accepts nonnegative enormous dimensions; `canvas.rs:13–21,80–81,109–115` computes/allocates lengths without a decoded-size budget; `export.rs:123–129` calls it. Read `_scratch/audit-E/importer_probe.log` and its synthetic harness: i32::MAX format-2 dimensions parse, then capacity-overflow panic is caught. Its command exited 0 because the harness caught the expected panic; it is not evidence that the production CLI catches it. No huge allocation or perf work was repeated by X.
- Web preservation is stronger than the finding implies: `web/import_worker.js:231–249` queues output in worker memory; deletion/writes start only at `:255–261`, after synchronous import returns. A decode panic/trap before return cannot replace the previous stored cache; failed worker memory is discarded. Wasm `:169–171` also rejects reports containing errors before returning success. No target trap/OOM test was run.
- Native preservation is **not** whole-import transactional: `import.rs:58,143–170` writes directly through FileSink as jobs finish; `export.rs:413–436` atomically replaces each file, not the bundle. The bad image panics before its page writes, but other images can already have changed; old `cache.json` may remain. Thus “every failed native import leaves the entire previous cache intact” is unsupported/refuted by the write design. It is repairable cache data, separate from save.json.
- Trigger: player's corrupted or crafted WZ contains a selected giant Canvas; normal owner's v83 input did not exhibit it. No remote multiplayer boundary, arbitrary code execution or proprietary-data leak is established. Add checked dimensions/budgets and return WzError; do not elevate to a security incident without additional evidence.
- Known/intentional: Q #132/Asset Pipeline `:63–75` permit streaming/per-file native output and host-owned portable staging. They do not require accepting impossible dimensions. Skill: save-systems commit/recovery boundary plus headless-testing failure semantics.

### 5. A-1 — Leftward charge clipping

**Verdict: CONFIRMED. Recommended severity: Medium.** Terrain-dependent extra damage is bounded to a specific skill/direction but violates the swept-path contract.

- `skill_runner.gd:455–472`: rightward `path.end.x` shrinks width; leftward `path.position.x` translates the unchanged width, moving the rear boundary. A reproduces player `580.01`, near slot 0 at 590 and rear slot 1 at 675, `hits=[0,1]`; the original rear edge was 640.
- Trigger: a left-facing Brawler charge stopped by a wall with an otherwise out-of-sweep mob behind the player. Movement stops correctly; this is not wall traversal or projectile tunneling. No real map incidence count established.
- Known/intentional: #190 explicitly requires charge hits inside the swept path; the resolver's comment agrees. Preserve movement and recompute clipped endpoints/width. Skill: physics-tuning swept-volume verification.

### 6. B-2 — Hub scroll seed changes after reconstruction

**Verdict: CONFIRMED-DOWNGRADE to Low. Recommended severity: Low.** Same-state continuity is wrong, but normal UI play offers neither advance knowledge of the roll nor a retry of a consumed failure.

- `free_market.gd:379–381` gives the hash to RunWorld; `run_world.gd:404,1970–1973` derives stream 11. After a saved mutation, `free_market.gd:411` instead seeds the stream with the raw hash. B reproduces same snapshot/hash 986129636: first live roll 16, reconstructed roll 73; 60% scroll outcomes differ.
- Trigger: buy/equip/sell/scroll, then either use the next scroll immediately or Save & quit → Continue / Cash Shop → return before using it. Every result is immediately saved (`free_market.gd:408–424`), so failure cannot be undone by normal Continue. Leaving/re-entering repeatedly without a mutation yields the same reconstructed roll, not arbitrarily many rerolls.
- Exploit qualification: external prediction/duplicate save experiments could select the live versus rebuilt mode. Without foreknowledge, it merely chooses between opaque rolls. Free equip/unequip state changes already alter hash inputs; this is not proof of a newly unlimited normal-UI save-scumming engine.
- Known/intentional: `free_market.gd:70–77` promises identical saved-state outcomes. ADR 0001's intentional round replay is separate. Unify seed derivation; no balance policy change. Skills: save-systems deterministic reconstruction/RPG resource stakes.

### 7. B-3 — Destination level leaks into batch growth

**Verdict: CONFIRMED-DOWNGRADE to Low. Recommended severity: Low.** Permanent MP differs, but the demonstrated magnitude is small and the eight-level synthetic batch is not representative of ordinary Dark Cave drops.

- `run_progression.gd:45–59` reaches the final level first; `run_world.gd:2506–2528` loops growth, while `:1145` allocates secondary AP using that final level; the following growth reads resulting INT. B reproduces Lv20→28: base MP 645 versus 648, identical final INT113/level28.
- U reads real private-cache Dark Cave facts: ordinary starting mobs award 35/42 EXP; Tauromacis/Taurospear 270/350; bosses have canonical EXP 1500/3180/2000. Current thresholds at Lv38/39/40 are 6061/6369/6684. **Global** `balance.json:114` multiplies boss EXP by 5 and splits it into 12 drops, inherited through `boss_director.gd:265–267`; stage entries do not remove it. Whole boss showers therefore total 7500/15900/10000, with individual pieces about 625/1325/833–834. A single piece cannot cross two thresholds at these levels, but collecting much of a shower together can. The stage's 1.0 multiplier alone would understate this trigger.
- Trigger: enough accumulated drops or boss-shower pieces collected in one `_step_pickups` result (`run_world.gd:927`, `:706–709`), or an unusually underlevelled character. Multi-level gains from a collected shower are plausible in normal Dark Cave; no frequency or natural eight-level batch was measured. Existing test shows 3 MP lost across eight levels (~0.5% of that base MP), not major progression damage; some smaller batches will not change the floored INT bonus at all.
- Known/intentional: #106 intentionally derives level-based LUK; immediate EXP queueing is intentional. Group-dependent growth is not. Compute intermediate attributes at the correct level. Skill: RPG leveling invariants.

### 8. B-4 — Last choice admits another damaging tick

**Verdict: CONFIRMED. Recommended severity: Medium; finale-precedence decision still required.** A completed objective can be superseded by lethal damage before the first clear check, but no natural incident was established.

- `run_world.gd:1021–1046,2591` returns from the last choice to PLAYING; `:696–712` then runs monsters/projectiles/contact before `_end_tick` checks clear (`:971–984`). B again reports `can_clear_before_tick=true`, `bosses_dead=true`, then DEAD.
- Trigger: all bosses/reward/level choices resolved, low HP, no applicable hit protection, and an ordinary contact or in-flight monster ball becomes damaging on the next tick. The choice freezes the threat rather than removing it; `_close_window` (`run_scene.gd:1498–1519`) grants no new safety interval.
- Challenge to frequency: B's probe inserts its overlapping mob after answering the choice; it proves ordering, not that this precise overlap commonly survives the preceding tick. Existing hit invulnerability, pet potions, outgoing attacks and HP condition can prevent death. A mob just outside contact or a pending ball can still be eligible next tick. The lead's clear proves a safe finale can succeed, not that this boundary is impossible.
- Known/intentional: GAME_DESIGN §1/§4.3 states bosses dead plus choices answered; #19/#20 do not explicitly require one more hazard test. Existing same-tick kill-and-death regression (`test_ui_flow.gd:564`) concerns death *before* unanswered rewards, a different boundary. Define objective precedence; do not characterize this as a normal-play fatality rate. Skill: RPG explicit win/loss states.

### 9a. D-2 — F3 rebinding conflict

**Verdict: CONFIRMED. Recommended severity: Medium.** A valid saved window binding cannot perform the advertised action in a round.

- `key_config_window.gd:34`, `key_bindings.gd:89,154–169`: F3 available/not fixed. `run_scene.gd:424–430` intercepts it before window dispatch. U: `F3_BIND_ACCEPTED=true`, `fixed=false`, then `perf=true`, `stat_open=false`.
- Trigger: bind Stat/Skill/Equip/Item to F3, then press it in-run. This conclusion specifically concerns windows; earlier potion/manual-skill latches need not be suppressed.
- Known/intentional: #87 reserves movement/Esc/cards; README advertises F3 diagnostics, but no binding-reservation integration exists. Reserve/explain it or honor the user binding. Skill: input-systems whole-dispatch conflict detection.

### 9b. D-3 — Hard-coded hub hints

**Verdict: CONFIRMED-DOWNGRADE to Low. Recommended severity: Low.** Misleading remapped prompts are recoverable through actual bindings/Key Config and NPC double-click.

- `free_market.gd:317` literally says Up/Space; actual interaction reads `npc_chat` at `:204` and movement follows selected actions. Settings has live action labels (`settings.gd:526` onward). R/source, no visual re-test.
- Trigger: choose WASD or rebind/unbind NPC Chat, including legacy Space=jump settings. Defaults remain correct. Double-clicking the NPC and restoring/rebinding controls remain available.
- Known/intentional: #87/#111 and GAME_DESIGN §2 intentionally preserve legacy mappings; misleading copy is not required. Generate live hints. Skill: input-systems prompt consistency.

### 9c. D-7 — Dead-state low-MP cue

**Verdict: CONFIRMED. Recommended severity: Low.** Terminal feedback retains a harmless stale action cue.

- `hud_messages.gd:25–26` checks only `mp_short`; `run_world.gd:2609` copies `runner.waiting_mp` into the player snapshot even when dead. U: dead/HP0/MP-short snapshot yields `DEAD_LOW_MP=true`. D's current death screenshots corroborate pixels; no new screenshot was generated by X.
- Trigger: die while the latest runner state is MP-short; tombstone appears and hint persists. It is independently drawn, not just an expiring historical log line.
- Known/intentional: #9/#82 require living MP-wait feedback, not a post-death instruction. Suppress by terminal state. Skill: RPG relevant combat state plus input-systems actionable prompts.

### 9d. D-8 — README controls

**Verdict: CONFIRMED. Recommended severity: Low.** Onboarding disagrees with current bindings and round flow.

- `README.md:48–60` lists A/D and W/S as alternatives without the setting qualification, E as MP potion, and Quit to stage select. `project.godot` InputMap binds E to Equip and End to MP; `settings.gd:458–490` activates one movement set. GAME_DESIGN §2 explicitly states those controls and Quit round replay.
- Trigger: a new reader presses E expecting MP, follows inactive WASD, or expects the old quit destination. Equip pauses the run, so this particular mistaken potion key does not itself leave combat advancing.
- Known/intentional: #85/#87/#108/#111/#188 changed controls; README has no legacy-build qualification. Refresh copy only. Skill: input-systems documented defaults.

### 10. A-2 — Unbounded paused telemetry

**Verdict: CONFIRMED-DOWNGRADE to Low. Recommended severity: Low.** Retention grows indefinitely inside one held scene, but the demonstrated default-rate cost is small, released with the round, and no memory-pressure failure was observed.

- `run_scene.gd:397–406,2050–2069` appends four packed arrays regardless of pause/perf. A: 10,000 retained samples = 160,000 raw payload bytes. At 164 FPS, ~9.0 MiB/hour; a 17-minute round is ~2.55 MiB. Container capacity adds overhead, so these are not process-memory measurements.
- Trigger: leave a round/inspection/pause open for hours. Ending the scene releases its recorder. Defaults cap display cadence, limiting the normal growth rate; uncapped settings can grow faster. Do not conflate this with a cross-scene leak or guaranteed OOM.
- Known/intentional: full automation summaries/F3 are intentional; whole-history retention in ordinary play is not documented. Bound ordinary recording, preserve tool output. Skill: performance-optimization budgets/evidence calibration.

### 11. A-4 / D hypothesis — 60 Hz actors, display-rate camera

**Verdict: NEEDS VALIDATION for a player-facing defect. Recommended severity: Low validation task, not a confirmed Medium visual regression.** The mechanism exists at default high-refresh settings; whether it is objectionable needs moving evidence/owner judgment.

- `run_scene.gd:527–559,1664` schedules fixed ticks then draws the latest rounded player position; `_acc/DT` is not used for rendering. Mob/projectile renderers likewise sample current arrays. `camera_rig.gd:38–50` follows every process frame with independent smoothing; dead zone/pixel snapping (`:86–111`) stabilize the view but do not reconstruct intermediate actor positions.
- Mitigation challenge resolved: `settings.gd:69,374–400` defaults max_fps to 0, meaning display refresh, not 60. U returns `DEFAULT_CAP_164=164`. Vsync plus Engine.max_fps can cap at 164; web uses rAF without an engine cap. Engine physics tick defaults do not limit this `_process`-driven custom sim/render loop. No engine interpolation setting or custom actor interpolation was found.
- A's deterministic 164-frame input probe reproduces 59 sim ticks and 105 repeated adjacent positions; this is a floating-point interval/sample-count result, not a new 59 Hz sim bug. Uneven 2–3 display-frame holds at 164 Hz are real. Frame capping at 60 would reduce the frequency mismatch, but is an optional setting, not the current default.
- Trigger: move on a high-refresh display while rendering above 60 FPS; slowly changing per-frame camera/background offsets can coexist with held actor positions. A still image cannot establish judder; no controlled motion capture or preference test was performed.
- Known/intentional: fixed ticks, pixel snapping and v83 movement are intentional. No evidence says owners demand interpolated motion. Evaluate presentation snapshots only if wanted; no physics/movement retuning. Skills: physics-tuning verify by feel; performance-optimization avoid unmeasured claims.

### 12. C-1 — Profiler drift

**Verdict: CONFIRMED. Recommended severity: Medium.** The development profiler measures different gameplay and can misdirect optimization, while normal `step` remains unaffected.

- `profile_run.gd:156–210` duplicates the tick, omitting `run_world.gd:886` Hidden, `:908` Final Attack drain, and `:905` live PDD argument. C reproduces queued follow-up 1→0 with one event in production versus 1→1 with zero events in the copied path.
- Trigger: use per-system `profile_run.gd` with physical Final Attack/Hidden/altered physical defense. It is not evidence that ordinary balance/run/playtest ticks omit those features. Existing copied-loop subsystem shares must be qualified; no new timing taken.
- Known/intentional: header promises equivalent order/output; #146 predates later combat and does not authorize divergence. Preserve clock-free simulation and test profiler identity. Skill: performance-optimization representative workloads.

### 13a. E-6 — Utility counting and empty green selections

**Verdict: CONFIRMED. Recommended severity: Medium for empty selection; Low for count inflation alone.** An empty requested verification can misleadingly succeed, although the supplied full suite did execute substantial behavioral coverage.

- `test_runner.gd:38–41` includes inherited static `test_dir` (`test_case.gd:41`) because it matches `test_*`; it returns a path and asserts nothing. E's discovery probe confirms it. 2,225 reported passes include 189 helpers, leaving 2,036 declared methods; this does not invalidate those 2,036 checks.
- `test_runner.gd:63–64,79` succeeds when `_discover` returns no files. Z independently returned 0, zero tests/files, TESTS_PASSED. Trigger: typo/unmatched filter or broken directory discovery. Normal full-suite file discovery is not empty.
- Known/intentional: #103's test isolation introduced a path helper, not 189 new behavior tests. Exclude utility discovery and reject empty selection explicitly. Skill: headless-testing meaningful accounting/exit codes.

### 13b. E-10 — NaN assertions

**Verdict: CONFIRMED. Recommended severity: Low.** Approximate/range checks can miss invalid numeric results, but no current production NaN failure was established.

- `test_case.gd:92–99` only tests ordered comparisons; NaN makes each false. U calls both real helpers with NaN and records `NAN_FAILURES=0`, exit 0.
- Trigger: a numerical regression produces NaN and coverage relies on these helpers alone. Other exact/golden/finite checks can still catch it; the real-cache full-suite pass does not prove absence of every NaN.
- Known/intentional: no NaN exception in the helper contract or issue inventory. Reject nonfinite values and invalid tolerances. Skill: headless-testing trustworthy failure recording.

## Additional significant-defect search

No independent significant missed defect is asserted. Read CharacterSnapshot validation/migration/restore, SceneFlow continuation/finalization, the advancement queue and JobAdvanceWindow page/confirmation paths.

- Format-1 **save-file** conversion intentionally keeps only historical bests/counts because that version had no character slots (`save_data.gd:100`, #68); this is not erased legacy character progress. Format-1 **CharacterSnapshots** inside newer wrappers migrate through `CharacterSnapshot.migrate` (`:62–96`) and `SceneFlow.migrated_character` (`:149–157`). Existing tests at `test_character_snapshot.gd:191,218` and `test_ui_flow.gd:642` cover preservation/idempotence, supported by the lead's executed suite. No contrary probe result.
- Terminal Flow uses the last valid character if death leaves unanswerable rewards (`scene_flow.gd:345–372`); existing `test_ui_flow.gd:564` specifically encodes it. This prevents a terminal-save dead end and does not require final-clear precedence to be reversed. B-4 remains separate.
- `RunWorld.apply_job` validates offered availability and path (`:987–1003`), grants the chosen weapon, and does not grant a free skill. JobAdvanceWindow uses a separate confirm phase and emits when it closes. No evidenced empty/invalid advancement reachable from an ordinary legitimate character was found. Unsupported IDs or hand-edited extreme values are input-validation extensions, not a newly proved normal-play High defect.

## Integrity and limits

All authored files are this gitignored report or throwaway probes/logs under `_scratch/audit-X/`; the explicitly requested private mirror is under `_scratch/godot_runs/audit-X/`. Existing specialist scratch was read/copied, never modified. No proprietary data was copied; U prints only numeric EXP facts. No held-out seeds, tuning, additional balance runs, perf work, real saves/settings changes, or cache writes.

Final `git diff --stat` and `git status --short`: empty, exit 0. X created no tracked-path-visible sidecars or other files requiring removal. Browser two-tab/import lifecycle, perceptual motion quality, natural finale-death frequency and malformed-input wasm behavior remain explicitly unvalidated.
