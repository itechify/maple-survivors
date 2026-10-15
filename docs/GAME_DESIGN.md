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
5. **Advance** to Magician at level 8. Further Explorer jobs are planned (section 9).
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

### 4.1 Pacing (`stages.json`)

The director keeps spawning until `alive >= max_alive(t)`, at `spawn_rate(t)` mobs/s, choosing from the pool active at
time t by weight. Values interpolate linearly between keyframes. Current difficulty-overhaul candidate for
Henesys Hunting Ground I (104040000), selected using training seeds only; independent acceptance follows freeze:

| Time | Rate (mobs/s) | Max alive | Pool (weight) | HP × | Speed × |
|---|---|---|---|---|---|
| 0:00 | 0.6 | 15 | Snail 4, Blue Snail 3 | 1.0 | 1.0 |
| 2:00 | 1.7 | 40 | + Red Snail 3, Shroom 3 | 1.0 | 1.0 |
| 4:00 | 3.1 | 65 | + Slime 3 | 1.0 | 1.05 |
| 6:00 | 6.0 | 100 | + Pig 2, Orange Mushroom 3 (Snails phase out) | 1.5 | 1.1 |
| 9:00 | 9.4 | 165 | + Green Mushroom 1 | 3.25 | 1.18 |
| 12:00 | 13.5 | 240 | full pool (Green Mushroom 3) | 4.25 | 1.28 |
| 15:00 | 20 | 330 | final boss | 6.875 | 1.4 |

The difficulty overhaul removed the time-based touch-damage column and the hidden 0.55 attack scale. Section 6.2
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
Aggregates report completed fight samples separately from unfinished or unspawned encounters and retain the
boss-hit source kind. A cap ends the measurement as TIMEOUT; reaching 15:00 alone cannot clear a run.

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

The full-run regression uses predetermined training seeds 1/2/2026 on both stages, separate from the held-out
acceptance matrix. Stage-sample medians retain Mage 150–225 s and Lv30 720–900 s, with at least two of three
runs reaching Lv30. Individual windows allow build variation: Mage 135–270 s, Lv10 150–360 s and Lv30 600–1080 s;
the Lv10 sample median is 180–330 s. Population acceptance still uses all thirty held-out seeds and explicit
reach/outcome counts, rather than that small regression sample. Spawning each minute (including after 15:00), crowd
growth, EXP/kill/event consistency, all-boss finale, no lost mobs, inherited 30% engagement floor, late 200+ density
and at least five ordinary nonmiss hits after 8:00 remain active. Boss hits and misses cannot satisfy that last
check. The draft guard is prepared before held-out execution and is run only after candidate freeze.
### 4.2 Tuning record (`scripts/balance.sh`)

Pacing is measured with `bash scripts/balance.sh [seeds | a..b] [--policy=...]` (whole headless runs on the real map,
`game/tools/balance_run.gd`). Movement is always the autoplay bot (`BotInput`): it kites on the ground, walks to EXP
drops and climbs a ladder or rope to drops left on a platform above, and takes the first available job. Card
policies: `bot` uses `BotInput.pick_card_for`, prioritizing eligible potion tiers, then Guard learning/ranks through
survivor score overrides, then the existing attack, shot, damage, pierce and defence scores; `random` is a careless player who
takes a random card of the three (the old `--first-card` policy is no longer a careless proxy: it always takes the
guaranteed card, which UpgradePool puts first). `--idle-after=300` takes the hands off the keys at 5:00.

#### Frozen difficulty-overhaul training

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
#### Frozen held-out assessment: one target failed

All **120 fresh runs** on seeds **101–130**, both stages and both card policies, use freeze milestone `b230305`
(gameplay `db9ef80`), actual data without patch overrides and the same 1,800 s cap. Every expected identity is
verified. The later `ab5d7fa` change only makes a scene-test fixture use the public EXP threshold; it does not
change gameplay, design data, the pacing guard or the already-running held-out mirror. No tuning followed these
results.

