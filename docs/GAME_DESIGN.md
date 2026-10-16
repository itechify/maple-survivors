# Game design

Maple Survivors: survive a classic MapleStory map while an ever-growing swarm of familiar monsters closes in. You move,
jump, climb and drop through the real v83 terrain; your skills fire on their own; you pick upgrades as you level, and
you advance jobs at the classic milestones.

All tuning numbers below live in `game/data/survivor/*.json`; this document explains them. Canonical MapleStory values
(mob stats, skill tables, frame timings, Physics.img) come from the player's WZ data and are never edited.

## 1. The run

1. **Stage select.** Pick a map (stage). A stage = an original v83 map + a survivor monster roster + a pacing curve.
2. **Start.** Level 1 Beginner, default MakeCharInfo look (face 20000, hair 30030, White Undershirt 1040002, Blue Jean
   Shorts 1060002, Red Rubber Boots 1072001), standing at a random spawn portal (`pn=sp`). The map's own BGM plays.
3. **Survive** the growing swarms and defeat the three bosses arriving at 5:00, 10:00 and 15:00. The final fight can
   continue past 15:00; reaching the timer alone does not clear a stage.
4. **Level up** by collecting EXP drops. An eligible upgrade choice pauses the game and offers up to three cards;
   an empty pool opens no window.
5. **Advance** to Magician at level 10 (survivor override). Further Explorer jobs are planned (section 9).
6. **End.** Death (HP 0) shows the tombstone falling, then the results. A clear requires all three bosses dead and
   their bonus reward choices answered. Results show time, level, job, kills, damage dealt and owned skills;
   Retry or Stage select.

Runs are independent: level, job and skills reset every run. Persistent progression is Phase 3.

## 2. Controls

| Action | Keys (MapleStory defaults first) |
|---|---|
| Move | Left / Right arrows (also A / D) |
| Jump | Left Alt (also Space, C) |
| Climb ladder/rope | Up / Down near a ladder (W / S) |
| Use a same-map portal | Hold Up in its entrance (also W) |
| Down-jump through a platform | Down + Jump |
| Prone | Down (on the ground) |
| Teleport (after learning it) | X + direction; no direction uses facing; hold X to repeat |
| Pick an upgrade | Mouse, or 1 / 2 / 3, or arrows + Enter |
| Pause | Esc |

There is no attack key: attacks cast automatically. Teleport is manual on X.

## 3. Movement (MapleStory physics)

Constants come from `Map.wz/Physics.img` (tier A). The integration model follows the closest documented model of the
client's `CVecCtrl` (NoLifeStory `physics.cpp` description, tier B), re-implemented from prose:

- **Ground:** holding a direction accelerates at `walkForce/100` = 1400 px/s² up to `walkSpeed` = 125 px/s × speed%/100;
  releasing decelerates at `walkDrag/100` = 800 px/s² (drag clamped by min/maxFriction). Velocity follows the foothold
  slope; steeper than |sin| 0.9 slips (slipForce/slipSpeed).
- **Jump:** take-off `jumpSpeed` = 555 px/s × jump%/100; a held direction sets vx into [0.8, 1.0] × max walk speed.
  Gravity 2000 px/s², terminal fall 670 px/s. Apex ≈ 77 px.
- **Air control:** almost none (≤ ~9 px/s change at 200 px/s²), as in v83: you commit to a jump.
- **Down-jump:** Down + Jump on a foothold without `cantThrough`/`forbidFallDown` with a floor below: vy = -196 px/s,
  the current foothold is ignored until landing.
- **Landing:** vy clamped to 162.5 px/s on contact; walking off an edge falls; vertical footholds are walls.
- **Ladders/ropes:** Up/Down within 10 px of a ladder's x grabs it; climb speed 100 px/s (tier C); Jump + direction
  leaves it; `uf=1` lets you climb off the top.
- **Same-map portals:** hold Up with the feet inside x ±25, y −100…+25 around the canonical portal point. The player
  arrives instantly and silently 30 px above the target and falls to its floor; velocity resets and the camera snaps.
  A global 384 ms cooldown prevents repeated warps. These values are tier C and live in `balance.json.portals`.
  Links resolve the source's `tn` to a destination `pn` when `tm` is this map's id or 999999999. Other-map exits stay
  drawn and inert; Up still grabs ladders when no portal activates. Monsters do not use portals.
  The Tree That Grew I's left hollows go up00 → up01 → up02 → up03 (floors P3, P4, P7); its right hollows go
  dw00 → dw01 → dw02 → dw03 (P4, P3, then the right ground chain P2). The left ground chain is P1. These platform
  indices describe the imported v83 geometry used by the real-map test. up03 exits to Tree II and is inert.
  Type-10 hidden portals loop the original MapHelper `ph/default/portalContinue` sparkle art; type-1 portals remain
  visually marked only by map hollows.
- **Map edges:** the player cannot leave the foothold span horizontally (walls at the outermost foothold x).
- **Fixed step:** the sim ticks at 60 Hz; the player integrates in 2 sub-steps per tick (≈8.3 ms).

## 4. Monsters and swarms

Each monster is the original mob: its WZ animations (`stand`, `move`, `jump`, `hit1`, `die1`), its stats from
`Mob.wz/<id>.img/info`, its sounds (`Sound.wz/Mob.img/<id>/Damage`, `Die`) and its name from `String.wz`.

