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
3. **Survive** for the stage duration (15:00 for the first stages). Monsters spawn continuously just outside the view,
   more and tougher over time.
4. **Level up** by collecting the EXP drops monsters leave. Each level pauses the game and offers 3 upgrades.
5. **Advance jobs** at 8 (Magician) / 10 (other Explorers) / 30 / 70 / 120.
6. **End.** Death (HP 0) shows the tombstone falling, then the results. Surviving the full duration clears the stage.
   Results show time, level, job, kills, damage dealt and owned skills; Retry or Stage select.

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
| Pick an upgrade | Mouse, or 1 / 2 / 3, or arrows + Enter |
| Pause | Esc |

There is no attack key: skills cast automatically.

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
- **Spawning:** at points on floors outside the camera view (+48 px margin, and 32 px more on the side a moving
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
- **Hit reaction:** a hit plays `hit1` and stuns for 0.24 s (tier C); damage ≥ `pushed` also pushes the mob 12 px
  away from the source (tier C).
- **Death:** `die1` plays with its WZ delays and alpha fades (`a0/a1`), the death sound plays, and the mob drops EXP.
- **Elites:** periodically one mob of the current pool spawns with ×8 HP and ×5 EXP, drawn with a name tag.

### 4.1 Pacing (`stages.json`)

The director keeps spawning until `alive >= max_alive(t)`, at `spawn_rate(t)` mobs/s, choosing from the pool active at
time t by weight. Values interpolate linearly between keyframes. First stage, Henesys Hunting Ground I (104040000),
tuned 2026-10-14 and re-tuned the same day for the swarm pass and its follow-up (section 4.2, "Swarm pass"; the
values before the swarm pass in brackets):

| Time | Rate (mobs/s) | Max alive | Pool (weight) | HP × | Speed × | Touch damage × |
|---|---|---|---|---|---|---|
| 0:00 | 0.6 (0.7) | 15 | Snail 4, Blue Snail 3 | 1.0 | 1.0 | 0.35 (1.0) |
| 2:00 | 1.7 (2.0) | 40 | + Red Snail 3, Shroom 3 | 1.15 | 1.0 | 0.35 (1.0) |
| 4:00 | 3.1 (3.6) | 65 | + Slime 3 | 1.3 | 1.05 | 0.35 (1.0) |
| 6:00 | 6.0 (5.0) | 100 | + Pig 2, Orange Mushroom 3 (Snails phase out) | 1.95 (1.5) | 1.1 | 0.35 (1.0) |
| 9:00 | 9.4 (8.5) | 165 | + Green Mushroom 1 | 2.6 (2.0) | 1.18 | 0.385 (1.1) |
| 12:00 | 13.5 (13) | 240 | full pool (Green Mushroom 3) | 3.4 (2.6) | 1.28 | 0.42 (1.2) |
| 15:00 | 20 | 330 | clear | 5.5 (4.2) | 1.4 | 0.525 (1.5) |

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

The Tree That Grew I uses the same rate, max alive, HP and damage numbers with its own pool: Snails only until 2:00,
since Slimes in the opening minute killed some runs before 1:00. It takes 0.85x EXP (its Lv 8 came at ~2:27, before
the 2:30-3:45 window, and Lv 30 at ~10:20), the henesys damage and default spawn preferences. It was only roughly
re-tuned (section 4.2, tuning seeds 1-24) and its stage card says "Not fully tuned yet" (`note`).

### 4.2 Tuning record (`scripts/balance.sh`)

Pacing is measured with `bash scripts/balance.sh [seeds | a..b] [--policy=...]` (whole headless runs on the real map,
`game/tools/balance_run.gd`). Movement is always the autoplay bot (`BotInput`): it kites on the ground, walks to EXP
drops and climbs a ladder or rope to drops left on a platform above, and takes the first available job. Card
policies: `bot` takes the card a sensible player would take (a new attack skill, then more shots / damage / pierce /
rank for the current job's attack skills, then defence; `BotInput.pick_card_for`); `random` is a careless player who
takes a random card of the three (the old `--first-card` policy is no longer a careless proxy: it always takes the
guaranteed card, which UpgradePool puts first). `--idle-after=300` takes the hands off the keys at 5:00.

**Seeds.** The 2026-10-14 pass was tuned on seeds 1-24 (variants compared on both policies) and is reported on the
held-out seeds 101-130, which were never used for tuning; the earlier record (seeds 1-23 + 2026) had been tuned and
reported on the same seeds, and it did not hold on fresh seeds (a review found 6 of 18 deaths on seeds 31-48). Keep
tuning on 1-60 and reporting on 101-130; `test_full_run` checks the pacing on seeds 101 and 102 (Lv 8 and Lv 10 on
their mean, see the test).

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
  against the same crowd). The Hill takes 1.0x EXP and touch damage 0.25-0.375, the Tree 0.85x EXP (section 4.1).
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

## 5. Experience and levels

- Mobs drop their **signature Etc item** as an EXP pickup (icon from `Item.wz/Etc/0400.img/<id>/info/iconRaw`), with
  the classic drop pop (`Sound.wz/Game.img/DropItem`). Snail -> Snail Shell 4000019, Blue Snail -> Blue Snail Shell
  4000000, Red Snail -> Red Snail Shell 4000016, Shroom -> Mushroom Spore 4000011, Slime -> Slime Bubble 4000010,
  Pig -> Pig's Head 4000017, Orange Mushroom -> Orange Mushroom Cap 4000001, Green Mushroom -> Green Mushroom Cap
  4000012.
- EXP value = the mob's canonical `exp` × 1.0 (× 5 for elites). Pickups within the magnet radius (90 px) fly to the
  player; collecting plays `Game.img/PickUpItem` and shows "+N EXP" in MapleStory's yellow system-message style.
- **Drops never expire** (owner decision 2026-10-14; `pickup.lifetime` = 0). Past `pickup.max_active` (600) a new
  drop merges into the nearest one, so the map cannot fill without bound. (Expiry after 60 s was tried and removed.)
- **Survivor EXP curve:** `exp_to_next(L) = round(4 + 8·L + 4·L²)` (L1 = 16, close to the canonical 15; L7 = 256,
  L9 = 400, L29 = 3600; 812 EXP to reach Lv 8, 1536 to Lv 10, 37816 to Lv 30; before the swarm follow-up
  round(4 + 12·L + 3·L²): 784 / 1431 / 31001). The quadratic term carries the late game: a strong build that levels
  fast meets steeper levels, which keeps the spread between builds small. Measured
  pace: section 4.2. The canonical v83 table (`data/canonical/exp_table.json`) is kept for reference and display
  only.
- **Level up:** the game pauses, `Effect.wz/BasicEff.img/LevelUp` plays on the character with `Game.img/LevelUp`, then
  the upgrade window opens. Several level-ups in a row queue their windows.
- **Stats per level** (tier C, emulator-like): Beginner +14 HP / +10 MP; Magician +12 HP / +22 MP; INT +5 per level
  (auto-assigned). Max HP/MP are refilled by 25% on level up.

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

### 6.2 Damage to the player

- **Touch damage** = max(1, round(PAD × 0.55 × rand[0.85, 1.0] × stage_damage_mult - PDD_player × 0.6)) (tier C).
- On hit: `NoViolet` digits over the player, knockback 187.5 px/s away and a small hop (tier C), 0.3 s of no input,
  1.5 s invincibility with blinking (tier C).
- **Magic Guard** moves `x`% (canonical 11-80% by level) of damage to MP while MP lasts.
- HP regenerates slowly (Recovery upgrade); MP regenerates 2/s (+Improved MP Recovery).

### 6.3 Damage numbers

`Effect.wz/BasicEff.img`: dealt = `NoRed1` first digit + `NoRed0` rest; crit = `NoCri1`/`NoCri0`; taken = `NoViolet`.
Digit advance overlaps per v95 RE (tier B); 400 ms hold, then 600 ms fade while rising 30 px. Multiple hits on one mob
stack upward one line per number: 30 px above a normal number, 36 px above a (taller) critical one.

## 7. Skills (auto-cast)

Survivor behaviour is in `data/survivor/skills.json`; the canonical numbers per skill level come from `Skill.wz`.
A skill's **rank** maps to a canonical skill level, so ranking up a skill visibly changes it the way the original did.
No skill costs MP in survivor mode (MP fuels Magic Guard instead).

| Skill (id) | Job | Behaviour | Rank -> canonical level | Upgrades |
|---|---|---|---|---|
| Three Snails (1000) | Beginner | Throws a shell (`level/N/ball`) at the nearest mob within 420 px every 1.1 s; 400 px/s; `level/N/hit/0` on impact | ranks 1-3 = levels 1-3: green -> blue -> red shell, 10 -> 25 -> 40 damage; the skill reaches level 2 at character Lv 3 and level 3 at Lv 6 on its own (`level_ranks`: the SP a v83 Beginner puts into it); there is no card for it (owner decision 2026-10-14: a card that only buys what Lv 6 gives for free is a wasted pick) | Additional Shell (+1 shell, ×4), Faster Snails (-12% cooldown, ×4), Piercing Shells (+1 pierce, ×3), Rapid Snails (+25% speed, ×3) |
| Energy Bolt (2001004) | Magician | `ball` projectile at the nearest mob every 0.9 s; 450 px/s; `hit/0` | rank r = level 1 + 4(r-1) (L1, L5, L9, L13, L17, L20) | Extra Bolt (+1, ×3), Bolt Pierce (+1, ×2), Overcharge (+20% damage, ×3) |
| Magic Claw (2001005) | Magician | Instant 2-hit claw (`attackCount` 2) on the nearest mob within 260 px every 1.25 s; `effect` on caster, `hit/0` on target (`CharLevel` variant by level) | same mapping | Twin Claw (+1 target, ×2), Quick Claw (-12% cooldown, ×3) |
| Magic Guard (2001002) | Magician | Passive damage-to-MP split (`x`%) | L1, L5, L10, L15, L20 | ranks only |
| Magic Armor (2001003) | Magician | Passive PDD (`pdd`) | L1, L5, L10, L15, L20 | ranks only |
| Fire Arrow (2101004) | F/P Wizard | Phase 2 | | Additional Projectile, Piercing Flames, Burning, Rapid Casting, Larger Flames |
| Poison Breath (2101005) | F/P Wizard | Phase 2 | | |

Targeting: nearest living mob within range (spatial hash query) of the body, excluding mobs already targeted this cast
when a skill fires several projectiles. A shot starts at the throwing hand: 22 px in front of the body toward its
target (`player.cast_forward`), level with the cast origin, so the shell never covers the face. Projectiles fly straight toward the target's position at cast time and expire at their range.
Projectile speeds and ranges are tier C (no `speed` key exists in v83 `ball` nodes).

Casting does not stop movement. When standing still the character plays the skill's `action` stance (or `swingO1`)
for its frame time; while moving it keeps walking.

## 8. Upgrades

`data/survivor/upgrades.json`. Each upgrade card has: `id`, `kind` (`skill_new`, `skill_rank`, `skill_mod`, `passive`,
`stat`, `filler`), `skill` (for skill cards), `icon` (a WZ path, e.g. `Skill.wz/000.img/skill/0001000/icon`), `name`,
`desc` (with `{value}` placeholders), `max_rank`, `weight`, `requires` (job ids, owned skills, min skill rank, min
level), `effects` (`{"stat": "count", "op": "add", "value": 1}`).

Draw rules:

1. Eligible = requirements met and rank < max. `skill_new` needs the job (`requires.jobs`) and that the loadout has a
   free active-skill slot (6 actives, 6 passives).
2. Three distinct cards are drawn by weight with the run's seeded RNG.
   **Pity:** cards that raise an attack skill's damage output carry `"power": true` (a new attack skill, its rank,
   more shots or targets, damage, cooldown). When a draw offered no power card, the next draw starts with one
   (`pity.draws` = 1), so a run's damage cannot stall on unlucky offers (a reviewed seed never saw an attack card
   before Lv 8 and fell behind for good).