**Tree careless timing fails acceptance:** only **12/29 deaths (41.4%)** fall in 540–720 s, versus a required
majority. Its 717.3 s death median alone would conceal 14 later deaths. The training share of 36/60 (60%) did not
reproduce on this reserved sample. This remains an open Spec #1 / #27 acceptance failure. Both sensible groups
meet their progression, clear-rate, late-hit and typical boss timing/source-hit gates; Henesys random meets the
careless timing gate. No run times out in the held-out matrix.

The actual frozen pacing run passed 5 tests with no failures or skips. After `ab5d7fa` corrected the stale
scene-test EXP fixture through the public progression API, the final full suite passed **482 tests, 0 failed,
0 skipped, 59 files** in 507.517 s. The survivor data and pacing guard remained unchanged.

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
#### Informational camper samples

On the same v28 data, seeds **1–6 and 2026**, `--camp-after=60 --cap=1800`, all 21 runs reached their requested
camping position. These observations are informational and did not select or tune the profile.

| Policy | Clear / dead / timeout | Death median [min–max], s |
|---|---|---|
| Henesys top platform | 0 / 7 / 0 | 300.3 [300.3–301.6] |
| Henesys rope | 0 / 7 / 0 | 207.2 [205.9–294.4] |
| Tree top platform | 0 / 7 / 0 | 321.0 [310.5–403.5] |

Raw records, requested-position flags and commands are preserved in `evidence/acceptance/campers/`.
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
250 px away. A narrow floor may require a closer point. Bosses never flinch or receive push (`info/boss`, tier A flag;
survivor immunity behavior), and ordinary relocation never removes them. Skipped bosses remain until killed.

Survivor settings (tier C; canonical stats and attack timings/boxes remain unchanged):

| Boss | Canonical HP | Survivor HP | HP multiplier | Touch multiplier | Attack multiplier |
|---|---|---|---|---|---|
| Mano | 2,000 | 3,600 | 1.8 | 1.15 | — |
| Mushmom | 20,000 | 4,800 | 0.24 | 0.85 | 0.55 |
| Blue Mushmom | 200,000 | 7,000 | 0.035 | 0.48 | 0.70 |
| Stumpy | 7,000 | 3,150 | 0.45 | 0.8 | 0.74 |
| King Slime | 8,000 | 8,800 | 1.1 | 1.4 | 1.1 |
| Dyle | 31,000 | 8,060 | 0.26 | 1.15 | — |

Calibration uses measured training builds rather than the former assumed HP300/550/800 and full Armor defense.
`stage.bosses` stores the multipliers; `typical_hp/pdd` are illustrative inputs only, never adaptive runtime scaling.
The target is typical whole-hit source medians of 40–50%, with individual-hit/build variation reported separately.
Completed fights target 30/60/90 seconds, each ±50%; unfinished encounters are not zero-duration observations.
`balance.bosses` stores warning time, placement and spawn reduction.

While any boss lives, the ordinary spawn rate and normal burst counts halve; elite scheduling stays independent.
Henesys continues the last rate/max-alive/HP/speed keyframe slopes at quarter pace after 15:00
(`post_duration_slope`), with ordinary mobs still capped by `hard_cap`. Clearing requires every scheduled boss dead;
stages without a boss list retain their duration clear. Stage select states the applicable objective.

If a living boss has no route or makes no progress toward the player for 5 s, it fades out over 300 ms, then
relocates about 250 px away on the player's platform using the same placement policy. HP is preserved; it stands
still and cannot touch during fade-out or the normal 300 ms arrival fade. Progress means closing the route distance
by at least 1 px through its own movement; a boss already at the player does not relocate.

