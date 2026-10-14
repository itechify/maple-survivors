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
- **Map edges:** the player cannot leave the foothold span horizontally (walls at the outermost foothold x).
- **Fixed step:** the sim ticks at 60 Hz; the player integrates in 2 sub-steps per tick (≈8.3 ms).

## 4. Monsters and swarms

Each monster is the original mob: its WZ animations (`stand`, `move`, `jump`, `hit1`, `die1`), its stats from
`Mob.wz/<id>.img/info`, its sounds (`Sound.wz/Mob.img/<id>/Damage`, `Die`) and its name from `String.wz`.

- **Speed:** move speed px/s = (speed stat + 100) × 0.625 (tier C, HeavenClient's terminal speed) × the stage's speed
  multiplier. Snail 21.9, Blue Snail 31.3, Shroom 43.8, Slime 50, Orange Mushroom/Pig 62.5 px/s, so the player
  (125 px/s) can outrun early mobs; late-stage multipliers close the gap.
- **Pursuit:** ground mobs walk along footholds. A mob on the player's platform walks toward the player; otherwise it
  follows a route through the **platform graph** (`NavGraph`): walking off an edge onto a lower platform ("drop"), or,
  for mobs with a `jump` animation (Slime, Pig, Orange Mushroom), jumping up to a platform within reach. Mobs never
  teleport or float. A mob that cannot reach the player wanders on its platform and is recycled once far off-screen.
- **Spawning:** at points on floors outside the camera view (+48 px margin) but inside the map bounds, preferring
  platforms that can reach the player's platform, never within 200 px of the player. New mobs fade in (regen) over
  0.3 s (tier C).
- **Contact:** touching a mob with `bodyAttack=1` deals touch damage (section 6), unless the player is invincible.
- **Hit reaction:** a hit plays `hit1` and stuns for 0.24 s (tier C); damage ≥ `pushed` also pushes the mob 12 px
  away from the source (tier C).
- **Death:** `die1` plays with its WZ delays and alpha fades (`a0/a1`), the death sound plays, and the mob drops EXP.
- **Elites:** periodically one mob of the current pool spawns with ×8 HP and ×5 EXP, drawn with a name tag.

### 4.1 Pacing (`stages.json`)

The director keeps spawning until `alive >= max_alive(t)`, at `spawn_rate(t)` mobs/s, choosing from the pool active at
time t by weight. Values interpolate linearly between keyframes. First stage, Henesys Hunting Ground I (104040000):

| Time | Rate (mobs/s) | Max alive | Pool (weight) | HP × | Speed × |
|---|---|---|---|---|---|
| 0:00 | 0.7 | 15 | Snail 4, Blue Snail 3 | 1.0 | 1.0 |
| 2:00 | 1.6 | 40 | + Red Snail 3, Shroom 3 | 1.1 | 1.0 |
| 4:00 | 2.6 | 70 | + Slime 3 | 1.25 | 1.05 |
| 6:00 | 3.5 | 110 | + Pig 2, Orange Mushroom 3 (Snails phase out) | 1.5 | 1.1 |
| 9:00 | 5 | 170 | + Green Mushroom 2 | 1.9 | 1.15 |
| 12:00 | 7 | 250 | full pool | 2.5 | 1.25 |
| 15:00 | 9 | 320 | clear | 3.0 | 1.3 |

Bursts every 90 s spawn a ring of 20-40 mobs around the view. The roster deliberately goes beyond the map's own `life`
list (Snail, Slime and Orange Mushroom are the classic trio); the original spawn list is shown in the stage info.

## 5. Experience and levels

- Mobs drop their **signature Etc item** as an EXP pickup (icon from `Item.wz/Etc/0400.img/<id>/info/iconRaw`), with
  the classic drop pop (`Sound.wz/Game.img/DropItem`). Snail -> Snail Shell 4000019, Blue Snail -> Blue Snail Shell
  4000000, Red Snail -> Red Snail Shell 4000016, Shroom -> Mushroom Spore 4000011, Slime -> Slime Bubble 4000010,
  Pig -> Pig's Head 4000017, Orange Mushroom -> Orange Mushroom Cap 4000001, Green Mushroom -> Green Mushroom Cap
  4000012.
- EXP value = the mob's canonical `exp` × 1.0 (× 5 for elites). Pickups within the magnet radius (90 px) fly to the
  player; collecting plays `Game.img/PickUpItem` and shows "+N EXP" in MapleStory's yellow system-message style.
- **Survivor EXP curve:** `exp_to_next(L) = round(8 + 6·L + 0.6·L²)` (L1 = 15 like the canonical table; L7 = 79,
  L29 = 687). Expected pace: Lv 8 at about 3:00, Lv 10 at 4:00, Lv 30 near 13:00-15:00. The canonical v83 table
  (`data/canonical/exp_table.json`) is kept for reference and display only.
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
| Three Snails (1000) | Beginner | Throws a shell (`level/N/ball`) at the nearest mob within 420 px every 1.1 s; 400 px/s; `level/N/hit/0` on impact | ranks 1-3 = levels 1-3: green -> blue -> red shell, 10 -> 25 -> 40 damage | Additional Shell (+1 shell, ×4), Faster Snails (-12% cooldown, ×4), Piercing Shells (+1 pierce, ×3), Stronger Snails (+1 skill level, ×2), Rapid Snails (+25% speed, ×3) |
| Energy Bolt (2001004) | Magician | `ball` projectile at the nearest mob every 0.9 s; 450 px/s; `hit/0` | rank r = level 1 + 4(r-1) (L1, L5, L9, L13, L17, L20) | Extra Bolt (+1, ×3), Bolt Pierce (+1, ×2), Overcharge (+20% damage, ×3) |
| Magic Claw (2001005) | Magician | Instant 2-hit claw (`attackCount` 2) on the nearest mob within 260 px every 1.25 s; `effect` on caster, `hit/0` on target (`CharLevel` variant by level) | same mapping | Twin Claw (+1 target, ×2), Quick Claw (-12% cooldown, ×3) |
| Magic Guard (2001002) | Magician | Passive damage-to-MP split (`x`%) | L1, L5, L10, L15, L20 | ranks only |
| Magic Armor (2001003) | Magician | Passive PDD (`pdd`) | L1, L5, L10, L15, L20 | ranks only |
| Fire Arrow (2101004) | F/P Wizard | Phase 2 | | Additional Projectile, Piercing Flames, Burning, Rapid Casting, Larger Flames |
| Poison Breath (2101005) | F/P Wizard | Phase 2 | | |

Targeting: nearest living mob within range (spatial hash query), excluding mobs already targeted this cast when a skill
fires several projectiles. Projectiles fly straight toward the target's position at cast time and expire at their range.
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
3. With fewer than three eligible cards, fillers fill the gap (e.g. "Elixir": heal 50% HP/MP).
4. Applying a card takes effect immediately.

General cards: Max HP +10%, Speed (Nimble Feet 1002 icon) +6 speed stat, Recovery (1001) HP regen, Improved Max MP
Increase (2000001), Improved MP Recovery (2000000), Magnet +25% radius.

## 9. Jobs

`data/canonical/jobs.json` holds the Explorer tree with canonical ids (Beginner 0; Warrior 100, Magician 200,
Bowman 300, Thief 400, Pirate 500; second jobs 110-130 / 210-230 / 310-320 / 410-420 / 510-520; third and fourth
jobs). `data/survivor/jobs.json` marks which are playable in this build and what advancing grants.

At an advancement level the level-up window is preceded by the **Job Advancement** window (UI.wz window frame, job
book name from `String.wz/Skill.img/<job>/bookName`, `BasicEff.img/JobChanged` + `Game.img/JobChanged` on accept):

- Level 8: Magician (playable). Warrior, Bowman, Thief, Pirate are shown with their requirement ("Lv. 10").
- Level 10: the other four are shown as "not in this build". "Not now" keeps you a Beginner and asks again next level.
- Advancing: job becomes 200, MP +120, and the next card draw guarantees one Magician skill card.
- Level 30: F/P Wizard (Phase 2), I/L Wizard and Cleric shown as not yet available.

## 10. Presentation

- 800x600 logical view (wider windows show more map at the same pixel scale), integer scaling, nearest filtering. An
  opt-in "fill window" setting fills large windows with more map instead of black bars (see View fit below).
- HUD: `UI.wz/StatusBar.img` bottom bar with HP/MP/EXP gauges, level from `Basic.img/LevelNo`, job name; survival timer
  and kill count at the top; owned-skill icons with ranks at the top left.
- Text uses the system's Arial-like font without antialiasing at MapleStory sizes (no fonts are shipped).
- Map name and street name from `String.wz/Map.img` on the stage card and at run start.
- Death: `Effect.wz/Tomb.img` tombstone falls on the character with `Game.img/Tombstone`.

## 11. Constants and provenance

| Constant | Value | Tier | Source |
|---|---|---|---|
| Physics.img values | see `docs/research/wz-inventory.md` §2 | A | v83 Map.wz |
| Walk/jump/air/down-jump/landing model | §3 | B | NoLifeStory physics description |
| Player sub-step | 2 per 1/60 s tick | C | ours |
| Vertical air drag | none (apex 555²/4000 = 77 px) | C | ours; NoLifeStory's 100 px/s² vertical float drag would give ~73 px |
| Climb speed | 100 px/s | C | ours (HeavenClient uses 125) |
| Ladder grab/exit | Up: hands 50 px above the feet within 10 px of x; Down: 10 px below the feet; 0.25 s re-grab delay; exit jump vx = max walk speed, vy = jumpSpeed/1.5; `uf=1` top exit onto a floor within 24 px above / 4 px below the top | C | ours / HeavenClient exit jump |
| Down-jump reach | a floor within 600 px below | C | HeavenClient |
| Player knockback hop, alert stance | 200 px/s up, 2 s | C | ours |
| Player placement | `PlayerMotion.place()` snaps onto a floor at most 1 px below, else the player falls | C | ours |
| Falling out of the world | below the MapBounds bottom the player is put back on the nearest floor (`EV_FELL_OUT`) | C | ours |
| Wall probe | a wall blocks where it covers the point 1 px above the feet (a wall hanging below a platform end can be walked off) | C | ours |
| Ceilings (x1 > x2) | stop upward motion at the feet (head bump), never landed on; mobs never hop straight up through one | B | NoLifeStory description (prior-art.md §1b) |
| Map bounds without VR | miniMap rect (-centerX, -centerY, width, height), else foothold box with top -300 / bottom +100 | C | ours / HeavenClient border rule |
| Mob nav (`NavGraph`) | hop 555 px/s, jump height ≤ 70 px, takeoff ≤ 90 px from landing, land 8 px inside; a drop steps off the end at 120 px/s for 4 px, then falls straight down (the same for every mob, so the graph predicts its landing exactly) | C | ours |
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
| Player body (touch box) / cast origin | (-14,-58)-(14,0) from the feet / 30 px above the feet | C | ours |
| Cast stance | the skill's `action` (swingO1) for 0.8 s (its WZ frames 300+150+350 ms) while standing still | C | ours |
| Skill cooldown/range/speed/count/pierce, shot radius | `skills.json` (12-14 px radius); shots ignore terrain and die at their range or 200 px outside the bounds | C | ours |
| Shots with fewer targets than projectiles | the extra shots reuse targets, aimed 8 px apart | C | ours |
| Upgrade card values | `upgrades.json` (e.g. Max HP ×1.1, Nimble Feet +6 speed, Recovery +1 HP/s, MP Recovery +1 MP/s, Max MP +25, Magnet ×1.25) | C | ours |
| EXP drop motion | pop 260 px/s up, ±40 px/s sideways, Physics.img gravity onto floors; magnet 220 px/s + 1400 px/s²; collected within 24 px of the body centre (25 px above the feet); past 600 drops new EXP merges into the nearest | C | ours |
| Spawn rings | within 320 px of the view, then 960 px, then the map within 1170 px of the player; 12 samples per ring for a platform that reaches the player before an unreachable spot | C | ours |
| Mob recycling | silent, after 3 s farther than 1300 px, or on a platform that cannot reach the player and 320 px off-screen; never elites | C | ours |
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

## 12. Later phases

Phase 2: Fire/Poison Wizard (Fire Arrow, Poison Breath with DoT), more maps (The Tree That Grew I for Slimes,
Henesys Hunting Ground II), more mobs. Phase 3: other Explorer paths, 3rd/4th job, bosses (Mushmom, King Slime),
elite waves with modifiers, passive items, skill evolutions, run modifiers, persistent unlocks.