3. With fewer than three eligible cards, fillers fill the gap (e.g. "Elixir": heal 50% HP/MP).
4. Applying a card takes effect immediately.
5. The level-up window names the skill a card learns or levels in the notice's "raised your ___ skill by a level."
   box and shows a skill_rank card as the skill's canonical level change ("Skill Lv. 2 → 3"); for other cards the
   sentence is left out and the notice reads "LEVEL n".

General cards: Max HP +10%, Speed (Nimble Feet 1002 icon) +6 speed stat, Recovery (1001) HP regen, Magnet +25% radius;
for Magicians also Improved MaxMP Increase (2000001) and Improved MP Recovery (2000000) (Magician skills in v83, and MP
only matters once Magic Guard exists).

Skill prerequisites follow `Skill.wz` `req` where v83 has one: Magic Claw needs Energy Bolt (`2001005/req/2001004 =
1`), Magic Armor needs Magic Guard level 3 (`2001003/req/2001002 = 3`; survivor rank 2 = level 5). Magic Guard also
waits for Energy Bolt (survivor rule), so the first Magician skill is always Energy Bolt.

## 9. Jobs

`data/canonical/jobs.json` holds the Explorer tree with canonical ids (Beginner 0; Warrior 100, Magician 200,
Bowman 300, Thief 400, Pirate 500; second jobs 110-130 / 210-230 / 310-320 / 410-420 / 510-520; third and fourth
jobs). `data/survivor/jobs.json` marks which are playable in this build and what advancing grants.