Boss deaths replace ordinary drops with a shower totaling rounded canonical boss EXP × survivor reward multiplier
(×5), split into 12 drops with no remainder lost, spread ±120 px. Default HP/MP bundles hold 3/6 potions of the
stock's current tier, separated by ±30 px. Mano overrides these to 6 HP/6 MP; Stumpy keeps 3 HP/6 MP, supporting
early builds. Both second bosses give 1 HP/6 MP, limiting later stock while ordinary HP supply stays scarce. The nested override includes
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
is 200 / 450. Mushmom and Blue Mushmom use separate attack scales 0.55/0.70 and contact scales 0.85/0.48,
calibrated against actual training HP pools. No attack-local canonical value is changed to achieve those fractions.
The `player_hit.source_kind` field distinguishes contact (`touch`) from these attack (`attack`) hits for metrics.
The handler is reusable for later Stumpy and King Slime type-0 attacks selected in their stage data.

The Tree That Grew I adds Stumpy (3220000) at 5:00, King Slime (9300003) at 10:00 and Dyle (6220000) at 15:00.
Stumpy uses HP ×0.45 (3,150), touch ×0.8 and attack ×0.74. Its selected attacks share an 8 s start-to-start cadence. The type-0 slam
keeps the 543×172 box and 1,500 ms attackAfter, including the same airborne dodge.
The type-2 ball keeps attack135, bulletSpeed140, range/r200, muzzle(6,-60) and 1,320 ms attackAfter. We adopt
`r ×600/bulletSpeed` ms maximum flight (857.14 ms), hence 233.33 px/s over 200 px. This conversion and using r
for acquisition/travel are tier C, inspired by the prose CMob comment in the later-client reference
`HaCreator/MapSimulator/Combat/MobAttackSystem.cs: ResolveProjectileTravelTimeMs`; that comment alone is not
verified v83 RE. Aim is at the current player body centre on launch; flight is straight, ignores terrain and
hits a swept body box grown by 8 px (tier C, survivor data). A ball is consumed on contact even if damage is
blocked or misses. Animation frames, origins, delays and sound remain canonical.
Stumpy's heal114/15 uses canonical HP gate80%, interval30 s and effectAfter1,500 ms. We interpret x700/y200 as
inclusive uniform bounds 200–700, then clamp to max HP and heal living mobs in the canonical area (tier C;
reference resolver `MapSimulator.cs: ResolveMobSkillHealAmount`, not a verified v83 formula). Its dedicated
seed stream8 makes the amounts replayable without changing card, potion, reward or hit rolls. The original
mob0 effect retains its 1,100 ms blank lead-in; it plays from cast, while HP restores at the application delay.
The heal notice reports actual restored HP, and the boss bar follows it immediately. No reference source code
was copied. Encounter scaling is survivor data; all heal bounds, gates, intervals and effect timing stay canonical.

King Slime keeps canonical maxHP 8,000, touch 130 and slam 165. Survivor HP ×1.1 gives 8,800; touch ×1.4
and slam ×1.1 are separate training-calibrated scales. Its type 0 slam
uses canonical attackAfter 900 ms, effectAfter 300 ms, 500×150 area and jumpAttack 1; grounded players in the area
are hit only at impact, airborne players can dodge. Skill 200/2 waits 50 s, HP ≤50%, summons the original three
210100 Slimes with summonEffect 3, and caps living encounter-owned summons at 15. Its eleven-entry info/revive
list spawns eleven ordinary canonical Slimes on death, independently of that cast limit. Relocations preserve
ownership and fresh slots reset it. King Slime lacks info/boss and hpTag colours in v83: the survivor no_flinch
override and existing 1/5 MobGage colour override supply scheduled-boss behavior without modifying WZ facts.
Dyle retains canonical maxHP 31,000 (survivor ×0.26=8,060) and touch 190 (survivor ×1.15).
Heal 114/17 uses HP ≤90%, interval 20 s and effectAfter 0: restoration occurs on the casting tick. Canonical
x 5,000/y 500 are interpreted as inclusive uniform 500–5,000 bounds (tier C, same reference interpretation as
Stumpy), clamped at max HP. Immunity 140/8 uses HP ≤80%, interval 30 s and duration 5 s. We interpret this as self
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

## 5. Experience and levels

