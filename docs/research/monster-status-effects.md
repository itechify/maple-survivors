# Monster statuses and elements: issue #54

Research date: 2026-10-15. Sources were read for facts and independently described below; no third-party
implementation is copied. **A** means original v83 WZ; **B** means third-party official-client reverse engineering;
**C** means a reimplementation or an explicit Survivor rule. B evidence from v95 is identified as such and does
not establish exact v83 behavior. The protected v83 executable was not unpacked or run for this investigation.

## Findings and limits

| Rule | Evidence | Tier / implementation implication |
|---|---|---|
| Poison amount depends on monster max HP and the applying skill's level | Cosmic uses max HP divided by `70 - skill_level`, approximate upward rounding, capped at 32,767 [1]. | C. This is a v83 server emulator, not binary RE. Do not describe its rounding or cap as verified v83. |
| Poison pulse | The reconstructed v95 `CMob::Update` compares the poison display clock against 1,000 ms and displays its stored status amount [2]. Cosmic also schedules 1,000 ms pulses [1]. | B for the v95 display cadence; C for authoritative damage timing and the first/last tick boundary chosen by this sim. |
| Poison cannot kill | Cosmic's damage task reduces a would-be lethal pulse to current HP minus one and attributes damage to the applying character [1]. | C corroboration; no native v83 HP-authority proof found. Player damage attribution follows #54. |
| Freeze stops movement and new skills | Native-derived v95 `IsImmovable` includes freeze; `TryDoingSkill` returns when this predicate is true [3]. | B, v95 extrapolation. |
| Freeze stops attacks | Native-derived v95 `DoAttack` checks status gates before retrieving attack information. HaCreator's IDA-backed reconstruction explicitly includes freeze in this gate [4]. | B, v95 extrapolation. These establish admission gates; this project's attacking scheduled bosses reject Freeze. |
| Touch damage while frozen | No native v83/v95 contact-admission evidence was established. HaCreator's separate contact loop does not check freeze [5]. | C only. Owner decision (PR #62 review): a frozen monster deals no touch damage, so Freeze protects in a swarm. Not a verified v83 fact either way. |
| Boss status eligibility | Cosmic rejects ordinary poison on `boss` templates along with most statuses [1]. No native source confirming #54's boss-poison claim was found. | C. Owner decision (PR #62 review) follows the server reference: bosses reject Slow, Poison and Freeze. |
| Elemental status rejection | Cosmic rejects a status when the monster's effectiveness against the status skill's element is IMMUNE (digit 1), STRONG (2) or NEUTRAL (4), and accepts NORMAL (absent) and WEAK (3) [1, lines 1138–1149; 8]. | C. Implemented as `MobKind.resists_status`; Poison uses S and Freeze I (the applying skills' canonical elements), Slow none. Digit 4 still deals ×1 hit damage. |
| Slow refresh without stacking | The ticket requires refresh. Canonical Slow text additionally mentions a two-consecutive-applications restriction, absent from this ticket's requested interface [6]. | C Survivor refresh policy; magnitude and duration remain A. |

The exact original poison HP computation is unresolved. The native client display reads a poison status option;
it does not derive that value from monster HP in the inspected update branch. Client RE therefore supports the
display cadence without proving the server's HP formula, rounding, kill floor, or boss eligibility. Cosmic's
documented approximation is suitable as a clearly marked C fallback. Applying the formula to stage-scaled max HP,
using ordinary poison on scheduled bosses, and the precise expiry/refresh behavior are also Survivor decisions.

## Original v83 data and available visuals

Verified against the user's original install at
`C:/Users/itech/Coding/maple-survivors-refs/v83-original`, through its generated cache and the prior-art read-only
WZ dumper. Cache `cache.json` identifies that original WZ root. Only descriptions are retained here; decoded images
and WZ files remain outside version control. The [cache contract](../ASSET_PIPELINE.md) documents the reader.

| Original path | Verified fields | Consequence |
|---|---|---|
| `Skill.wz/210.img/skill/2101003/level/<n>` | Slow: signed `x` from -2 to -40; `time` from 2 to 40 seconds | Interpret canonical negative `x` as a reduction, not an already positive percent. |
| `Skill.wz/210.img/skill/2101003/mob` | Five frames, each 100 ms; `pos=3`; no `repeat` | Already cached. An authored one-shot cue exists. Replaying it throughout the status would be C presentation policy. |
| `Skill.wz/210.img/skill/2101005` | Poison Breath: `elemAttr=s`; per-level `prop` and `time`; `mob` has five 70 ms frames, `pos=2`, `repeat=1` | Already cached; use its authored repeating poison overlay. |
| `Skill.wz/220.img/skill/2201004` | Cold Beam: `elemAttr=i`, `x=-100`; `time=1` through level 15 and 2 thereafter; `effect` and `hit/0`, no `mob` branch | Not currently selected by the manifest. No persistent Cold Beam mob overlay was found here; a freeze tint is a C fallback. |
| `String.wz/Skill.img/2201004/desc` | Describes freezing, 1.5 times damage to fire enemies and half damage to ice enemies | A support for element weakness/resistance factors. |
| `Mob.wz/1110100.img/info/elemAttr` | `S1` | A real poison-immune example; the existing inventory records it [7]. |

The `pos` numbers above are canonical data. Mapping them to head/body/feet anchors requires a separate client rule;
the data alone does not establish those meanings. A chosen fallback anchor or tint must remain C.

Mob element letters and effectiveness decoding are also implemented by Cosmic: F fire, I ice, L lightning,
S poison, H holy, D dark, P physical; effectiveness digits 1 immune, 2 strong, 3 weak [8]. Preserve original IDs,
normalize letter case, leave absent/unknown elements neutral, and keep elemental immunity from becoming the
combat layer's existing minimum-one-damage clamp. The factors requested by #54 are 0, 0.5 and 1.5. The original
`undead` flag can be exposed independently; it does not by itself make every element weak.

## Source pointers

1. [Cosmic Monster.java, fixed commit fec53bc](https://github.com/P0nk/Cosmic/blob/fec53bc7714dc0f1ae3f50b2986cdf2727e0912a/src/main/java/server/life/Monster.java#L1137-L1291): elemental status rejection at 1138–1165; HP admission at 1167; boss gate at 1172–1178; poison amount and interval at 1222–1229. [DamageTask at 1611–1668](https://github.com/P0nk/Cosmic/blob/fec53bc7714dc0f1ae3f50b2986cdf2727e0912a/src/main/java/server/life/Monster.java#L1611-L1668): one-HP floor and caster attribution. AGPL-3.0; facts only.
2. [shroom95-decomp Mob_regen.ipp, fixed commit 6eada75, lines 641–690](https://github.com/jon-zu/shroom95-decomp/blob/6eada755b00522e39213ee93e75471a98b1e30a3/src/game/Mob/Mob_regen.ipp#L641-L690): reconstructed v95 `CMob::Update` (`0x00254300`), poison timer and `ShowDamage`. Read via raw source when GitHub's large-file view timed out.
3. [Native-derived IsImmovable](https://github.com/jon-zu/shroom95-decomp/blob/6eada755b00522e39213ee93e75471a98b1e30a3/src/game/Mob/Mob.cpp#L598-L601) and [TryDoingSkill admission](https://github.com/jon-zu/shroom95-decomp/blob/6eada755b00522e39213ee93e75471a98b1e30a3/src/game/Mob/Mob_regen.ipp#L8770-L8801), same fixed v95 reconstruction.
4. [HaCreator MobAttackSystem.cs, fixed commit 4d7fcec, lines 3766–3803](https://github.com/lastbattle/Harepacker-resurrected/blob/4d7fcecbdff0767e333a34d47cbf331caa16416a/HaCreator/MapSimulator/Combat/MobAttackSystem.cs#L3766-L3803), explanatory client gates; corroborating [native-derived DoAttack entry](https://github.com/jon-zu/shroom95-decomp/blob/6eada755b00522e39213ee93e75471a98b1e30a3/src/game/Mob/Mob_regen.ipp#L37265-L37335). HaCreator's [combat parity notes](https://github.com/lastbattle/Harepacker-resurrected/blob/4d7fcecbdff0767e333a34d47cbf331caa16416a/docs/mapsimulator/MapSimulator-Client-Parity-Backlog-6-Combat-Effects-Mobs.md#L150-L156) identify IDA functions `CMob::DoAttack 0x6504d0` and `CMob::ProcessAttack 0x652950`.
5. [HaCreator PlayerCombat.cs, contact loop](https://github.com/lastbattle/Harepacker-resurrected/blob/4d7fcecbdff0767e333a34d47cbf331caa16416a/HaCreator/MapSimulator/Character/PlayerCombat.cs#L583-L610). This is reimplementation evidence, not a claim of native contact parity.
6. Original `String.wz/Skill.img/2101003/desc` inspected from the cache on this date. [Issue #54](https://github.com/itechify/maple-survivors/issues/54) defines the requested refresh and boss-poison policies.
7. Existing original-WZ [inventory](wz-inventory.md) and [mob reference table](cosmic-data.md), cross-checked against the cache.
8. [Cosmic Element.java](https://github.com/P0nk/Cosmic/blob/fec53bc7714dc0f1ae3f50b2986cdf2727e0912a/src/main/java/server/life/Element.java#L43-L61), [ElementalEffectiveness.java](https://github.com/P0nk/Cosmic/blob/fec53bc7714dc0f1ae3f50b2986cdf2727e0912a/src/main/java/server/life/ElementalEffectiveness.java#L27-L34), and [LifeFactory element parsing](https://github.com/P0nk/Cosmic/blob/fec53bc7714dc0f1ae3f50b2986cdf2727e0912a/src/main/java/server/life/LifeFactory.java#L286-L292).

## Validation record

These measurements and checks moved here from `docs/GAME_DESIGN.md` during the PR #62 review.

Initial implementation (2026-10-15): Henesys seed 2026, `scripts/playtest.sh --warp=720 --minutes=13 --speed=1 --vsync=off`;
baseline 5e178c3 versus #54, separate sequential runs with no concurrent tests from this task. Other worktrees were
running balance jobs on the shared machine, so these timings are noisy. Each measured 3,600 drawn sim ticks,
all at 200+ mobs, max 288, with identical gameplay totals and `missing: []`:

| Capture (`evidence/issue54/`) | Sim µs/tick | 200+ frame p95 ms |
|---|---:|---:|
| `baseline` (5e178c3) | 1,235.95 | 4.808 |
| `after` (first implementation) | 1,040.83 | 3.864 |
| `after_final` (renderer fast path) | 1,530.81 | 5.411 |
| `baseline_final` (fresh 5e178c3) | 1,469.27 | 5.201 |

The initial pair alone cannot establish the no-regression criterion under changing CPU load. After adding the
movement fast path, three alternating `scripts/bench.sh run 300` baseline/implementation samples (600 timed ticks
after 240 warmup ticks, built-in seed 4542) gave real-map µs/tick 1184.4/1173.4, 1200.2/1220.9 and 2002.9/2065.6;
synthetic 1011.2/1028.4, 1061.0/1120.4 and 1899.0/1688.9. All held 300 mobs and matching gameplay counts.
The large timing variation prevents a precise small-regression conclusion from these unrestricted samples.
Raw output: `evidence/issue54/bench-300.log`.

Final controlled pair: the same playtest at `--minutes=12.25` (12:00–12:15), pinning only each owned native Godot
process to logical CPU 15 (affinity mask 32768) at High priority before the measured interval. Both ran 900 ticks,
max 247 mobs, every drawn frame 200+, 1,974 kills and 392,213 damage, missing[]. Baseline **1,483.16 µs/tick** versus
final implementation **933.92 µs/tick**: no observed simulation slowdown in this pair. This is not a speedup claim;
frame pacing still differed (p95 6.322/6.962 ms), and a small CPU-cost difference remains below what these shared-machine
measurements can establish. Scheduling settings and summaries are preserved in
`evidence/issue54/{baseline_controlled,after_controlled}/`; settings ended with the test processes. The implementation's
final screenshot was skipped because the window was occluded; visual QA uses the earlier captures described below.

These exercise inactive-status cost because applying skills remain sibling work. Evidence/logs are gitignored;
cached status-cue/expiry captures in `evidence/issue54/statuses/status_0..2.png` were checked by eye, as were the
real-game captures. These 13:00 timeouts are not clears or balance acceptance runs.

Final checks: `bash scripts/test.sh` passed **551 tests, 0 failed, 0 skipped** (both stages' fixed training-seed
full-run regressions included). `cargo test` with `MAPLE_WZ_ROOT` set to the original v83 install passed **46 tests**,
including all 17 real-data integration tests. Final isolated status/movement/render checks passed **42 tests, 0 skips**.
Console output is preserved under gitignored `evidence/issue54/`.

### PR #62 review: active statuses (2026-10-15)

The initial measurements only exercised inactive-status cost. `scripts/bench.sh run 300 --statuses` now keeps every
live mob of the 300-mob RunWorld benchmark slowed (x -40) and poisoned (level 20) and every third slot frozen,
reapplying expired statuses between timed ticks (application itself is untimed). Merge-base `5e178c3` without
statuses versus this branch without and with statuses, alternating, shared machine (wall-clock noise is large):

| Round set | Map | Base µs/tick | Branch µs/tick | Branch + statuses µs/tick |
|---|---|---:|---:|---:|
| Median of 3 final rounds | synthetic | 1,699.3 | 1,682.7 | 1,817.4 |
| Median of 3 final rounds | 104040000 | 2,061.3 | 1,915.7 | 2,103.7 |

No difference is measurable without statuses. Timing the status tick directly (300 mobs, 600 ticks, three runs):
every mob carrying statuses costs about 150–185 µs per tick; 5 statused mobs among 300 cost about 2–3.5 µs because the
tick visits only a compact list of statused slots. Before that list, the scan of every slot cost about 41–55 µs per
tick even with only 5 statused mobs, in both the original and the table-based version.

Visual check: a temporary, uncommitted playtest hook applied statuses to every live mob after a warp to 7:00.
Frozen mobs show the cyan tint (brown Stirges turn blue-violet), poison loops its green bubble cue and prints its tick
numbers, and `missing` stayed empty. The original PR head rendered the identical frame for the same hook, so the
table refactor changed no presentation. Captures are in gitignored `evidence/pr62_review/`.