At an advancement level the level-up window is preceded by the **Job Advancement** window (UI.wz window frame, job
book name from `String.wz/Skill.img/<job>/bookName`, `BasicEff.img/JobChanged` + `Game.img/JobChanged` on accept):

- Level 8: Magician (playable). Warrior, Bowman, Thief, Pirate are shown with their requirement ("Lv. 10").
- Level 10: the other four are shown as "not in this build". "Not now" keeps you a Beginner and asks again next level.
- Advancing: job becomes 200, MP +120, Energy Bolt is learned at once (`grants.skills`: the first SP of a v83
  Magician; a player who takes cards at random could otherwise stay a Magician without a Magician attack), and the
  next card draw guarantees another Magician skill card (with the prerequisites of section 8: Magic Claw or Magic
  Guard).
- The JobChanged pillar and sound play on the character first; the level's upgrade window opens once the effect has
  played (~1.3 s). A level-up window opens 1.2 s into the LevelUp effect.
- Level 30: F/P Wizard (Phase 2), I/L Wizard and Cleric shown as not yet available.

## 10. Presentation

- 800x600 logical view (wider windows show more map at the same pixel scale), integer scaling, nearest filtering. An
  opt-in "fill window" setting fills large windows with more map instead of black bars (see View fit below).
- HUD: `UI.wz/StatusBar.img` bottom bar with HP/MP/EXP gauges, level from `Basic.img/LevelNo`, job name; survival timer
  and kill count at the top; owned-skill icons with ranks at the top left.