Potions are separate persistent pickups, pulled in by the same magnet as EXP. Stock is unlimited and a run starts
with five Red Potions (2000000); MP stock starts empty with Blue Potion (2000003) selected. Delete/Q drinks HP,
End/E drinks MP, once per press, instantly and without a cooldown even on a rope. Empty stock does nothing.
Restoration comes unchanged from canonical item `spec.hp`/`spec.mp` (Red 50 HP, Blue 100 MP), clamped to max.
Normal kills use a global fallback of HP 1.2% and MP 6% independently; elites roll HP 15% and MP 65%. These choices and starter stock
are tier C data in `balance.potions`; potion rolls use a separate seeded stream. Potions never expire or enter the
EXP cap/absorption path. The bot drinks below 80% HP or 30% MP, with thresholds in the same survivor data.
The optional stage-keyframe `normal_hp_drop_chance` is tier C survivor supply tuning: clamp each endpoint to [0, 1],
interpolate linearly, hold the nearest endpoint outside the range, and substitute the global normal HP chance for
missing endpoints. Elite HP, all MP rolls and fixed boss bundles keep their existing settings. This curve is
independent of card policy.

Potion-tier score 112 prioritizes a useful permanent supply upgrade above Guard and attack cards. Learning a new
attack remains score 100; attack ranks/modifiers have maximum 87. The fallback 52 preserves callers without this field.
Only sensible choices use these scores; careless choices use their separate seeded card RNG.
Optional final card-score overrides set Guard learning to 110 and ranks to 109, without adding a job bonus. Missing
entries preserve legacy scoring. Guard learn/rank offer weights 8/8 improve availability; Orange/White offer
weights 30 make their eligible upgrades likely to appear. Snail count/cooldown/pierce weights 12/8/8 support the
Beginner; these are survivor choices, and the random policy still chooses uniformly among offered cards.
Normal HP supply interpolates by stage: HG 1.8% through 4:00, 1.2% at 5:00/6:00 and 0.2% at 8:00; Tree 3% through 4:00 and 0.6% at 6:00.
Both stages reach 0% at 9:00, hold through 12:00, recover to 0.6% at 13:00 and 0.8% at 15:00. These ordinary-drop
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
  measurements remain in section4.2. The quadratic term carries the late game: a strong build that levels
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
  Level-ups raise the maxima without restoring current HP or MP (`level_up_refill` = 0); explicit maximum-pool
  upgrade cards still grant their stated increase.
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

After skill priority, a standing or airborne player automatically attacks when a monster intersects its facing
stance afterimage box. Walking, climbing, a skill fired this tick or no reachable target prevents a new swing.
There is no movement lock. Each swing chooses uniformly among swingO1/O2/O3 and stabO1/O2 on its own seeded stream.
One nearest live monster is hit; a moving target may leave the box before impact. The interval is
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
- **Avoid** (tier B−): miss probability is `clamp(21.6 × player avoid / monster accuracy / 100, 0, 1)`; zero/missing
  accuracy disables the roll for synthetic data. A miss emits `player_hit` with `miss=true`, zero damage and zero
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
| Slow 126 / 7 | 15 s | omitted ? 100% | 15 s; rectangle (-300,-120)..(300,120) from boss feet; x80 retains 80% upgraded speed (tier C owner choice), refreshes rather than stacks |
| Summon 200 / 78 | 10 s | 90% | 2 Snails 100100, 2 Blue Snails 100101, 2 Red Snails 130101; at most 30 living summons belonging to that encounter |
| Weapon defense 112 / 1 | 10 s | omitted ? 100% | 30 s; rectangle (-300,-200)..(300,200); x85 adds 85 W.DEF to living mob feet inside, including Mano (tier C arithmetic) |
| Magic defense 113 / 1 | 10 s | omitted ? 100% | Same area/duration; x85 adds 85 M.DEF (tier C arithmetic) |

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

## 7. Skills (auto-cast)