- **Speed:** move speed px/s = (speed stat + 100) × 0.625 (tier C, HeavenClient's terminal speed) × the stage's speed
  multiplier. Snail 21.9, Blue Snail 31.3, Shroom 43.8, Slime 50, Orange Mushroom/Pig 62.5 px/s, so the player
  (125 px/s) can outrun early mobs; late-stage multipliers close the gap.
- **Pursuit:** ground mobs walk along footholds. A mob on the player's platform walks toward the player; otherwise it
  follows the **shortest way** through the platform graph (`NavGraph`): walking off an edge onto a lower platform
  ("drop"), or, for mobs with a `jump` animation (Slime, Pig, Orange Mushroom), jumping up to a platform within reach.
  "Shortest" is the walk in px (each drop or hop counts 40 px, about a fall's time) to the player's x, not the number
  of edges: on 104040000 the 1518 px platform above the ground drops onto the ground only at its left end and onto a
  step at its right end, and a mob above the player's right half now takes the near right end instead of crossing the
  whole platform. A mob keeps the way it chose until another is 96 px shorter (no turning back and forth under a
  player who paces), and a straight-up hop takes off where the way goes on. A walker below a player standing on a low
  step (at most 40 px up, within touch) walks under the player; jumpers hop onto the step. Mobs never teleport
  visibly or float. A mob that cannot reach the player wanders on its platform.
- **Player-platform spawns:** 35% of ground spawn attempts target the player's platform (`spawn.platform_share`),
  at least 150 px away (`spawn.platform_min_dist`). If the whole platform fits in view, these mobs can appear visibly
  with the existing 0.3 s regen fade and remain harmless until fully opaque. If it extends past the view, placements
  stay on its off-screen portions. When that platform has no valid point, the ordinary rings serve instead.
- **Other spawning:** at points on floors outside the camera view (+48 px margin, and 32 px more on the side a moving
  player runs away from, where the camera lags behind it) but inside the map bounds, first on the floors beside the
  view (within 160 px of its sides and 48 px of its height), so the crowd walks in from the screen edges; preferring
  points whose way to the player is no longer than the walk in from 160 px beyond the view's side
  (`spawn.prefer_route`; a platform above qualifies near the end that drops next to the player), then any point that
  can reach the player; never within 200 px of the player, never where a wall crossing a platform stands anywhere on
  the way to the player (100010000's hill faces cross its ground). New mobs fade in (regen) over 0.3 s (tier C).
- **Relocation:** an off-screen mob that has not come closer by its own walking for 3 s (left behind by a player who
  runs off, on a way that keeps getting longer, or stopped at a wall; the player walking up to it does not count),
  that is 1300 px away, or that cannot reach the player is moved silently to a fresh spawn point ahead of the player
  (on the side it is moving toward), keeping its HP; it fades in there like a new mob. Never a mob on screen (it must be
  80 px outside the view, since the camera can lag on either side), never an elite; a mob standing still on screen
  (at a wall) keeps counting and is moved as soon as it leaves the screen. The player can still climb away for a
  while: the mobs below stay where they are while on screen, and the swarm re-forms around the new platform as the
  off-screen ones are moved.
- **Contact:** touching a mob with `bodyAttack=1` deals touch damage (section 6), unless the player is invincible.
- **Hit reaction:** only a hit reaching the monster's canonical `pushed` value plays `hit1`, stuns for 0.24 s and
  pushes it 12 px away from the source (tier C timings/distance, tier A threshold). Weaker hits leave its movement
  and animation state unchanged.
- **Flyers:** mobs with a `fly` stance steer directly toward the player through footholds, walls and ceilings,
  inside the map bounds. Speed = (`flySpeed` + 100) × `mob_speed_factor` × the stage speed multiplier (tier C
  conversion, canonical `flySpeed` unchanged). A 2 px bob over 1.2 s (`balance.mob_motion`) is independent of the
  pursuit and never accumulates drift. Flyers fade in before moving or hurting the player and spawn at off-screen
  air points without needing a floor or a route. They use their own canonical contact attack, never ranged attacks,
  and their canonical HP receives the same stage HP multiplier as ground mobs. `fly`, `hit1`, and `die1` use the
  original WZ frames; dying flyers stay in the air until their animation ends.
  Henesys Hunting Ground I adds PQ Stirge 9300063 (Lv 6) at 3:00, Flyeye 9300062 (Lv 8) at 5:00, Goblin Fire 9300064
  (Lv 11) at 8:00, and regular Stirge 2300100 (Lv 20) at 11:00, each at weight 1; earlier flyers remain in the pool.
  The added arrival keyframes interpolate the existing pacing values. The Tree That Grew I has no flyers.
- **Death:** `die1` plays with its WZ delays and alpha fades (`a0/a1`), the death sound plays, and the mob drops EXP.
- **Elites:** periodically one mob of the current pool spawns with ×8 HP, ×5 EXP and an explicit ×1.5 mitigated
  hit multiplier (`elites.damage_mult`), drawn with a name tag. All three multipliers are survivor data (tier C).

### Monster statuses and elements (#54)

`MobSwarm.apply_status(slot, status, params, events)` is the shared sim entry point for sibling skills. `status`
is `slow`, `poison` or `freeze` (`MobSwarm.STATUS_NAMES`); parameters contain the canonical `time` in seconds, signed
`x` for Slow, or the applying canonical skill `level` for poison (plus an optional survivor `skill` key for damage
events), and optionally the applying skill's canonical `element`. Each status is a row of one packed per-slot status
table, refreshes without stacking, and clears on death, release or relocation. Application and natural expiry emit
`mob_status_applied` / `mob_status_expired`. Removal clears silently. A rejected status emits nothing.

- Slow uses `(100 + x) / 100` of walking/flying pursuit speed: canonical x -40 means 40% slower; a positive x is
  clamped away (tier C). Ballistic jump/drop trajectories retain the navigation graph's physics. Refreshing is the #54
  Survivor policy; the original Slow text also describes a consecutive-use limit that this interface does not impose.
- Poison snapshots `min(32767, ceil(slot max HP / (70 - canonical skill level)))` damage per second, first at 1 s,
  with a final pulse when due exactly at expiry. Reapplication restarts the pulse clock and duration. HP never drops
  below 1; pulses do not stun or push. Actual lost HP contributes to player damage, and the eventual ordinary final
  hit awards the normal kill/EXP. This is a **tier C v83 server-reference fallback**, not verified v83 client RE.
- Freeze holds walking, facing, state/animation clocks and the monster attack/skill gate until expiry. Nonlethal
  hits do not restart frozen art or stun/push; lethal hits start the normal death animation. Movement/new-attack/
  new-skill suppression has **tier B evidence from a later v95 client reconstruction**, extrapolated to v83. Owner
  choices (**tier C**): a frozen monster deals **no touch damage**, a monster frozen mid-air still falls straight down
  and lands, and a fading-in monster keeps fading in.
- **Bosses reject every status**: scheduled bosses (`steady`) and canonical `info/boss` monsters refuse Slow, Poison
  and Freeze, matching the inspected v83 server reference (**tier C**, Cosmic `Monster.applyStatus` boss gate; owner
  decision replacing #54's boss-poison permission).
- **Elemental status immunity**: a status fails on a monster whose Mob.wz digit for its element is 1 (immune), 2
  (strong) or 4 (neutral), as in the same reference (**tier C**; digit 4 still takes ×1 hit damage). Poison
  carries `S` and Freeze `I` (Poison Breath `elemAttr=s`, Cold Beam `i`, tier A); Slow is elementless. An applying
  skill may pass its own canonical `element` instead. Weak and unlisted elements accept the status.
- Player skill hits read Skill.wz `elemAttr`, case-insensitively match the target's parsed Mob.wz letter/digit pairs,
  and apply immune 1 → ×0, strong 2 → ×0.5, weak 3 → ×1.5 before final rounding. Unlisted/elementless hits are neutral.
  Instant and projectile impacts share this resolution; immune hits display zero and cannot stun/push. `MobKind.undead`
  exposes the original flag for skill code; it does not imply an automatic element weakness.

Presentation reads the status table. Slow plays its cached 2101003/mob animation once and retains an amber tint;
Poison loops cached 2101005/mob. Cold Beam has no persistent mob overlay, so Freeze uses a cyan tint. A violet
poison tint is the fallback when its cached cue is absent. Anchors and tints are tier C; original art/timings are A.
The formulas, source limitations, pinned citations and the performance/visual validation record are in
[the status research](research/monster-status-effects.md). The applying Slow/Poison Breath/Cold Beam skill
implementations remain sibling work.

### 4.1 Pacing (`stages.json`)

The director keeps spawning until `alive >= max_alive(t)`, at `spawn_rate(t)` mobs/s, choosing from the pool active at
time t by weight. Values interpolate linearly between keyframes. Henesys Hunting Ground I (104040000) uses
the coarse #30 C46 stage data (2026-10-15). It preserves the spec #29
tuning waits for the dedicated balance pass (section 4.2).
for now; balance will be revisited after more features (section 4.2).

| Time | Rate (mobs/s) | Max alive | Pool additions | HP × | Speed × | Normal HP chance | Normal MP chance |
|---|---|---|---|---|---|---|---|
| 0:00 | 0.15 | 3 | Snail 4, Blue Snail 3 | 1 | 1 | 8% | 10% |
| 2:00 | 0.4 | 8 | Red Snail, Shroom | 1 | 1 | 5% | 10% |
| 3:00 | 0.6 | 12 | PQ Stirge | 1 | 1.025 | 4% | 10% |
| 4:00 | 1 | 20 | Slime | 1 | 1.05 | 3% | 10% |
| 5:00 | 2.5 | 50 | Flyeye | 1.25 | 1.075 | 1.2% | 10% |
| 6:00 | 4.5 | 85 | Pig, Orange Mushroom | 1.75 | 1.1 | 0.8% | 10% |
| 8:00 | 8.2667 | 143.3333 | Goblin Fire | 3.84 | 1.1533 | 0.8% | 10% |
| 9:00 | 9.4 | 165 | Green Mushroom | 3.9 | 1.18 | 0.7% | 10% |
| 11:00 | 12.1333 | 215 | Stirge | 4.7 | 1.2467 | 0.7% | 10% |
| 12:00 | 13.5 | 240 | full pool | 6.375 | 1.28 | 0.805% | 4% |
| 13:00 | 15.6667 | 270 | full pool | 7.6875 | 1.32 | 1.035% | 4% |
| 15:00 | 20 | 330 | final boss | 8.25 | 1.4 | 1.2075% | 4% |

The Beginner phase is sword-paced: a v83 Beginner (5 MP, one Three Snails shell at canonical 3 MP) kills mostly with
the basic attack, so until 4:00 only a few mobs are alive, ordinary HP drops are generous (8% falling to 3%), no
elite appears before 4:00 and no burst before 5:00, and ordinary kills pay 2.5x EXP so Magician arrives near 4:40.
Density and HP then ramp from 5:00 into the calibrated mid/late curve. Canonical mob HP and skill damage/costs remain
unchanged. Tree stage data are unchanged.

The changed 8:00 HP endpoint interpolates from the unchanged 6:00 point. MP stays 10% through 11:00,
then interpolates to 4% at 12:00; the extra late HP support also begins after 11:00. Both potion curves hold
after 15:00, independent of the spawn ramp. Ordinary/elite HP continues after 15:00 at
0.25 × (8.25−7.6875)/120 = 0.001171875 per second; other pacing fields retain their existing quarter-slope
extrapolation. Global normal MP 10% remains the fallback, elite MP stays 60%, and elite HP/boss bundles are
unchanged. Stage EXP remains a constant 2.5; the rejected optional EXP-keyframe experiment is removed.

The earlier difficulty overhaul removed the time-based touch-damage column and the hidden 0.55 attack scale. Section 6.2
defines current monster damage. The tuning history below and section 4.2 describe the former damage model;
the overhaul's tuning and independent acceptance results are recorded separately below. The older tables remain
historical evidence, including the removed Hill stage; they do not describe the current hit model.

Two levers do different jobs: `max_alive` is the crowd a struggling player faces (the cap binds when kills fall
behind), `rate` is what pressures a strong build (it only matters while the player kills faster than the cap refills),
so a strong build still ends up surrounded by 200-300 mobs late in the run. The first 2026-10-14 pass lowered
`max_alive` at 4:00-9:00 (weak builds were overrun there; strong builds never meet the cap) and raised the early
`rate`. The swarm pass (section 4 Pursuit / Spawning / Relocation) made the crowd actually reach the player: mobs
that used to idle on far platforms or trail a running player now arrive and die, so the same numbers gave a thin
mid-game crowd and fast levels, and the crowd that did gather hit far more often. So it raised the mid/late HP
(x1.3) and the 6:00-12:00 rate a little (mobs live long enough near the player to form a crowd), lowered the early rate
(Lv 8 stays at ~2:40) and halved touch damage over the whole run (after 8:00 the kiting bot now takes ~120 touches
instead of ~20; with the old damage most runs died). That left Lv 30 at ~11:15, before the ~12:00-15:00 target, so the
follow-up made the EXP curve steeper (section 5; Lv 30 needs 22% more EXP, Lv 8 4% more) and, because a build that
levels slower is weaker against the same crowd (the steeper curve alone killed 45 of 48 tuning runs), took touch
damage down to 0.7 of the swarm pass's values (0.35 of the original 1.0-1.5). The pool also sets the EXP income: the 6:00 pool's Pigs and
Orange Mushrooms give 15 EXP against 8 for a Red Snail, and a variant that kept the older mobs longer to spare weak
builds starved the strong ones of levels (14 of 24 tuned-bot runs died instead of 3), so change pools and the EXP
curve together. Bursts every 90 s spawn a ring of 10-40 mobs around the view (growing over the stage). The roster
deliberately goes beyond the map's own `life` list (Snail, Slime and Orange Mushroom are the classic trio); the
original spawn list is shown in the stage info. Stage select offers Henesys Hunting Ground I and The Tree That Grew I.
The Hill East of Henesys was removed in the difficulty overhaul because its gameplay was too similar to Henesys
Hunting Ground I. Its map and unused Ribbon Pig assets are no longer selected for import; old save records for
retired stages are ignored.

The Tree That Grew I retains its own ground-only pool: Snails until 2:00, then the existing Slimes and mushrooms.
Its ordinary kills yield 0.90x EXP, and it uses the same rate/crowd caps with HP multipliers 0.8/1.0/1.5 at 2/4/6 minutes, then
3.25/4.25/6.875 at 9/12/15 minutes. The early HP curve supports weak builds without changing canonical
monster HP or redesigning the roster. It has no flyers, and its portals connect the playable branches.

### 4.1.1 New-system measurements

The balance harness records completed boss spawn-to-death times per encounter, HP/MP potion collection and use,
MP-short waiting seconds, and whole boss-hit damage divided by max HP at the hit (before Magic Guard's split).
Aggregates report completed fight samples separately from unfinished, unspawned or skipped encounters, print the
completed/spawned count beside each median and a censored median over all spawned fights (an unfinished fight counts
as at least its elapsed seconds; `>=` marks a lower bound), and retain the boss-hit source kind. A cap ends the measurement as TIMEOUT; reaching 15:00 alone cannot clear a run.
The per-policy `SYSTEMS` report also divides total MP potions collected by total MP potions used (not a mean of
per-run ratios). `mp_collected_used_ratio` is JSON null, printed as `undefined (no MP used)`, when use totals zero.

The #42 harness also reports `ordinary_kill_hits_by_min` for the first five run minutes: each bucket contains
landed lifetime damage-line hits, ordinary kills and their ratio (null without kills). The death minute receives
all hits on that mob, including earlier-minute hits; a death exactly on a minute boundary belongs to the preceding
minute. Relocation preserves a lifetime's count and fresh slot reuse resets it. Elites, scheduled bosses and
canonical boss kinds are excluded; ordinary summons/offspring are included. Magic Claw counts each landed line,
basic attacks count, and immune contacts do not. Aggregation divides summed hits by summed kills.
`late_mp_short_seconds` measures ticks after 8:00 when an eligible ready skill fails affordability during the cast
scan; a later affordable skill or basic attack may still act. `late_observed_seconds` and reached/waiting run counts
distinguish unobserved late time from observed zero shortage. Final `potions_left` includes starting stock,
recorded separately in `potions_start`; collection totals exclude starters. `outcomes` keeps timeouts separate
from clears and deaths, and `death_seconds` samples deaths alone. Run records retain simulation warnings.
Boss diagnostic snapshots use JSON null for an unobserved/nonfinite `best_distance`; the live simulation retains
its infinity sentinel. The report reader normalizes that field in preserved legacy `1e99999` records before parsing,
logs every normalization and leaves raw files and measured values unchanged.

Since the buff-timeline diagnostic, `buff_casts` also records each observed cast tick, skill ID, canonical level,
duration and active effect stat/value. This exposes the real cast snapshot, unlike a final rank or an absorbed
hit fraction (which available MP may clip). It changes no gameplay or RNG. Old records without the field cannot
prove zero casts. It supports diagnosis; aggregate Guard coverage and offensive cast counts remain unrecorded.
The legacy `cards_taken` prefix is the queued level at `progression.front()`, not the character level or a bonus
flag. A bonus pick can carry a positive prefix while normal levels are queued; −1 is not an exhaustive bonus
marker. These strings cannot isolate normal-choice timing or replace the actual cast snapshots.
Three harness-only camper policies use sensible cards and potions, then park after a normal 60 s warmup:
Henesys highest platform, Henesys ground rope, and Tree's highest playable branch reached through the real
up00/up01/up02 chain. Henesys placement is a one-time controlled setup; Tree uses movement inputs. Arrival
success and portal use are recorded, and displaced campers are not placed back. The 60 s warmup, placement
choice and navigation cost/jump tolerance are tier C measurement policy, not MapleStory facts or gameplay tuning.
CLI, record fields, aggregate semantics and seed separation are documented in AGENTS.md. Ticket #26 adds the
core measurements without changing balance data; #27 adds the cast snapshot trace. Training and held-out results
remain separate.

Issue #37's initial MP scarcity pass uses normal/elite MP chances 2%/30% and boss MP bundles of 3,
with HP supply unchanged (tier C). Before integrating the subsequent #48/#49/#50 changes, HG training seeds 1..12
showed sensible collected/used falling from
1.917 to 1.064 and median leftover from 85 to 0; random falls from 2.275 to 1.034, with median leftover
59.5 to 0. Sensible clears fall from 4/12 to 0/12; random remains 0/12. Median MP-short seconds become
116.884 (sensible) and 54.367 (random), from zero. This overshoots the 1.2-1.5 target; final calibration
belongs to the balance pass. No held-out seeds were run. Configuration and exact training output:
[issue37-mp-drops.md](research/issue37-mp-drops.md).

Spec #29 replaces #1/#27's “most runs clear” target (including the historical 22/30 result) with **40–50% sensible
clears and 5–15% careless clears** in Henesys. Death-only median time should fall between the first and third boss
arrivals, **300–900 s**. Sensible MP collection/use should be **1.2–1.5**, with final stock far below the former 117;
careless runs must actually observe some MP waiting after 8:00. First-five-minute ordinary lifetime hits/kill and
their denominators report whether early durability is meaningful; mid-game mobs should typically need 2–3 hits.

The full-run regression uses predetermined training seeds 1/2/2026 on both stages, separate from population
acceptance. Henesys retains Mage/Lv10 median **180–330 s**, individual 150–360 s. The coarse owner-review pass
(sword-paced v83 Beginner, 2.5x stage EXP) moves Lv30 to median 540–720 s when reached, individual 480–1080 s, and
Lv8 to median 210–270 s, individual 180–300 s; Lv30 near 10:00 is earlier than the original 12:00–15:00 aspiration; the owner accepts the current
progression for now and will revisit it after more features. The regression windows remain unchanged. At least one of the three regression runs must reach Lv30 under the 40–50% clear target.
These windows apply only to reached milestones, with at least two of the three fixed runs reaching
Lv8/Lv10/Magician and every reach count printed. Occasional early deaths remain valid outcomes under the new population target; they are never filtered.
Spawning each minute (including after 15:00), crowd growth, EXP/kill/event consistency, all-boss finale, no lost mobs,
the inherited 30% engagement floor and late 200+ density remain active in Henesys. Runs observed for at least a full
minute after 8:00 must include at least five ordinary nonmiss hits; boss hits and misses cannot satisfy that check.

Tree outcomes and clear rate are recorded without judging pacing or difficulty. Its regression still checks
required cache data, no simulation warnings, EXP/kill/level event consistency, no lost mobs, correct deaths and
all scheduled bosses dead before a clear. A living Tree run at the cap is a timeout, never a clear. Earlier Tree
pacing tables and guards below are historical information. Freeze candidate data and guards before the full suite
and any fresh held-out assessment. **601–630 is consumed** by #30's frozen assessment below. Reserve fresh
**701–730** for the dedicated balance pass after its data and guards freeze. Spent or retired
101–130/201–212/301–330/401–430/501–530/601–630 are never reused for tuning or fresh evidence.

### 4.2 Tuning record (`scripts/balance.sh`)

Pacing is measured with `bash scripts/balance.sh [seeds | a..b] [--policy=...]` (whole headless runs on the real map,
`game/tools/balance_run.gd`). Movement is always the autoplay bot (`BotInput`): it kites on the ground (dueling a
lone ordinary mob with the basic attack while no attack skill can fire), walks to EXP drops and climbs a ladder or
rope to drops left on a platform above, and picks a seeded-random available branch (override with `--branch=210|220|230`). Card
policies: `bot` uses `BotInput.pick_card_for`, prioritizing eligible potion tiers, then Guard learning/ranks through
survivor score overrides, then the existing attack, shot, damage, pierce and defence scores; `random` is a careless player who
takes a random card of the three (the old `--first-card` policy is no longer a careless proxy: it always takes the
guaranteed card, which UpgradePool puts first). `--idle-after=300` takes the hands off the keys at 5:00.

#### #31 / #61 second-job QA (2026-10-15)

Report only on integration `34c04e1`: `ISOLATE=t61 bash scripts/balance.sh 1 2 2026`, forced branches
210/220/230, both stages and bot/random, rarity active, real cache, 800x600, 1,800 s cap, no patches/tuning.
All 36 runs finish without crashes, script errors or world warnings. Per-seed records, exact console output,
systems reports and screenshots remain ignored under `evidence/spec31_qa/<branch>/`. Detailed milestones,
completed/censored boss durations and counts, potions, MP waits and cards by job/tier are in the draft
`research/spec31/qa-61.md`; the separate follow-up draft is `qa-61-defects.md` (external spec31 research folder).

| Henesys branch / policy | Clear / dead / timeout | Death seconds (seed order) | Lv at 15:00 (observed n) | HP collected/used; MP collected/used | MP-short seconds, mean/run |
|---|---|---|---|---|---|
| 210 bot | 0 / 3 / 0 | 949.7, 812.3, 322.7 | 35 (n=1) | 58/73; 360/360 | 260.5 |
| 210 random | 1 / 2 / 0 | 714.8, 329.0 | 43 (n=1) | 79/81; 435/335 | 178.5 |
| 220 bot | 0 / 3 / 0 | 926.5, 812.3, 322.7 | 35 (n=1) | 57/72; 359/359 | 252.6 |
| 220 random | 1 / 2 / 0 | 714.8, 329.0 | 42 (n=1) | 80/83; 433/310 | 178.5 |
| 230 bot | 0 / 3 / 0 | 920.2, 812.3, 322.7 | 35 (n=1) | 57/72; 363/363 | 246.1 |
| 230 random | 1 / 2 / 0 | 714.8, 329.0 | 42 (n=1) | 80/83; 428/300 | 178.5 |

Henesys reaches Magician/Mano in 3/3 per group. Lv10: bot 270.6–283.2 s, random 263.2–278.3 s (n=3);
only seed 1 reaches Lv30, at 614.9 / 557.8 s (n=1). Completed Mano medians: 37.55 / 33.69 s (2/3 spawned;
censored >=27.62 / >=29.00 s, n=3). Final boss: bot none (0/1 spawned each); random 37.70/103.35/74.55 s
for 210/220/230 (1/1 spawned each). Earlier deaths and missing 15:00 samples are not zero observations.

| Tree branch / policy | Clear / dead / timeout | Death seconds (seed order) | Lv at 15:00 (observed n) | HP collected/used; MP collected/used | MP-short seconds, mean/run |
|---|---|---|---|---|---|
| 210 bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 210 random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 220 bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 220 random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 230 bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 230 random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |

Tree matches the prior smoke: no Magician/Lv10/Lv30 reaches or bosses (completed durations none, n=0).
Henesys picked tiers N/R/E/U/L, branch order: bot 60/16/0/1/0, 62/14/0/1/0, 61/15/0/1/0; random
60/21/6/0/0, 59/21/6/0/0, 59/21/6/0/0. Tree: 4/1/0/0/0 per group. Counts mean picks, not rank steps.

**Teleport MP starvation:** seed-1 bots learn rank-1 Teleport at 614.93 s and use it 257/263/298 times;
MP-short totals are 310.733/286.950/267.550 s, with 49.6%/45.7%/40.3% of post-learning ticks short.
Non-learners (seeds 2/2026) use zero and wait 276.450/194.383 s over shorter lives. Observer-only replays
exactly match the official seed-1 outcomes/cards/skills/milestones/potions/fights. Separate matched diagnostics
suppress only Teleport input: F/P/Cleric clear at 989.4/971.9 s with zero post-learning MP shortage; I/L dies
later at 1163.8 s with fewer shortages. These are diagnostic policies, not extra smoke observations or tuning.
The #60 bot-clear drift persists (0/3 per branch versus earlier 1/3); autoplay MP use is a drafted follow-up.

**Owner stop-and-ask gate:** no Henesys branch dies entirely before its first boss or clears untouched.
Tree's all-before-first-boss pattern is present in all 18 runs, but unchanged, before second job, and remains
AGENTS.md's explicit record-only owner rework; flagged in the draft comment. No new feature-induced gate.
Close probes check every branch skill, real advancement cards, stacked buffs, Teleport endpoints/grey X icon,
and all 15 HUD icons fitting two rows at 800x600; all report `missing: []`. No confirmed blocking defect.
All configured Use sounds load; audible identity/mix needs human listening, so audio acceptance is unverified.
Full isolated suite: **656 tests, 0 failed, 0 skipped, 71 files** (299.020 s); real-cache tests execute.
Normal seed-1 playtests (`--warp=540 --speed=8 --window-autopick=1`, 18-minute absolute cap) reach real
advancement windows and die at 949.733/926.483/920.233 s (210/220/230), Lv35 each, all `missing: []`;
checked advancement cards, the final-boss/MP views and final tombstones under each branch’s `playtest/`.

**After the bot Teleport rule fix (#60 follow-up, 2026-10-15):** one Henesys-only 18-run smoke on `574da80`,
`ISOLATE=bott bash scripts/balance.sh 1 2 2026 --stage=henesys_hg1 --branch=<210|220|230> --policy=<bot|random>`,
real cache, rarity active, 1,800 s cap, no PATCH. The reserve (max of 25% max MP and two most-expensive learned
auto-attack costs), 5 s interval and tighter same-height emergency rule were chosen and committed before measurement;
no values were iterated. Player Teleport, costs and all game data are unchanged. Tree was excluded by the follow-up
brief because no smoke run reaches second job there. Records, exact console output and systems summaries remain
ignored under `evidence/bot_teleport/<branch>/<policy>/`; `teleports` counts successful arrival events, once per blink.

Below, before is QA #61 above; lists use seed order 1/2/2026. C = clear (time shown for new bot clears), other end
times are deaths; no timeouts. MP-short is the whole-run mean, so different lifetimes remain a comparison limit.

| Henesys branch / policy | Clear/dead before -> after | End seconds before -> after | MP-short seconds, mean/run before -> after | Teleports before -> after |
|---|---|---|---|---|
| 210 bot | 0/3 -> 1/2 | 949.7/812.3/322.7 -> C930.1/812.3/322.7 | 260.5 -> 205.1 | 257/0/0 -> 58/0/0 |
| 210 random | 1/2 -> 1/2 | C/714.8/329.0 -> C/714.8/329.0 | 178.5 -> 178.5 | unmeasured -> 0/0/0 |
| 220 bot | 0/3 -> 0/3 | 926.5/812.3/322.7 -> 1081.9/812.3/322.7 | 252.6 -> 231.5 | 263/0/0 -> 68/0/0 |
| 220 random | 1/2 -> 1/2 | C/714.8/329.0 -> C/714.8/329.0 | 178.5 -> 178.5 | unmeasured -> 0/0/0 |
| 230 bot | 0/3 -> 1/2 | 920.2/812.3/322.7 -> C967.8/812.3/322.7 | 246.1 -> 205.1 | 298/0/0 -> 66/0/0 |
| 230 random | 1/2 -> 1/2 | C/714.8/329.0 -> C/714.8/329.0 | 178.5 -> 178.5 | unmeasured -> 0/0/0 |

Bot seed-1 MP-short totals: 310.733/286.950/267.550 -> 144.567/223.583/144.567 s (branch order 210/220/230).
Bot seeds 2/2026 remain 276.450/194.383 s; all random groups remain 155.733/179.050/200.583 s in seed order
(QA's rounded 155.7/179.1/200.6). Random seed-1 clears occur at 937.7/1003.4/974.6 s by branch.
All 18 runs reach Magician and spawn Mano, all clears have every scheduled boss dead, and none clears untouched.
No crashes, script errors or world warnings; no new stop gate. The bot still uses Teleport, with far fewer blinks
and less total MP wait on the three learners; I/L still dies. This is fixed-seed regression evidence, not balance
tuning. Pre-merge isolated suite: **661 tests, 0 failed, 0 skipped, 72 files**; real-cache tests execute.
After merging integration `84d1782` (review-fix ownership refactors; both records preserved), the full
`ISOLATE=bott bash scripts/test.sh` suite passes **663 tests, 0 failed, 0 skipped, 72 files**. The smoke above
remains the single measurement on `574da80`; no additional smoke or outcome-driven changes followed the merge.

#### Spec #31 review-fix equivalence (2026-10-15)

Behaviour-preserving ownership refactors, baseline `34c04e1`: Slow history/admission/application and relocation
live in MobSwarm; box/nearest instant casts share their capped line resolver; MP Eater reads `absorb_mp` definitions
in learned order (section 7). No tuning. Ran `ISOLATE=rfix bash scripts/balance.sh 1 2 2026
--stage=henesys_hg1 --policy=bot --branch=<210|220|230>` before and after, with separate absolute `BALANCE_OUT`
directories under `_scratch/spec31-review-fixes/{before,after}/<branch>`. All nine complete JSON records were
byte-identical, including outcomes, end times, levels, kills and every boss spawn/death/duration/elapsed field;
no crashes or world warnings. Values below are identical before/after: outcome / end seconds / level / kills.

| Forced branch | Seed 1 | Seed 2 | Seed 2026 |
|---|---|---|---|
| 210 | DEAD / 949.7 / 35 / 2204 | DEAD / 812.3 / 28 / 1399 | DEAD / 322.7 / 10 / 153 |
| 220 | DEAD / 926.5 / 35 / 2138 | DEAD / 812.3 / 28 / 1399 | DEAD / 322.7 / 10 / 153 |
| 230 | DEAD / 920.2 / 35 / 2220 | DEAD / 812.3 / 28 / 1399 | DEAD / 322.7 / 10 / 153 |

Only seed 1 reaches the forced second job; seeds 2/2026 end as Magician. These card picks do not learn Slow or
MP Eater. Focused seeded support/skill-foundation/MP Eater tests cover Slow's consecutive-use history across
relocation and fresh spawns, lethal-line hit order/RNG, and live-rank absorption with configured fields/learned
order: 43 passed, 0 failed, 0 SKIP. The full `ISOLATE=rfix bash scripts/test.sh` suite passed: 658 passed,
0 failed, 0 SKIP across 71 files. Raw records/logs and the field-by-field comparison remain in ignored scratch.

#### #30 / #45: rarity tiers, coarse C46 stage data (2026-10-15)

Rarity tiers were calibrated on training seeds 1–60 and 2026 to the C46 profile: card weights 86/8/3.5/1.7/0.8,
the older 1/1/2/3/max stacking and 1/1/2/3/5 new-skill ladders, and the Henesys late HP multipliers, HP support and
ordinary MP taper in the 4.1 table. The owner accepted that state for the current features, then restored the spec
weights **75/18/5/1.7/0.3** and a ladder in which every tier gives more than the one below (section 8.1). The stage
data stays C46 and is **not re-tuned** for those changes: feature tickets now run a regression smoke only, and tuning
waits for the dedicated balance pass (AGENTS.md "Balance"). The C46 figures below therefore describe the measured
C46 weights, not the shipped odds.

| C46 (86/8/3.5/1.7/0.8 weights) | Sensible clears | Sensible death median | Careless clears | MP collected / used |
|---|---|---|---|---|
| Training 1–60 + 2026 | 32/61 (52.46%) | 902.3 s (29 deaths) | 4/61 (6.56%) | 1.21 sensible / 1.25 careless |
| Held-out 601–630 (consumed) | 19/30 (63.33%) | 943 s (11 deaths) | 4/30 (13.33%) | 1.30 sensible / 1.36 careless |

Sensible clears exceed the 40–50% band (slightly in training, clearly held out); the careless late MP-wait requirement was observed in 7/41 training
and 0/16 held-out runs. These are known deviations for the balance pass. A short summary of the C46 search and how
to reproduce it is in [research/spec30-rarity-balance.md](research/spec30-rarity-balance.md).

Regression smoke after the owner's changes (spec odds, new ladder, untouched C46 stage data), 2026-10-15, seeds
1/2/2026, compared with the same seeds on the C46 PR head. No crashes or world warnings. Full suite on the final head: 571 tests, 0 failed, 0 skipped.

| Stage / policy | Clears (now) | Deaths (now) | Clears (C46) | Deaths (C46) |
|---|---|---|---|---|
| Henesys sensible | 1/3 | 5:28, 15:31 | 1/3 | 12:36, 15:36 |
| Henesys careless | 2/3 | 12:25 | 0/3 | 10:28, 12:03, 12:19 |
| Tree, either policy | 0/3 | 1:17, 2:21, 2:21 | 0/3 | 1:17, 2:10, 2:21 |

Henesys still reaches Magician at 4:23–4:43 and Lv 30 near 9–10:30; MP collected/used 1.17 sensible, 1.40 careless.
Tiers offered (Normal/Rare/Epic/Unique/Legendary) over three runs: sensible 182/63/12/1/0, careless 289/72/9/3/2.
Careless play is easier than under C46, as expected from the restored odds; this is input for the balance pass,
not a tuning target. Tree deaths before 2:30 are unchanged from C46 (Tree awaits the owner's rework).

#### #31 / #58 support regression smoke (2026-10-15)

`ISOLATE=t58 bash scripts/balance.sh 1 2 2026`, both stages and `bot`/`random`, real cache, unforced branches,
1,800 s cap, no patches/tuning. All 12 runs finish without crashes, script errors or world warnings. Outcomes and
death times match #56 below; Henesys reaches Magician and spawns its first boss in all six runs. Tree is unchanged
and record-only. Raw records and exact console output are ignored under `_scratch/t58-balance/` and
`_scratch/t58-balance-*.log`. The full second-job branch smoke remains #61's responsibility.

| #58 stage / policy | Clear / dead / timeout | Death seconds | MP collected / used | Mean MP-wait seconds/run |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 376 / 317 (1.186) | 205.1 |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 425 / 269 (1.580) | 178.5 |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7 / 0 (undefined) | 99.0 |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7 / 0 (undefined) | 99.0 |

Visible seed-1 playtests on branches 210/220/230 use `--warp=840 --speed=8 --minutes=16`, saved under
`evidence/t58/branch_<id>/`; all report `missing: []` and remain PLAYING at the cap (no clear claimed).
Checked by eye: `branch_210/t890.png` (late-game rendering), `branch_230/t950.png` (Invincible buff row).
Temporary real-cache RunScene probes learn only this ticket's support skills at rank 20. Inspected
`focus_210/support_8.png` and `focus_220/support_25.png` show Meditation's icon/cast art; each probe records six
slowed mobs at speed factor 0.6. Closer `close_210/support_115.png` and `close_220/support_100.png` show Slow's
white monster rings without damage numbers; `focus_230/support_25.png` shows Bless and Invincible icons with
separate timers and canonical cast art. Probe summaries also report `missing: []`. No cache nodes are missing.
`evidence/t58/cards/cards.png` was checked for readable, fitting Bless/Invincible/Slow rank previews and the
accuracy-without-combat-effect label. After merging integration at `f8af37b`, the full isolated suite passes
**610 tests, 0 failed, 0 skipped, 67 files** (300.672 s); the real-cache tests execute. Focused support,
advancement and data checks pass **36 tests, 0 failed, 0 skipped**. No held-out seeds or tuning were used.

#### #60 Teleport regression smoke (2026-10-15)

No tuning: ISOLATE=t60, training seeds 1/2/2026, both stages and bot/random, 800 x 600, 1,800 s cap,
unforced branches, no patch. All 12 records completed without crashes, script errors or world warnings. Henesys
reaches Magician and spawns Mano in 3/3 for each policy. Compared with Foundations, sensible clears fall 1/3 to 0/3
(seed 1 now dies at 955.3 s with Cleric Teleport rank 13); random remains 1/3. Earlier deaths and Tree outcomes
are unchanged. This is feature drift for #61, not a tuning pass; no held-out seeds were used.

| Stage / policy (3 runs each) | Clear / dead / timeout | Death seconds | Magician reaches | MP collected / used | MP-wait median (n=3) |
|---|---|---|---|---|---|
| Henesys bot | 0 / 3 / 0 | 955.3, 812.3, 322.7 | 3/3 | 365/365 (1.000) | 225.200 s |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 3/3 | 419/419 (1.000) | 179.050 s |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 | 7/0 (undefined) | 117.217 s |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 | 7/0 (undefined) | 117.217 s |

Raw records and regenerated absolute-path systems reports: ignored _scratch/t60_balance/; console output:
_scratch/t60-smoke-*.log. The initial relative BALANCE_OUT reached all runs but the supplemental reporter could
not locate those paths from its project directory; reports were regenerated from the same records, without reruns.
The branch-210 seed-1 playtest (warp 480, speed 8, cap 780 s) reaches Lv35, remains PLAYING, and reports missing: [].
Its inspected evidence/t60/playtest_fp_seed1/t780.png shows the late run; this bot did not learn Teleport.
The close driver learns Teleport through its card and injects X. Inspected evidence/t60/close_fp/teleport.png
and teleport_no_mp.png show the X icon and affordability tint. Its missing list contains only
Effect.wz/BasicEff.img/Teleport: that canonical subtree is absent from the shared cache. The manifest now requests
it, but #60 did not run the prohibited import. The effect-frame test explicitly SKIPs while this prerequisite is
missing; that SKIP does not verify the effect. Canonical effect visual acceptance remains unverified pending import.
This smoke was recorded before the #56 merge; its unforced second advancements are Cleric, so it does not assess
I/L branch pacing. After merging #56 and preserving both sets of fixtures/data, the final full suite reports
**612 tests: 611 passed, 0 failed, 1 skipped (67 files)**. The only SKIP is
`test_teleport::test_real_cache_teleport_effect_frames`, for that missing canonical art. Final log:
`_scratch/t60-full-merged-final.log`; focused Teleport/advancement/I-L/data checks: 48 tests, 0 failed, 1 same SKIP.

**#60 effect-import follow-up (2026-10-15):** the owner authorized one import. A fresh original-v83
dump confirms `Effect.wz/BasicEff.img/Teleport`, four 80 ms frames (tier A; dimensions/origins recorded
in `docs/research/wz-inventory.md` section 7). The ticket manifest already selected that subtree.
The incremental import reports 84 imgs: 1 written, 83 up to date; 10,800 canvases (+4), 87 pages,
131 sounds, 112,434,965 bytes; 0 warnings, errors or unresolved UOLs. All 84 prior img entries and
prior BasicEff subtrees remain present; only `Teleport` was added. Of 319 prior cache files, only
BasicEff JSON/atlas and cache.json changed; none were removed. Evidence: `evidence/t60/import.log`
and `cache-*-comparison.json`.

The close real-map driver learns `teleport_fp` through its card and injects X: departure
(1200, 37.6531), arrival (1330, 95). Inspected `evidence/t60/close_fp_imported/teleport.png` shows
both blue endpoint effects and the X skill label; `teleport_no_mp.png` shows the grey unaffordable
icon at 0 MP. Its summary reports `missing: []`, resolving the earlier visual-acceptance gap.
The additional normal autoplay playtest (Henesys, seed 1, branch 230, warp 930, speed 8, cap 990 s)
ends DEAD at 955.35 s, level 36, Teleport rank 13, `missing: []`; records are in
`evidence/t60/playtest_cleric_imported/`. No gameplay or balance data changed, so the prior smoke
was not repeated. The real-cache effect test now fails rather than SKIPs when a present cache lacks
this required animation; focused Teleport checks pass 16/16, with no failures or SKIPs.
After `git merge origin/t3/issue-31-implementation` (already up to date), the full
`ISOLATE=t60 bash scripts/test.sh` passes **612/612 tests, 0 failed, 0 skipped, 67 files**
in 279.597 s. Log: `_scratch/t60-full-imported.log`.

#### #31 / #56 Ice/Lightning regression smoke (2026-10-15)

`ISOLATE=t56`, training seeds 1/2/2026, both stages and `bot`/`random`, unforced branches, real cache,
1,800 s cap, no patches or tuning. All 12 runs finish without crashes, script errors or world warnings.
Outcomes and death times match the Foundations/#53 smoke below. Henesys reaches Magician and spawns its first
boss in all six runs; Tree's early deaths remain record-only. The two second advancements in this fixed sample
choose 230, so this is an existing-run regression check; #61 owns the full second-job branch smoke.
Raw records and exact console output remain ignored under `_scratch/t56_smoke/` and `_scratch/t56_smoke_*.log`.

| #56 stage / policy | Clear / dead / timeout | Death seconds | Magician / first-boss reaches |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 3/3 / 3/3 |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 3/3 / 3/3 |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 / 0/3 |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 / 0/3 |

A separate visible Henesys run uses `--branch=220 --seed=1 --warp=480 --speed=8 --minutes=20 --shot-every=1`.
It clears at 996.567 s, Lv39, with Cold Beam and Thunder Bolt both at rank 9 and `missing: []`.
Checked by eye: `evidence/t56/branch220/t700.png` (Cold Beam's ice impact) and `t740.png` (Thunder Bolt's
lightning columns on both sides, with ice impacts also visible). Both skills' cached use sounds and art load
in the real-cache test, and the normal RunScene cast path plays those sounds; no missing cache nodes found.
After merging the current integration branch, the full suite passes **599 tests, 0 failed, 0 skipped, 66 files**
(312.975 s). Focused Ice/Lightning, advancement and data-file validation passes **32 tests, 0 failed, 0 skipped**;
the real-cache test executes, so no SKIP is counted as coverage. No shared simulation or presentation paths change.

#### #55 Fire/Poison attack regression smoke (2026-10-15)

`ISOLATE=t55 bash scripts/balance.sh 1 2 2026`, both stages and `bot`/`random`, unforced branches,
no patches or tuning: all 12 records completed with no crashes, script errors or world warnings. Outcomes,
death times and potion totals match the preceding #53/foundations smoke. Henesys reaches Magician and the first
boss in 3/3 runs per policy. Each policy's surviving seed 1 selects Cleric (230); the other seeds die before
second job, so this smoke establishes regression safety, not Fire/Poison balance. Tree remains record-only.
Exact console output and JSON records stay in ignored `_scratch/t55/balance/` and `evidence/t55/`.
After fetching/merging the integration branch (already up to date), the final full suite passes **599 tests,
0 failed, 0 skipped, 66 files**; focused F/P, data-file and upgrade checks pass **42 tests, 0 failed, 0 skipped**.
The shared synthetic book now includes a separate Poison Breath fixture; the existing pity regression exhausts
all current-job power cards instead of assuming Fire Arrow's rank cap exhausts the whole F/P attack pool.

| #55 stage / policy | Clear / dead / timeout | Death seconds | MP collected / used |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 376/315 (1.194) |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 426/268 (1.590) |
| Tree bot / random (each) | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7/0 (undefined) |

The separate forced-210 seed-1 visual run (warp 480 s, speed 8) clears at 919.933 s with Fire Arrow rank 14,
Poison Breath rank 9 and `missing: []`. `evidence/t55/playtest_210_s1/t646.png` shows Fire Arrow's projectile
and caster effect. A temporary real Flow/RunScene driver stages each attack alone against a durable stationary
mob for closer inspection; its screenshots and sound/asset counters stay in `evidence/t55/focused_visuals/`.
Checked by eye: `poison_breath_03.png` (green orb and caster effect), `poison_breath_05.png` (expanding green hit
cloud on the pig), and `fire_arrow_03.png` (caster bow/fire effect and impact). Both staged summaries have empty
missing lists and successful sound calls; the cached Use/Hit streams also decode in the focused test.
This is visual evidence only, not a balance run. The initial occluded playtest attempt produced no screenshots;
the successful run uses Godot's always-on-top window option. No importer or shared cache changes were needed.

#### Spec #31 foundations smoke

Foundations for spec #31 regression smoke (2026-10-15), `ISOLATE=found`, training seeds 1/2/2026,
both stages and `bot`/`random`, no patches/tuning, repeated after merging #53 at `a248aba`. All 12 final records
completed without crashes or world warnings; outcomes and death times match #53's smoke below. Henesys reaches
Magician in all six runs and spawns its first boss in all six; Tree's unchanged early deaths remain recorded only.
Foundations adds no second-job skill/card data. Final raw records/console output remain under ignored
`_scratch/foundations_balance_merged/`; the preliminary pre-#53 smoke in `_scratch/foundations_balance/`
matched the preceding current-odds results. Full merged suite: **592 tests, 0 failed, 0 skipped** (65 files).

| Foundations stage / policy | Clears | Deaths | Magician reaches | MP collected / used |
|---|---|---|---|---|
| Henesys bot | 1/3 | 5:22, 13:32 | 3/3 (4:30–4:43) | 376/315 (1.194) |
| Henesys random | 1/3 | 5:29, 11:54 | 3/3 (4:23–4:38) | 426/268 (1.590) |
| Tree bot / random (each) | 0/3 | 1:17, 2:21, 2:21 | 0/3 | 7/0 (undefined) |

Restoration presentation was triggered through the real Flow/RunScene with a temporary evidence driver;
`evidence/foundations/gain_numbers.png` was checked by eye (HP/MP digits, placement and stacking; missing assets
empty). Synthetic seam and cached gain-number tests: 15 tests, 0 failed, 0 skipped.
The existing all-event schema test needed one new restoration scenario (and `stat` String validation) because it
requires every `EVENT_FIELDS` entry to be exercised. Its previous assertions and scenarios are unchanged.

#### #31 / #59 MP Eater regression smoke (2026-10-15)

No tuning: `ISOLATE=t59 bash scripts/balance.sh 1 2 2026`, both stages and `bot`/`random`, real cache,
unforced seeded branches, no patch, 1,800 s cap. Feature head `24ff1be` includes Foundations `e51d6b7`;
this smoke precedes later sibling-ticket integration. All 12 runs completed without crashes, script errors or
world warnings. Outcomes and death times match the Foundations smoke: Henesys reaches Magician and the first
boss in all six runs (Magician 263.2–283.2 s). Tree remains record-only and unchanged. No held-out seeds were used.

| MP Eater stage / policy | Clear / dead / timeout | Death seconds | MP collected / used | Foundations MP collected / used |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 378/314 (1.204) | 376/315 (1.194) |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 430/214 (2.009) | 426/268 (1.590) |
| Tree bot / random (each) | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7/0 (undefined) | 7/0 (undefined) |

Each surviving Henesys seed-1 run advances to Cleric and learns MP Eater; the other seeds die before second job.
Bot seed 1 clears at 1087.7 s and random seed 1 at 998.2 s. The changed MP collection/use ratio is feature
evidence for #61 and the later balance pass, not a tuning result. Raw records and console output stay in ignored
`_scratch/t59_balance/` and `_scratch/t59-smoke-*.log`. Windowed playtests forced 210 and 230 (seed 1, warp 480,
speed 8); both have `missing=[]`. F/P clears at 995.2 s without learning MP Eater; Cleric owns rank 17 and is
still PLAYING at the 18-minute cap (not a clear). Checked-by-eye evidence: `evidence/t59/branch230/mp_eater.png`
and the focused real-hit captures `evidence/t59/focused/mp_eater_{fp,il,cleric}.png`: canonical absorb art and cyan
14-MP gain numbers for every branch, all `missing=[]`. v83 has no MP Eater sound entry; no required cache data is missing.
After merging integration `f8af37b` (I/L attacks) and retaining both tickets' data/fixtures, the final
`ISOLATE=t59 bash scripts/test.sh` passes **616 tests, 0 failed, 0 skipped** (67 files); no cache checks skipped.

#### #31 / #53 advancement regression smoke (2026-10-15)

No balance tuning. `ISOLATE=t53 bash scripts/balance.sh 1 2 2026` ran on both stages with both policies,
with the real cache, 800 x 600 view, 1,800 s cap, no patch and unforced seeded branches. No crashes, script errors
or world warnings. Henesys reaches Magician and the first boss in 3/3 for each policy; Lv30 in 1/3 for each.
Compared with the preceding current-odds smoke, sensible clears remain 1/3 and careless clears fall from 2/3 to 1/3.
Tree is record-only and unchanged. Branch 0 means no second advancement yet.

| Stage / policy | Clear / dead / timeout | Death seconds | Branch counts | Previous clears |
|---|---|---|---|---|
| Henesys sensible | 1 / 2 / 0 | 812.3, 322.7 | 230: 1; 0: 2 | 1/3 |
| Henesys careless | 1 / 2 / 0 | 714.8, 329.0 | 230: 1; 0: 2 | 2/3 |
| Tree sensible | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0: 3 | 0/3 |
| Tree careless | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0: 3 | 0/3 |

The requested Henesys drift sample (training 1-6 and 2026) clears 5/7 sensible and 1/7 careless; Lv10 medians
270.7 s (7/7) and 277.6 s (5/7), conditional Lv30 medians 574.6 s (5/7) and 561.55 s (2/7). The owner-requested
external `drift-53.md` preserves per-seed results and comparisons with #42's published frozen C21 training and
held-out figures; the superseded opening, rarity changes and different cohorts prevent attributing that historical
difference to #53 alone. No held-out seeds were run and no data were retuned. A visible seed-1 run forced 210,
cleared with `missing: []`, and its inspected `evidence/t53/job_window/window_job_30.png` shows all three branches selectable.

#### #31 / #57 Cleric attacks regression smoke (2026-10-15)

No tuning. Seeds 1/2/2026, both stages, bot/random policies, real cache, 800 × 600, 1,800 s cap,
unforced seeded branches, `ISOLATE=t57`, no patch. All 12 records have empty world warnings; no crashes or
script errors. Henesys reaches Magician and the first boss in 3/3 per policy, and Cleric in 1/3 per policy.
Clear counts and death times match the preceding #53 smoke; Tree remains record-only.
After merging #56's integration changes and retaining both skill families, the full `ISOLATE=t57` suite passed
**608 tests, 0 failed, 0 skipped, 67 files** in 297.667 s. No SKIP is counted as coverage.

| Stage / policy | Clear / dead / timeout | Death seconds | Cleric clear / skill ranks |
|---|---|---|---|
| Henesys sensible | 1 / 2 / 0 | 812.3, 322.7 | 1008.5 s; Holy Arrow 8, Heal 14 |
| Henesys careless | 1 / 2 / 0 | 714.8, 329.0 | 962.7 s; Holy Arrow 8, Heal 8 |
| Tree sensible | 0 / 3 / 0 | 141.9, 141.0, 77.4 | no second advancement |
| Tree careless | 0 / 3 / 0 | 141.9, 141.0, 77.4 | no second advancement |

Logs/records and systems aggregates are ignored under `_scratch/t57_smoke/`. The first sensible report invocation
used relative record paths and failed to open them; the report was rerun successfully with absolute paths, without
replaying or changing the runs. The visible seed-1 forced-230 playtest cleared at 1008.5 s, `missing: []`.
Inspected `evidence/t57/cleric_s1/t700.png` and `t938.png` show Holy Arrow; the focused controlled RunScene captures
`evidence/t57/focused/heal_gain.png` and `holy_arrow_flight.png` expose Heal's rising art/blue HP gain and the arrow
without crowd occlusion. Both use the actual cache and sounds; the focused summary also has no missing assets.
The seed-2026 attempt ended before its 480 s warp target and the existing warp path did not finish the dead run;
it was stopped and replaced by seed 1. Exact v83 recovery remains unverified, as detailed in the #57 research note.

#### Owner review of #51: vanilla skills and the v83 opening (historical coarse pass)


The owner rejected the C21 profile's survivor projectile coverage and opening pool: every skill starts as its vanilla
v83 form (one Three Snails shell, one Energy Bolt; more only from cards, later rarity) and the opening pool stays the
v83 Beginner's 5 MP with no starter Blues. With canonical MP costs a Beginner then casts Three Snails about once per
10 s regeneration pulse, so C21's data killed all twelve 1..12 sensible runs before 1:40, and lighter waves alone
still died before 4:00: the bot fled every nearby mob (its sword only swings while standing) and drained potions
that mostly overflowed the small pools. The owner chose a sword-paced opening, a bot sword duel (a lone ordinary mob
while no attack skill can fire) and a potion waste guard (drink only when half of one restore fits) instead of raw
80% / 30% thresholds; final tuning waits until later specs change the game again, so this is a coarse pass with no
held-out report. At that historical pass, 601–630 remained reserved and unused; #30's later assessment above
consumes that range.

Levers, training seeds only: the 0:00–6:00 keyframes (table in 4.1) with HP drops 8% → 3% before 4:00, Henesys
elites from 4:00 and bursts from 5:00, Henesys ordinary EXP 2.5x, and MP drops 10% normal / 60% elite. Each policy ran
all **61 training seeds, 1–60 and 2026**, unpatched, 800 × 600 view, 1,800 s cap:

| Policy | Clear / dead / timeout | Clear rate | Death-only median (deaths) | Magician median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 27 / 34 / 0 | **44.26%** | **760.4 s** (34) | 276.7 s (61/61) | 600 s (56/61) |
| Random | 2 / 59 / 0 | **3.28%** | **329.4 s** (59) | 281.3 s (42/61) | 574 s (8/61) |

| Policy | MP collected / used | Ratio of totals | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|
| Sensible | 15,652 / 9,971 | **1.570** | 84 | 0 / 59 |
| Random | 4,466 / 3,458 | 1.291 | 3 | **2 / 24** |

| Run minute | Sensible mean hits/ordinary kill (hits / kills) | Random mean (hits / kills) |
|---|---|---|
| 1 | 1.667 (732 / 439) | 1.706 (701 / 411) |
| 2 | 1.362 (1,282 / 941) | 1.454 (1,147 / 789) |
| 3 | 1.413 (1,837 / 1,300) | 1.515 (1,353 / 893) |
| 4 | 1.171 (3,465 / 2,960) | 1.308 (2,345 / 1,793) |
| 5 | 1.433 (8,682 / 6,057) | 1.441 (6,265 / 4,349) |

Sensible clears and both death medians are inside the 4.1.1 bands. Known coarse deviations, left for the final pass:
careless clears 3.28% (band 5–15%), sensible MP ratio 1.57 (band 1.2–1.5), Lv30 near 10:00 (goal 12:00–15:00; the
2.5x EXP applies all run), and early ordinary kills averaging 1.2–1.7 hits rather than two by minute five. The
regression seeds 1/2/2026 give Henesys one clear and two deaths with Lv8/Lv10/Magician 3/3 and Lv30 2/3.

#### Spec #29 / #42 Henesys rebalance: chosen training profile (superseded by the owner review above)

C21, gameplay/data commit `cec3fe8`, meets every new training target in 4.1.1. Each policy includes all **61 seeds,
1–60 and 2026**, an 800 × 600 view and a 1,800 s safety cap. No held-out results informed selection. Sensible runs
were freshly run on committed, unpatched data; random contains nine same-profile mechanism records plus 52
remaining runs, included once each. The exact patch matches every shipped tuning leaf. Data Git tree:
`e585c58d2728212ecc2d10b5c55c4c55dd6ea371`; pacing-guard blob:
`837c5f2639820d8149f46809ae625f55f598fac4`. The sealed freeze manifest records the commit and all 122 record hashes.

| Policy | Clear / dead / timeout | Clear rate | Death-only median (deaths) | Magician median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 30 / 31 / 0 | **49.18%** | **886.7 s** (31) | 201.9 s (60/61) | 748.3 s (53/61) |
| Random | 4 / 57 / 0 | **6.56%** | **660.6 s** (57) | 200.8 s (59/61) | 708.55 s (14/61) |

The random Lv30 median is conditional on its fourteen reaches, not a progression target. Legitimate early deaths
remain in these counts, including sensible seed 2026 at 204.7 s. All 122 records have empty simulation warnings.

| Policy | MP collected / used | Ratio of totals | MP stock median / empty runs | Late MP-wait runs / observed | Wait / observed seconds after 8:00 |
|---|---|---|---|---|---|
| Sensible | 9,646 / 7,271 | **1.32664** | **50 / 8 of 61** | 10 / 60 | 697.568 / 27,638.619 |
| Random | 6,443 / 5,776 | 1.11548 | 2 / 28 of 61 | **21 / 54** | 1,484.218 / 12,682.881 |

Sensible stock is 57% below the former median 117. Normal/elite/boss MP supply is 4% / 30% / three, compared with
the original 6% / 65% / six. Canonical restoration, damage, MP costs and ranks are unchanged. The finite 30-MP pool
and five Blue starters reduce opening capacity waste; the first five uses occur around the opening minute and
still clip about 60% of their canonical restoration, measured separately from collected supply.

| Run minute | Sensible mean hits/ordinary kill (hits / kills) | Random mean (hits / kills) |
|---|---|---|
| 1 | 1.149 (5,277 / 4,591) | 1.149 (5,263 / 4,581) |
| 2 | 1.000 (8,346 / 8,346) | 1.000 (8,281 / 8,279) |
| 3 | 1.217 (12,190 / 10,014) | 1.219 (12,025 / 9,866) |
| 4 | 1.560 (21,370 / 13,701) | 1.563 (20,784 / 13,295) |
| 5 | **2.187** (40,532 / 18,530) | **2.195** (37,069 / 16,888) |

Density rises before durability: HP stays at ×1 through 2:00, then increases so ordinary kills average roughly
two landed hits by minute five. Means pool lifetime hits over kills; they are not per-cast counts or averages of
per-run means. [The detailed balance record](research/spec29-henesys-balance.md) preserves completed/spawned boss
counts, censoring, rejected cohorts, resource measurements and exact reproduction/provenance.

Freeze commit `81afb94` seals the candidate and conditional Henesys pacing guards. The complete suite passed
**536 tests, zero failures, zero skips** (60 files), including fixed seeds 1/2/2026 on both stages. Henesys recorded
one clear/two deaths and reaches Lv8/Lv10/Magician 2/3, Lv30 1/3; Tree recorded one clear/two deaths and reaches
2/3 for each milestone. All event, EXP, kill, finale, cache and meaningful conditional pacing guards passed.
Three separate actual headless Tree RunScene checks ended in death with **`missing: []` and no script errors**;
their 0/3 clear rate is informational. The detailed report keeps their outcomes separate from the simulation fixtures.

The inspected **306-second x1** Henesys opening at `f6637da` passes final visual acceptance by independently
verified prefix equivalence: the only subsequent runtime/data differences are four Henesys HP-drop keyframe
leaves at 540/660/780/900 s; interpolation first changes behavior after 480 s. All scripts and other data are
unchanged. All five minute screenshots and the final image were inspected, with no missing assets or log errors
(`evidence/spec29/x1/c14_s1/QA.md`). Fresh held-out **501–530** runs were executed once per policy after these
QA gates and are reported separately below, without tuning on their outcomes.

The initially reserved 401–430 range was retired before execution: the historical "Review-fix pass 3" below
already reports 401–406 for both policies. The untouched replacement 501–530 was audited against repository
reports/history before release. This reservation correction changes no gameplay, data, pacing guard or training
record; the original unexecuted freeze manifest is preserved beside the amended one.

#### Frozen held-out report (501–530; consumed)

Both policies ran once on the unchanged frozen profile. All **60 unique records** validate with empty world
warnings and no script/error/warning log lines. This fresh cohort **does not reproduce the training clear-rate
bands**: sensible is above 50%, random below 5%. It is reported without retuning, reruns or pooling it with training.

| Policy | Clear / dead / timeout | Clear rate | Death median (deaths) | Magician median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 16 / 14 / 0 | **53.33%** | 770.0 s (14) | 200.15 s (30/30) | 740.3 s (23/30) |
| Random | 1 / 29 / 0 | **3.33%** | 654.2 s (29) | 201.6 s (30/30) | 701.5 s (6/30) |

| Policy | MP collected / used | Ratio | MP stock median / empty runs | Late wait runs / observed | Wait / observed seconds after 8:00 |
|---|---|---|---|---|---|
| Sensible | 4,760 / 3,530 | 1.34844 | 44.5 / 3 of 30 | 5 / 30 | 490.700 / 13,010.118 |
| Random | 2,854 / 2,648 | 1.07779 | 0 / 18 of 30 | 12 / 23 | 770.768 / 5,806.333 |

| Run minute | Sensible mean hits/ordinary kill (hits / kills) | Random mean (hits / kills) |
|---|---|---|
| 1 | 1.162 (2,604 / 2,241) | 1.159 (2,616 / 2,257) |
| 2 | 1.000 (4,113 / 4,113) | 1.000 (4,104 / 4,104) |
| 3 | 1.211 (6,150 / 5,078) | 1.210 (5,882 / 4,862) |
| 4 | 1.565 (10,632 / 6,793) | 1.562 (10,136 / 6,488) |
| 5 | 2.192 (20,434 / 9,321) | 2.161 (16,990 / 7,862) |

Completed/spawned boss counts, censored medians, hit fractions, timestamps and all raw-record hashes are retained
in [the detailed record](research/spec29-henesys-balance.md) and `evidence/spec29/balance/issue42/final/heldout/`.
The amended freeze manifest SHA256 is `6d12b85a5c86b4b107571ff77df7ca2958495030addeaf8c7b4936d7d960767b`.
At this historical #29 assessment, the next reserved range was **601–630**; #30 later consumes it above.
None of these results may be used as fresh tuning evidence.

The pre-#29 cohorts below are historical. Their statements about passing or final acceptance refer to the
earlier targets, which #29 replaces as specified in 4.1.1. Historical Tree pacing is informational.

#### Magician at Lv10 (#40)

The only gameplay data change in this pass is Magician's survivor advancement level, 8 → 10. The sensible bot's
actual `job_changed` time is reported as `magician_seconds` (min/median/max/count) in the balance aggregate and
as "Magician seconds" in its console report. Missing or negative `job_t` records are excluded, with no observations
reported as `none (n=0)`. This measures advancement rather than assuming a level milestone is a job change.

Training seeds **1–6 and 2026**, both stages, `--policy=bot --cap=420`, no patches:

| Stage | Time to Magician min / median / max, seconds | Reached | Outcome at 7:00 cap |
|---|---|---|---|
| Henesys Hunting Ground I | 234.3 / **235.9** / 250.2 | 7/7 | 7 TIMEOUT |
| The Tree That Grew I | 202.0 / **208.2** / 213.7 | 7/7 | 7 TIMEOUT |

Both medians fit the revised 180–330 s target in 4.1.1. These capped probes measure early advancement only;
they are not clears or a new population balance acceptance. No held-out seeds were run for this change.
Reproduce with `BALANCE_OUT=evidence/issue40/henesys bash scripts/balance.sh 1..6 2026 --cap=420` and
`BALANCE_OUT=evidence/issue40/tree bash scripts/balance.sh 1..6 2026 --stage=tree_that_grew_1 --cap=420`.
Each directory preserves the per-seed JSON/logs, aggregate JSON/log and the captured full `console.log`.
The full-run regression also exercised fixed training seeds **1/2/2026** on both stages: Henesys cleared 3/3,
Tree cleared 2/3 with seed 1 dying at 987 s. All six reached Lv30; stage median Lv30 times were approximately
775 / 812 s, within the unchanged 720–900 s bounds. These small regression samples do not replace population
acceptance. Output is preserved in `evidence/issue40/full-suite.log` and `full-run-recheck.log`.
Validation ran all 491 tests with zero skips. Three test failures exposed two stale Lv8 stat fixtures and a
floating-point tolerance at the harness's next-tick job-event observation. After correcting only those tests,
the affected progression/player-stat files passed 19 tests and the full-run file passed 5 tests, all with zero
failures/skips. The optional five-minute windowed probe recorded job 200 and no missing assets, but generated
no PNGs and waited for a rendered frame after saving its summary; it was stopped and is not visual verification.
The earlier cohorts below used Lv8 advancement and remain historical evidence.

#### Historical difficulty-overhaul training

The frozen data are v28, gameplay commit `db9ef80`, with the pooled-projectile identity fix. The actual pacing
regression passes 5 tests with zero failures/skips, including the unchanged fixed stage guards. No held-out runs
had been consumed at freeze. Training uses **1–60 and 2026**, 61 runs per
stage/policy, with a 1,800 s cap. Henesys records retain their original v27 / `e8197d7` provenance: v28 changes
only Tree King HP ×0.8→×1.1 (6,400→8,800). Selected Henesys stage data are identical, and predetermined sensible
controls 1/2/2026 match the full v27 records byte-for-byte. Tree's 122 records were freshly run on v28. The profile
diff, source hashes, controls, commands and every rejected comparison remain in local `evidence/acceptance/`.

“Most” means a majority of all runs clear, with at least one non-clear. “Careless dies mostly at 9–12 minutes”
means a majority of recorded deaths fall in 540–720 s, inclusive; clears and timeouts remain separate.
Milestone medians include only reaches, whose counts are explicit. Conditional random Lv30 medians are not
progression acceptance: only 4/61 and 6/61 reach it. Sensible progression has majority reach counts.
| Stage / policy | Clear / dead / timeout | Deaths early / 9-12 / late | Window share of deaths | Mage median (reaches) | Lv30 median (reaches) | Clears below Lv30 |
|---|---|---|---|---|---|---|
| Henesys sensible | 40 / 21 / 0 | 0 / 11 / 10 | 11/21 = 52.38% | 178.6 s (61) | 777.4 s (45) | 1 |
| Henesys random | 2 / 59 / 0 | 16 / 38 / 5 | 38/59 = 64.41% | 178 s (61) | 776.8 s (4) | 0 |
| Tree sensible | 38 / 23 / 0 | 0 / 5 / 18 | 5/23 = 21.74% | 163.6 s (61) | 784.7 s (50) | 0 |
| Tree random | 0 / 60 / 1 | 9 / 36 / 15 | 36/60 = 60% | 164.9 s (59) | 845 s (6) | 0 |

| Sensible boss, in arrival order | Completed / unfinished / unspawned | Completed duration median [min-max], s | Whole-hit HP median [min-max] | Source medians (landed hit count) |
|---|---|---|---|---|
| Mano | 61 / 0 / 0 | 30.6 [11.53-62.27] | 45.92% [41.2%-50%] | touch 45.92% (130) |
| Mushmom | 52 / 7 / 2 | 51.67 [12.07-163.15] | 44.82% [35.66%-57.86%] | attack 44.12% (61), touch 45.09% (228) |
| Blue Mushmom | 40 / 2 / 19 | 71.49 [27.33-176.67] | 44.46% [35.38%-53%] | attack 43.12% (25), touch 44.59% (183) |
| Stumpy | 61 / 0 / 0 | 22.85 [9.55-269.68] | 42.27% [27.8%-74.17%] | attack 42.31% (88), projectile 43.27% (38), touch 40.87% (47) |
| King Slime | 55 / 6 / 0 | 67.32 [20.93-197.93] | 45.6% [35.75%-59.59%] | attack 45.88% (88), touch 45.59% (403) |
| Dyle | 38 / 12 / 11 | 56.91 [6.62-337.88] | 45.05% [35.77%-54.12%] | touch 45.05% (588) |

| Stage / policy | Mean HP collected / used | HP stock median / empty runs | Mean inferred HP stock | Mean MP collected / used | MP stock median / empty runs | MP-wait runs / maximum |
|---|---|---|---|---|---|---|
| Henesys sensible | 32.1 / 33.3 | 0 / 35 | 3.8 | 235.5 / 113.8 | 121 / 0 | 0/61 / 0 s |
| Henesys random | 22.1 / 27 | 0 / 60 | 0.1 | 128 / 54 | 74 / 0 | 0/61 / 0 s |
| Tree sensible | 35.4 / 32.1 | 4 / 26 | 8.3 | 244.7 / 119.6 | 117 / 1 | 1/61 / 77.63 s |
| Tree random | 26.3 / 31.1 | 0 / 60 | 0.2 | 139.6 / 72.4 | 71 / 1 | 1/61 / 34.58 s |

The sensible clear rates are 65.6% / 62.3%; careless window-death shares are 64.4% / 60.0%. Tree random seed
2026 times out at 1,800 s with Dyle alive for 900 s, at Lv36 and zero MP wait. It is neither a clear nor a
completed finale. No unfinished fight is assigned a completed duration. Dyle's sensible 56.91 s median is
within 45–135 s but lower than the nominal 90 s; all encounter ranges and censoring remain visible.

Boss whole damage is measured before Guard splits it between HP and MP, not actual clamped HP loss.
Per-source medians describe typical landed hits, rather than requiring every hit to lie in 40–50%.
Canonical stats, costs, timings, heal bounds and attack boxes remain unchanged. Separate survivor contact and
attack multipliers account for actual build HP at impact. Ordinary late nonmiss hits over completed minute
buckets have sensible medians 211 / 150 and minima 28 / 43; all 61 sensible runs per stage live beyond 8:00.

Stock is inferred exactly as starter stock plus collected minus used (HP starts at 5, MP at 0); rounded means
may not sum exactly. Drop chances are the explicit curves in §5, including no ordinary HP from 9–12 minutes,
elite HP 15% and current-tier boss bundles. HP scarcity is supported by actual collection/use and exhaustion,
not only comparison with MP. The Tree sensible mean HP bank of 8.3 and median 4 remain explicit; scarcity is
not universal exhaustion. MP-wait medians are zero; rare waits and depleted-stock runs remain recorded.
The harness lacks potion source/tier totals, depletion timestamps and healed-HP totals, so these counts do not
establish source-specific supply or exact healing. Guard cast snapshots are separately traced, without exact
offer timestamps or damage-weighted absorption.

The fixed regression sample stays **1/2/2026 on both stages**, with the unchanged 720–900 s stage-median Lv30
guard and at least two reaches. V28 medians are Henesys 805.15 s (2/3) and Tree 890.0 s (3/3), Mage 179.0 /
163.7 s. V26 population gates passed but its fixed Tree median 909.2 s failed; it was not frozen. V27 reshaped
survivor EXP to 4+15L+3.8L² while preserving exact Mage cost 980. Its full Tree careless timing was only 30/59
(50.8%), so the King-only comparison was selected from training, not held-out evidence. Guard final scores
110/109, tier score 112, offer weights 8/8 and HP-drink threshold 0.8 remain in survivor data; random choices
remain uniform. Earlier v22 versus v24 sensible results change both rank weight and threshold and cannot
isolate either. Independent HP-only probe results are kept separate, not pooled with selected training.
#### Historical frozen held-out assessment: Henesys-first acceptance scope

All **120 fresh runs** on seeds **101–130**, both stages and both card policies, use freeze milestone `b230305`
(gameplay `db9ef80`), actual data without patch overrides and the same 1,800 s cap. Every expected identity is
verified. The later `ab5d7fa` change only makes a scene-test fixture use the public EXP threshold; it does not
change gameplay, design data, the pacing guard or the already-running held-out mirror. No tuning followed these
results.

**Tree careless timing fails the original two-stage target:** only **12/29 deaths (41.4%)** fall in 540–720 s, versus a required
majority. Its 717.3 s death median alone would conceal 14 later deaths. The training share of 36/60 (60%) did not
reproduce on this reserved sample. This fails the original two-stage target. The user then clarified that this
pass should gate on Henesys ("Mainly henesys"); Tree careless timing is deferred and informational, with no
further tuning or replacement held-out sample. Both stages remain implemented and playable. Both sensible groups
meet their progression, clear-rate, late-hit and typical boss timing/source-hit gates; Henesys random meets the
careless timing gate. No run times out in the held-out matrix.

The actual frozen pacing run passed 5 tests with no failures or skips. `ab5d7fa` corrected the stale scene-test
EXP fixture through the public progression API. `2805a24` then made the optional canonical recipient-burst path
explicit without changing recipients, RNG or gameplay. That pre-review runtime full suite passed **485 tests, 0 failed,
0 skipped, 59 files** in 590.147 s. The survivor data and pacing guard remained unchanged.

| Stage / policy | Clear / dead / timeout | Deaths early / 9-12 / late | Window share of deaths | Mage median (reaches) | Lv30 median (reaches) | Clears below Lv30 |
|---|---|---|---|---|---|---|
| Henesys sensible | 18 / 12 / 0 | 0 / 5 / 7 | 5/12 = 41.67% | 178.3 s (30) | 794.4 s (23) | 0 |
| Henesys random | 2 / 28 / 0 | 4 / 21 / 3 | 21/28 = 75% | 177.8 s (29) | 810.3 s (3) | 0 |
| Tree sensible | 24 / 6 / 0 | 0 / 4 / 2 | 4/6 = 66.67% | 163.6 s (30) | 812.7 s (24) | 1 |
| Tree random | 1 / 29 / 0 | 3 / 12 / 14 | 12/29 = 41.38% | 162.4 s (27) | 814.7 s (8) | 0 |

| Sensible boss, in arrival order | Completed / unfinished / unspawned | Completed duration median [min-max], s | Whole-hit HP median [min-max] | Source medians (landed hit count) |
|---|---|---|---|---|
| Mano | 30 / 0 / 0 | 31.37 [11.23-48.45] | 47.45% [42.35%-52.17%] | touch 47.45% (72) |
| Mushmom | 28 / 1 / 1 | 74.15 [34.63-128.73] | 44.89% [38.74%-51.27%] | attack 44.32% (27), touch 45% (136) |
| Blue Mushmom | 18 / 4 / 8 | 71.42 [35.88-143.28] | 45.54% [34.77%-51.46%] | attack 44.72% (9), touch 45.59% (76) |
| Stumpy | 29 / 1 / 0 | 22.93 [8.87-78.33] | 42.5% [32.46%-65.67%] | attack 42.79% (43), projectile 41.83% (17), touch 41.82% (30) |
| King Slime | 25 / 4 / 1 | 80.3 [26.67-148.67] | 45.59% [39.36%-60.82%] | attack 45.81% (46), touch 45.47% (210) |
| Dyle | 24 / 1 / 5 | 68.62 [8.45-237.68] | 45.75% [35.83%-53%] | touch 45.75% (247) |

| Stage / policy | Mean HP collected / used | HP stock median / empty runs | Mean inferred HP stock | Mean MP collected / used | MP stock median / empty runs | MP-wait runs / maximum |
|---|---|---|---|---|---|---|
| Henesys sensible | 32 / 34 | 0 / 19 | 3 | 241.5 / 109.5 | 119 / 1 | 1/30 / 81.5 s |
| Henesys random | 25 / 29.8 | 0 / 29 | 0.2 | 144.9 / 55.5 | 99 / 0 | 0/30 / 0 s |
| Tree sensible | 34.6 / 30.9 | 4 / 9 | 8.7 | 239.2 / 106.7 | 132.5 / 1 | 1/30 / 2.32 s |
| Tree random | 27.8 / 32.6 | 0 / 29 | 0.2 | 160.6 / 70.3 | 89.5 / 1 | 1/30 / 20.4 s |

Sensible clear rates are 60% / 80%. Ordinary late nonmiss hit medians are 219 / 145, minima 25 / 29; every
sensible run lives beyond 8:00. HP stock medians 0 / 4 and exhaustion 19/30 / 9/30 show scarcity is uneven;
mean inferred banks are 3.0 / 8.7. MP waiting occurs in one run per sensible stage (81.5 s / 2.317 s), with zero
wait medians and stock medians 119 / 132.5. These remain measured counts, not a claim that every build has
ample MP or exhausts HP. Tree has one clear below Lv30, retained explicitly rather than excluding it.

Random-policy encounter/source observations remain in the raw audit, including small and censored finale
samples: Henesys Blue Mushmom has only 2 completed fights, 1 unfinished and 27 unspawned, with a whole-hit
median 39.43% across 8 landed hits. Tree Dyle has 1 completed fight (422.27 s), 8 unfinished and 21 unspawned.
They are not substituted for the sensible-policy boss medians. All durations, source counts, stock inference
and missing harness measurements follow the definitions above. The frozen data remain unchanged after this
failed assessment; these seeds must not become another tuning input.

#### Historical corrected-runtime training and Henesys assessment

Final review corrected the unequal-afterimage reach gate: swing selection remains uniform while the chosen
stance keeps its own impact box. It also replaced steady boss-action buffer allocation with a reusable borrowed
view and shared the bot/camper portal-entrance approach without changing their goal policies. These fixes are
runtime `a25697e`; **all survivor data, canonical values and pacing guards remain unchanged** from the v28 freeze.
The corrected full suite passed **489 tests, 0 failed, 0 skipped, 59 files** in 695.839 s, including the unchanged
fixed pacing sample on both stages and real-cache tests. No skip is counted as coverage.

The corrected-runtime 101–130 Henesys audit did not pass every gate: sensible clears were **15/30**, exactly
half, failing “most but not all”; careless timing passed at **21/29 deaths** in 540–720 s. These results remain
preserved in `evidence/acceptance/post_review_hg/`, separate from both the original 120 and the final assessment.
They were not used to choose data changes. The original Tree careless **12/29** timing failure remains deferred
under the owner's Henesys-first scope; no Tree tuning or replacement Tree validation was performed.

Before further training, the corrected-runtime baseline cohort was declared as **1–24 plus 2026**, both policies.
Its sensible 12/25 clears prompted a sensible-only expansion through training seeds 25–60; careless already met
its timing target at 14/25 deaths in-window. The resulting **61 sensible / 25 careless** training records supported
selecting the data unchanged: sensible 38/61 clears, Mage median 178.6 s (61 reaches), Lv30 789.0 s (43 reaches),
boss duration medians 30.60/65.17/74.12 s (61/51/38 completed), and every sensible boss/source hit median in-band.
Ordinary late hits have median 209/minimum 25. Sensible HP stock median is 1 (29/61 empty); MP stock median 118,
with no MP-wait ticks. Careless HP stock is zero in all 25 runs. Full ranges and censoring are preserved in
`evidence/acceptance/final-review/training-assessment.md` and its machine-readable metrics; cohorts are not pooled.

Ticket #27's final reserved range was explicitly amended to **301–330** before any of those runs, because 101–130
was consumed and historical 201–212 was also consumed. Substantive targets stayed unchanged. Selection of unchanged
`a25697e` was sealed at **2026-10-15 03:46:14 UTC**, before the first held-out log at **03:46:48 UTC**. The initial
PowerShell manifest construction failed and left an empty file; its metadata was rebuilt at **03:48:21 UTC**,
after launch, from the sealed decision and unchanged commit/data. The runner's recorded account says completed-result
existence was checked during repair, no outcome values were read, and no tuning or selection changed. Independent
audit verified the sealed decision, hashes and timestamps; absence of outcome reads is the runner's account.
The preserved manifest discloses this repair, all 86 training-record hashes, six unchanged data hashes and the
unchanged pacing-guard hash.

All **60 final Henesys runs** use `a25697e`, actual data without patches, and the 1,800 s cap. This final amended
assessment passes the Henesys targets; it neither replaces the earlier failed audit nor claims Tree timing passed.

| Final 301–330 policy | Clear / dead / timeout | Deaths early / 9–12 / late | Window share of deaths | Mage median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 22 / 8 / 0 | 0 / 6 / 2 | 6/8 = 75% | 177.45 s (30/30) | 774.4 s (23/30) |
| Careless | 1 / 29 / 0 | 4 / 23 / 2 | 23/29 = 79.31% | 175.7 s (30/30) | 838.6 s (1/30) |

Sensible clears are **73.33%**, most but not all; careless timing has a majority of deaths in 9–12 minutes.
No clear occurs below Lv30. The careless single Lv30 reach is an observation, not a progression acceptance sample.
Sensible ordinary late nonmiss hits have median **218.5**, minimum **58**, using completed minute buckets after
8:00. Boss hits and misses do not satisfy that ordinary-hit observation.

| Final sensible boss | Completed / unfinished / unspawned | Completed-fight duration median [min–max], s | Whole-hit HP median [min–max] | Source medians (landed hits) |
|---|---|---|---|---|
| Mano | 30 / 0 / 0 | 27.29 [11.13–73.40] | 45.92% [41.84–50.00%] | touch 45.92% (75) |
| Mushmom | 25 / 5 / 0 | 57.23 [20.85–161.92] | 45.00% [39.20–50.30%] | attack 44.31% (20), touch 45.06% (126) |
| Blue Mushmom | 22 / 0 / 8 | 73.44 [22.80–131.77] | 44.95% [38.46–51.46%] | attack 43.09% (12), touch 45.63% (73) |

These duration medians cover completed fights only (Mushmom 25 of 30 spawned); unfinished fights are censored, not
missing. The harness now prints `completed n/spawned` beside the median and a censored median that counts each
unfinished fight as at least its elapsed seconds (`>=` when that makes it a lower bound); pass 3 re-measures with it.
All sensible completed-duration medians fit 15–45 / 30–90 / 45–135 s, and all whole/source-hit medians fit 40–50%.
Ranges show that individual fights and damage rolls can fall outside those typical bands. Fractions precede
Magic Guard's split. Unfinished fights are not completed observations or zero durations. Careless boss samples
remain separate: Mano 28/2/0, Mushmom 4/15/11, Blue Mushmom 1/0/29 completed/unfinished/unspawned.

| Final policy | Mean HP collected / used | HP stock median / empty runs | Mean inferred HP stock | Mean MP collected / used | MP stock median / empty runs | MP-wait runs / maximum |
|---|---|---|---|---|---|---|
| Sensible | 33.13 / 33.80 | 2 / 11 of 30 | 4.33 | 238.87 / 112.13 | 117 / 0 of 30 | 0/30 / 0 s |
| Careless | 24.03 / 28.70 | 0 / 29 of 30 | 0.33 | 129.03 / 55.23 | 67.5 / 0 of 30 | 0/30 / 0 s |

HP scarcity is uneven, not universal exhaustion; MP supply supports the recorded builds without waiting. Stock
remains starter plus collected minus used. Exact potion-source/tier counts, depletion timestamps and healed-HP
totals remain unmeasured. Final records, console reports, audit and repair disclosure are retained in
`evidence/acceptance/final_301_330/`. No further tuning followed this assessment.

The final corrected-runtime density capture uses `a25697e`, Henesys seed 2026, speed 1, vsync off, warp 600 and an
absolute 780 s cap. It remains PLAYING at that deliberate cap, not cleared. After all owned heavy jobs ended,
**74,953 frames with 200+ mobs have p95 3.070 ms**, p99 3.662 ms and max 25.346 ms; max 274 mobs, `missing: []`.
Work p95 is 1.806 ms and sim cost 0.865 ms/tick. The final screenshot was checked by eye. The PowerShell wrapper
exited 1 after treating the expected stderr status line as an error; the game completed and wrote valid summary,
screenshots and engine log. The late after-process sample and wrapper issue are disclosed in
`evidence/acceptance/density_hg_final/completion-context.json`; full hardware/background context is in the
Implementation Plan. Earlier visual/performance evidence remains separate below.

#### Historical review-fix pass 3: Henesys 9:00 HP trickle (2026-10-15)

Giving potion drop rolls their own RNG stream 7 (they had shared stream 5 with basic-attack stance rolls) reshuffled
seeded outcomes, and fixed regression seed 1 on Henesys then died at 592 s, failing the `test_full_run` guard
"a death comes late in the run" (>= 600 s); with the shared stream it had died at 950 s. The stream fix and the guard
stay. **Change (tier C, survivor data only):** the Henesys keyframe at 9:00 (`t` 540) gets `normal_hp_drop_chance`
0.002 instead of 0, so the 0.2% ordinary HP chance of 8:00 holds to 9:00 and trickles to 0% at 11:00 instead of
reaching 0% at 9:00. Rationale: it is the smallest supply change that clears the guard. Runs are bit-identical before
8:00; from 8:00 to 9:00 the same stream-7 rolls are drawn against a flat 0.2% instead of one falling to 0%; after
9:00 the HP rolls that were skipped at 0% are drawn, which also shifts the later MP rolls on stream 7. The extra supply
is about one Red Potion per run (HP potions collected on 1–60: sensible 1909 -> 1979, careless 1414 -> 1438 in
total), and Tree data are untouched.

Selection used only training seeds (1, 2, 2026 as a gate, then 1–60). Rejected: raising the 8:00
keyframe to 1.2% (holding the 6:00 value) or 1.6% also passed, but raised sensible clears from 37 to 45 and 48 of
60, an easing that belongs to the planned Henesys rebalance (#42); 0.4–1.0% at 8:00 and Mano's HP bundle 6 -> 7
left seed 1 dying before 600 s or within 2 s of it. In the test harness seed 1 now dies at 610 s, a thin 10 s
margin over the guard; seeds 2 and 2026 clear (Lv30 at 828 s and 770 s). Before = HEAD before this change, after =
with it; Tree 1–30 rerun on the committed data is identical row for row.

| Training seeds, policy | Clear / dead / timeout | Deaths early / 9–12 / late | Death median | Mage median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Henesys 1–60 sensible, before | 37 / 23 / 0 | 0 / 11 / 12 | 12:22 | 2:58 (60) | 13:01 (44) |
| Henesys 1–60 sensible, after | 39 / 21 / 0 | 0 / 9 / 12 | 12:37 | 2:58 (60) | 13:07 (45) |
| Henesys 1–60 careless, before | 2 / 58 / 0 | 16 / 35 / 7 | 10:07 | 2:56 (59) | 14:12 (4) |
| Henesys 1–60 careless, after | 2 / 58 / 0 | 15 / 35 / 8 | 10:08 | 2:56 (59) | 13:34 (4) |
| Tree 1–30 sensible, before = after | 11 / 19 / 0 | 0 / 4 / 15 | 16:51 | 2:43 (30) | 13:50 (22) |

Four sensible seeds changed outcome (33 cleared -> died; 39, 59, 60 died -> cleared) and two careless seeds (19, 54)
swapped; the earliest sensible death stays 9:15. Fresh held-out smoke, Henesys 401–406, report only and never tuned
on: sensible 3/6 cleared (deaths 11:22, 12:27, 13:07; Mage median 2:59; Lv30 median 12:25, 4 reaches), careless 0/6
(deaths 5:05, 5:09, 9:56, 10:49, 12:15, 12:25). Records: `_scratch/p3/` (local, uncommitted).

#### Historical informational camper samples

On the same v28 data, seeds **1–6 and 2026**, `--camp-after=60 --cap=1800`, all 21 runs reached their requested
camping position. These observations are informational and did not select or tune the profile.

| Policy | Clear / dead / timeout | Death median [min–max], s |
|---|---|---|
| Henesys top platform | 0 / 7 / 0 | 300.3 [300.3–301.6] |
| Henesys rope | 0 / 7 / 0 | 207.2 [205.9–294.4] |
| Tree top platform | 0 / 7 / 0 | 321.0 [310.5–403.5] |

Raw records, requested-position flags and commands are preserved in `evidence/acceptance/campers/`.

Pre-review visual evidence preserves the original full composites and the corrected Tree replay: both stages actually
clear beyond 15:00, and corrected summaries have `missing: []`. Optional Dyle recipient art is selected from the
canonical field rather than assumed. The separate Henesys speed1 uncapped 10:00–13:00 measurement records
62,580 frames with 200+ live mobs at p95 **3.912 ms**, max274 mobs, no missing assets. It stops PLAYING at its
deliberate 13:00 measurement cap, not a clear. Hardware, background load and timing detail are in the
Implementation Plan performance log; screenshots were checked by eye. This completed the pre-review implementation evidence
for the user-amended Henesys-first scope, with Tree careless timing still deferred.
#### Historical Phase 1 records

**Historical seeds.** The earlier 2026-10-14 pass was tuned on seeds 1-24 (variants compared on both policies) and is reported on the
held-out seeds 101-130, which were never used for tuning; the earlier record (seeds 1-23 + 2026) had been tuned and
reported on the same seeds, and it did not hold on fresh seeds (a review found 6 of 18 deaths on seeds 31-48). Keep
tuning on 1-60 and reporting on 101-130. The earlier regression consumed seeds 101/102; the new-system regression
uses fixed training seeds 1/2/2026 on both stages as described in 4.1.1.

Targets: Lv 8 (Magician) at 2:30-3:45, Lv 10 at 3:00-5:30, Lv 30 at ~12:00-15:00, a crowd of 200+ alive in the last
minutes, hits taken regularly after 8:00, deaths of the sensible player late and on a minority of seeds; a careless
player should reach the job advancement and usually get past 8:00.

| henesys_hg1, held-out seeds 101-130 | Before (data of 2026-10-13) | After (this data) |
|---|---|---|
| Sensible player (`bot`): outcome | 22/30 cleared; deaths 9:33-14:12, 3 before 12:00 | 20/30 cleared; deaths 8:57-14:39, 4 before 12:00 (8:57, 10:19, 10:48, 11:33) |
| Lv 8 / Lv 10 / Lv 30 (median) | 2:28-4:50 (2:59) / 3:52 / 10:23-13:31 (11:53), 24 reach Lv 30 | 2:26-4:54 (2:45) / 3:48 / 11:22-13:03 (12:03), 25 reach Lv 30 |
| Level at 15:00 or death | 20-41, median 35 | 17-39, median 35.5 |
| Alive at 4/8/12/14 min (median of the minute's mean) | 42 / 155 / 232 / 289 | 24 / 74 / 123 / 220 (max 156-330, median 311) |
| Mobs near the player (300 x 150 px) at 4/8/12 min | 0.9 / 10.8 / 18.7 | 0.5 / 7.1 / 15.3 |
| Hits before 6:00 / after 8:00 (median) | 2 (26 of 30 runs hit) / 18 | 1 (16 of 30 runs hit) / 23 |
| EXP drops lying on the map at 4/8/12 min | 82 / 316 / 512 | 52 / 77 / 135 (14% of the EXP expires) |
| Careless player (`random`) | 0/30 cleared; median death 7:31; 24/30 reach Lv 8; 13/30 live past 8:00; 9 die before 6:00 | 2/30 cleared; median death 8:57; 27/30 reach Lv 8; 18/30 live past 8:00; 3 die before 6:00 |
| Hands off the keys from 5:00 (`bot` cards, seeds 101-112) | 1/12 survive; deaths 6:30-13:39, median 11:54 | 0/12 survive; deaths 6:34-12:28, median 9:40 |

What changed (all data toggles, see sections 5, 7, 8, 9 and 11): Three Snails levels with the character
(`level_ranks`), Energy Bolt comes with the Magician job (`grants.skills`), a power card is guaranteed after a draw
without one (`pity.draws`), spawns prefer the player's platform and its neighbours (`spawn.prefer_hops`), drops expire
(`pickup.lifetime`), the EXP curve is steeper (c 2.25 -> 3), and the keyframes of section 4.1 (lower `max_alive` at
4:00-9:00, gentler HP growth, smaller early bursts, a faster early spawn rate).

Reading: careless builds now usually reach the Magician and survive past 8:00, a build left alone from 5:00 dies about
two minutes sooner (play matters more than before), and the sensible player's outcome is about the same as before
(20 vs 22 clears of 30 is within the seed-to-seed spread). The price is a thinner mid-game
crowd for a strong build (74 alive at 8:00 instead of 155); a larger share of it is near the player (10% and 12% of
the alive mobs at 8:00 and 12:00, against 7% and 8%), the strong build takes more hits after 8:00, and the crowd still
reaches 200-330 in the last minutes. Not reached: early pressure on a
strong build. The kiting bot takes about one hit before 6:00 (14 of 30 runs none at all), fewer than before, because
Three Snails is stronger early; a variant with higher 6:00-12:00 spawn rates (5.5/10/15) gave a bigger mid-game crowd
(88 / 139 alive at 8 / 12 min on seeds 1-24) but more deaths (18 instead of 21 clears of 24) and Lv 30 at ~11:20, and
was not taken. The bounds of a human player lie between the kiting bot and the hands-off run; how punishing the
careless and early game should be is a design decision for the lead.

Other stages (held-out seeds 101-112, `bot`), not tuned as carefully (their stage cards say so): The Tree That Grew I
(henesys numbers with its own pools, no opening Slimes, `prefer_hops` -1 because spawning next to the player on its
small platforms killed runs in the first minutes) clears 8/12, Lv 8 at ~2:36 and Lv 30 at ~10:47 (too fast), deaths
at ~10:00 and one at 2:51. The Hill East of Henesys (gentler numbers, `prefer_hops` -1, `exp_mult` 1.2) clears 6/12,
Lv 8 at ~3:06, Lv 30 reached on 5/12 (slow), deaths 10:41-14:58.

#### Swarm pass (2026-10-14, later the same day)

**Problem.** In a playtest (seed 555) the mid-game crowd (6:00-12:00) stood in long rows on the platform above the
ground of 104040000 and never reached the player on the ground; only a handful of mobs were near it.

**Engagement metric** (`balance_run.gd` `eng_by_min`, `scripts/balance.sh` column `eng6/9/12`): the share of the live
mobs within 400 px horizontally and 200 px vertically of the player's feet, as the ratio of sums (engaged mob-ticks /
live mob-ticks) over every tick of the minute centred on m:00 ([m:00 - 30 s, m:00 + 30 s)); the tables give the median
over the seeds. **Stale** (`stale_by_min`): over the same windows, the share of live mobs that have been outside that
box for 20 s or more in a row (since their spawn or their last time in it; a relocated mob keeps its time,
`mob_spawned.relocated_from`; until the follow-up below a relocation restarted it, so the first version's 0% could not
show mobs idling off-screen until they were relocated).

**Diagnosis** (an instrumented headless run of the kiting bot, seeds 1-12, 5:00-12:00, the data and code before this
pass; every second each live mob that had been outside the box for 15 s or more was classified by platform, state,
NavGraph route and edge kind, whether it moved, whether its route flipped, and why it spawned where it did):

- Only 8% of the live mob-seconds were such long-idle mobs. Of those, 72% were on the ground platform itself, walking
  after a player who kites at 125 px/s from mobs walking at 22-80 px/s; 22% were on the long platform above the ground
  (1518 px, 300 px up) walking to its drop, half of them *away* from the player: the route was the fewest edges, and
  that platform drops straight onto the ground only at its left end (its right end drops onto a step one edge
  further), so every mob on it walked to the left end, then all the way back on the ground. Airborne, no route and
  route flipping were about 1% each. Nothing was stuck: no mob waited at a takeoff it could not use, none pushed a wall
  (104040000 has no wall inside a platform), no jump edge failed (`test_real_every_edge_lands_where_the_graph_says`).
- The cause of the rows was spawning: `prefer_hops` 1 counted that long platform as one edge from the ground, so 33% of
  the spawns after 5:00 landed on it (and 24% on the two small platforms above its left end) against 40% on the ground.
  At 6:00, 18% of the live mobs were within 400 px horizontally of the player but 300+ px above it (the visible rows),
  69% were 400-1300 px away (on their way, or trailing), 8% were engaged.
- 7% of the spawns (5-32% on seeds 101-112) were recycled silently, 79% of them for falling 1300 px behind.
- The bot kills 85% of the mobs inside the box ~10 s after they spawn, so engagement is capped by how long a mob takes
  to arrive (every spawn is 448+ px out, outside the view + 48 px) against how long it survives once there.

**Changes, first version** (sections 4, 4.1 and 11; `NavGraph`, `MobSwarm`, `SpawnDirector`, `RunWorld`,
`FootholdMap`, `balance.json` `spawn`, `stages.json`): mobs steer by the shortest walk to the player's x (a travel-cost
field) with 96 px of hysteresis; straight-up hops take off where the route goes on; walkers under a player on a low
step walk under it; the first spawn ring is the floors beside the view (160 px out, 48 px above/below), and a point is
preferred when its way in is no longer than the walk in from that ring's outer edge; no spawns on floor buried behind a
wall; off-screen mobs that stop closing in for 3 s, or are far or cannot reach the player, are moved ahead of the
player instead of being removed; the keyframes of section 4.1 (HP x1.3 from 6:00, 6:00-12:00 rate +10-20%, early rate
-15%, touch damage halved); The Tree That Grew I and The Hill East of Henesys take the same numbers (Hill `exp_mult`
1.2 -> 1.1).

**Follow-up** (after an independent verification of the first version). The first version's record was taken on the
held-out seeds 101-112 only, which happened to draw the high-crowd outcome (alive at 9:00: 149.5 there against 57.5 on
the other 30 seeds of the verification), so its "55-60% engaged at 9:00 / 12:00" did not hold on the rest (46% / 50% on
101-130, 35% / 39% on the fresh seeds 201-212), and it brought Lv 30 to ~11:15 on every stage, before the
~12:00-15:00 target. The follow-up changed:

- The stall rule counts only the mob's own progress: its way left must shrink *and* the mob must have moved 1 px since
  it last came closer (the player walking up to a mob stopped at a wall shortened its way, so such mobs were never
  relocated); a mob standing still on screen keeps counting and is moved as soon as it is off screen; and a mob is
  only moved from 80 px outside the view (48 + 32 on every side: right after the player turns, the camera still lags
  on the other side).
- Spawning and relocation reject a point when a wall across a platform stands anywhere on its way to the player
  (followed edge by edge onto the player's platform), not only on its first platform: on 100010000 mobs that dropped
  onto the ground outside the hill's faces walked into them while the player stood between the faces.
- Spawns stay 32 px further out on the side a moving player runs away from (`spawn.trail_margin`; the camera lags
  ~29 px behind a running player, so mobs faded in there with up to 23 px of their body on screen).
- The EXP curve is steeper (section 5: 22% more EXP to Lv 30, 4% more to Lv 8), and touch damage is 0.7 of the first
  version's (0.35-0.525; the steeper curve alone killed 45 of 48 tuning runs: a build that levels slower is weaker
  against the same crowd). The Hill takes 1.0x EXP and touch damage 0.25-0.375, the Tree 0.85x EXP in that historical model.
- `balance_run.gd`'s stale share follows a mob across relocations (`mob_spawned.relocated_from`).

**Seeds.** Tuned on seeds 1-48 (henesys) and 1-24 (the other stages). The record below is the whole held-out range
101-130 plus the fresh seeds 201-212 that the verification added (42 seeds, never used for tuning), each run once with
the final data and code. The 209be82 and first-version columns are the verification's runs with the same
`balance_run.gd` (its stale share then restarted at relocations).

| henesys_hg1, held-out seeds 101-130 + 201-212 (42), `bot` | 209be82 | First version | After the follow-up |
|---|---|---|---|
| Engagement (400 x 200 px) at 6:00 / 9:00 / 12:00, median of 42 (range) | 8.5% (4-21) / 15% (5-42) / 21% (11-39) | 32% (18-54) / 41.5% (20-63) / 44% (26-70) | 34.5% (19-60) / 52% (21-61) / 58% (24-78) |
| The same on 101-130; on 201-212 | 9 / 17 / 20; 7.5 / 11 / 23 | 34.5 / 46 / 50; 26 / 35 / 39 | 36 / 53.5 / 58; 32 / 43.5 / 54 |
| Near the player (300 x 150 px) / alive, minutes 8-12 (medians) | 5-12% | 23-36% | 31.5-43% |
| Stale (20 s+ outside the box) at 6:00 / 9:00 / 12:00 | 3% / 4% / 3% | 0% / 0% / 0% (could not show off-screen idling) | 0% / 0% / 0% (relocated mobs keep their time) |
| Spawns recycled / relocated per spawn (median) | 9.5% / - | 0% / 32.5% | 0% / 34.5% |
| Alive at 4 / 6 / 8 / 9 / 12 / 14 min (median of the minute's mean) | 24 / 33 / 67.5 / 67 / 112.5 / 220 | 11 / 20 / 97 / 107.5 / 158 / 280.5 | 10 / 19 / 122 / 138 / 222.5 / 284 |
| Outcome | 27/42 cleared; deaths 8:57-14:40, 4 before 12:00 | 32/42 cleared; deaths 10:44-14:54, 3 before 12:00 | 29/42 cleared; deaths 10:27-14:42, 2 before 12:00 (10:27, 11:37) |
| Lv 8 / Lv 10 (median) | 2:46 (39/42 in 2:30-3:45) / 3:49 | 2:40 (41/42) / 3:34 | 2:42 (41/42) / 3:42 |
| Lv 30 (median of the runs reaching it) | 11:47; 36 reach it, 15 at 12:00 or later | 11:16; 38 reach it, 5 at 12:00 or later | 12:09 (11:30-14:19); 33 reach it, 22 at 12:00 or later |
| Lv 30 on 101-130; on 201-212 | 12:04; 11:42 | 11:19; 11:11 | 12:17; 12:07 |
| Level at 15:00 or death (median) | 35.5 | 38 | 34 |
| Hits before 6:00 / after 8:00 (median) | 1 / 27 | 0 / 100.5 | 0 / 146 |
| EXP lost to expired drops (median) | 13% | 7.5% | 5.5% |
| Careless player (`random`), seeds 201-212 | 1/12 cleared; deaths 5:47-13:15 | 2/12 cleared; deaths 7:12-14:17 | 3/12 cleared; deaths 9:39-13:11; Lv 8 median 2:53 (12/12 reach it) |

On the tuning seeds 1-48 the final data gives 35/48 clears (13 deaths, 4 before 12:00), Lv 8 at 2:44, Lv 30 at 12:14
(22 of 34 at 12:00 or later), engagement 34% / 50.5% / 64% (the first version's data with the follow-up's sim changes:
32/48 clears, Lv 30 at 11:22, 4 of 39 at 12:00 or later, engagement 37% / 44% / 55%).

Other stages, seeds 201-212, `bot` (209be82 -> first version -> after the follow-up): The Tree That Grew I 10 -> 12 ->
9 of 12 cleared (deaths after the follow-up 12:02, 14:11, 14:40), Lv 8 2:32 (9 in the window) -> 2:28 (3) -> 2:38
(12), Lv 30 10:35 -> 10:06 -> 11:49 (10 reach it, 3 at 12:00 or later), engagement 4.5% / 6% / 12% -> 24.5% / 27% /
32.5% -> 31.5% / 40.5% / 57%. The Hill East of Henesys 9 -> 11 -> 10 of 12 cleared (deaths 12:19, 14:38), Lv 8 3:05
(12 in the window) -> 3:00 (11) -> 3:11 (9; 2:45-4:46), Lv 30 12:32 (3 reach it) -> 10:41 (11) -> 11:43 (10, 2 at
12:00 or later), engagement 9.5% / 9.5% / 28% -> 40.5% / 55.5% / 58% -> 39.5% / 60.5% / 76.5%, EXP lost to expiry 57.5%
-> 12.5% -> 7%, hits after 8:00 10.5 -> 110 -> 206.5.

**On screen** (a headless probe that replays CameraRig: smoothing 6/s, 8 px dead zone, feet at 58%, x4 frames; the
verification's seeds 777, 113, 117, 201-206 on henesys and 201-203 on the other two; first version -> after the
follow-up): spawns fading in with part of the body on screen 49-102 -> 0-1 per henesys run (26-33 at 209be82), 141-196
-> 0 per Tree run, 30-123 -> 1-9 per Hill run; relocations landing partly on screen 2-12 -> 0-3 (henesys), 19-32 -> 0-2
(Tree), 11-26 -> 0-1 (Hill); relocations starting with any of the body on screen 0 -> 0; no mob airborne for 2.5 s.
Mobs standing at a wall across the Hill's ground (mob-seconds standing still for 5 s+ away from the player) on seeds
201 / 202 / 203: 22903 / 73777 / 48783 at 209be82, 8382 / 3766 / 0 in the first version (2680 / 1531 / 0 of them on
screen; 5087 off screen on 201 alone), 45 / 484 / 1006 after (43 / 405 / 864 on screen); on the tuning seeds 1-12 the
sim changes alone took the first version's 43645 such mob-seconds (21216 on screen) to 583 (149 on screen).

Reading: the crowd presses the player: about a third of it is within reach at 6:00 and over half from 9:00 on the 42
held-out seeds, against 8-21% before the swarm pass; nothing idles off-screen (stale 0% with relocated mobs keeping
their time), nothing is lost (relocation instead of recycling) and no mob appears or vanishes on screen. Engagement at
6:00 stays just under the 35-50% target (34.5% median; 32% on the fresh seeds 201-212): a strong build kills mobs as
they arrive, so before 6:00 the crowd is thin (10-19 alive, against 24-33 before the swarm pass, when mobs idled
off-screen) and the bot takes no hits; from 6:00 the crowd builds quickly (122 at 8:00). Lv 30 is back in the
~12:00-15:00 window on henesys (12:09 median, 22 of 33 runs at 12:00 or later); on the Hill (11:43) and the Tree
(11:49) it is 10-20 s short of its low edge. The price of the steeper curve is lighter touches: the kiting bot is
touched ~146 times after 8:00 (~27 before the swarm pass, ~100 in its first version), each for 0.7 of the first
version's damage; on the Hill ~200 times. The survival numbers are partly the bot's: about one run in ten starts
slowly (seed 101: the bot pinned against the map's right end with the swarm on one side, Lv 8 at 3:54), and late
deaths often come with the bot pinned at a map end. Seen in windowed playtests (`evidence/swarm2/s777_x4`, henesys
seed 777, CLEARED Lv 36, the same run as headless; `evidence/swarm2/hill_s202_x4`): at 6:00 a thin crowd (17 alive)
on the ground beside the player; from 8:00 the ground is packed on both sides; at 11:00 and 12:00 the bot stands at the
map's right end with a dense wall pressing from the left; at 14:00 it is surrounded (300 alive). Moving rows on the
long platform above the ground (mobs walking to its near drop, one mid-fall at 11:00) still show at 9:00, 11:00, 12:00
and 14:00; they are on their way in, not queueing. On the Hill the crowd presses the player along its own floor from
5:00 (a row of snails on a small platform above, mobs dropping in at the screen edge).

### 4.3 Boss encounter lifecycle (difficulty overhaul)

Henesys Hunting Ground I schedules Mano (2220000) at 5:00, Mushmom (6130101) at 10:00 and Blue Mushmom (9400205) at
15:00. The encounters use canonical movement, contact attack, art and enabled skill kits; the mushroom family
also uses its jump slam. The Tree schedules Stumpy, King Slime and Dyle at the same arrival times.
Each boss gives a 3 s warning, then arrives with the normal regen fade on the player's reachable platform, preferably
250 px away. A narrow floor may require a closer point. If no arrival point exists at all on the arrival tick, the
arrival slips by 3 s behind a fresh warning (tier C). A boss whose mob img is missing from the asset cache is skipped
with a run warning at its arrival time and never blocks the clear. Scheduled bosses never flinch or receive push,
whatever their WZ `info/boss` flag (tier C survivor rule; the tier A flag and the `no_flinch` override still apply to
their kinds), and ordinary relocation never removes them. Bosses the player runs away from remain until killed.

Survivor settings (tier C; canonical stats and attack timings/boxes remain unchanged):

| Boss | Canonical HP | Survivor HP | HP multiplier | Touch multiplier | Attack multiplier |
|---|---|---|---|---|---|
| Mano | 2,000 | 3,600 | 1.8 | 1.15 | — |
| Mushmom | 20,000 | 4,800 | 0.24 | 0.85 | 0.55 |
| Blue Mushmom | 200,000 | 7,000 | 0.035 | 0.48 | 0.72 |
| Stumpy | 7,000 | 3,150 | 0.45 | 0.83 | 0.77 |
| King Slime | 8,000 | 8,800 | 1.1 | 1.36 | 1.06 |
| Dyle | 31,000 | 8,060 | 0.26 | 1.14 | — |

Calibration uses measured training builds rather than the former assumed HP300/550/800 and full Armor defense.
`stage.bosses` stores the multipliers; `typical_hp/pdd` are illustrative inputs only, never adaptive runtime scaling.
The target is typical whole-hit source medians of 40–50%, with individual-hit/build variation reported separately.
At the documented `typical_hp`/`typical_pdd` the whole roll range of every contact hit and selected attack (85% and
100% of PAD after defense, rounded) lies in 40–50% (`test_boss_hit_bands`). The 2026-10-14 review pass moved six
multipliers by the smallest 0.01 step that does this (Blue Mushmom slam 0.70→0.72, Stumpy touch 0.8→0.83 and
attacks 0.74→0.77, King Slime touch 1.4→1.36 and slam 1.1→1.06, Dyle touch 1.15→1.14; medians moved at most 1.8
points); the measured results in 4.2 predate this change.
Completed fights target 30/60/90 seconds, each ±50%; unfinished encounters are not zero-duration observations.
`balance.bosses` stores warning time, placement and spawn reduction. The mobs a boss summons (MobSkill 200 at the
levels its `info/skill` lists) and its `info/revive` list are read from the canonical data at load time (`StageRoster`)
and loaded with the stage; `stages.json` never repeats these v83 lists.

While any boss lives, normal spawns run at half rate (spec). Bursts count as normal spawns, so both the steady spawn
rate and each burst's count halve (`balance.bosses.normal_spawn_mult` 0.5, burst count rounded; tier C reading of
the spec); elite scheduling stays independent.
Both stages continue the last rate/max-alive/HP/speed keyframe slopes at quarter pace after 15:00
(`post_duration_slope`), with ordinary mobs still capped by `hard_cap`. Burst size keeps its 10→40 slope over the
stage at the same quarter pace past 15:00, and the elite interval shrinks in proportion to the extrapolated spawn rate
(`every × rate(15:00) / rate(t)`), so elites stay the same share of the growing stream until the clear (tier C). Clearing requires every scheduled boss dead;
stages without a boss list retain their duration clear. Stage select states the applicable objective.

If a living boss has no route or makes no progress toward the player for 5 s, it fades out over 300 ms, then
relocates about 250 px away on the player's platform using the same placement policy. HP is preserved; it stands
still and cannot touch during fade-out or the normal 300 ms arrival fade. Progress means closing the route distance
by at least 1 px through its own movement; a boss already at the player does not relocate.

Boss deaths replace ordinary drops with a shower totaling rounded canonical boss EXP × survivor reward multiplier
(×5), split into 12 drops with no remainder lost, spread ±120 px. Default HP/MP bundles hold 3/3 potions of the
stock's current tier, separated by ±30 px. Mano overrides these to 6 HP/3 MP; Stumpy keeps 3 HP/3 MP, supporting
early builds. Both second bosses give 1 HP/3 MP, limiting later stock while ordinary HP supply stays scarce. The nested override includes
MP explicitly; EXP and reward geometry retain the global defaults. Ordinary potion rolls do not add to bundles. Each death
also grants one bonus upgrade pick, before any queued normal level pick, with no level gain or queued-level
consumption. Final clear waits for the choices to finish. The bonus window reads "Boss Reward" and has no gained-level
header. All reward and relocation values are tier C in `balance.bosses`; a schedule entry's `rewards` may override
reward defaults for tuning.

Presentation uses the original `UIWindow.img/MobGage` icon frame, gauge borders and colour strips, centred below
the timer; multiple surviving bosses keep separate rows. Names come from `String.wz`, HP comes from the swarm,
and colour indices come from canonical `info/hpTagColor` and `info/hpTagBgcolor`. Blue Mushmom lacks a v83 icon and
colour tags, so survivor `mobs.json.boss_ui` borrows Mushmom's icon and 1/5 colours (tier C). King Slime keeps its
canonical icon but receives the missing 1/5 colour tags (tier C). No WZ metadata is modified.
Warnings say "<name> will appear in 3 seconds!"; arrival replaces the warning with yellow "<name> has appeared!"
and the original `BasicEff.img/Summoned` effect at the boss. Selecting this effect and positioning the notices is
tier C; the effect frames, origins and 80 ms delays are tier A. Keyed notices sit above EXP and low-MP messages,
expire after the warning lead or 4 s after arrival, and cannot be evicted by EXP pickup traffic.

Mushmom and Blue Mushmom select their canonical `attack1` type-0 jumping attack: attack-local PADamage 300,
500×150 range (-250,-150) through (250,0), impact at `attackAfter = 1050 ms`, and `effectAfter = 0`. The boss holds
its captured ground anchor/facing during the 1.85 s stance (tier C anchoring); the apparent jump comes from the
original frame origins. The range mirrors with facing. A player body inside the captured area at impact takes the
physical hit through `take_hit`; when `jumpAttack` is set, being airborne at that moment avoids it (lore, tier C).
Leaving the area during the windup also avoids it. A boss killed before impact cannot finish the attack.
An intentional attack/skill stance resets pursuit stall rather than causing a teleport; a fading boss cannot
begin another action (tier C action/teleport coordination).
Windup art, sound and effect use original timings. The effect's ground-wave frames begin at 1.10 s, 50 ms after
the damage impact; neither timeline is retimed to conceal this canonical difference. Selected attacks repeat at
an initial 8 s start-to-start interval when in range and the shared action gate is free (tier C; WZ has no interval).

Slam scaling is separate from touch scaling because both mushrooms' slam attack is 300 while their contact attack
is 200 / 450. Mushmom and Blue Mushmom use separate attack scales 0.55/0.72 and contact scales 0.85/0.48,
calibrated against actual training HP pools. No attack-local canonical value is changed to achieve those fractions.
The `player_hit.source_kind` field distinguishes contact (`touch`) from these attack (`attack`) hits for metrics.
The handler is reusable for later Stumpy and King Slime type-0 attacks selected in their stage data.

The Tree That Grew I adds Stumpy (3220000) at 5:00, King Slime (9300003) at 10:00 and Dyle (6220000) at 15:00.
Stumpy uses HP ×0.45 (3,150), touch ×0.83 and attack ×0.77. Its selected attacks share an 8 s start-to-start cadence. The type-0 slam
keeps the 543×172 box and 1,500 ms attackAfter, including the same airborne dodge.
The type-2 ball keeps attack135, bulletSpeed140, range/r200, muzzle(6,-60) and 1,320 ms attackAfter. We adopt
`r ×600/bulletSpeed` ms maximum flight (857.14 ms), hence 233.33 px/s over 200 px. This conversion and using r
for acquisition/travel are tier C, inspired by the prose CMob comment in the later-client reference
`HaCreator/MapSimulator/Combat/MobAttackSystem.cs: ResolveProjectileTravelTimeMs`; that comment alone is not
verified v83 RE. Aim is at the current player body centre on launch; flight is straight, ignores terrain and
hits a swept body box grown by 8 px (tier C, survivor data). A ball is consumed on contact even if damage is
blocked or misses. Animation frames, origins, delays and sound remain canonical.
Stumpy's heal114/15 uses canonical HP gate80%, interval30 s and effectAfter1,500 ms. Following the spec ("restoring
the canonical amount"), each living mob in the canonical area regains exactly the canonical x (700), clamped to its
max HP; there is no random roll. The canonical y (200) is unused: its role in the v83 client is unverified (tier C;
an earlier build rolled uniformly between y and x after a later-client reference resolver). The original
mob0 effect retains its 1,100 ms blank lead-in; it plays from cast, while HP restores at the application delay.
The heal notice reports actual restored HP, and the boss bar follows it immediately. No reference source code
was copied. Encounter scaling is survivor data; all heal bounds, gates, intervals and effect timing stay canonical.

King Slime keeps canonical maxHP 8,000, touch 130 and slam 165. Survivor HP ×1.1 gives 8,800; touch ×1.36
and slam ×1.06 are separate training-calibrated scales. Its type 0 slam
uses canonical attackAfter 900 ms, effectAfter 300 ms, 500×150 area and jumpAttack 1; grounded players in the area
are hit only at impact, airborne players can dodge. Skill 200/2 waits 50 s, HP ≤50%, summons the original three
210100 Slimes with summonEffect 3, and caps living encounter-owned summons at 15. Its eleven-entry info/revive
list spawns eleven ordinary canonical Slimes on death, independently of that cast limit. Relocations preserve
ownership and fresh slots reset it. King Slime lacks info/boss and hpTag colours in v83: the survivor no_flinch
override and existing 1/5 MobGage colour override supply scheduled-boss behavior without modifying WZ facts.
Dyle retains canonical maxHP 31,000 (survivor ×0.26=8,060) and touch 190 (survivor ×1.14).
Heal 114/17 uses HP ≤90%, interval 20 s and effectAfter 0: restoration occurs on the casting tick. Each cast
restores the canonical x 5,000 (y 500 unused; tier C, the same rule as Stumpy), clamped at max HP.
Immunity 140/8 uses HP ≤80%, interval 30 s and duration 5 s. We interpret this as self
weapon immunity (tier C): basic swings and Three Snails shells are blocked at live impact time; magic remains
effective. A blocked shell consumes a contact/pierce hit without damage or crit RNG consumption (tier C).
The original repeat 1/pos 2 34×34 icon with origin (17,44) stays above Dyle's body and follows relocations;
body-top anchor mapping is tier C, art/origins are tier A. Status stops at expiration or death, never leaks
into a reused pool slot. Dyle's canonical 112/113 defense skills reuse the existing handlers; 110 is not enabled.
Death offspring use survivor summon_spacing 24 px on the death platform, with no new per-entity Nodes.
Source facts are the owner's original Mob.wz/9300003.img, Mob.wz/6220000.img and Skill.wz/MobSkill.img;
Local reference summaries: research/stage-bosses/out/bosses_3220000_5220002_9300003.json (King Slime),
bosses_5220000_6220000_8130100_3300008_3300005_9500326_9300187.json (Dyle), and the context mob-skills.txt.
Dyle's Tree Branch EXP icon is a tier-C existing stage icon, not a claim about its original drop table.

The balance harness continues until death/clear or `balance.run_time_cap` (initially 30:00, CLI `--cap` override).
An unfinished capped run is `TIMEOUT`, separately counted from deaths. Records include each boss's spawn/death
times and landed boss hits with whole damage, HP at impact and the damage/HP fraction. No survival/pacing claim
follows from the calibration table alone.

#### Additions beyond the spec (kept)

The spec (issue #1, tickets #3-#27) does not ask for these; each is kept and recorded here with its reason.

- **Time-varying ordinary HP potion chance** (`normal_hp_drop_chance` keyframes, tier C): early supply bridges weak
  Red-potion builds and late scarcity limits banking (section 5).
- **Per-boss `attack_interval`, `attack_dmg_mult` and `rewards` overrides** (tier C): WZ attack nodes carry no
  interval, so the 8 s cadence is ours; a slam's PAD differs from the contact PAD (300 against 200/450), so it needs
  its own scale to land in the 40-50% band; reward overrides support early builds (Mano 6 HP / 6 MP, Stumpy 3 HP / 6 MP) and
  limit later stock (second bosses 1 HP).
- **`balance.bot.card_scores`** (tier C): the sensible bot learns and ranks Magic Guard before another attack (scores
  110/109), as a sensible player facing 40-50% boss hits would; the careless policy stays uniform.
- **Retuned survivor EXP curve** `4 + 15L + 3.8L²` (tier C): V27 kept the Magician's exact 980 EXP cost (Mage near
  3:00) while the quadratic term carries the late game toward Lv 30 at 12:00-15:00 (section 5, 4.2).
- **Boss defense buffs reach ordinary mobs** (tier A area and values, tier C arithmetic): MobSkill 112/113 are v83
  area buffs (`lt`/`rb`), so Mano's, Stumpy's and Dyle's casts give their flat PDD/MDD to every living mob inside the
  canonical area for the canonical time, boss or not.
- **Extra events** (`boss_attack`, `mob_projectile_spawned`/`_hit`, `mob_healed`, `mob_revives_spawned`,
  `boss_teleported`, `potion_tier_up`, `mp_short`, `buff_cast`/`_expired`/`_pulse`): presentation and metrics seams of
  the specced systems with no gameplay effect of their own (schema in ARCHITECTURE.md 4.4.3).
- **Playtest default length 30:00** (tier C tooling): `scripts/playtest.sh` runs through the post-15:00 finale until a
  death or clear; documented in AGENTS.md and the script header.

## 5. Experience and levels

Potions are separate persistent pickups, pulled in by the same magnet as EXP. Stock is unlimited and a run starts
with five Red Potions (2000000) and no Blue Potions (2000003). Delete/Q drinks HP,
End/E drinks MP, once per press, instantly and without a cooldown even on a rope. Empty stock does nothing.
Restoration comes unchanged from canonical item `spec.hp`/`spec.mp` (Red 50 HP, Blue 100 MP), clamped to max.
Normal kills use a global fallback of HP 1.2% and MP 10% independently; elites roll HP 15% and MP 60%. With every
skill in its single-shot vanilla form at canonical MP, Blue Potions are the main MP income once regeneration (3 MP per
10 s) runs out; boss bundles stay 3 rather than 6. These choices and starter stock
are tier C data in `balance.potions`; potion rolls use a separate seeded stream. Potions never expire or enter the
EXP cap/absorption path. Both card policies drink a potion only when the missing HP or MP is at least half of one
current potion's canonical restore (`balance.potions.bot.min_restore_fraction`, tier C), so a sip never mostly
overflows the pool; a five-MP Beginner never drinks a 100-MP Blue.

The opening pool is the v83 Beginner's 50 HP / 5 MP (owner decision), with no ordinary level-up refill. Three
Snails at its canonical 3 MP therefore casts about once per 10 s regeneration pulse, and the Beginner phase is
sword-paced: the basic attack does most of the killing until Magician. Real-run sip restoration/waste is recorded
per event.
The optional stage-keyframe `normal_hp_drop_chance` / `normal_mp_drop_chance` fields are tier C survivor supply
tuning: clamp each endpoint to [0, 1], interpolate linearly, hold the nearest endpoint outside the range, and
substitute that kind's global normal chance for missing endpoints. Elite rolls and fixed boss bundles keep their
existing settings. Both curves are independent of card policy. The MP curve permits late scarcity while retaining
the v83 Beginner phase's existing supply and seeded behavior; changing a global MP chance also changes which
ground pickups the bot approaches during the opening.

Potion-tier score 112 prioritizes a useful permanent supply upgrade above Guard and attack cards. Learning a new
attack remains score 100; attack ranks/modifiers have maximum 87. The fallback 52 preserves callers without this field.
Only sensible choices use these scores; careless choices use their separate seeded card RNG.
Optional final card-score overrides set Guard learning to 110 and ranks to 109, without adding a job bonus. Missing
entries preserve legacy scoring. Guard learn/rank offer weights 8/8 improve availability; Orange/White offer
weights 30 make their eligible upgrades likely to appear. Snail count/cooldown/pierce weights 12/8/8 support the
Beginner; these are survivor choices, and the random policy still chooses uniformly among offered cards.
Current Henesys normal HP/MP supply follows the C46 endpoint table in section 4.1; both curves interpolate and hold.
Global normal MP remains 10%, elite MP 60%, with scheduled boss bundles unchanged. Tree retains its earlier 3% through 4:00, 0.6% at 6:00, 0% at 9:00/12:00,
0.6% at 13:00 and 0.8% at 15:00. These ordinary-drop
chances do not suppress elite or boss-bundle HP drops. Elite chances remain
global. Early supply bridges weak Red-potion builds; later scarcity limits banking without policy adaptation.
The quickslot shows each kind's current icon, stock count and keys; balance/perf records report collected and used
quantities per kind.

- Mobs drop their **signature Etc item** as an EXP pickup (icon from `Item.wz/Etc/0400.img/<id>/info/iconRaw`), with
  the classic drop pop (`Sound.wz/Game.img/DropItem`). Snail -> Snail Shell 4000019, Blue Snail -> Blue Snail Shell
  4000000, Red Snail -> Red Snail Shell 4000016, Shroom -> Mushroom Spore 4000011, Slime -> Slime Bubble 4000010,
  Pig -> Pig's Head 4000017, Orange Mushroom -> Orange Mushroom Cap 4000001, Green Mushroom -> Green Mushroom Cap
  4000012.
- Flyer EXP icons: Stirges use Stirge Wing 4000042, Flyeye uses Fly-Eye Wing 4000076, and Goblin Fire uses
  Firebomb Flame 4000081 as a tier C visual choice (not a claim about a canonical drop table).
- EXP value = the mob's canonical `exp` × 1.0 (× 5 for elites). Pickups within the magnet radius (90 px) fly to the
  player; collecting plays `Game.img/PickUpItem` and shows "+N EXP" in MapleStory's yellow system-message style.
- **Drops never expire** (owner decision 2026-10-14; `pickup.lifetime` = 0). At `pickup.max_active` (600), the EXP drop
  farthest from the player is absorbed into the new drop at the monster's death position. The combined EXP pops
  there with a fresh age, keeping the pool bounded and collection near recent kills; no EXP is lost.
- **Survivor EXP curve:** `exp_to_next(L) = round(4 + 15·L + 3.8·L²)` (L1 = 23, L7 = 295,
  L9 = 447, L29 = 3635; 980 EXP to reach Lv 8, 1794 to Lv 10, 39150 to Lv 30). Historical curves and their
  measurements remain in section 4.2. The quadratic term carries the late game: a strong build that levels
  fast meets steeper levels, which keeps the spread between builds small. Measured
  pace: section 4.2. The canonical v83 table (`data/canonical/exp_table.json`) is kept for reference and display
  only.
- **Level up:** the game pauses, `Effect.wz/BasicEff.img/LevelUp` plays on the character with `Game.img/LevelUp`, then
  the upgrade window opens. Several level-ups in a row queue their windows.
- **Attributes and AP** (tier C, survivor choices): start at STR 12, DEX 5, INT 4, LUK 4, with 5 AP per level.
  Beginners assign AP to STR. On advancement the AP earned above those base stats moves to the new job's primary
  stat (INT for Magician); subsequent AP goes there too. The job's nearest configured ancestor supplies the rule.
  All starting values, AP gains and primary-stat choices are in `balance.json/player`.
- **Stats per level** (tier C for HP/MP base growth): Beginner +14 HP / +10 MP; Magician +12 HP / +22 MP, plus
  `floor(INT/10)` MP using INT before that level's AP (tier B). Magic skill damage uses the resulting INT.
  Level-ups raise the maxima without restoring current HP or MP (`level_up_refill` = 0). The owned Improved MaxMP
  Increase passive is the exception: when Max MP grows it preserves current MP's fraction of the maximum, including
  growth from later levels and job grants. It never restores HP.
- **Defense and avoid**: W.DEF and M.DEF sum the worn starter equipment's canonical `incPDD` and `incMDD`, plus
  active defense modifiers. The starter outfit is W.DEF 7 (3 + 2 + 2), M.DEF 0 (tier A, v83 Character.wz).
  Avoidability is DEX × 0.25 + LUK × 0.5 + equipment `incEVA` (tier B, pre-Big-Bang formula compilations).

## 6. Combat

### 6.1 Player damage

- **Fixed-damage skills** (Three Snails) deal the canonical `fixdamage` of their skill level (10 / 25 / 40) × survivor
  damage multipliers.
- **Magic skills** use the classic community formula (tier C; the v83 client formula is in packed code):
  `MAX = ((MAG²/1000 + MAG)/30 + INT/200) × spellAttack`, `MIN = ((MAG²/1000 + MAG×mastery×0.9)/30 + INT/200) ×
  spellAttack`, where `MAG = INT + magic attack`, `spellAttack` = the skill's canonical `mad`, `mastery` =
  (10 + 5×`mastery` field)%. Rolled uniformly.
- **Critical hits:** base 0% (Beginner/Magician cannot crit in v83); upgrades may add crit (×1.5) as survivor modifiers.
  Crits use the `NoCri` digits and the `NoCri1/effect` burst.
- Mob defence: magic damage × (1 - MDD/(MDD+150)) (tier C, keeps early mobs readable).

### 6.1.1 Basic weapon attacks

The Beginner holds Sword 1302000 from the first frame; Magician holds Wooden Wand 1372005. Canonical equipment
info supplies Sword W.ATT17/speed4 and Wand W.ATT15/M.ATT23/speed6. Magic attack sums the worn equipment's
`incMAD`; survivor data only selects the weapon, never duplicates its canonical attack value.

After skill priority, a standing or airborne player automatically attacks when a monster intersects any of its
five facing stance afterimage boxes. Walking, climbing, a skill fired this tick or no reachable target prevents a new swing.
There is no movement lock. Each swing chooses uniformly among swingO1/O2/O3 and stabO1/O2 on its own seeded stream.
The chosen stance retains its own impact box: a shorter stance can miss an outer-range target. One live monster in
that box is hit: a scheduled boss first (#83), otherwise the nearest; a moving target may leave before impact. The interval is
`ceil(800 * (10 + attackSpeed) / 16 / 30) * 30 ms`: Sword720ms, Wand810ms (tier B). The first numbered afterimage
body frame supplies impact timing, summing earlier canonical body delays (tier A): Sword swingO1 frame2 starts at
450ms; stabO2 frame1 starts at350ms. Body delays remain canonical. Pending swings finish without locking motion.

Physical bounds (tier B, owner-provided pre-Big-Bang formula) are `MAX=(STR*k+DEX)*WATT/100` and
`MIN=(STR*k*0.9*0.1+DEX)*WATT/100`. Sword k=4; Wand swing k=4.4, stab k=3.2. With
`D=max(0,mobLevel-playerLevel)`, apply `MAX*(1-0.01D)-0.5PDD` and `MIN*(1-0.01D)-0.6PDD`, clamp each to1,
roll uniformly and round once. Starting STR12/DEX5 reaches STR22/DEX5 at Beginner Lv3 without balance changes;
Sword bounds then are 2.1964..15.81, so rounding to at least the unscaled Snail's 8HP has about61% probability.
The fixed-seed 1000-swing test checks at least50%. Variant0 for both below-Lv10 starter weapons, and normal sword/mace
spark family1 for swings / family2 for stabs, are tier C selections. Bounds, canvases, origins, alpha and sound
come directly from the imported v83 afterimage and Weapon images (tier A). Effects use the existing pooled renderer.

### 6.2 Damage to the player

- **Monster hits** (tier C, the owner's chosen formula, unverified for v83): roll uniformly from 85% to 100% of
  the source monster's PAD (MAD for magic attacks), then subtract `floor(0.75 × player defense)` (W.DEF for physical,
  M.DEF for magic). Apply `(1 − elemental resistance/100)`, then explicit elite/boss damage multipliers, round once
  to the nearest integer and enforce minimum 1. There is no hidden scale or time-based damage multiplier.
  Orange Mushroom PAD 42 versus W.DEF 7 yields 31–37; Green Mushroom PAD 82 yields 65–77, or 35–47 at W.DEF 47.
- **Avoid** (tier B, weakly sourced: a single owner-provided private-server wiki page, not corroborated): miss
  probability is `clamp(21.6 × player avoid / monster accuracy / 100, 0, 1)`; zero/missing accuracy disables the
  roll for synthetic data. A miss emits `player_hit` with `miss=true`, zero damage and zero
  MP absorption, draws the original violet MISS, and causes no knockback, invincibility or hurt expression.
- On a landed hit: `NoViolet` digits over the player, knockback 187.5 px/s away and a small hop (tier C), 0.3 s of no input,
  1.5 s invincibility with blinking (tier C).
- **Active Magic Guard** moves `x`% (canonical 11-80% by level) of damage to MP while MP lasts.
- Regeneration is a 10 s pulse: +10 HP (tier C, owner choice) and +3 MP (tier B, v83 recovery rule), capped at each
  maximum. Improved MP Recovery 2000000 adds `floor(character level × canonical skill level / 10)` MP (tier B).
  Interval, amounts and divisor live in `balance.regen`. Recovery's separate timed HoT replaces the old passive
  regen card. Pulses continue on ropes and ladders; paused ticks do not
  advance the timer, and partial pulse intervals survive skill/card changes.

### 6.3 Damage numbers

`Effect.wz/BasicEff.img`: dealt = `NoRed1` first digit + `NoRed0` rest; crit = `NoCri1`/`NoCri0`; taken = `NoViolet`.
Digit advance overlaps per v95 RE (tier B); 400 ms hold, then 600 ms fade while rising 30 px. Multiple hits on one mob
stack upward one line per number: 30 px above a normal number, 36 px above a (taller) critical one.

### 6.4 Mano's canonical kit

Mano 2220000 reads its original info/skill list and MobSkill levels, with no copied canonical tuning in survivor data.
The first use waits one full interval after spawn. HP above the canonical hp percentage holds a ready skill until the
first eligible tick; an omitted hp means 100% (tier C default). Respawn fade blocks new skills until fully visible.
One skill at a time plays skill1 for its canonical 1.5 seconds, holding its grounded position/facing through the shared
BossDirector action gate (tier C scheduling). Colliding readiness uses the original info/skill order. effectAfter is
zero for all four Mano entries, so statuses apply when the action starts. WZ intervals, durations, bounds and frames
are tier A; the interpretations below are tier C where stated.

| Skill / level | Interval | HP gate | Effect |
|---|---|---|---|
| Slow 126 / 7 | 15 s | omitted → 100% | 15 s; rectangle (-300,-120)..(300,120) from boss feet; x80 retains 80% upgraded speed (tier C owner choice), refreshes rather than stacks |
| Summon 200 / 78 | 10 s | 90% | 2 Snails 100100, 2 Blue Snails 100101, 2 Red Snails 130101; at most 30 living summons belonging to that encounter |
| Weapon defense 112 / 1 | 10 s | omitted → 100% | 30 s; rectangle (-300,-200)..(300,200); x85 adds 85 W.DEF to living mob feet inside, including Mano (tier C arithmetic) |
| Magic defense 113 / 1 | 10 s | omitted → 100% | Same area/duration; x85 adds 85 M.DEF (tier C arithmetic) |

Defense refreshes without stacking; Mano's canonical PDD20/MDD30 stay unchanged in the shared kind. Basic attacks,
instant magic and in-flight projectiles all use the slot's current defense at impact. Status survives relocation and
is reset when a new mob reuses a slot. Summon ownership uses the stable encounter index, survives ordinary relocation,
and counts only living slots, so dying/recycled summons free capacity and an unrelated slot occupant cannot count.
Full lists use the canonical order; a nearly full limit takes only remaining places. Summons use their unscaled canonical
HP and fade in normally. Survivor spacing is 24 px symmetrically on Mano's platform, clamped to its span (tier C).

Slow affected art is repeat-marked in WZ and loops while its sim status is active. Defense uses the original effect/mob0
art, and each summoned snail plays Effect.wz/Summon.img/1 selected by summonEffect1. Choosing that effect family and
placing pos1 at the player body top / pos3 at a mob's body center are tier C interpretations; art, origins and delays
remain canonical. No Summon.img sound1 exists, so summons use Mano's canonical Skill1 sound. All effects use pooled
canvas items. Evidence facts: original v83 Mob.wz/2220000 and Skill.wz/MobSkill.img; local research/stage-bosses/out/
bosses_2220000.json confirms the same fields. The real-import test checks the canonical rows and the summon art.

## 7. Skills (auto-cast and manual)

Shared skill-definition seams for spec #31 (no second-job content is enabled by these fields):

- Optional `cast: {"rule": "nearest"|"box"|"manual", "min_targets": 1}` resolves to
  `Loadout.stats().cast_rule` (empty when absent) and `cast_params` (the whole block). Absent/`nearest` keeps
  nearest-in-range attacks and `can_start_buff` admission. `manual` never auto-casts; unknown rules wait too.
  `box` admits at `min_targets` (tier C default 1), then hits up to `mob_count` targets once per `attack_count` line.
  Admission prepares targets before the existing single MP payment/cooldown/cast; later rules extend the same
  `SkillRunner._admit_cast` / `_resolve_cast` dispatches with their own admission/resolution functions.
- Canonical level `lt`/`rb` resolve to `has_box` and `box: Rect2`; `area` starts at 1.0 and scales both offsets.
  `skill_mod` effects with `stat: "area", op: "mul"` multiply that scale (the planned ×1.2 card step is tier C).
  `mob_count` reads canonical `mobCount` then applies existing `count` modifiers; legacy `count` stays unchanged.
  `RunWorld.skill_box_targets(box, filter = Callable())` anchors at player feet, mirrors canonical left-facing x
  offsets when facing right, broad-phases through the spatial hash and intersects live bodies. It returns all
  matches with scheduled bosses first (#83), then by body-centre distance from the cast origin, then slot. Minimum
  edges include touching bodies;
  maximum edges exclude them. Optional `filter(slot) -> bool` runs before sorting/capping.
- Optional `on_hit: {"status": "poison"|"freeze"|"slow", "chance_field": "prop", "duration_field": "time"}`
  reads canonical fields at the cast level (missing `chance_field`: guaranteed attempt; signed Slow `x` stays
  canonical). Projectiles retain that level in a packed array. Both impact paths call `RunWorld._on_player_hit`
  once per damaging line, apply the status through `MobSwarm.apply_status`, then invoke registered
  `add_hit_listener(callable)` listeners with `(slot, {skill, level, magic, damage, element})`, before HP/kill
  resolution. Damage is after elements; physical hits participate, poison ticks and zero-damage immunity do not.
  Existing zero-damage `mob_hit` events for elemental immunity are retained for compatibility with the existing
  tests/presentation; the hook is suppressed regardless of that legacy event.
  Listeners must consume RNG only when their effect can apply.
- Optional `absorb_mp: {"chance_field": "prop", "percent_field": "x"}` enables monster MP absorption on
  damaging magic hits. The listener visits owned skills in loadout (learned) order and reads these canonical
  fields at each passive's current level: chance in percent, transfer as a percent of the monster's maximum MP.
  It truncates to whole MP, caps at remaining monster MP and consumes no proc RNG unless a positive transfer
  is possible. Branch-exclusive MP Eater learn cards allow only one copy per normal run, so this order matches
  the previous fixed F/P, I/L, Cleric key scan after unowned skills were skipped. Synthetic multi-passive loadouts
  follow learned order. Canonical values, restoration and absorb events are unchanged.
- `RunWorld.restore_player(stat: String, amount: int, skill: String) -> int` caps positive HP/MP gains, updates
  public pools and emits `player_restored: {stat, amount, skill, pos}` only for an actual positive integer pool
  change. The returned amount matches the displayed pool gain (HP rounds up, MP down, as elsewhere). Recovery
  and potions retain their existing paths. `DamageNumbers.HP_GAIN` uses cached `BasicEff/NoBlue1` then `NoBlue0`;
  `MP_GAIN` uses the same art tinted cyan. These digit sets exist in the v83 cache (tier A); assigning Blue to HP
  recovery remains tier C because the cache does not prove usage. Without Blue, tinted Violet is the tier C
  fallback. RunScene draws restoration events above the player's head using the existing number pool/timing.

Survivor behaviour is in `data/survivor/skills.json`; the canonical numbers per skill level come from `Skill.wz`.
A skill's **rank equals its canonical skill level**: every rank table covers levels 1 through the v83 maximum,
without skips. Learning starts at level 1 and each rank card adds one level. Energy Bolt, Magic Claw, Magic Guard
and Magic Armor have 20 levels, Improved MP Recovery has 16, Fire Arrow has 30, and the Beginner skills have 3.
The smaller per-card steps are intentional; canonical skill values remain untouched.
All skills pay the canonical `mpCon` of their current skill level on each successful cast (tier A). Three Snails
costs 3 / 5 / 7 MP at skill levels 1 / 2 / 3 (`Skill.wz/000.img/skill/0001000/level/N/mpCon`). Each tick auto-casts at most
one skill, oldest-ready first; learned order breaks a tie. A ready skill without a target or sufficient MP waits
without restarting its cooldown. An unaffordable skill permits a later affordable skill to fire. A waiting skill emits `mp_short` once
per waiting episode, while `player_state.mp_short` keeps the warm-red "Not enough MP" HUD cue visible until casting
can resume (tier C presentation). No MP is charged while climbing or when no target exists.

While hanging on a rope or ladder, no new auto-action casts: skills, basic attacks and buff casting share
`RunWorld.can_cast()`. Cooldowns continue, so a ready skill fires on the first eligible tick after leaving the
rope or ladder. Already-launched projectiles, active buffs and passives keep applying. This is the owner-selected
climbing rule; tier C. The seeded camper probe parks on a rope at 1:00 and reports new casts and skill kills after
existing shots finish separately from carry-over projectile kills.

| Skill (id) | Job | Behaviour | Rank -> canonical level | Upgrades |
|---|---|---|---|---|
| Three Snails (1000) | Beginner | Throws one shell (`level/N/ball`) within 420 px every 1.1 s; 400 px/s; `level/N/hit/0` on impact; one canonical MP cost per cast | ranks 1-3 = levels 1-3: green -> blue -> red shell, 10 -> 25 -> 40 damage; the skill reaches level 2 at character Lv 3 and level 3 at Lv 6 on its own (`level_ranks`: the SP a v83 Beginner puts into it); there is no card for it (owner decision 2026-10-14: a card that only buys what Lv 6 gives for free is a wasted pick) | Additional Shell (+1 shell, ×4), Faster Snails (-12% cooldown, ×4), Piercing Shells (+1 pierce, ×3), Rapid Snails (+25% speed, ×3) |
| Recovery (1001) | Beginner | Auto-cast below the data HP threshold; heals `x` every 5 s for canonical duration, with canonical MP cost/cooldown | ranks 1–3 = canonical levels 1–3: 5/10/15 MP, 4/8/12 HP per pulse, 30 s duration, 120 s cooldown | learn, then two rank cards |
| Nimble Feet (1002) | Beginner | Targetless speed buff; canonical speed +10/+15/+20 for 4/8/12 s, costing 4/7/10 MP; 60 s cooldown from cast | ranks 1–3 = levels 1–3 | learn/rank |
| Energy Bolt (2001004) | Magician | One `ball` projectile every 0.9 s; 450 px/s; `hit/0`; one canonical MP cost per cast | ranks 1–20 = levels 1–20 | learn/rank; Extra Bolt (+1, ×3), Bolt Pierce (+1, ×2), Overcharge (+20% damage, ×3) |
| Magic Claw (2001005) | Magician | Instant 2-hit claw (`attackCount` 2) on the nearest mob within 260 px every 1.25 s; `effect` on caster, `hit/0` on target (`CharLevel` variant by level) | ranks 1–20 = levels 1–20 | learn/rank; Twin Claw (+1 target, ×2), Quick Claw (-12% cooldown, ×3) |
| Magic Guard (2001002) | Magician | Timed damage-to-MP split (`x`%) | ranks 1–20 = levels 1–20 | learn/rank |
| Magic Armor (2001003) | Magician | Timed PDD (`pdd`) | ranks 1–20 = levels 1–20 | learn/rank |
| Improved MP Recovery (2000000) | Magician | Adds `floor(character level × skill level / 10)` MP to each 10 s pulse | ranks 1–16 = levels 1–16 | learn/rank |
| Improved MaxMP Increase (2000001) | Magician | Passive: computed Max MP × `(1 + 0.02 × skill level)`, preserving current MP ratio on growth (tier C reinterpretation) | ranks 1–10 = levels 1–10 | learn/rank |
| Holy Arrow (2301005) | Cleric | Holy projectile at nearest mob: canonical mad/mastery/mpCon and element h; 1 s recast, 480 px reach, 520 px/s, radius 12 | ranks 1–30 = levels 1–30 | learn/rank; +1 projectile (3 steps), +1 pierce (2), cooldown ×0.88 (3); job 230 only |
| Heal (2301002) | Cleric | Instant self recovery below 50% HP OR holy damage to every undead intersecting canonical lt/rb; 2 s recast, canonical mpCon/hp; provisional historical stat-based recovery fit, exact v83 amount unresolved ([evidence](research/cleric-heal.md)) | ranks 1–30 = levels 1–30 | learn/rank only; job 230 only |
| Fire Arrow (2101004) | F/P Wizard | Nearest-target fire (`elemAttr f`) projectile every 1 s within 480 px, 520 px/s, radius 12 px, `shoot1` stance 0.8 s; canonical `mad`/`mastery`/`mpCon`, ball/hit/effect and Use sound | ranks 1–30 = levels 1–30 | learn/rank; Extra Fire Arrow (+1 shot, ×3), Fire Arrow Pierce (+1 pierce, ×2), Quick Fire Arrow (cooldown ×0.88, ×3) |
| Poison Breath (2101005) | F/P Wizard | Nearest-target poison (`elemAttr s`) projectile every 1.25 s within 450 px, 400 px/s, radius 14 px, `swingO3` stance 0.8 s; canonical `mad`/`mastery`/`mpCon`; `on_hit` applies poison with canonical `prop`% for `time`; cached ball/hit/effect and Use/Hit sounds | ranks 1–30 = levels 1–30 | learn/rank; Poison Breath Pierce (+1 pierce, ×3), Quick Poison Breath (cooldown ×0.88, ×3) |
| Meditation (2101001 / 2201001) | F/P / I/L Wizard | Self-only timed canonical `mad` -> magic attack; invalidates cached attack ranges on start/expiry | ranks 1–20 = levels 1–20 | branch-specific learn/rank only |
| Bless (2301004) | Cleric | One timed buff: canonical `pdd`, `mdd`, `acc`, `eva` -> weapon/magic defence, accuracy, avoid; accuracy is stored with no outgoing combat effect yet | ranks 1–20 = levels 1–20 | learn/rank only |
| Invincible (2301003) | Cleric | Canonical `x`% reduction of physical/touch damage before Magic Guard; magic damage unaffected | ranks 1–20 = levels 1–20 | learn/rank only |
| Slow (2101003 / 2201003) | F/P / I/L Wizard | At least 3 eligible unslowed mobs in canonical `lt`/`rb`; nearest-first up to `mobCount`, signed canonical `x` for `time`, 1 s recast delay | ranks 1–20 = levels 1–20 | branch-specific learn/rank only |

| Teleport (2101002 / 2201002 / 2301001; `teleport_fp` / `teleport_il` / `teleport_cleric`) | F/P / I/L / Cleric | Manual X: arrow direction, otherwise facing. Horizontal blink lands on a floor up to canonical range, stopped by walls/map limits; vertical blink needs a floor strictly above/below within range. Ground/air allowed; climbing blocks it. Successful blinks pay canonical MP and emit fixed departure/arrival effects and Use sound. Hold repeats every 0.3 s (tier C); invalid destinations and short MP spend nothing. HUD shows X and dims when unaffordable. | ranks 1-20 = levels 1-20; `mpCon` 60 to 13, `range` 130 to 150 px (tier A, all three books) | branch-specific learn and rank cards only; no grant or slot cap |
| MP Eater (2100000 / 2200000 / 2300000) | F/P Wizard / I/L Wizard / Cleric | Passive: each resolved magic hit may absorb canonical `x`% of the monster's max MP with canonical `prop`% chance; remaining monster MP and player Max MP cap the transfer | ranks 1–20 = levels 1–20, separate branch copies | learn/rank only |
| Cold Beam (2201004) | I/L Wizard | Instant ice hit on the nearest target within 300 px every 1.25 s; canonical `mad`/`mastery`/`mpCon`; guaranteed freeze attempt for canonical `time` (1–2 s), rejected by bosses and ice-status immunity; real `effect` and `hit/0`, no `ball` | ranks 1–30 = levels 1–30 | learn/rank; Spreading Frost (+1 target, 3 steps), Quick Frost (cooldown ×0.88, 3 steps) |
| Thunder Bolt (2201005) | I/L Wizard | Instant lightning hits when at least one monster intersects the canonical `lt`/`rb` box around the player's feet; up to canonical `mobCount` (6), nearest first, every 1.5 s; canonical damage/mastery/MP; real `effect` and `hit/0` | ranks 1–30 = levels 1–30 | learn/rank; Wider Storm (box offsets ×1.2, 3 steps), Quick Storm (cooldown ×0.88, 3 steps) |

MP Eater registers on the shared player-hit listener, after on-hit statuses and before lethal damage/kill handling.
It reads the passive's current canonical level at impact; physical basic attacks, Three Snails, poison pulses and
elementally immune hits cannot absorb. It consumes no proc RNG when unlearned, depleted, or unable to absorb even
one whole MP. Absorb truncates `maxMP × x / 100` to whole points (tier C integer interpretation), caps at remaining
monster MP, and drains that pool even when player MP is full. `restore_player` supplies the actual capped gain and
the shared `player_restored` MP number. A separate `mp_eater_absorbed: {mob, amount, skill, pos}` event shows the
canonical 700 ms effect on every absorb, including zero player gain; it does not duplicate the restoration event.
The cache has all three effects and icons. Original v83 Sound.wz has no MP Eater entry, so presentation quietly
probes for an optional use sound and otherwise stays silent without a missing-asset lookup.

Ice/Lightning attack cards require exactly job 220 and all eight learn/rank/behaviour cards are power cards.
Behaviour steps share the first-job Potential magnitudes and remaining-headroom clamp. Cold Beam uses the existing
`count` modifier (up to four distinct targets); Thunder Bolt uses `cast: {"rule": "box"}` and the shared `area`
modifier (up to ×1.728 on both canonical offsets). Cold Beam's `on_hit` block omits `chance_field`: every v83 level
has `x = -100` and `time`, with no `prop`. Freeze duration is canonical, and no separate proc or box path is added.
Both cached skills have no `action` node; selecting `swingO1` for a 0.8 s cast stance is tier C.

Fire/Poison attack cards require current job 210. Both learn/rank cards and all five behaviour cards are power
cards. Behaviour caps count modifier steps, so three Extra Fire Arrow steps produce four shots. Poison Breath
uses the shared on-hit status block and its projectile's cast-level snapshot; poison ticks, immunity and boss
rejection retain the status system's existing rules (section 3). Canonical poison duration is used unchanged,
including level 29's 58 seconds (level 30 has 40). Both attacks use their canonical skill-node elements, never a
survivor element override. Existing bot scores classify these projectile attacks and their cards automatically.

Targeting: nearest living mob within range (spatial hash query) of the body, excluding mobs already targeted this cast
when a skill fires several projectiles.
**Boss priority (#83):** in every targeting rule (nearest, box, crowd, Heal's undead box and the basic attack) a
scheduled boss (a BossDirector encounter; not elites or boss offspring) that qualifies takes target slots first;
the remaining slots fill nearest-first as before. The order is boss, then distance, then slot
(`RunWorld.targets_before`). Projectiles aim at the chosen targets, so the first shot flies at the boss, but still
hit whatever they cross first. Slow still rejects scheduled bosses (status immunity), so it never spends a slot on one. A shot starts at the throwing hand: 22 px in front of the body toward its
target (`player.cast_forward`), level with the cast origin, so the shell never covers the face. Projectiles fly straight toward the target's position at cast time and expire at their range.
Projectile speeds and ranges are tier C (no `speed` key exists in v83 `ball` nodes).
A piercing projectile can hit each logical mob once. Moving that mob through relocation does not grant a second
hit; a fresh mob using the same pool slot can still be hit. Run-local packed 64-bit spawn identities implement
this bookkeeping rule without changing canonical mob IDs, damage, pierce counts or flight tuning (tier C).

Casting does not stop movement. When standing still the character plays the skill's `action` stance (or `swingO1`)
for its frame time; while moving it keeps walking.

Guard and Armor auto-cast only when inactive, pay canonical MP cost, and last canonical `time` seconds at the
cast's skill level. L1 Guard costs 6 MP for 111 s at 11% absorption; L1 Armor costs 8 MP for 54 s at +2 PDD.
They recast on expiry when affordable. Their timers and effects continue while climbing; no cast starts there.
Effects are snapshots of the cast rank, so a rank upgrade changes the next cast. Active Guard alone splits damage;
active Armor alone adds its canonical PDD through the hit-defense hook. The HUD shows v83 skill icons and countdowns.
Rank cards preview duration, absorption/defense and MP cost. Both are passive-category skills without slot caps and share the one-cast-per-tick
readiness ordering with attacks. The alert2 stance comes from v83 skill action data; its 800 ms hold is tier C.

Second-job support (#58): `buff.effects` accepts multiple canonical stat/field pairs alongside legacy scalar
`stat`/`field`; every skill retains one timer/icon and snapshots all effects at cast rank. Meditation, Bless and
Invincible use their canonical `alert2`, effect and Use sound. Their self-only auto-cast, expiry, affordable recast
and climbing gate follow Guard/Armor. Bless's active avoid feeds each miss roll; active PDD/MDD feed hit defence.
Invincible scales the already-resolved whole weapon hit, rounds to nearest and keeps minimum 1 before Guard.
No player-accuracy formula is introduced: Bless `acc` is exposed in buff effects/player state, with no combat effect.

Slow uses the shared box query with a status-eligible, unslowed filter before charging MP. Canonical or scheduled
bosses cannot count toward the crowd. It applies through `MobSwarm.apply_status`, deals no hit damage and does not
invoke damaging-hit listeners. Tier A String.wz text limits consecutive uses on the same monsters to two; our
tier C auto-cast reading counts consecutive **successful Slow casts affecting each logical mob**, shared across
the two branch copies. A third consecutive application is ineligible until a successful Slow cast excludes that
mob. Time, other skill casts, insufficient MP and failed admission do not break that sequence. Relocation preserves
the history; fresh spawns reset it. The status interface itself still allows refresh for other callers.
Crowd threshold 3, cooldown 1 s, stance hold 0.8 s and card learn/rank weights 3/2 are untuned survivor choices.
All six skills retain the existing support bot scores (learn 50, rank 42 + current/ancestor job bonus 12), below
damaging attack cards. No behaviour cards are added.

## 8. Upgrades

`data/survivor/upgrades.json`. Each upgrade card has: `id`, `kind` (`skill_new`, `skill_rank`, `skill_mod`, `passive`,
`stat`, `potion_tier`, `filler` for the separate fallback), `skill` (for skill cards), `icon` (a WZ path, e.g. `Skill.wz/000.img/skill/0001000/icon`), `name`,
`desc` (with `{value}` placeholders), `max_rank`, `weight`, `requires` (job ids, owned skills, min skill rank, min
level), `effects` (`{"stat": "count", "op": "add", "value": 1}`).

Draw rules:

1. Eligible = requirements met and rank < max. `requires.jobs` matches the **exact current job id**, never its
   ancestors or descendants. Beginner skill cards (Three Snails changes, Recovery and Nimble Feet) require job 0;
   Magician skill cards require job 200. Earlier-job skills stay learned and keep casting at their retained rank,
   but their cards stop appearing. Job-neutral magnet and potion-tier cards omit `requires.jobs`.
   `skill_new` needs an unowned skill. Active and passive skill counts have no caps; only job eligibility and each skill's maximum rank bound the pool.
2. Three distinct cards are drawn by weight with the run's seeded RNG.
   **Pity:** cards that raise an attack skill's damage output carry `"power": true` (a new attack skill, its rank,
   more shots or targets, damage, cooldown). When a draw offered no power card, the next draw starts with one
   (`pity.draws` = 1), so a run's damage cannot stall on unlucky offers (a reviewed seed never saw an attack card
   before Lv 8 and fell behind for good). Both pity and the advancement draw select only eligible cards
   from the current pool; if no eligible power card exists, pity adds none.
3. With fewer than three eligible cards, offer those cards plus **one Power Elixir** alternative (item 2000005).
   With no eligible cards, offer Power Elixir alone. This applies to normal level-ups and boss rewards; every
   reward opens a window. `upgrades.fallback` holds the job-neutral Elixir definition outside the weighted pool,
   so it never displaces a normal card in a full draw. It uses the canonical Power Elixir name and icon and fully
   restores HP and MP immediately when chosen, without changing carried potion stock. This reward rule is tier C;
   the item identity, art and 100% restoration are tier A.
4. Applying a card takes effect immediately.
   Rank cards declare `max_rank` as the canonical skill cap; eligibility also checks the owned skill level.
   A skill learned at level 1 therefore needs N−1 **Normal** rank-card picks to reach level N; higher tiers grant
   several levels. The window marks the final skill level `MAX`, independently of consumed card steps.
5. The level-up window keeps the "You've gained a Level!" header and mascots, masks the baked-in skill-raising
   sentence for every card, and reads "LEVEL n". Rank cards show the canonical level change ("Skill Lv. 2 → 3")
   and before → after Magic ATT, mastery percent, MP cost and fixed damage when those fields exist in the skill's
   WZ level data. These previews use canonical values without survivor modifiers (tier A); mastery is converted
   with the combat formula in section 6.1.

### 8.1 Fortune and Potential tiers (#30 / #43)

Fortune is a survivor run stat in `player_state.fortune`, separate from canonical LUK. Its base is
`balance.player.fortune` (0); this spec adds no equipment or NX sources. It changes only card rarity, leaving
drop and critical rolls untouched. Every scalable offered card, including every advancement-draw skill, rolls a tier
using the existing seeded card RNG stream 3 after card identities are selected. A choice retains its final `tier`
and `magnitude` while pending; selecting its id applies that tier's ranks/steps.

| Potential tier | Normal | Rare | Epic | Unique | Legendary |
|---|---|---|---|---|---|
| Base weight at Fortune 0 | 75 | 18 | 5 | 1.7 | 0.3 |
| Skill rank gain | +1 | +2 | +3 | +5 | all remaining ranks |
| Stacking steps (`skill_mod`, `stat`, `passive`) | +1 | +2 | +3 | +4 | all remaining steps |
| New skill starting rank | 1 | 2 | 3 | 4 | 5 |

All numbers and rules in this table are tier C survivor choices. `upgrades.rarity.weights` stores the spec #30
weights (the owner restored them on 2026-10-15 after the C46 calibration had used 86/8/3.5/1.7/0.8; tuning waits for
the balance pass). Every non-Normal weight is multiplied by `1 + max(0, Fortune) × upgrades.rarity.fortune_scale`
(0.02), then weights normalize together: at Fortune 100 the weights total 150, i.e. 50/36/10/3.4/0.6%.
`upgrades.magnitudes` holds the per-kind tables; every default tier gives more than the one below it (owner,
2026-10-15). An individual card's `magnitudes` can override any tier, with unspecified tiers retaining their kind
defaults. Legendary can max a 20-rank attack or buff in one pick.

A card whose requested magnitude exceeds remaining headroom drops to the highest fitting tier, and any tier whose
gain equals a lower tier's (Legendary's `max` spending the last steps, or an equal per-card entry) wears the lowest
such label, so a label never overstates the card: a rank card at 17/20 rolling Legendary shows Epic (+3), at 15/20
Unique (+5), at 16/20 Legendary (+4); an Epic at 18/20 shows Rare (+2). Stacking cards cap at 2–4 steps, so a fresh
cap-2 card shows at most Rare, a cap-4 card at most Unique, and no current stacking card can show Legendary.
Nimble Feet and Recovery (3 ranks) learn at most at Epic. An unlimited stacking card downgrades a `max` roll to
its highest finite tier. All tier C.

Boss bonus rolls promote Normal to Rare before clamping. Scalable cards that cannot retain at least Rare are
omitted from boss draws (e.g. a skill rank card with only one rank remaining). Potion-tier cards and Power Elixir
are always Normal, including at bosses; sparse or exhausted rewards still offer the Elixir. Tier C.

Stacking magnitudes consume several card steps, preserving the card cap. Additive effects add their value once per
step; multiplicative effects compound (four cooldown ×0.88 steps reduce cooldown by 40.03%). Card text shows
compounded percentages to two decimals; application keeps full precision. `choice_card` previews the final skill
level and canonical before/after values at the complete gain; `rank_before/rank` show consumed card steps.

The balance record has `card_tiers_offered` and `card_tiers_picked` per run (displayed tier after clamping, one
count per card); the SYSTEMS summary sums them.

Level-up and boss-reward cards keep the v83 skill-row art and show the tier with a 2 px frame and a label band
tinted with the tier colour: Normal white, Rare blue, Epic purple, Unique gold, Legendary green
(`#FFFFFF / #77BBFF / #CC99FF / #FFCC44 / #77DD88` over `#17344F` at 30%; tier C). The label carries the meaning
independently of colour. New skills show their starting level in the rank line (`NEW  Skill Lv. 5`, plus `MAX` when
that is the cap). Unchanged canonical values are omitted from the preview. Dense windows shorten prose first and
keep the panel 128 px shorter than the view so the mascots and HUD stay clear (tier C layout).

A window with a Unique or Legendary offer plays `Sound.wz/Game.img/mCardGet` once when it opens (owner-approved by
ear on 2026-10-15; `EnchantSuccess` is reserved for future scrolling). Automated picks without a window are silent.
The debug gallery shows the tiers with `--window=levelup_tiers|levelup_high|levelup_dense` (`--bonus` for the boss
heading); screenshots stay in ignored `evidence/spec30/ui/`.

Beginner cards include Nimble Feet (1002) and Recovery (1001) learn/rank cards. Nimble Feet occupies a passive slot
and auto-casts when inactive, off its canonical cooldown and affordable. It keeps the cast level's canonical speed
bonus for the canonical duration, shows the v83 buff icon/countdown, and pays canonical MP. The 60-second cooldown
starts on cast: expiry after 4/8/12 seconds leaves 56/52/48 seconds before it is ready again. No cast starts while
climbing; its active effect and cooldown keep advancing there. Its original effect/sound/icon are used; no stance
is imposed because v83 provides no action node. Auto-casting and slot/lifecycle rules are tier C; the skill values
and assets are tier A. The former flat +6 speed card and Max HP +10% card are removed.

Magnet's Normal step is +25% radius and stays job-neutral. Magicians learn Improved MaxMP Increase (2000001) at
their card's starting rank and rank it through level 10 with the tier gains above. Its tier C, owner-selected reinterpretation multiplies the computed Max MP
(level growth, Magician INT/10 growth and job grant included) by `1 + 0.02 × skill level`, rounded once to whole MP.
This is +2% through +20%, recalculated from the base on every recompute rather than compounded or granted once.
Current MP keeps its ratio when the maximum grows from learning/ranking, level growth or a job grant. The canonical
skill instead raises MP gained per level; no canonical values are edited. The old flat +25 Max MP card is removed.
Rank previews show the survivor Max MP percentage rather than the canonical per-level gain.

Improved MP Recovery (2000000) is an owned canonical passive skill, learned/ranked by the tier tables through level 16,
adding the level-scaled pulse bonus in section 6.2.

Recovery casts only below 50% HP and when off cooldown, paying canonical MP. Its duration is 30 seconds, with
six pulses at 5/10/15/20/25/30 seconds; the last heals before expiry. The 5-second interval and `x × 6` reading are
tier C interpretation, recorded with the threshold in `skills.recovery.buff`; MP cost, `time`, `x` and `cooltime`
are unchanged v83 values. The 120-second cooldown starts at cast, so the inactive wait after the HoT is 90 seconds.
No cast starts on a rope, while an existing Recovery continues healing and expires there. Its original cast effect,
sound and icon are used; rank previews show duration, HP per pulse, cooldown and MP cost. Learning/ranking Recovery
never adds permanent HP regeneration, and the skill remains available after advancement.

Potion tiers are one-time cards: HP Red (2000000) → Orange (2000001) from Lv 10 → White (2000002) from Lv 25;
MP Blue (2000003) → Mana Elixir (2000006) from Lv 20. Each requires its previous item, preserves the entire stock
count and changes all future drops of that kind. The current item drives canonical restoration and the HUD icon.
The ladders, level gates and weights are tier C entries in `upgrades.json` (`potion_kind`, `item_id`,
`requires.potions`, `requires.min_level`); no canonical item value is changed. The sensible bot scores tier cards at
the configured `potions.bot.tier_score` (currently 112), with fallback 52 when absent; first/random policies can
offer and take them normally.

Skill prerequisites (`Skill.wz` `req`) are ignored (tier C owner decision #31). Cards retain their exact
job requirement and rank/modifier cards still require the skill they upgrade. Skills learned in an earlier job keep
working after advancement; their job-restricted cards leave the pool.

Accepting any job opens an **advancement draw** before the normal level draw, without consuming the queued level.
It offers every eligible new attack (`skill_new`, `power: true`, `requires.jobs` containing the new job), even if there
are more than three. If fewer than three attacks exist, seeded weighted draws fill the remaining places with that
job's other eligible new skills. Sparse draws include one Power Elixir; an exhausted job pool offers it alone.
Each scalable card rolls the usual rarity tier and contributes to offered/picked tier telemetry. No skill is granted.
`choice_pending.advancement` identifies this draw independently of `bonus`; the window reads "Job Advancement".
"Not now" goes directly to the normal level draw.


## 9. Jobs

`data/canonical/jobs.json` holds the Explorer tree with canonical ids (Beginner 0; Warrior 100, Magician 200,
Bowman 300, Thief 400, Pirate 500; second jobs 110-130 / 210-230 / 310-320 / 410-420 / 510-520; third and fourth
jobs). `data/survivor/jobs.json` marks which are playable in this build and what advancing grants. Its optional
`level` overrides the advancement level for survivor mode. Magician uses 10 (tier C, owner choice, #40);
the canonical record keeps level 8 and INT 20. Existing INT handling is unchanged: advancement redistributes
earned AP to INT rather than adding a stat eligibility gate.

At an advancement level the level-up window is preceded by the **Job Advancement** window (UI.wz window frame, job
book name from `String.wz/Skill.img/<job>/bookName`, `BasicEff.img/JobChanged` + `Game.img/JobChanged` on accept):

- Levels 8–9: ordinary upgrade choices; no job window.
- Level 10: Magician is playable; Warrior, Bowman, Thief and Pirate are shown as "not in this build".
  "Not now" keeps you a Beginner and asks again next level.
- Advancing to Magician changes job to 200 and keeps the existing +120 Max MP bonus; it teaches no skill.
  The extra advancement draw includes Energy Bolt, Magic Claw and one other new Magician skill before the normal draw.
- The JobChanged pillar and sound play on the character first; the advancement draw opens once the effect has
  played (~1.3 s), then the level's normal draw follows. A level-up window opens 1.2 s into the LevelUp effect.
- Level 30: Wizard (Fire, Poison) 210, Wizard (Ice, Lightning) 220 and Cleric 230 are all selectable at their canonical
  level. Each adds +475 Max MP and teaches no skill. This fixed tier C bonus is the midpoint of the 450-500 range
  in the v83 server reimplementation reference, **unverified against GMS** ([research](research/cosmic-data.md),
  job-change rewards, `client/Character.java:1204` in the local reference). It does not claim a tier B native-client fact.
- The bot uses its independent seeded branch stream (8), leaving card and combat streams separate; a single available
  job consumes no branch roll. `balance.sh` and `playtest.sh --branch=210|220|230` force an available branch. Run records
  store `branch` (0 before second job), and balance summaries group outcomes by branch; legacy records are unobserved.
- Skill counts have no caps. The owned-skill HUD uses eight 24 px icons per row, 4 px gaps, so about fifteen icons
  fit left of the timer and boss bars at the minimum 800 px view (tier C layout).

## 10. Presentation

- 800x600 logical view (wider windows show more map at the same pixel scale), integer scaling, nearest filtering. An
  opt-in "fill window" setting fills large windows with more map instead of black bars (see View fit below).
- HUD: independent status-bar, counter, skill-icon and message widgets receive state from RunScene. The original
  gauges, level, job name, timer, kill count and skill icons keep their layout. Decorative controls on the bar's
  right side are removed to reserve a potion quickslot; separate buff and boss widgets reserve space below the
  kill count and timer. Full-run pacing and structural checks cover progression, EXP collection, Magician
  advancement, boss-only completion, late ordinary hits and no lost mobs (4.1.1).
- Text uses the system's Arial-like font without antialiasing at MapleStory sizes (no fonts are shipped).
- Map name and street name from `String.wz/Map.img` on the stage card and at run start.
- Death: `Effect.wz/Tomb.img` tombstone falls on the character with `Game.img/Tombstone`.
- Results: RETRY is the v83 mini-game's green button (`UIWindow.img/RpsGame/BtRetry`), Back the login book's banner.
- Frame rate: vsync on and capped at the display's refresh rate (`Settings` `[display] max_fps`; 0 = refresh rate,
  -1 = uncapped); `--vsync=off` uncaps it for perf runs.

## 11. Constants and provenance

| Constant | Value | Tier | Source |
|---|---|---|---|
| Teleport costs, range, effect and sound | canonical `mpCon`/`range` at owned rank; BasicEff/Teleport four 80 ms frames; branch Skill Use sound | A | local v83 cache and `docs/research/wz-inventory.md` section 7 |
| Teleport repeat and destination policy | 0.3 s between successful blinks; vertical input wins diagonals, opposite directions cancel to facing; horizontal chooses furthest supported point, snaps at most one canonical range vertically, closest height breaks ties; stops EPS (0.01 px) before walls; landing resets velocity | C | ours; `skills.json.teleport`, FootholdMap and RunWorld |
| Teleport autoplay and HUD | same-height threats (existing duel band, feet +/-40 px): blink within 60 px, or when mobs block both sides within existing 160 px flee distance. An edge within 60 px plus a threat within 60 px on the interior side escapes toward the interior; otherwise choose the safer side. Requires learned skill, reserve, interval and a destination. HUD tint 0.35 grey; 80 ms evidence capture delay | C | ours; BotInput, HudSkills, RunScene |
| Bot Teleport MP reserve | after canonical cost, retain max(25% max MP, 2 x highest MP cost among learned automatic attacks); buffs, passives and manual skills excluded | C | a priori policy: preserve one attack plus an equal combat margin; the quarter-pool floor leaves MP for Magic Guard even with cheap attacks; `BotInput.TELEPORT_MP_RESERVE_FRACTION` / `TELEPORT_ATTACK_RESERVE_CASTS` |
| Bot Teleport interval | at least 5 simulation seconds between valid-destination escape requests, recorded in bot memo | C | a priori policy: allow several auto-cast cycles and ordinary kiting before another emergency blink; independent of the player's 0.3 s repeat; `BotInput.TELEPORT_MIN_INTERVAL` |
| Teleport card weights | new/rank weight 2, max rank 20; no behaviour modifiers | C | ours; upgrades.json |
| Physics.img values | see `docs/research/wz-inventory.md` §2 | A | v83 Map.wz |
| Potion restore amounts and icons | Red 50 HP, Orange 150 HP, White 300 HP, Blue 100 MP, Mana Elixir 300 MP | A | Item.wz/Consume/0200.img, unchanged spec/info |
| Potion stock, drop chances and bot drinking | start 5 Red/0 Blue; normal HP .012 fallback (stage curve in §5)/MP .10, elite HP .15/MP .60; the bot drinks only when the missing amount is at least half of one current potion's restore; persistent drops, unlimited stock, no drink cooldown | C | ours; balance.potions |
| Ordinary HP supply curve | Optional stage-keyframe chance, endpoint clamping, linear interpolation, global fallback per missing endpoint and endpoint holding outside the range | C | ours; SpawnDirector.normal_hp_drop_chance_at |
| Ordinary MP supply curve | Optional `normal_mp_drop_chance` stage endpoints; the same clamp, interpolation, per-endpoint global fallback and endpoint holding as HP; no effect on elite rolls or fixed boss bundles | C | ours; SpawnDirector.normal_mp_drop_chance_at; #30 calibration preserves opening supply |
| Potion quickslot geometry | two slots, 104 px apart within the 221 × 59 area | C | ours; HudPotionQuickslot |
| Walk/jump/air/down-jump/landing model | §3 | B | NoLifeStory physics description |
| Player sub-step | 2 per 1/60 s tick | C | ours |
| Vertical air drag | none (apex 555²/4000 = 77 px) | C | ours; NoLifeStory's 100 px/s² vertical float drag would give ~73 px |
| Climb speed | 100 px/s | C | ours (HeavenClient uses 125) |
| Ladder grab/exit | Up: hands 50 px above the feet within 10 px of x; Down: 10 px below the feet; 0.25 s re-grab delay; exit jump vx = max walk speed, vy = jumpSpeed/1.5; `uf=1` top exit onto a floor within 24 px above / 4 px below the top | C | ours / HeavenClient exit jump |
| Same-map portal activation and arrival | feet x ±25, y −100…+25; arrive 30 px above target with zero velocity; global cooldown 384 ms; camera snaps, no sound or transition | C | owner choice; `balance.json.portals` |
| Autoplay portal choice | approach a same-map entrance when its walk plus arrival-to-drop distance is less than going directly (horizontal distance + 2 × vertical); with a mob within 160 px, an entrance within 250 px can instead lead to less nearby mob danger. Reach entrance ledges through existing jump-graph edges; hold Up in the activation box and during the entrance hop | C | ours; uses the bot's existing drop, danger and alignment rules |
| Down-jump reach | a floor within 600 px below | C | HeavenClient |
| Player knockback hop, alert stance | 200 px/s up, 2 s | C | ours |
| Player placement | `PlayerMotion.place()` snaps onto a floor at most 1 px below, else the player falls | C | ours |
| Falling out of the world | below the MapBounds bottom the player is put back on the nearest floor (`EV_FELL_OUT`) | C | ours |
| Wall probe | a wall blocks where it covers the point 1 px above the feet (a wall hanging below a platform end can be walked off) | C | ours |
| Ceilings (x1 > x2) | stop upward motion at the feet (head bump), never landed on; mobs never hop straight up through one | B | NoLifeStory description (prior-art.md §1b) |
| Map bounds without VR | miniMap rect (-centerX, -centerY, width, height), else foothold box with top -300 / bottom +100 | C | ours / HeavenClient border rule |
| Mob nav (`NavGraph`) | hop 555 px/s, jump height ≤ 70 px, takeoff ≤ 90 px from landing, land 8 px inside; a drop steps off the end at 120 px/s for 4 px, then falls straight down (the same for every mob, so the graph predicts its landing exactly) | C | ours |
| Mob way (travel-cost field) | mobs take the way of least walking to the player's x, a drop or hop counting 40 px (`edge_cost`, about a fall's time; not the fewest edges); the field is rebuilt when the player moves 16 px (`target_step`); a mob keeps its way until another is 96 px shorter (`route_hysteresis`); a straight-up hop takes off at the point of its range nearest to where the way goes on | C | ours |
| Low step | a walker on a floor at most 40 px below the player's feet (`reach_y`, about a mob's height: it can touch the player from there) walks under the player instead of having no way; jumpers hop onto the step | C | ours |
| Mob stop distance | a mob on the player's platform stops 2 px from the player's x | C | ours |
| Mob regen fade | 0.3 s, standing still meanwhile | C | ours |
| Mob fallbacks | die time 0.5 s without `die1`; hitbox (-20,-40)-(20,0) without `lt/rb` | C | ours |
| Mob speed | (speed+100) × 0.625 px/s | C | HeavenClient terminal speed |
| Mob hit stun / push | 0.24 s / 12 px | C | HeavenClient / ours |
| Mob Slow magnitude/duration | signed canonical x; speed × clamp((100+x)/100,0,1); canonical time | A fields / C steering integration | original Skill.wz/210.img/2101003; [status research](research/monster-status-effects.md) |
| Mob status refresh/lifecycle | independent statuses; refresh duration without stacking; poison restarts pulse; clear silently on death/release/relocation; natural expiry event; pause holds timers | C | #54 interface policy; double timers expire at fixed-tick boundaries (1e-9 s numerical tolerance) |
| Mob poison HP rule | min(32767, ceil(slot max HP/(70-skill level))); 1 HP floor; no stun/push; actual player damage credit | C | Cosmic v83 server reference, not native-client RE; [pinned sources and limits](research/monster-status-effects.md) |
| Mob poison cadence | 1 s; first after 1 s, final pulse at expiry when due | B v95 display / C sim boundary policy | native-derived v95 CMob::Update; Cosmic schedules 1 s; [status research](research/monster-status-effects.md) |
| Mob Freeze behavior | no walking, facing changes, attacks, skills, stun/push or animation advance; lethal hits still die; an airborne monster still falls straight down and a fading-in one keeps fading in | B v95 extrapolation / C animation-hit integration and owner fall/fade choice | native-derived IsImmovable, TryDoingSkill, DoAttack; [status research](research/monster-status-effects.md) |
| Frozen touch damage | a frozen monster deals no touch damage (MobSwarm.can_act gates touch) | C | owner decision; no native v83 contact gate verified either way; [status research](research/monster-status-effects.md) |
| Boss status immunity | scheduled steady or canonical boss: reject Slow, Poison and Freeze | C | v83 server reference (Cosmic Monster.applyStatus boss gate), owner decision replacing #54's boss-poison permission |
| Elemental status immunity | a status fails on Mob elemAttr digit 1 (immune), 2 (strong) or 4 (neutral) for its element: Poison S, Freeze I (or the applying skill's element); Slow elementless | A element letters / C rejection rule | Poison Breath elemAttr s and Cold Beam i in Skill.wz; rejection per Cosmic Monster.applyStatus; [status research](research/monster-status-effects.md) |
| Player elemental hits / undead | Mob elemAttr digit1 ×0, digit2 ×0.5, digit3 ×1.5; absent/elementless ×1; final rounding; undead exposed independently | A factors/flags; C rounding integration | original Cold Beam String.wz text and Mob.wz; [status research](research/monster-status-effects.md) |
| Mob status cues | Slow one-shot cached mob art, Poison repeat art; pos3 centre/pos2 top; Slow amber (1,.72,.40), Freeze cyan (.45,.80,1), fallback Poison violet (.72,.45,.90) | A art / C anchors and tint choices | original Skill.wz/210.img, Cold Beam has no mob overlay; [status research](research/monster-status-effects.md) |
| Default frame delay | 100 ms | C | HeavenClient |
| Background scroll | rx × 5 px/s | B | 3 reimplementations agree |
| Damage number timing | 400 ms hold + 600 ms fade, 30 px rise | B | v95 RE (Harepacker docs) |
| Player knockback | 187.5 px/s, 0.3 s lock | C | HeavenClient |
| Invincibility after hit | 1.5 s | C | ours |
| Mano slow / defense interpretation | x80 retains 80% speed; x85 adds flat PDD/MDD, refreshed without stacking | C | owner-selected slow; explicit defense arithmetic interpretation, not verified client code |
| Boss skill first use | every enabled boss skill (all six bosses) first becomes ready one canonical `interval` after the boss arrives, then one interval after each cast; never on the arrival tick | C (timing rule), A (intervals) | ours; MobSkillRunner; original v83 MobSkill.img intervals |
| Boss defense buff recipients | MobSkill 112/113 give their flat PDD/MDD to every living mob inside the canonical area (ordinary mobs included) for the canonical time | A (area, x, time), C (flat arithmetic) | v83 MobSkill.img area buffs; MobSkillRunner |
| Mano skill scheduling / summons | first use after interval, one canonical stance at a time; omitted hp100%; 24 px symmetric spawn spacing | C (policy/spacing), A (intervals/list/limit/art) | ours; original v83 WZ |
| MobSkill effect anchors / summon family | affected pos1 at body top, effect pos3 at mob center; summonEffect1 selects Effect.wz/Summon.img/1 | C (mapping/placement), A (art/origins/delays) | ours; original v83 WZ |
| Basic physical damage / interval | §6.1.1; Sword k4, Wand swing4.4/stab3.2, mastery0.1; quantized speed interval | B | owner-provided pre-Big-Bang mechanics |
| Starter afterimage / sparks | variant0; sword/mace normal spark1 swing / spark2 stab | C (selection), A (art/bounds/delays) | ours; original v83 WZ |
| Magic damage formula | §6.1 | C | community formula |
| Monster-to-player damage | attack × uniform[0.85,1] − floor(0.75 × defense), elemental resistance, explicit source multipliers, rounded, minimum 1 (§6.2) | C | owner's choice; not verified in the v83 client |
| Monster miss chance | 21.6 × player avoid / mob accuracy percent, clamped 0–100% | B | weak: a single private-server wiki page describing pre-Big-Bang RE (owner-provided), not corroborated by a second source |
| Elite damage | ×1.5 after defense/resistance, before final rounding | C | survivor choice in stage elites.damage_mult |
| Boss arrivals and scaling | both stages at 5/10/15 min; HP/contact/attack multipliers in §4.3 | C | survivor data calibrated on training runs; canonical base stats unchanged |
| Normal spawns during a boss | while any boss lives the steady spawn rate and every burst's count are ×0.5 (bursts are normal spawns; count rounded); elites unchanged | C | spec "normal spawns run at half rate", our reading that bursts are normal spawns; balance.bosses.normal_spawn_mult |
| Boss warning / placement / pressure | 3 s lead; no arrival point on the arrival tick: slip 3 s behind a fresh warning; missing mob img: skipped with a run warning; preferred 250 px, minimum 150 px (closer fallback on narrow floors); ordinary rate/bursts ×0.5 while a boss lives | C | survivor choices in balance.bosses |
| Boss relocation | no route/progress for 5 s; progress requires 1 px of own movement and route gain; 300 ms fade-out, ~250 px platform arrival with ordinary harmless regen | C | owner rule; balance.bosses |
| Boss rewards | canonical EXP ×5 in 12 drops, spread ±120 px; current-tier HP3/MP3 bundles (Mano HP6, second bosses HP1; MP3 throughout) at ±30 px; one bonus upgrade before clear, preserving level queue | C (multipliers/design); A (base EXP) | survivor reward data; v83 Mob.wz |
| Bonus choice layout | first row at 52 px below reward title/instruction, canonical card rows and panel fill | C | ours; LevelUpWindow |
| Boss stun and push immunity | every scheduled boss: no stun/push, regardless of pushed or info/boss; kinds with info/boss or `no_flinch` also never flinch | A flag / C behavior | v83 info/boss, survivor encounter rule (`MobSwarm.steady`) |
| Mushroom slam cadence / scaling / dodge | 8 s; separate attack ×0.55 / ×0.72; airborne at impact dodges jumpAttack; captured ground anchor/facing | C | survivor choice and lore; canonical attack300, range, attackAfter1050ms, frames and effectAfter0 are A |
| Stumpy HP/contact/attack | ×0.45 / ×0.83 / ×0.77; attacks every 8 s when eligible; Tree Branch EXP icon | C | training calibration; canonical stats/art A |
| King Slime / Dyle HP and hit scaling | HP ×1.1/×0.26; King touch×1.36/slam×1.06, Dyle touch×1.14; King8s cadence | C | training calibration; canonical stats and attack delays A |
| King Slime stance / death list | no_flinch override;24px offspring spacing, unconditional canonical eleven-entry revive list | C (stance/placement), A (list/IDs) | ours; original v83 info/boss absent, info/revive untouched |
| Dyle heal / weapon immunity | canonical x 5,000 heal (y unused); timed self physical immunity, consumed blocked shell; pos2 body-top anchor; Tree Branch EXP icon | C (interpretations), A (bounds/gates/durations/art) | ours; original Skill114/17 and140/8; spec "canonical amount" |
| Monster ball flight / collision | bulletSpeed×1000/600 px/s, range/r lifetime, straight aimed launch;8 px contact radius | C | later-client reference comment inspires interpretation; original v83 values A |
| Mob heal arithmetic / timing / art anchor | each mob in the canonical area regains exactly canonical x, clamped to max HP; y unused; no RNG; effectAfter application; mob0 starts at cast, pos0 at feet | C (interpretation/anchor), A (fields/art) | spec "canonical amount"; original v83 WZ |
| Slam evidence screenshots | windup at 0.85 s; ground wave 0.12 s after impact | C | presentation capture timings only |
| Post-finale ramp / harness cap | final keyframe slopes ×0.25 after 15:00; burst size slope ×0.25 past the duration; elite interval × rate(last keyframe) / rate(t); 30:00 cap reported as timeout | C | survivor stage/balance data |
| First MISS screenshot | 0.05 presentation seconds after the first miss, only when screenshots are enabled | C | evidence capture timing |
| Projectile speeds/ranges | §7 | C | ours |
| Projectile hit exclusion identity | packed 64-bit run-local spawn identity; fresh spawns differ, relocation preserves it | C | our pool bookkeeping; no canonical or balance values changed |
| Camera smoothing | exponential, 6/s, 8 px dead zone, player at 58% height | C | ours |
| Player start | 50 HP, 5 MP (v83 Beginner, owner decision), STR 12 / DEX 5 / INT 4 / LUK 4, Three Snails rank 1; Magician magic attack 23 (Wooden Wand 1372005 incMAD) | C (A for the wand) | ours |
| Automatic AP and advancement reset | 5 AP per level, Beginner → STR, Magician → INT; only earned AP is redistributed on advancement | C | survivor rule, emulator-style reset |
| INT MP growth | Magician adds floor(INT / 10) to base growth, before assigning the new level's AP | B | pre-Big-Bang formula compilations, refs/research/v83-mechanics |
| Player avoidability | DEX × 0.25 + LUK × 0.5 + worn equipment incEVA | B (A for equipment) | Exoot 2009 formula compilation / v83 Character.wz |
| Player body (touch box) / cast origin | (-14,-58)-(14,0) from the feet / 30 px above the feet; shots start 22 px further toward their target (the hand) | C | ours |
| Cast stance | the skill's `action` (swingO1) for 0.8 s (its WZ frames 300+150+350 ms) while standing still | C | ours |
| Climbing cast gate | no new skills, basic attacks or buffs while on a rope/ladder; cooldowns and existing effects continue | C | owner choice |
| Guard/Armor values and durations | canonical mpCon/time/x/pdd at cast skill level; L1 Guard 6 MP/111 s/11%, Armor 8 MP/54 s/+2 PDD | A | Skill.wz/200.img |
| Player buff lifecycle and row | cast while inactive, expire/recast if affordable; snapshot cast rank, passive slots; 32 px icons with 4 px gaps and countdown labels; alert2 stance held 800 ms | C (lifecycle/layout/timing), A (icons/action) | owner choice; ours; v83 Skill.wz |
| Flyer speed / bob / arrivals | (`flySpeed` + 100) × `mob_speed_factor` × stage speed; bob 2 px / 1.2 s (`balance.mob_motion`); Henesys arrival keyframes 180 / 300 / 480 / 660 s, weights 1 | C (conversion and tuning); A (stats and frames) | ours; original v83 WZ |
| Goblin Fire EXP icon | Firebomb Flame 4000081 stands in for a signature EXP drop | C | ours (item art A) |
| Skill cooldown/range/speed/count/pierce, shot radius | `skills.json` (12-14 px radius); shots ignore terrain and die at their range or 200 px outside the bounds | C | ours |
| I/L attacks (#56) | Cold Beam nearest-target auto-cast: 300 px, 1 target, 1.25 s cooldown; Thunder Bolt box auto-cast: at least 1 target, 1.5 s cooldown; both use swingO1 for 0.8 s | C | survivor skill definitions; v83 has no action node for either skill |
| I/L canonical attack facts (#56) | ranks 1–30, elements i/l, mad/mastery/mpCon; Cold Beam x=-100/time=1–2 with no prop; Thunder Bolt mobCount=6 and lt/rb; effect/hit art and Use sounds, no ball | A | original v83 Skill.wz/220.img and Sound.wz/Skill.img/2201004–2201005, real-cache tests |
| I/L cards (#56) | Cold Beam +1 target; Thunder Bolt box offsets ×1.2; both cooldown ×0.88; 3 modifier steps each; learn/rank/modifier weights 4/3/2, all power, exact job 220; shared rarity magnitudes | C | owner #31/#56 behaviour choices; existing count/area/cooldown and Potential seams |
| Shots with fewer targets than projectiles | the extra shots reuse targets, aimed 8 px apart | C | ours |
| Pity / power cards | after 1 draw without a power card the next draw starts with one | C | ours |
| Potion tier gates and sparse draws | HP Orange from Lv 10, White from Lv 25 after Orange; MP Mana Elixir from Lv 20; one-time cards, preserve stock, future drops current tier; 3 choices when full; otherwise eligible cards plus one Elixir | C | owner choice; upgrades.json |
| Current-job cards and Elixir reward | strict job equality, Beginner cards require 0; learned earlier-job skills retained; one Power Elixir alternative below 3 eligible cards, alone at 0; fully restores both pools | C (reward/pool rule), A (2000005 identity/art/restoration) | owner choice, #38; upgrades.json fallback |
| Bot potion tier score | 112 (above Guard and attack cards); fallback 52 when absent | C | survivor balance.potions.bot.tier_score; random card policy unaffected |
| Bot potion waste guard | drink when missing HP/MP >= 0.5 x one current potion's canonical restore (`min_restore_fraction`) | C | owner review of #29; BotInput, shared by sensible and random card policies |
| Bot sword duel | a lone ordinary mob within 160 px and 40 px of the feet while no attack skill is ready and affordable: stand facing it so the basic attack swings; flee from two or more | C | owner review of #29; BotInput, shared by every movement policy that uses it |
| Bot Guard preference / offers | final scores learn 110, rank 109; no job bonus added; learn/rank offer weights 8/8 | C | balance.bot.card_scores; upgrades.json; random choices uniform |
| Three Snails auto levels | skill level 2 at Lv 3, 3 at Lv 6 (`level_ranks`) | C | ours, after the v83 Beginner's SP |
| Three Snails MP cost | 3 / 5 / 7 MP at skill levels 1 / 2 / 3, with the normal insufficient-MP wait and cue | A (costs), C (auto-cast wait/cue) | v83 Skill.wz/000.img/skill/0001000/level/N/mpCon; survivor casting rules |
| Advancement draws / skill counts | no skill grants; extra new-job attack-first draw with rarity before the normal level draw; no skill slot caps | C | owner decisions #31 / #53; sections 8?9 |
| Second-job Max MP | +475 for 210/220/230, fixed midpoint of the reference 450-500 mage range; existing first-job +120 retained | C | server reimplementation, unverified against GMS; [research](research/cosmic-data.md), local `Character.java:1204` |
| Bot branches / owned-skill HUD | independent seeded stream 8; optional forced branch; eight 24 px icons per row, 4 px gaps | C | #53 harness and presentation |
| Upgrade prerequisites | canonical `req` and previous survivor skill prerequisites ignored; exact job gates and owned-skill rank/modifier requirements retained | C | owner decision #31 |
| EXP curve, pacing keyframes | sections 4.1, 5 (`balance.json` `exp_curve`, `stages.json`), tuned with `scripts/balance.sh` | C | ours |
| Skill rank tables | every rank equals its canonical level; Beginner skills 3, first-job attacks/buffs 20, MP Recovery 16, Fire Arrow 30 | A (level counts); C (tier gain per card) | v83 Skill.wz level tables; owner choices #39 / #30 |
| Fortune and card odds | base 0; Normal/Rare/Epic/Unique/Legendary weights 75/18/5/1.7/0.3; non-Normal weights ×(1 + max(0, Fortune) ×0.02), normalized | C | spec #30 weights (owner restored them over C46 on 2026-10-15; untuned); upgrades.rarity and balance.player.fortune; cards only, not canonical LUK/drops/crits |
| Card tier magnitudes | rank +1/+2/+3/+5/max; stacking +1/+2/+3/+4/max; new skill 1/2/3/4/5; per-card overrides | C | spec #30, each tier above the last (owner 2026-10-15); upgrades.magnitudes; Legendary deliberately maxes even 20-rank skills |
| Card honesty / boss floor | highest fitting tier; a gain equal to a lower tier wears the lowest such label; boss promotes Normal to Rare and omits scalable cards unable to retain Rare; potion/Elixir always Normal | C | spec #30 / #43; headroom interpretation and exceptions in §8.1 |
| Tier text precision / telemetry | compounded percentages rounded to 0.01 for text; application full precision; offered/picked count each displayed card once; legacy records are unobserved | C | ours; choice_card, RunWorld counters, balance report |
| Tier reward presentation | white/blue/purple/gold/green accents `#FFFFFF/#77BBFF/#CC99FF/#FFCC44/#77DD88`, dark `#17344F` 16px label band tinted 30% with the tier colour and a 2px frame; rows start at 140px in blanked notice, 4px gaps, target view height minus 128px; prose compacts before changed values | C | #30 / #44; Potential ladder semantics on original v83 window art |
| High-tier offer cue | one `Sound.wz/Game.img/mCardGet` per displayed Unique/Legendary level-up or boss-reward window; prewarmed; no cue for invisible autopicks or focus/pick | A (v83 2664ms audio), C (reward use) | implementation selection after owner reserved EnchantSuccess for future scrolling; existing whole Game.img manifest; actual WASAPI playback verified by agent, fit auditioned and approved by owner on 2026-10-15 |
| Upgrade card values | `upgrades.json`: Recovery/Nimble Feet ranks 1–3, MP Recovery ranks 1–16, MaxMP Increase ranks 1–10, Magnet ×1.25; old Max HP/flat-speed/flat-MP cards removed | C (card tuning); A (canonical levels) | ours; original WZ |
| Improved MaxMP Increase percentage | computed Max MP (level/INT growth + job grant) × (1 + .02 × skill level), rounded once; +2–20% across 10 levels; preserve current MP ratio whenever this maximum grows, including later levels/jobs | C | owner reinterpretation; skills.improved_max_mp.passive; canonical 2000001 instead improves MP gained per level |
| MP Eater monster pools and level values | canonical `Mob.wz/info/maxMP`, never HP-scaled; spawn full, relocation preserves depletion, fresh reuse refills; `prop` 11–30%, `x` 21–40% over levels 1–20 for all three IDs; depleted monsters give no MP | A (data and exhaustion), C (survivor slot lifecycle) | original v83 Mob.wz, Skill.wz and String.wz; #59 |
| MP Eater cards and bot priority | learn/rank weights 2/2, no behaviour cards; existing passive bot scores learn 50, current-job rank 42 + 12 = 54, below attacks and above Magnet | C | survivor integration, existing BotInput defaults; #59 |
| MP Eater hit and presentation rules | whole-MP truncation; current passive level at impact, proc only on damaging magic lines; full player MP still drains monster MP, effect accompanies every absorb, gain number uses actual capped restoration; evidence shot at 0.12 s | C (integer interpretation and survivor integration), A (700 ms effect art/timing) | #59; shared Foundations hook/restoration, original v83 Skill.wz effects |
| Nimble Feet values and lifecycle | speed +10/15/20 for 4/8/12 s, costs 4/7/10 MP; cooldown 60 s from cast; auto-cast when inactive/ready/affordable, passive slot, no new cast while climbing | A (values), C (auto-cast/slot/lifecycle) | v83 Skill.wz/000.img/skill/0001002; owner casting rule |
| Recovery HoT | canonical levels 1–3 cost 5/10/15 MP, heal x=4/8/12, last 30 s, cooldown 120 s from cast; trigger below 50% HP, six 5 s pulses including the expiry tick | A (values); C (trigger/pulse interpretation) | v83 Skill.wz/000.img; survivor skill buff rules |
| Regeneration | 10 s pulses, base 3 MP + floor(character level × MP Recovery skill level / 10); always 10 HP; `balance.regen` | B (MP rule); C (HP choice) | pre-Big-Bang formula compilation; owner choice |
| Level-up pools / casting order / low-MP cue | no level-up healing or implicit current-pool gain from maximum growth; oldest-ready affordable skill, one per tick; warm-red persistent cue above EXP messages | C | owner choices; ours |
| EXP drop motion | pop 260 px/s up, ±40 px/s sideways, Physics.img gravity onto floors; magnet 220 px/s + 1400 px/s²; collected within 24 px of the body centre (25 px above the feet); at 600 drops the farthest from the player is absorbed into a fresh drop at the new kill | C | ours |
| EXP drop lifetime | never expires (`pickup.lifetime` 0); capped absorption resets the new drop's age and conserves EXP | C | owner decision 2026-10-14 |
| Player-platform spawns | 35% of ground placements, at least 150 px away; visible only when the whole platform fits in view, otherwise on off-screen portions; normal regen fade and harmlessness | C | owner choice, `balance.json.spawn` |
| Spawn rings | first the floors beside the view (within 160 px of its sides, `band`, and 48 px of its height, `band_y`), then within 480 px of the view, then the map within 1170 px of the player; 12 samples per ring, looking first for a point whose way to the player is at most half the view width + 48 + 160 px (`prefer_route`, 608 px on an 800 px view: no longer than the walk in from the ring's outer edge), then for any point that reaches the player, before an unreachable spot; never where a wall that crosses a platform stands anywhere on the way to the player (followed edge by edge onto the player's platform) | C | ours |
| Spawn trail margin | spawns stay 32 px further out (`trail_margin`) on the side a moving player (horizontal speed > 1 px/s) runs away from: the camera lags about 125 / 6 + 8 = 29 px behind a running player (smoothing 6/s, 8 px dead zone) | C | ours |
| Mob relocation | silent, never on screen (only from outside the view + 48 + 32 px on every side: the camera can lag either way) and never elites: a mob that has not come 1 px closer along its way while itself moving 1 px for 3 s (`stall_time`, `stall_progress`; a mob standing still on screen keeps counting and is moved once off screen), or that is farther than 1300 px or cannot reach the player 160 px off-screen for 3 s, is moved to a fresh spawn point, preferring the side the player is moving toward (its horizontal speed > 1 px/s), with its HP; only when no point is found is it recycled (removed) | C | ours |
| Bursts / elites | bursts may exceed max_alive up to `hard_cap` 400; first elite at 1:15 (Henesys 4:00), then every 60 s; first burst at 1:30 (Henesys 5:00), then every 90 s | C | ours; the Henesys delays keep them out of the sword-paced Beginner phase |
| Henesys stage EXP | 2.5x canonical mob EXP for ordinary kills (`stages.henesys_hg1.exp_mult`) | C | coarse #29 pass so a sword-paced Beginner reaches Magician near 4:40 |
| Job window | at every queued level while an option is available; once at the tier's first level when none is | C | ours |
| Magician advancement level | survivor level 10; canonical level 8 and INT 20 stay unchanged | C | owner choice, #40; `data/survivor/jobs.json` |
| Background auto-scroll axis | types 4-7: no camera term on the scrolling axis (screen x = x + rx·5·t + W/2), parallax on the other | C | ours (reading of "auto-scroll X, parallax Y") |
| Negative frame delay | used by magnitude (`magic1/0` = -900 ms) | C | ours |
| a0/a1 with one key | the other is 255 minus it | C | HeavenClient |
| Damage number stacking | same mob within 0.5 s goes one line up: 30 px above a normal number, 36 px above a critical one (8 lines, then wraps) | C | HeavenClient row heights 30/36; window and wrap ours |
| Boss target priority (#83) | every targeting rule (nearest, box, crowd, Heal undead, basic attack) orders qualifying targets scheduled boss first, then distance, then slot; elites get no priority | C | ours; spec #79 owner decision (`RunWorld.targets_before`) |
| Skill box admission / area scoring | minimum 1 target unless `cast.min_targets` overrides; base area 1.0, future area-card multiplier ×1.2; bot `area` score 58 plus existing job bonus | C | spec #31 binding foundations decisions; no skill/card entries added |
| Holy Arrow flight / cards (#57) | 1 s recast, 480 px range, 520 px/s, 12 px radius, count 1, pierce 0, 0.8 s stance; count +1 ×3, pierce +1 ×2, cooldown ×0.88 ×3; learn/rank weights 4/3, modifiers 2; standard attack bot scores | C (tuning), A (skill fields/art/sound/action) | copied existing Fire Arrow/first-job survivor steps; [Cleric evidence](research/cleric-heal.md) |
| Heal trigger / recast / targets (#57) | strictly below half HP OR one boxed undead; 2 s recast in heal block; 0.8 s stance; every boxed undead once, overriding canonical mobCount=6; target multiplier counts undead plus caster | C (trigger/delay/cap override), A (box/cost/hp/action/art/sound) | ticket #57; [Cleric evidence](research/cleric-heal.md) |
| Heal undead formula (#57) | bounds `(0.3×INT+LUK)` / `(1.2×INT+LUK)` × `(INT+matk)/1000` × `hp/100` × `(1.5+5/N)`; holy h; existing hit/defense/element path | B (pre-BB client RE, not directly v83) | Southperry #1033 posts 685–692; [derivation and worked example](research/cleric-heal.md) |
| Heal recovery approximation (#57; unresolved verification) | historical LUK polynomial × `(INT+matk)` × INT × `hp/10`, lower bound ×0.8; single-target multiplier 1, uniform seeded roll truncated to HP, capped by restore_player; learn/rank weights 4/3 | B weak (historical coefficients); C (selecting this unverified fit, multiplier, RNG/rounding, weights) | [evidence gap and original observations](research/cleric-heal.md); exact v83 recovery acceptance criterion remains open |
| Fire/Poison attacks (#55) | Fire Arrow: cooldown 1 s, range 480 px, speed 520 px/s, count 1, pierce 0, radius 12 px, stance 0.8 s, rotates; Poison Breath: 1.25 s, 450 px, 400 px/s, count 1, pierce 0, radius 14 px, stance 0.8 s, no rotation; both target nearest | C | survivor skills.fire_arrow / poison_breath; untuned; canonical elements, level numbers, actions and assets remain tier A |
| Fire/Poison cards (#55) | Fire Arrow +1 shot ×3, +1 pierce ×2, cooldown ×0.88 ×3; Poison Breath +1 pierce ×3, cooldown ×0.88 ×3; weights learn/rank/mod 4/3/2; exact job 210, all power; existing bot scores learn 100, rank 62, count 75, pierce 58, cooldown 54 plus 12 job bonus on rank/mod | C | issue #55 / owner #31; first-job modifier steps and score defaults; no rarity overrides or tuning |
| Second-job support values and casts | Meditation mad/time/mpCon; Bless pdd/mdd/acc/eva/time/mpCon; Invincible x/time/mpCon; Slow signed x/time/mobCount/lt/rb; alert2, effect, Use sounds, 20 levels each | A | original v83 Skill.wz/210.img, 220.img, 230.img; cache checked at levels 1/20 |
| Support auto-casts / hit integration | self only, one snapshot timer/icon; 0.8 s stance; Meditation invalidates caster stats, Bless live avoid/defence (accuracy stored only); Invincible whole physical hit ×(1−x/100), nearest rounding/minimum 1 before Guard | C lifecycle/arithmetic, A effects | #58; section 7; existing timed-buff rules |
| Slow crowd / consecutive uses | at least 3 eligible unslowed mobs, 1 s cooldown; 2 consecutive successful Slow casts per logical mob, reset by a successful cast excluding it; preserve across relocation, reset on fresh spawn | A text, C interpretation/trigger/cooldown | original String.wz/Skill.img Slow description; #58; survivor cast data and section 7 |
| Support cards / bot | learn/rank only, weights 3/2; learn 50, rank 42 + job bonus 12 (including Slow); below attacks | C | #58 survivor cards; existing support score defaults |
| Restoration gain digits | HP NoBlue1/0; MP same art tinted RGB (0.65,1,1); absent Blue falls back to Violet (HP tint 0.55,1,0.55; MP cyan) | A (cached digit art), C (selection/tints/fallback) | original v83 BasicEff cache; HP-use inference remains unverified (prior-art.md); existing number timing/stacking reused |
| Critical burst | `NoCri1/effect` behind the first digit (origin on the digit's anchor) from 250 ms; the v95 "y-30" and "+30 px leading space" are not applied (the prose leaves their axis/reference open) | B/C | v95 RE timing; placement ours |
| Face blink | `blink` every 2-5 s (seeded) | C | ours |
| Tombstone drop | `Tomb.img/fall` from 300 px above over its own duration (ease-in), then `land`, stays | C | ours |
| Pickup drawing | iconRaw centred on x, bottom on the drop point; bob 2 px over 1.2 s | C | ours |
| BGM fade / volumes | 0.8 s cross-fade; defaults master 1.0, BGM 0.8, SFX 0.9; 16 SFX voices (oldest stolen) | C | ours |
| HUD layout | gauge at (216, 37) of the 800×71 bar, fills measured from `gauge/bar`; button/key positions and top timer/kills/skills layout | A (measured art) / C (buttons, top HUD) | ours |
| Reserved HUD areas | quickslot (571, 8), 221×59 inside the bar; buffs 212×44 at (view width −224, 42); boss bars 300 px wide centred at y=42 with 42 px row pitch (37 px canonical icon frame) | C (layout), A (art size) | ours, difficulty overhaul |
| Starter equipment selection | Coat 1040002, Pants 1060002, Shoes 1072001; Sword 1302000 and Wooden Wand 1372005 loaded for job weapon selection | C (selection), A (info) | existing avatar look and v83 Character.wz |
| Elite name tag | mob name (String.wz) in the white 12 px system font on a black 60% box, 3 px padding, 15 px high, 2 px below the feet; hidden while dying | C | ours (v83 draws the default tag in code; `UI.wz/NameTag.img` holds only cash styles 3-28) |
| System messages | "+N EXP" in yellow (#FFFF00) with a black outline above the left end of the status bar, newest at the bottom; 4 s each (last 0.5 s fading), at most 6 lines | C | ours |
| Boss notices / respawn effect | keyed yellow notices above EXP and low-MP; warning lead / 4 s lifetime; BasicEff/Summoned at boss feet | C (selection/layout), A (art/timing) | ours; original v83 WZ |
| Missing boss UI metadata | Blue Mushmom uses Mushmom icon and 1/5 colour tags; King Slime uses 1/5 tags with its own icon | C (override), A (borrowed art) | survivor mobs.json.boss_ui |
| Mob draw layer | the foothold layer of the mob's current foothold, kept while it is airborne | C | ours |
| View fit | default: Godot's 800×600 expand + integer scale (1920×1080 → 1066×600 at 1× with bars); opt-in `fill_window`: s = ⌊min(W/800, H/600)⌋, view = window / s (3440×1440 → 1720×720 at 2×, 1920×1080 → 1920×1080 at 1×); windows below 800×600 are scaled down, not cropped | C | ours |
| Level-up window delay | the `LevelUp` effect plays 1.2 s (about its pillar's peak) on the character before the upgrade window opens; after a job advancement the next window waits for the whole `JobChanged` effect (~1.3 s; 1.3 s without the animation). Presentation only; the sim is already paused | C | ours |
| Frame cap | vsync on, `Engine.max_fps` = the display's refresh rate rounded up (144 when unknown, at least 30) | C | ours |
| Run end holds | results 2 s after the tombstone has landed; on a clear the party-quest `CLEAR` field effect (`Map.wz/Effect.img/quest/party/clear`, `Sound.wz/Field.img/Party1/Clear`) at the screen centre for 3.5 s | C | ours (art/sound A) |
| Invincibility blink, hit face | the whole character (one CanvasGroup) alternates alpha 1.0 / 0.4 every 0.08 s while invincible; face `hit` for 1 s after a hit | C | ours |
| Drop draw order | EXP drops are drawn after the mobs and the character of the character's foothold layer (never hidden in a crowd) | C | ours |
| Run start title | street name + map name (String.wz) under the timer for 3.5 s, the last 1 s fading | C | ours |
| Sound throttle | each sound path plays at most once per frame (a piercing shell through 20 mobs is one Damage sound) | C | ours |
| Character name tag | the character name under the feet in the elite name-tag style | C | ours |
| UI windows (level-up, job, pause) | open: 0.15 s fade-in while dropping 10 px; close: 0.12 s fade-out; keys ignored for 0.2 s after opening; the job dialog's confirmation line stays 1.8 s (any key/click skips) before `job_chosen` | C | ours (art A: UI.wz SkillUp, Skill rows, UtilDlgEx, Basic.img YesNo3) |
| UI text colours | NPC dialog black text, options #0000FF (#b), unavailable grey #888888, system yellow #FFFF00; Arial/Tahoma/Dotum without antialiasing at 11-12 px | C | ours, matched to v83 screenshots |
| Best result per stage | a clear beats a death, then longer survival, then higher level, more kills, more damage (`user://save.json`) | C | ours |

## 12. Later phases

Remaining second-job skills and behavior arrive in spec #31 sibling tickets; #53 enables all three branches and the existing Fire Arrow. Later: more maps (Henesys Hunting Ground II), more mobs.
The Tree That Grew I and the six stage bosses are already playable. Phase 3: other Explorer paths, 3rd/4th job,
additional bosses, elite waves with modifiers, passive items, skill evolutions, run modifiers, persistent unlocks.