- Text uses the system's Arial-like font without antialiasing at MapleStory sizes (no fonts are shipped).
- Map name and street name from `String.wz/Map.img` on the stage card and at run start.
- Death: `Effect.wz/Tomb.img` tombstone falls on the character with `Game.img/Tombstone`.
- Results: RETRY is the v83 mini-game's green button (`UIWindow.img/RpsGame/BtRetry`), Back the login book's banner.
- Frame rate: vsync on and capped at the display's refresh rate (`Settings` `[display] max_fps`; 0 = refresh rate,
  -1 = uncapped); `--vsync=off` uncaps it for perf runs.

## 11. Constants and provenance

| Constant | Value | Tier | Source |
|---|---|---|---|
| Physics.img values | see `docs/research/wz-inventory.md` §2 | A | v83 Map.wz |
| Walk/jump/air/down-jump/landing model | §3 | B | NoLifeStory physics description |
| Player sub-step | 2 per 1/60 s tick | C | ours |
| Vertical air drag | none (apex 555²/4000 = 77 px) | C | ours; NoLifeStory's 100 px/s² vertical float drag would give ~73 px |
| Climb speed | 100 px/s | C | ours (HeavenClient uses 125) |
| Ladder grab/exit | Up: hands 50 px above the feet within 10 px of x; Down: 10 px below the feet; 0.25 s re-grab delay; exit jump vx = max walk speed, vy = jumpSpeed/1.5; `uf=1` top exit onto a floor within 24 px above / 4 px below the top | C | ours / HeavenClient exit jump |
| Same-map portal activation and arrival | feet x ±25, y −100…+25; arrive 30 px above target with zero velocity; global cooldown 384 ms; camera snaps, no sound or transition | C | owner choice; `balance.json.portals` |
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
| Default frame delay | 100 ms | C | HeavenClient |
| Background scroll | rx × 5 px/s | B | 3 reimplementations agree |
| Damage number timing | 400 ms hold + 600 ms fade, 30 px rise | B | v95 RE (Harepacker docs) |
| Player knockback | 187.5 px/s, 0.3 s lock | C | HeavenClient |
| Invincibility after hit | 1.5 s | C | ours |
| Magic damage formula | §6.1 | C | community formula |
| Touch damage | §6.2 | C | ours |
| Projectile speeds/ranges | §7 | C | ours |
| Camera smoothing | exponential, 6/s, 8 px dead zone, player at 58% height | C | ours |
| Player start | 50 HP, 5 MP, 4 INT, Three Snails rank 1; Magician magic attack 23 (Wooden Wand 1372005 incMAD) | C (A for the wand) | ours |
| Player body (touch box) / cast origin | (-14,-58)-(14,0) from the feet / 30 px above the feet; shots start 22 px further toward their target (the hand) | C | ours |
| Cast stance | the skill's `action` (swingO1) for 0.8 s (its WZ frames 300+150+350 ms) while standing still | C | ours |
| Skill cooldown/range/speed/count/pierce, shot radius | `skills.json` (12-14 px radius); shots ignore terrain and die at their range or 200 px outside the bounds | C | ours |
| Shots with fewer targets than projectiles | the extra shots reuse targets, aimed 8 px apart | C | ours |
| Pity / power cards | after 1 draw without a power card the next draw starts with one | C | ours |
| Three Snails auto levels | skill level 2 at Lv 3, 3 at Lv 6 (`level_ranks`) | C | ours, after the v83 Beginner's SP |
| Energy Bolt on advancing | learned with the Magician job (`grants.skills`) | C | ours, after the v83 Magician's first SP |
| Upgrade prerequisites | Magic Claw needs Energy Bolt, Magic Armor needs Magic Guard rank 2 (v83 `req`); Magic Guard needs Energy Bolt; MP cards need the Magician job | A (req) / C (the rest) | v83 Skill.wz / ours |
| EXP curve, pacing keyframes | sections 4.1, 5 (`balance.json` `exp_curve`, `stages.json`), tuned with `scripts/balance.sh` | C | ours |
| Upgrade card values | `upgrades.json` (e.g. Max HP ×1.1, Nimble Feet +6 speed, Recovery +1 HP/s, MP Recovery +1 MP/s, Max MP +25, Magnet ×1.25) | C | ours |
| EXP drop motion | pop 260 px/s up, ±40 px/s sideways, Physics.img gravity onto floors; magnet 220 px/s + 1400 px/s²; collected within 24 px of the body centre (25 px above the feet); past 600 drops new EXP merges into the nearest (its age restarts) | C | ours |
| EXP drop lifetime | never expires (`pickup.lifetime` 0); past 600 drops new EXP merges into the nearest drop | C | owner decision 2026-10-14 |
| Spawn rings | first the floors beside the view (within 160 px of its sides, `band`, and 48 px of its height, `band_y`), then within 480 px of the view, then the map within 1170 px of the player; 12 samples per ring, looking first for a point whose way to the player is at most half the view width + 48 + 160 px (`prefer_route`, 608 px on an 800 px view: no longer than the walk in from the ring's outer edge), then for any point that reaches the player, before an unreachable spot; never where a wall that crosses a platform stands anywhere on the way to the player (followed edge by edge onto the player's platform) | C | ours |
| Spawn trail margin | spawns stay 32 px further out (`trail_margin`) on the side a moving player (horizontal speed > 1 px/s) runs away from: the camera lags about 125 / 6 + 8 = 29 px behind a running player (smoothing 6/s, 8 px dead zone) | C | ours |
| Mob relocation | silent, never on screen (only from outside the view + 48 + 32 px on every side: the camera can lag either way) and never elites: a mob that has not come 1 px closer along its way while itself moving 1 px for 3 s (`stall_time`, `stall_progress`; a mob standing still on screen keeps counting and is moved once off screen), or that is farther than 1300 px or cannot reach the player 160 px off-screen for 3 s, is moved to a fresh spawn point, preferring the side the player is moving toward (its horizontal speed > 1 px/s), with its HP; only when no point is found is it recycled (removed) | C | ours |
| Bursts / elites | bursts may exceed max_alive up to `hard_cap` 400; first elite at 1:15, then every 60 s | C | ours |
| Job window | at every queued level while an option is available; once at the tier's first level when none is | C | ours |
| Background auto-scroll axis | types 4-7: no camera term on the scrolling axis (screen x = x + rx·5·t + W/2), parallax on the other | C | ours (reading of "auto-scroll X, parallax Y") |
| Negative frame delay | used by magnitude (`magic1/0` = -900 ms) | C | ours |
| a0/a1 with one key | the other is 255 minus it | C | HeavenClient |
| Damage number stacking | same mob within 0.5 s goes one line up: 30 px above a normal number, 36 px above a critical one (8 lines, then wraps) | C | HeavenClient row heights 30/36; window and wrap ours |
| Critical burst | `NoCri1/effect` behind the first digit (origin on the digit's anchor) from 250 ms; the v95 "y-30" and "+30 px leading space" are not applied (the prose leaves their axis/reference open) | B/C | v95 RE timing; placement ours |
| Face blink | `blink` every 2-5 s (seeded) | C | ours |
| Tombstone drop | `Tomb.img/fall` from 300 px above over its own duration (ease-in), then `land`, stays | C | ours |
| Pickup drawing | iconRaw centred on x, bottom on the drop point; bob 2 px over 1.2 s | C | ours |
| BGM fade / volumes | 0.8 s cross-fade; defaults master 1.0, BGM 0.8, SFX 0.9; 16 SFX voices (oldest stolen) | C | ours |
| HUD layout | gauge at (216, 37) of the 800×71 bar, fills measured from `gauge/bar`; button/key positions and top timer/kills/skills layout | A (measured art) / C (buttons, top HUD) | ours |
| Elite name tag | mob name (String.wz) in the white 12 px system font on a black 60% box, 3 px padding, 15 px high, 2 px below the feet; hidden while dying | C | ours (v83 draws the default tag in code; `UI.wz/NameTag.img` holds only cash styles 3-28) |
| System messages | "+N EXP" in yellow (#FFFF00) with a black outline above the left end of the status bar, newest at the bottom; 4 s each (last 0.5 s fading), at most 6 lines | C | ours |
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

Phase 2: Fire/Poison Wizard (Fire Arrow, Poison Breath with DoT), more maps (The Tree That Grew I for Slimes,
Henesys Hunting Ground II), more mobs. Phase 3: other Explorer paths, 3rd/4th job, bosses (Mushmom, King Slime),
elite waves with modifiers, passive items, skill evolutions, run modifiers, persistent unlocks.
