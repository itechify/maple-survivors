# B — Gameplay systems and progression audit

Audit revision: `a68e74f`; 2026-10-21. Read-only audit. No source, tuning, settings, saves, or shared cache changes. This report and synthetic probes under `_scratch/audit-B/` are the authored outputs. Findings distinguish reproducible correctness issues from policy/experience recommendations. No held-out seeds or tuning candidates were run.

## 1. Skills read and application

All paths below are under `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/` (the project-installed skill collection, not this worktree).

- `game-ai/SKILL.md`, full: decision/motion/path separation, stuck recovery, cached routing, and observation. Applied to swarm navigation, relocation, scheduled bosses and the sensible bot.
- `rpg/SKILL.md`, full; `rpg/references/stats-combat-quests.md`, full: reversible derived stats, reward→growth→harder-content loop, combat/equipment and meaningful choices. Applied to HP/MP, EXP, cards, weapons, shops and inter-round rewards. Quests/dialogue conventions do not apply.
- `level-design/SKILL.md`, full; `level-design/references/pacing-and-flow.md`, full: reachability from fixed movement metrics, encounter pacing, safe teaching, critical path. Applied to real-map traversal, boss pursuit, tier transitions and current evidence coverage; no geometry/movement retuning proposed.
- `godot-2d-movement/SKILL.md`, full: fixed-step movement, slopes, collision correctness. Its CharacterBody2D/move_and_slide recipes are inapplicable to this deliberate pure-sim v83 integrator.
- `platformer/SKILL.md`, full: jump commitment, one-way surfaces, reachability, frame independence. Coyote time, variable jump cuts, asymmetric gravity and generic feel defaults were deliberately not applied.
- `input-systems/SKILL.md`, full: named actions, edge versus held input, capturing presses across fixed ticks. Applied only to gameplay input and modal boundaries; no controller/touch requirement inferred.
- `procedural-gen/SKILL.md`, full: owned seeded randomness, weighted outcomes, stable reproduction. Applied only to RNG streams, card/drop picks and scroll outcomes; no generated-map conventions applied.
- `roguelike/SKILL.md`, full: run/profile separation, resource stakes, seedable runs, intentional continuation semantics. No grid, FOV, turn scheduler or save-deletion convention applied.

## 2. Scope and verification

