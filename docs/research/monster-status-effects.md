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
| Freeze stops attacks | Native-derived v95 `DoAttack` checks status gates before retrieving attack information. HaCreator's IDA-backed reconstruction explicitly includes freeze in this gate [4]. | B, v95 extrapolation. Blocking already pending attacks is the implementation's C boundary choice. |
| Touch damage while frozen | No native v83/v95 contact-admission evidence was established. HaCreator's separate contact loop does not check freeze [5]. | C only. Keeping ordinary canonical `bodyAttack` contact damage while freezing active attacks is a defensible explicit choice, not a verified v83 fact. |
| Bosses resist slow/freeze but accept poison | Cosmic actually rejects ordinary poison on `boss` templates along with most statuses [1]. No native source confirming the ticket's boss poison claim was found. | C Survivor policy required by #54. Do not cite Cosmic as evidence that v83 bosses accept Poison Breath. |
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