Survivor behaviour is in `data/survivor/skills.json`; the canonical numbers per skill level come from `Skill.wz`.
A skill's **rank** maps to a canonical skill level, so ranking up a skill visibly changes it the way the original did.
Job skills pay the canonical `mpCon` of their current skill level on each successful cast (tier A). Three Snails
uses the survivor `mp_cost_override` of 0 (tier C, owner choice). Each tick casts at most one skill, oldest-ready
first; learned order breaks a tie. A ready skill without a target or sufficient MP waits without restarting its
cooldown. An unaffordable skill permits a later affordable skill to fire. A waiting skill emits `mp_short` once
per waiting episode, while `player_state.mp_short` keeps the warm-red "Not enough MP" HUD cue visible until casting
can resume (tier C presentation). No MP is charged while climbing or when no target exists.

While hanging on a rope or ladder, no new auto-action casts: skills, basic attacks and buff casting share
`RunWorld.can_cast()`. Cooldowns continue, so a ready skill fires on the first eligible tick after leaving the
rope or ladder. Already-launched projectiles, active buffs and passives keep applying. This is the owner-selected
climbing rule; tier C. The seeded camper probe parks on a rope at 1:00 and reports new casts and skill kills after
existing shots finish separately from carry-over projectile kills.

| Skill (id) | Job | Behaviour | Rank -> canonical level | Upgrades |
|---|---|---|---|---|
| Three Snails (1000) | Beginner | Throws a shell (`level/N/ball`) at the nearest mob within 420 px every 1.1 s; 400 px/s; `level/N/hit/0` on impact | ranks 1-3 = levels 1-3: green -> blue -> red shell, 10 -> 25 -> 40 damage; the skill reaches level 2 at character Lv 3 and level 3 at Lv 6 on its own (`level_ranks`: the SP a v83 Beginner puts into it); there is no card for it (owner decision 2026-10-14: a card that only buys what Lv 6 gives for free is a wasted pick) | Additional Shell (+1 shell, ×4), Faster Snails (-12% cooldown, ×4), Piercing Shells (+1 pierce, ×3), Rapid Snails (+25% speed, ×3) |
| Recovery (1001) | Beginner | Auto-cast below the data HP threshold; heals `x` every 5 s for canonical duration, with canonical MP cost/cooldown | ranks 1–3 = canonical levels 1–3: 5/10/15 MP, 4/8/12 HP per pulse, 30 s duration, 120 s cooldown | learn, then two rank cards |
| Energy Bolt (2001004) | Magician | `ball` projectile at the nearest mob every 0.9 s; 450 px/s; `hit/0` | rank r = level 1 + 4(r-1) (L1, L5, L9, L13, L17, L20) | Extra Bolt (+1, ×3), Bolt Pierce (+1, ×2), Overcharge (+20% damage, ×3) |
| Magic Claw (2001005) | Magician | Instant 2-hit claw (`attackCount` 2) on the nearest mob within 260 px every 1.25 s; `effect` on caster, `hit/0` on target (`CharLevel` variant by level) | same mapping | Twin Claw (+1 target, ×2), Quick Claw (-12% cooldown, ×3) |
| Magic Guard (2001002) | Magician | Timed damage-to-MP split (`x`%) | L1, L5, L10, L15, L20 | ranks only |
| Magic Armor (2001003) | Magician | Timed PDD (`pdd`) | L1, L5, L10, L15, L20 | ranks only |
| Fire Arrow (2101004) | F/P Wizard | Phase 2 | | Additional Projectile, Piercing Flames, Burning, Rapid Casting, Larger Flames |
| Poison Breath (2101005) | F/P Wizard | Phase 2 | | |

Targeting: nearest living mob within range (spatial hash query) of the body, excluding mobs already targeted this cast
when a skill fires several projectiles. A shot starts at the throwing hand: 22 px in front of the body toward its
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
Rank cards preview duration, absorption/defense and MP cost. Both occupy passive slots but share the one-cast-per-tick
readiness ordering with attacks. The alert2 stance comes from v83 skill action data; its 800 ms hold is tier C.