Read the binding `reports/COMMON_BRIEF.md`, AGENTS.md, architecture contracts/pause and round-boundary sections, GAME_DESIGN §§1–4.1, the relevant §4.2 records (#232, #228/#229, #235 and historical campers), boss lifecycle/kit rules in §4.3, and relevant §§5–9; ADRs 0001–0005, GLOSSARY and RESEARCH §6.

Targeted source review covered:

- Movement/input: `player_motion.gd`, `ladder_set.gd`, `portal_set.gd`, `portal_approach.gd`, `move_input.gd`, foothold/teleport contracts and RunScene input latches.
- Combat: `skill_runner.gd`, `basic_attack.gd`, `combat_math.gd`, `projectile_system.gd`, `weapon_info.gd`, `ammo.gd`, `skill_book.gd` contracts, `loadout.gd`, `player_buffs.gd`, `player_upkeep.gd`, RunWorld hit/target/cast rules.
- Enemies/bosses: `spawn_director.gd`, `mob_swarm.gd`, `nav_graph.gd`, `mob_attacks.gd`, `mob_projectile_system.gd`, `mob_skill_runner.gd`, `boss_director.gd`, `boss_attacks.gd`, `stage_roster.gd` and stage data.
- Progression/economy: `run_progression.gd`, `upgrade_pool.gd`, `job_tree.gd`, `exp_curve.gd`, `auto_ap.gd`, equipment/drop/meso/scroll/shop/bot-shop/potion modules, `nx_award.gd`, `cash_catalog.gd`, FreeMarket/SceneFlow boundary wiring, per-line skill/card data and associated tests. Review was targeted, not a claim that every line of every large module received exhaustive verification.

Commands/check status:

- **Passed, exit 0:** read-only `gh issue list --state all --limit 300` and targeted `gh issue view` for #41, #105, #181, #186, #187, #189, #202, #203, #77. Only #46 and #77 open. Checked historical owner decisions before classifying differences.
- **Passed, exit 0:** `MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit ISOLATE=audit-B bash scripts/test.sh worn_equipment maxmp`: **14 tests, 0 failed, 0 skipped, 1 file**. The `maxmp` filter matched no separate file; this validates existing worn-equipment tests, not the newly identified passive interaction. The last observed PERF_DONE before this launch was present; a later inspection showed the lead had withdrawn it to extend perf capture. Its exact removal versus this launch was not recorded, so this test may overlap perf2. After reading NOTE_PERF, no further Godot process was started until PERF_DONE was recreated. Elapsed time was contended and is not a performance finding.
- **Probe results:** `_scratch/audit-B/probe.gd` (seed 1, synthetic data, fixed 1/60 tick where advancing time is needed), output `_scratch/audit-B/probe.log`. Ran after the recreated PERF_DONE. First launch attempts failed with exit 1 because Bash here is WSL (Windows `/c`/`C:` paths are not script paths for the Linux Godot); corrected to `/mnt/c/...`. These launch failures did not execute the probe. Corrected run **passed, exit 0**, with no script errors. The synthetic eligibility sweep reached **all 283/283 card IDs** across playable jobs, weapon families and unowned/low/near-cap rank states (`CARD_REACHABILITY`, `not_seen: []`). This proves possible eligibility, not natural draw frequency, effective gain at every canonical rank, or balanced diversity. Reproduction: use the existing audit-B isolated mirror and run `MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit ISOLATE=audit-B bash scripts/godot.sh --headless --path _scratch/godot_runs/audit-B/game --script /mnt/c/Users/itech/.t3/worktrees/maple-survivors/t3-eb28f480/_scratch/audit-B/probe.gd` from WSL.
- **Not executed / pending lead:** full game-suite result, four standard balance smoke groups and HG bot repeat-record determinism comparison. At **08:18 PDT**, after a bounded wait of about nine minutes following completion of the specialist probes, CHECKS_DONE was still absent, the balance folders had not appeared, and pipeline.log showed `test_suite` started at 08:05:19 with no completion entry. Consequently no current 12-run outcome table or determinism verdict is claimed. Read the lead outputs and append this comparison when CHECKS_DONE exists; no need to rerun the matrix.
- **Lead completed checks read:** `logs/node_tests.log`: **51 passed, 0 failed/skipped**, exit 0 after correcting the invocation; `logs/cargo_test_realwz.log`: real-WZ suite **18 passed**, exit 0. These are lead-owned results, not duplicated runs. Game suite/balance remain pending as stated above.
- **Visual/manual gameplay:** no independent play session executed; visually inspected the lead fixture finale `perf/finale_hg_s2026_fixture_fp/clear.png` with `view_image`. It shows a clear at 15:07 with 325 mobs and 354 loose drops; the image does not identify which drops are final-boss rewards. Lead perf/visual/flow captures are centrally coordinated. The original seed-2026 perf captures ended during warp (HG DEAD 4:19/Lv7, Tree about 0:47/Lv1; `NOTE_PERF.md`), so those are not evidence of late density, finale quality or natural clears.
- A few exploratory `rg` commands used Windows-incompatible wildcard path arguments and returned exit 2; corrected directory/glob searches were used. They were searches, not failing game checks.

### Baseline comparison and evidence limits

#232 (2026-10-18): Henesys bot deaths 339.6/455.4/323.4 s, levels 11/13/11; random 450.6/325.4/316.3 s, levels 19/11/12; Tree 128.9/63.6/51.5 s, levels 3/2/2. All died; no crashes/warnings/missing assets/skipped bosses. Those records predate the merged #235 state. Open issue #77 explicitly withdraws the old win-rate/end-level targets until re-triage, so historical numeric population targets are not current pass/fail requirements.

#235 (2026-10-19) explicitly records HG bot seeds 2/2026 becoming Beginner deaths around 4:34/4:19 and the temporary guard relaxation: Lv8 on 2/3, Lv10/Magician on 1/3. Its 24 forced-Magician training runs are a different experiment, not a replacement three-seed baseline. A repeat of seed 2026 dying at 4:19 is therefore known behavior, not a new regression. Tree early deaths remain owner-rework/#77 material. Natural tier-1 clear, inter-round economy and Dark Cave engagement cannot be inferred from diagnostic invulnerability/forced-boss-hit flow QA. The later lead fixture performance run `perf/finale_hg_s2026_fixture_fp/summary.json` does record **CLEARED, all 3 bosses dead, 907.833 s, Lv55, missing []**, starting from the committed **Lv38 F/P** fixture. It demonstrates an existing stronger build can resolve the finale, not that a fresh seed-2026 Beginner clears or that every loose reward was collected.

## 3. Strengths worth preserving

- Fixed-step plain-data simulation and distinct RNG streams make small deterministic reproductions practical (`run_world.gd:393`, `:1970`). Equipment, scroll, meso, job and class-specific rolls do not casually shift the combat stream.
- Movement preserves v83 commitment and geometry; named input plus latches bridges frame input to sim ticks (`run_scene.gd:398`, `:1009`). Jump-held behavior is explicit v83 policy, not an accidental application of a generic platformer recipe.
- Target selection is deterministic, boss-first then distance/slot; sweeps prevent ordinary projectile tunneling. Cooldowns run while climbing, but new casts wait; a short-MP skill does not prevent another affordable skill from casting (`skill_runner.gd:148–235`).
- Swarm routing separates the graph/cost field from movement and has progress hysteresis/off-screen stuck recovery. Boss pursuit teleport, harmless fade and preserved logical identity reduce unreachable-finale risk (`boss_director.gd:159`, `mob_swarm.gd:295`).
- Empty card pools and sparse rewards have an always-accepted Elixir path; exact-job/held-weapon checks, one chosen advancement weapon, no skill caps and separate advancement draws are consistently encoded (`upgrade_pool.gd:103–211`, `run_world.gd:2561`). No unsupported demand for stat cards or automatic skill grants.
- Pure shop/scroll modules, limited upgrade slots, canonical sale prices and run-owned mesos create a coherent sink. No buy/sell arbitrage was found in shipped scroll stock (scroll resale is canonical, not the 35k/70k purchase price).
- Run versus account state is explicit: death/clear NX is awarded at the boundary; cash Fortune is derived from account ownership and is not compounded into the carried character (ADR 0003; `nx_award.gd`, `cash_catalog.gd`, `scene_flow.gd:338`).

## 4. Findings

### B-1 — MaxMP equipment can refill MP repeatedly while the game is paused

- **Category/severity:** resource economy / **High**. **Type:** Confirmed bug.
- **Evidence:** `game/scripts/sim/run_world.gd:1165–1177` preserves current MP proportion whenever a MaxMP passive exists and the maximum rises, even with `grant_growth=false`. A decrease only clamps current MP. Equipment changes explicitly use `refresh_player_stats(false)` at `:1668–1670`. Therefore removing +MP equipment while below both maxima keeps absolute MP; putting it back multiplies that MP upward. Repeating costs no potion, cooldown or sim time because inventory windows hold the run.
- **Reproduction:** seed-1 synthetic Magician with Improved MaxMP Increase, partially empty MP, and one removable +MaxMP item; unequip/equip repeatedly. Probe label `MP_EQUIP_LOOP`: MP **10.0 → 179.318206608295** after five swaps, MaxMP 228, simulation time **0.0**.
- **Skills:** RPG reversible modifier layers; resource scarcity/run economy from roguelike. Derived capacity changes must not mint a consumable resource on a reversible cycle.
- **Impact:** bypasses MP scarcity and, with Magic Guard, indirectly supports survival. Large equipment is not required; a small positive bonus merely takes more cycles.
- **Recommendation:** separate passive-rank growth's intentional ratio preservation from equipment-capacity recomputation; gear swaps should follow the documented clamp-only policy. Do not remove #41's intended passive behavior.
- **Effort:** S. **Confidence:** Confirmed by synthetic runtime probe.
- **Acceptance:** repeated swaps at low MP do not raise current MP; passive learning/ranking still preserves its intended ratio; full pools clamp on capacity reduction.
- **False positive if:** equipment recomputation were excluded from the ratio branch or an input rule prevented repeated swaps. Both were checked and neither is present; the `false` argument does not guard this branch.
- **Known/intentional check:** #41 intentionally preserves ratio on passive growth; #105 and existing worn-equipment tests require derived gear stats but do not authorize free MP from swaps. No matching open issue found.

### B-2 — Continuing the same hub state changes the next scroll's RNG

- **Category/severity:** seeded economy correctness / **Medium**. **Type:** Confirmed bug.
- **Evidence:** hub construction passes `FreeMarket.scroll_seed(snapshot)` as the RunWorld seed (`game/scripts/run/free_market.gd:379–381`); RunWorld assigns scroll RNG stream 11 (`run_world.gd:404`), whose seed is `seed_value * 1000003 + 11 * 7919` (`:1970–1973`). After any inventory action, the hub instead assigns the raw hash directly to `inventory.scroll_rng.seed` (`free_market.gd:411`). Identical saved states thus have different next rolls in the live hub and a reconstructed hub.
- **Reproduction:** compare an immediate scroll after an item action with Save & quit→Continue (or Cash Shop→return) at that exact boundary. Probe label `HUB_SCROLL_RELOAD` compares raw-seeded/live and stream-11/resumed rolls for the identical synthetic snapshot. With seed hash **986129636**, live next rolls were **16, 9, 91, 67** and resumed rolls **73, 97, 9, 18**. Thus a 60% plain scroll succeeds live and fails after rebuild at this state.
- **Skills:** procedural-gen's same seed/state→same result; roguelike's resource stakes and predictable seeded continuation.
- **Impact:** breaks the explicit anti-reroll promise and creates two selectable scroll outcome sequences. No claim that a consumed failed scroll can be undone: actions save immediately. Foreknowledge/state manipulation can choose between the two next-roll modes.
- **Recommendation:** use one seed derivation at initial hub construction and after every saved mutation. Test actual outcome/RNG equality across rebuild, not only equality of `scroll_seed()` hashes.
- **Effort:** S. **Confidence:** Confirmed by synthetic runtime probe.
- **Acceptance:** next success/curse rolls and scroll results match before/after hub reconstruction, including after buy, equip, sell and use-scroll actions.
- **False positive if:** hub construction overwrote stream 11 with the raw hash before enabling input. `_build_windows`, `_ready`, `_on_item_action` and Cash Shop return were inspected; no such initialization exists.
- **Known/intentional check:** `free_market.gd:70–77` explicitly promises no reroll; `test_free_market.gd:167` checks hash changes but not the two initialization paths. This is distinct from ADR 0001's intentional same-stage replay.

### B-3 — Batch EXP awards use the destination level while calculating intermediate MP growth

- **Category/severity:** permanent character progression / **Medium**. **Type:** Confirmed bug.
- **Evidence:** `RunProgression.add_exp()` immediately advances to the final level (`run_progression.gd:45–59`). `RunWorld._gain_exp()` then calls `_on_level_up()` for each crossed level (`run_world.gd:2506–2510`). Although `_on_level_up(level)` receives the intermediate level, its stat refresh allocates secondary AP using `progression.level`, the final level (`:1145`), and the next growth reads the resulting INT (`:2519–2522`). A multi-level EXP award can therefore allocate later-level LUK early and reduce INT-dependent MP growth compared with the same EXP crossing one level at a time.
- **Reproduction:** identical seed-1 Lv20 Magicians, no advancement crossed; award EXP to Lv28 either in one batch or threshold by threshold. Compare final base MP, attributes and level. Probe label `BATCH_EXP_GROWTH`: both finish Lv28/INT113; batch base MP **645**, separate-award base MP **648**.
- **Skills:** RPG derived stats/leveling invariants; procedural-gen repeatable state transitions. Reward batching should not change permanent growth for otherwise identical progression.
- **Impact:** reward/collection grouping can permanently change MaxMP. High-EXP Dark Cave drops and boss rewards make multi-level gains a practical path; this is not a proposal to change the stage EXP multiplier.
- **Recommendation:** compute each level's AP-derived attributes against that intermediate level before its next growth; preserve the existing queue/modal advancement policy.
- **Effort:** M. **Confidence:** Confirmed by synthetic runtime probe.
- **Acceptance:** same-job, same-start, same-total EXP produces identical base HP/MP/AP and final attributes for batch versus single-threshold awards; potion notices and queued level choices remain ordered.
- **False positive if:** MP growth intentionally depended on how drops were grouped, or refresh received the intermediate level. No such decision found; refresh reads the final progression level directly.
- **Known/intentional check:** multi-level immediate queueing is intentional; #106 specifies level-based automatic LUK. Neither requires group-dependent permanent MP. No matching issue found.

### B-4 — A completed finale can still lose the character on the next combat tick

- **Category/severity:** finale transition / **Medium**. **Type:** UX concern (objectively demonstrable transition, intended precedence needs confirmation).
- **Evidence:** `apply_choice()` drains the last reward then returns to PLAYING (`run_world.gd:1021–1046`, `:2591`). `can_clear()` is then true, but is checked only by `_end_tick()` (`:971–984`). The next step first advances monsters, attacks, pickups and contact damage (`:696–712`); death makes `_end_tick()` return. A lethal ordinary contact/ball after every scheduled boss is dead and every choice is answered can archive a death instead of a clear.
- **Reproduction:** all encounter records dead, final bonus resolved, low HP, a settled ordinary mob overlapping the player; one fixed tick. Probe label `FINALE_TRANSITION` records `can_clear` before the tick and the resulting state: **can_clear=true before tick, all bosses dead, DEAD after tick**.
- **Skills:** level-design critical-path completion and RPG explicit combat win/loss state transitions.
- **Impact:** player can meet the stated clear condition, answer its reward and still lose the entire carried run without an intervening movement decision.
- **Recommendation:** define finale precedence explicitly. Prefer settling the successful objective as soon as the last mandatory choice is answered, before admitting another damaging tick; coordinate this with B-5's reward settlement.
- **Effort:** S/M. **Confidence:** Confirmed behavior; intended precedence needs owner confirmation.
- **Acceptance:** deterministic lethal-contact and pending-projectile cases at the final-choice boundary produce the agreed outcome; ordinary deaths before completing the objective remain unchanged.
- **False positive if:** one further dangerous tick after the final answer is deliberate. Architecture says choices return to PLAYING, but no player-facing/design rule explaining an additional hazard test was found. Do not silently treat this recommendation as a balance change.
- **Known/intentional check:** GAME_DESIGN §1/§4.3 requires all bosses dead and reward choices answered. Existing lifecycle tests use god mode and do not decide this precedence.

### B-5 — Final-boss ground rewards can be discarded when the round clears

- **Category/severity:** reward/carry experience / **Medium**. **Type:** UX concern / proposed improvement, not asserted as a violation of the in-round EXP-cap rule.
- **Evidence:** boss death spawns EXP, potion, mesos and equipment pickups (`run_world.gd:2314–2361`). `can_clear()` checks bosses and choices, not reward collection (`:550–554`); the clear ends `step()` processing. The outgoing character carries collected inventory only (`run_scene.gd:1884–1896`, `scene_flow.gd:338–387`). A ranged final kill can leave its shower outside magnet range with no chance to approach after the bonus window. Any remaining pickups end with the old world.
- **Reproduction:** final encounter complete with an EXP drop outside magnet range; answer the last bonus and step once. Probe label `FINALE_LOOT` records **CLEARED with one active EXP drop and zero collected EXP**. Confirm the same outcome with a distant final boss and its normal shower before implementing a solution.
- **Skills:** RPG encounter→reward→growth loop; level-design release/reward after a climax; roguelike inter-round resource carry.
- **Impact:** final-boss rewards may contribute less than earlier bosses to the tier-2 character and scroll budget, depending on kill distance. Diagnostic flow completion does not prove reward receipt.
- **Recommendation:** agree an explicit final-boss payout policy (safe collection/settlement phase or deterministic reward transfer), including inventory-full equipment handling. Avoid an unbounded wait for every ordinary drop, which would itself soft-lock the finale.
- **Effort:** M. **Confidence:** Confirmed behavior; payout policy remains an experience recommendation.
- **Acceptance:** distant final kills deliver the agreed final-boss payout exactly once; all resulting level/job choices finish before snapshot; full inventory has an explicit outcome; quitting cannot duplicate rewards.
- **False positive if:** final-boss loose loot is intentionally forfeited, or all rewards are swept before snapshot. No sweep found. The owner's “EXP never disappears” rule is about in-round lifetime/cap and is not used as proof that all map leftovers must carry.
- **Known/intentional check:** ADR 0001 carries character state, not map entities; #19/#20's rewards and current boss lifecycle reviewed. This proposes a defined settlement policy, not persistence of the live simulation.

### B-6 — Gun Pirate/Gunslinger bot equipment scoring favors the wrong primary stat

- **Category/severity:** gameplay policy / evidence validity / **Medium**. **Type:** maintainability risk with objectively demonstrated data mismatch.
- **Evidence:** `balance.json:16` uses DEX for `500:gun` and `520`; `BotShop.weights_for()` resolves only numeric job lineage (`bot_shop.gd:21–26`) and `equipment_weights` has entries for 0/200/300/400, not 500/510/520. Both gun jobs inherit Beginner weights: STR 6 versus DEX 3. The scoring drives auto-equip, spare retention/sales and best-scroll selection (`:64`, `:183`, `:247–291`). Knuckle Pirate's STR preference does fit that fallback.
- **Reproduction:** compare equal-cost/equal-other-stat +STR and +DEX items/scrolls for a gun Pirate and a Gunslinger; inspect `weights_for()` and chosen score. Probe label `PIRATE_WEIGHTS`: jobs 500, 510 and 520 all resolve **STR 6 / DEX 3**.
- **Skills:** game-ai intent and decision policy matching the agent's goal; RPG primary-stat→derived-combat scaling and meaningful gear upgrades.
- **Impact:** the supposedly sensible bot can prefer a less effective gun build and spend mesos on its secondary stat. This biases class comparison and #77's future calibration; it does not prove current player-facing gun damage is wrong.
- **Recommendation:** let equipment policy resolve the recorded Pirate weapon path and Gunslinger branch consistently with AP/combat. Treat the exact weight calibration as #77 work; add a qualitative primary-stat direction guard rather than inventing new optimal numbers here.
- **Effort:** S/M. **Confidence:** Confirmed by source and runtime lookup.
- **Acceptance:** gun-path and Gunslinger scoring intentionally values their DEX primary; knuckle/Brawler still use STR; branch switches select branch policy; sensible equipment/scroll tests cover both paths without tuning stage balance.
- **False positive if:** the owner intentionally wants sensible gun bots to prefer STR, or a path-specific override exists elsewhere. No such override found; all three consumers call `weights_for`.
- **Known/intentional check:** #186/#189 specify the primary/secondary split; #112 defines the sensible policy. Existing `_equipment_weights` text predates Pirate handling. No matching open issue found.

### B-7 — Bless still tells players its accuracy does nothing

- **Category/severity:** progression choice information / **Low**. **Type:** Confirmed bug (stale gameplay text).
- **Evidence:** `skills/magician.json:319–320` and `upgrades/magician.json:248` say accuracy has no effect. `SkillText.desc()` prefers that override and dresses learn cards with it (`skill_text.gd:45`, `:88–100`). In contrast, `_refresh_caster()` includes buff ACC (`run_world.gd:1207`); resolved critical chance includes `acc * crit_per_acc` (`loadout.gd:330`), as required by ADR 0005.
- **Reproduction:** open Bless's Skill tooltip or learn card; compare before/after effective crit with Bless active. No real-WZ fact is needed to establish the stale override.
- **Skills:** RPG choices require accurate consequences; input-systems/readable actionable state applies to the player's decision, not an extra UI redesign requirement.
- **Impact:** undervalues a real offensive benefit of the Cleric's buff and makes the ACC stat misleading.
- **Recommendation:** update both skill text override and fallback card description to explain the implemented accuracy→crit relationship.
- **Effort:** S. **Confidence:** Confirmed source path.
- **Acceptance:** Bless learn card and Skill tooltip no longer claim ACC is inert; text agrees with effective crit behavior. A focused semantic check is sufficient; no new balance run needed for a text-only correction.
- **False positive if:** Bless's ACC were excluded from critical chance. `_refresh_caster` and `Loadout.stats` checked: it is included.
- **Known/intentional check:** ADR 0005 and #153 explicitly repurpose accuracy. Historical #58 text explains the stale wording, not current intent.

### B-8 — Power-card semantics vary between equivalent Warrior and Bowman mechanics

- **Category/severity:** progression data consistency / **Low**. **Type:** proposed improvement / needs #77 policy decision.
- **Evidence:** Warrior Final Attack and Booster learn/rank cards are power cards by #181 and GAME_DESIGN §7.9; Bowman equivalents have `power:false` (`upgrades/bowman.json:242`, `:293`, crossbow equivalents at `:506`/`:571`). Both use the same damaging Final Attack and attack-speed mechanics. Pity and guaranteed advancement selection key solely off `power` (`upgrade_pool.gd:146–203`).
- **Skills:** RPG meaningful growth choices and procedural-gen weighted-table semantics; game-ai policy consistency across builds.
- **Impact:** equivalent offensive options participate differently in drought prevention and advancement guarantees. This is not an empty-window bug: Hunter/Crossbowman still guarantee their specified active attacks, and the fallback remains available.
- **Recommendation:** record whether this asymmetry is intentional and add a data-level semantic guard for the agreed classification. Any offer/probability change belongs with owner approval/#77, since it changes draws and seeded histories.
- **Effort:** S. **Confidence:** Confirmed metadata difference; whether it is undesirable Needs validation.
- **Acceptance:** a documented classification says which offensive passives/buffs count toward pity per line; tests encode it; no silent bulk reclassification or specific new weights in this audit.
- **False positive if:** the asymmetry is an intentional class identity/balance rule. #202/#203 explicitly require the active attacks in their advancement draw, so there is no claimed spec breach here.
- **Known/intentional check:** checked #181, #202/#203 and §7.9/§8. Existing tests cover their own branch expectations, not cross-line semantics. Present as policy cleanup, not a reopened completed ticket.

## 5. Considered and rejected

- Generic movement retuning, coyote time, variable-height jumps, CharacterBody2D conversion: conflict with owner v83 fidelity and the deliberate architecture.
- Stunned/frozen mobs finishing a pre-existing windup: #187 says “doesn't start attacks”; only Disorder explicitly interrupts pending windups. Do not infer a generic interrupt requirement.
- Save-scumming/known-seed foreknowledge from Quit round→Continue: explicitly chosen in ADR 0001; do not delete run saves or silently reroll the seed. B-2 is a separate hub-RNG inconsistency.
- No attack key, no skill prerequisites/slot caps, no skills automatically granted at advancement, current-job-only Mage cards, no stat/Magnet/potion-tier cards: intentional owner rules.
- Buying potion tiers that arrive free: removed by #225; no such cards found in the current Beginner pool. Power Elixir as an exhausted-pool filler is an explicit exception, even when a player is already full.
- Dark-scroll weapon destruction and bare hands getting no weapon-family drops: explicit #105/#159/ADR 0002/0005 consequences. A reserve-weapon warning may help, but changing weapon drop eligibility would reverse owner policy.
- Rope camping automatically clearing a stage: casting is blocked while hanging and clear requires boss deaths; mere survival or TIMEOUT is not a clear. Current safety/dominance still needs measured camper observations, not speculation.
- Tree early deaths and lack of natural clears in the recent tiny smoke: known record-only owner-rework/#77 territory, not evidence for immediate tuning or a new difficulty bug.
- Boss immunity consuming a Three Snails/pierce contact, bosses resisting statuses, only bosses inflicting player statuses, ordinary ball/hit-window behavior: intentional documented rules.
- HP restored by equipment swapping: `_equipment_changed` passes false and HP is clamp-only. Rejected; B-1 is the separate unconditional MaxMP-passive branch.
- Supposed scroll arbitrage from canonical resale: shipped buy price greatly exceeds the scroll's canonical resale. No normal UI path to a negative-price stock entry found.
- Cash Fortune compounding through character carry or repeated NX for Quit round: derived Fortune and boundary-only NX prevent those paths in inspected code.

## 6. Unverified hypotheses and evidence needed

- **Current camper dominance / portal abuse:** historical camper samples precede current classes/cards. After central checks, a bounded seed-1 camper comparison could assess arrival, attacks, boss engagement and timeout; lack of damage alone would not prove an exploit. Do not retune movement or spend held-out seeds.
- **No-op rank/card corners at high level:** a full real-WZ rank-by-rank effective-change sweep was not run. Static eligibility excludes owned/maxed/new/wrong-weapon duplicates and filler handles exhaustion. A low-rank sample cannot prove every rare high-rank combination is meaningful. In particular, stacked/capped speed or crit can make a canonical rank's marginal gain build-dependent; this requires context, not automatic removal of real skills.
- **Natural tier chain and branch diversity:** the default three-seed smoke can end before second jobs. Use fixtures for mechanics and separate actual natural-clear/tier-feed observations for experience. Diagnostic victory proves transition plumbing only.
- **Finale precedence/loose-loot intent:** B-4/B-5 need an explicit owner settlement decision. Their observable states can be reproduced without proving which player experience is desired.
- **Full-smoke determinism:** compare matching base/repeat records recursively, excluding only actual wall-clock/performance fields; do not ignore event/card/loot/character differences. Pending lead results are not a determinism pass.

## 7. Small independent backlog tasks

1. **Close the MP swap loop (B-1).** Load `rpg`, `roguelike`; assert repeated gear swaps cannot create MP and preserve #41's passive-rank behavior.
2. **Unify hub scroll RNG setup (B-2).** Load `procedural-gen`, `rpg`; assert identical next success/curse rolls before/after reconstruction of the same post-action snapshot.
3. **Make intermediate growth independent of EXP batching (B-3).** Load `rpg`, `procedural-gen`; same-job batch/single-threshold awards must produce identical permanent stats and ordered pending choices.
4. **Specify and implement finale settlement (B-4/B-5).** Load `rpg`, `level-design`, `roguelike`; cover lethal contact/ball at last answer, distant boss loot, inventory capacity and exactly-once carry without persisting the live world.
5. **Make sensible gun equipment policy path-aware (B-6).** Load `game-ai`, `rpg`; cover gun/knuckle and branch-switch preference direction. Defer numerical calibration to #77.
6. **Correct Bless's gameplay description (B-7).** Load `rpg`; both fallback and live skill text agree that accuracy contributes to crit.
7. **Decide offensive-card classification consistency (B-8).** Load `rpg`, `procedural-gen`; document the rule and test per-line exceptions before changing draw behavior in #77.

No issue writes, implementation changes, commits, balance patches or movement retuning were performed.