## 8. Upgrades

`data/survivor/upgrades.json`. Each upgrade card has: `id`, `kind` (`skill_new`, `skill_rank`, `skill_mod`, `passive`,
`stat`, `potion_tier`), `skill` (for skill cards), `icon` (a WZ path, e.g. `Skill.wz/000.img/skill/0001000/icon`), `name`,
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
3. With fewer than three eligible cards, offer only those cards. With none, continue without a choice window.
   Percentage-heal fillers (Elixir, Power Elixir, the former White Potion card) are removed.
4. Applying a card takes effect immediately.
5. The level-up window keeps the "You've gained a Level!" header and mascots, masks the baked-in skill-raising
   sentence for every card, and reads "LEVEL n". Rank cards show the canonical level change ("Skill Lv. 2 → 3")
   and before → after Magic ATT, mastery percent, MP cost and fixed damage when those fields exist in the skill's
   WZ level data. These previews use canonical values without survivor modifiers (tier A); mastery is converted
   with the combat formula in section 6.1.

General cards: Max HP +10%, Speed (Nimble Feet 1002 icon) +6 speed stat, Recovery (1001) learn/rank cards,
Magnet +25% radius; for Magicians also Improved MaxMP Increase (2000001) and Improved MP Recovery (2000000).
The latter is an owned canonical passive skill, learned at level 1 and ranked through levels 4 / 8 / 12 / 16,
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
| Physics.img values | see `docs/research/wz-inventory.md` §2 | A | v83 Map.wz |
| Potion restore amounts and icons | Red 50 HP, Orange 150 HP, White 300 HP, Blue 100 MP, Mana Elixir 300 MP | A | Item.wz/Consume/0200.img, unchanged spec/info |
| Potion stock, drop chances and bot thresholds | start 5 Red/0 Blue; normal HP .012 fallback (stage curve in §5)/MP .06, elite HP .15/MP .65; drink below HP .8/MP .3; persistent drops, unlimited stock, no drink cooldown | C | ours; balance.potions |
| Ordinary HP supply curve | Optional stage-keyframe chance, endpoint clamping, linear interpolation, global fallback per missing endpoint and endpoint holding outside the range | C | ours; SpawnDirector.normal_hp_drop_chance_at |
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
| Default frame delay | 100 ms | C | HeavenClient |
| Background scroll | rx × 5 px/s | B | 3 reimplementations agree |
| Damage number timing | 400 ms hold + 600 ms fade, 30 px rise | B | v95 RE (Harepacker docs) |
| Player knockback | 187.5 px/s, 0.3 s lock | C | HeavenClient |
| Invincibility after hit | 1.5 s | C | ours |
| Mano slow / defense interpretation | x80 retains 80% speed; x85 adds flat PDD/MDD, refreshed without stacking | C | owner-selected slow; explicit defense arithmetic interpretation, not verified client code |
| Mano skill scheduling / summons | first use after interval, one canonical stance at a time; omitted hp100%; 24 px symmetric spawn spacing | C (policy/spacing), A (intervals/list/limit/art) | ours; original v83 WZ |
| MobSkill effect anchors / summon family | affected pos1 at body top, effect pos3 at mob center; summonEffect1 selects Effect.wz/Summon.img/1 | C (mapping/placement), A (art/origins/delays) | ours; original v83 WZ |
| Basic physical damage / interval | ?6.1.1; Sword k4, Wand swing4.4/stab3.2, mastery0.1; quantized speed interval | B | owner-provided pre-Big-Bang mechanics |
| Starter afterimage / sparks | variant0; sword/mace normal spark1 swing / spark2 stab | C (selection), A (art/bounds/delays) | ours; original v83 WZ |
| Magic damage formula | §6.1 | C | community formula |
| Monster-to-player damage | attack × uniform[0.85,1] − floor(0.75 × defense), elemental resistance, explicit source multipliers, rounded, minimum 1 (§6.2) | C | owner's choice; not verified in the v83 client |
| Monster miss chance | 21.6 × player avoid / mob accuracy percent, clamped 0–100% | B− | owner-provided pre-Big-Bang RE evidence |
| Elite damage | ×1.5 after defense/resistance, before final rounding | C | survivor choice in stage elites.damage_mult |
| Boss arrivals and scaling | both stages at 5/10/15 min; HP/contact/attack multipliers in §4.3 | C | survivor data calibrated on training runs; canonical base stats unchanged |
| Boss warning / placement / pressure | 3 s lead; preferred 250 px, minimum 150 px (closer fallback on narrow floors); ordinary rate/bursts ×0.5 while a boss lives | C | survivor choices in balance.bosses |
| Boss relocation | no route/progress for 5 s; progress requires 1 px of own movement and route gain; 300 ms fade-out, ~250 px platform arrival with ordinary harmless regen | C | owner rule; balance.bosses |
| Boss rewards | canonical EXP ×5 in 12 drops, spread ±120 px; current-tier HP3/MP6 bundles (Mano HP6, second bosses HP1; MP6 throughout) at ±30 px; one bonus upgrade before clear, preserving level queue | C (multipliers/design); A (base EXP) | survivor reward data; v83 Mob.wz |
| Bonus choice layout | first row at 52 px below reward title/instruction, canonical card rows and panel fill | C | ours; LevelUpWindow |
| Boss stun and push immunity | no stun/push, regardless of pushed | A flag / C behavior | v83 info/boss, survivor encounter rule |
| Mushroom slam cadence / scaling / dodge | 8 s; separate attack ×0.55 / ×0.70; airborne at impact dodges jumpAttack; captured ground anchor/facing | C | survivor choice and lore; canonical attack300, range, attackAfter1050ms, frames and effectAfter0 are A |
| Stumpy HP/contact/attack | ×0.45 / ×0.8 / ×0.74; attacks every 8 s when eligible; Tree Branch EXP icon | C | training calibration; canonical stats/art A |
| King Slime / Dyle HP and hit scaling | HP ×1.1/×0.26; King touch×1.4/slam×1.1, Dyle touch×1.15; King8s cadence | C | training calibration; canonical stats and attack delays A |
| King Slime stance / death list | no_flinch override;24px offspring spacing, unconditional canonical eleven-entry revive list | C (stance/placement), A (list/IDs) | ours; original v83 info/boss absent, info/revive untouched |
| Dyle heal / weapon immunity | uniform500–5,000 heal; timed self physical immunity, consumed blocked shell; pos2 body-top anchor; Tree Branch EXP icon | C (interpretations), A (bounds/gates/durations/art) | ours; original Skill114/17 and140/8; reference heal resolver prose |
| Monster ball flight / collision | bulletSpeed×1000/600 px/s, range/r lifetime, straight aimed launch;8 px contact radius | C | later-client reference comment inspires interpretation; original v83 values A |
| Mob heal arithmetic / timing / art anchor | inclusive uniform x/y, max clamp and canonical area; independent RNG8; effectAfter application; mob0 starts at cast, pos0 at feet | C (interpretation/anchor), A (fields/art) | local reference resolver; original v83 WZ |
| Slam evidence screenshots | windup at 0.85 s; ground wave 0.12 s after impact | C | presentation capture timings only |
| Post-finale ramp / harness cap | final keyframe slopes ×0.25 after 15:00; 30:00 cap reported as timeout | C | survivor stage/balance data |
| First MISS screenshot | 0.05 presentation seconds after the first miss, only when screenshots are enabled | C | evidence capture timing |
| Projectile speeds/ranges | §7 | C | ours |
| Projectile hit exclusion identity | packed 64-bit run-local spawn identity; fresh spawns differ, relocation preserves it | C | our pool bookkeeping; no canonical or balance values changed |
| Camera smoothing | exponential, 6/s, 8 px dead zone, player at 58% height | C | ours |
| Player start | 50 HP, 5 MP, STR 12 / DEX 5 / INT 4 / LUK 4, Three Snails rank 1; Magician magic attack 23 (Wooden Wand 1372005 incMAD) | C (A for the wand) | ours |
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
| Shots with fewer targets than projectiles | the extra shots reuse targets, aimed 8 px apart | C | ours |
| Pity / power cards | after 1 draw without a power card the next draw starts with one | C | ours |
| Potion tier gates and sparse draws | HP Orange from Lv 10, White from Lv 25 after Orange; MP Mana Elixir from Lv 20; one-time cards, preserve stock, future drops current tier; no fillers, 0–3 eligible choices | C | owner choice; upgrades.json |
| Bot potion tier score | 112 (above Guard and attack cards); fallback 52 when absent | C | survivor balance.potions.bot.tier_score; random card policy unaffected |
| Bot Guard preference / offers | final scores learn 110, rank 109; no job bonus added; learn/rank offer weights 8/8 | C | balance.bot.card_scores; upgrades.json; random choices uniform |
| Three Snails auto levels | skill level 2 at Lv 3, 3 at Lv 6 (`level_ranks`) | C | ours, after the v83 Beginner's SP |
| Energy Bolt on advancing | learned with the Magician job (`grants.skills`) | C | ours, after the v83 Magician's first SP |
| Upgrade prerequisites | Magic Claw needs Energy Bolt, Magic Armor needs Magic Guard rank 2 (v83 `req`); Magic Guard needs Energy Bolt; MP cards need the Magician job | A (req) / C (the rest) | v83 Skill.wz / ours |
| EXP curve, pacing keyframes | sections 4.1, 5 (`balance.json` `exp_curve`, `stages.json`), tuned with `scripts/balance.sh` | C | ours |
| Upgrade card values | `upgrades.json` (e.g. Max HP ×1.1, Nimble Feet +6 speed, Recovery ranks 1/2/3, MP Recovery ranks 1/4/8/12/16, Max MP +25, Magnet ×1.25) | C (rank mapping/tuning); A (canonical levels) | ours; original WZ |
| Recovery HoT | canonical levels 1–3 cost 5/10/15 MP, heal x=4/8/12, last 30 s, cooldown 120 s from cast; trigger below 50% HP, six 5 s pulses including the expiry tick | A (values); C (trigger/pulse interpretation) | v83 Skill.wz/000.img; survivor skill buff rules |
| Regeneration | 10 s pulses, base 3 MP + floor(character level × MP Recovery skill level / 10); always 10 HP; `balance.regen` | B (MP rule); C (HP choice) | pre-Big-Bang formula compilation; owner choice |
| Level-up pools / casting order / low-MP cue | no level-up healing or implicit current-pool gain from maximum growth; oldest-ready affordable skill, one per tick; warm-red persistent cue above EXP messages | C | owner choices; ours |
| EXP drop motion | pop 260 px/s up, ±40 px/s sideways, Physics.img gravity onto floors; magnet 220 px/s + 1400 px/s²; collected within 24 px of the body centre (25 px above the feet); at 600 drops the farthest from the player is absorbed into a fresh drop at the new kill | C | ours |
| EXP drop lifetime | never expires (`pickup.lifetime` 0); capped absorption resets the new drop's age and conserves EXP | C | owner decision 2026-10-14 |
| Player-platform spawns | 35% of ground placements, at least 150 px away; visible only when the whole platform fits in view, otherwise on off-screen portions; normal regen fade and harmlessness | C | owner choice, `balance.json.spawn` |
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

Phase 2: Fire/Poison Wizard (Fire Arrow, Poison Breath with DoT), more maps (Henesys Hunting Ground II), more mobs.
The Tree That Grew I and the six stage bosses are already playable. Phase 3: other Explorer paths, 3rd/4th job,
additional bosses, elite waves with modifiers, passive items, skill evolutions, run modifiers, persistent unlocks.
