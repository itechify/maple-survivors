# v83 mob skills and boss attacks for Boss kits II (#448)

> Research for the region progression (#447, #448, #449), 2026-10-30. The numbers are read from the owner's v83 files with `tools/wzimport dump` (`Skill.wz/MobSkill.img/<id>/level/<lv>`), using throwaway scripts that are not committed (mentions of `_scratch/` are those).
>
> Behaviour descriptions are prose summaries of third-party emulator behaviour and secondary wiki text. Nothing was copied from AGPL/GPL/MPL sources.
>
> Provenance tiers:
> - **A:** a value read from v83 WZ.
> - **B:** third-party reverse engineering or emulator behaviour, used as fact.
> - **C:** our own inference or proposal.

## Field semantics and data traps

**Fields:**
- `interval`: the cooldown, in seconds (A).
- `time`: how long the effect lasts, in seconds (A).
- `prop`: a percent chance, rolled first (A+B).
- `lt`/`rb`: a box relative to the boss, mirrored by facing (A).
- `hp`: the skill casts only at or below this percent of HP (A).
- `limit`: the cap on living summons for MobSkill 200.
- `count`: the most players Seduce hits (B).
- `mpCon`: a mob MP cost; our sim ignores it.

**Art nodes:**
- `affected`: art over the debuffed player. Every level of 120-133 has one.
- `effect`: art on the caster or the area.
- `mob`: the status icon.
- `mob0`: art on the mobs a buff reaches.
- `tile`: 131's 11-frame mist art.

**Traps:**
- Level 2 of 132 spells its interval key `inteval` (value 60).
- Level 12 of 121 is empty.
- Levels 6-8 of 120-125 hold only `time`, `prop` and `x`. They are event or test levels, with no area and no interval.
- A boss's `info/skill/N` holds `skill`, `level`, `action` (stance skillN) and `effectAfter`.

**Emulator facts (B):**
- A player holds at most 2 diseases at once.
- The value sent to the client is `x`; expiry is `time`.
- Holy Shield blocks area diseases and Stun.
- A boss with magic immunity up can't put up physical immunity, and vice versa.

## Buffs 101/102/103/111 (Chimera 8220002, Dodo 8220004, Eliza)

| id | boss, level | x | interval | time | area |
|---|---|---|---|---|---|
| 101 MAD up (self) | Chimera L1, Eliza L1 | 115 | 35 | 30 | none |
| 111 MAD up (area) | Chimera L5 | 140 | 60 | 30 | (-400,-350)-(400,250) |
| 111 MAD up (area) | Eliza L2 | 115 | 40 | 30 | (-300,-200)-(300,200) |
| 102 PDD up (self) | Dodo L3 | 85 | 30 | 20 | none |
| 103 MDD up (self) | Chimera L2 | 60 | 40 | 30 | none |

All have an `effect` (position 3) and a `mob` icon (A).

How they map here: 101 and 111 add a magic multiplier `x/100` next to `attack_up_mult`, so today's "magic attacks unchanged" no longer holds (C). 102 and 103 are self-only variants of 112/113. Each is cost S.

## Player statuses

`prop` is rolled once per cast on a player inside the area. A failed roll still spends the interval.

| id | v83 effect | levels used (interval / time / prop, area) | tier | here | cost |
|---|---|---|---|---|---|
| 120 Seal | No skills; the basic attack still works. **Stays unsupported** (owner rule). | Alishar L1, Thanatos L1: 10/30/50, (-300,-120)-(300,120) | B | none | - |
| 121 Darkness | Accuracy down and a dimmed screen. There is no `x`; the size is client-side. | Alishar L1: 10/30/50, same box. Fox L7: 15/10/80, same box, has an `effect`. Eliza L7: as Fox. Thanatos L1: 10/30/50. | B | Crit chance 0 for `time` (ADR 0005 maps accuracy to crit), plus a screen vignette with a lit circle round the avatar (C) | M |
| 122 Weakness | Can't jump (secondary wiki; no `x`). | Fox L10: 30/10/80, (-200,-120)-(200,30). Leviathan L3: 45/30/70, (-450,-300)-(450,300). | B | Jump disabled (the hook is in `refresh_player_speed`) | S |
| 123 Stun | Can't move, jump, attack or cast; art above the head. | Timer L1, Gatekeeper L1: 10/5/50, ±300×120. Fox L7: 30/5/60, (-350,-150)-(30,25). Snowman L8, King Clang L8: 15/2/60, (-200,-120)-(200,20). Papulatus clock L4: 1/3/100, ±300×120. | A values, B behaviour | Port from `origin/spec-264-nautilus` (below). Papulatus L4 would chain-stun, so add a lockout floor (C). | M |
| 124 Curse | EXP gained is halved. | Thanatos L1: 10/60/50, ±300×120 | B | `_gain_exp` ×0.5 while active | S |
| 125 Poison | HP lost over time. `x` per second is the likely reading (x runs 15..300); unverified. | Thanatos L1: 10/60/50, x15, (-150,-90)-(0,0), a strip in front | B/C | A timed DoT of `x` per second that never kills (it leaves 1 HP), with a new hit `source_kind` | M |
| 127 Dispel | Removes the player's active buffs. | Papulatus clock L1: interval 1, prop 100, no `time`, ±300×120 | B | Cancel timed self-effects, with a floor of at least 20 s (C) | S-M |
| 128 Seduce | The player is forced to walk toward the caster and input is ignored. What `x` (1..7) means is unverified. One emulator makes the player sit instead. | Lyka L7: 20/10/80, x6, (-310,-400)-(500,300) | B/C | Force horizontal input toward the boss for min(time, 4 s) (C cap) | M |
| 131 Mist | A mist box stays in front of the boss for `time`. `x` is its strength, unit unclear. `elemAttr` is S (poison) or I (ice). | Snowman L7: x500, 30/10/80, (-50,-160)-(300,40), `elemAttr` I | A values, B/C behaviour | A hazard box for `time`: Slow if I, a Poison DoT if S. Needs a hazard entity and the `tile` art. | L |
| 132 Confuse | Reversed controls. The WZ level notes say "great confusion". | Leviathan L2: x1, 60 (key `inteval`)/15/100, ±300×120 | B | Swap left and right input for `time` | S |
| 133 Undead | Zombify: recovery is reversed. | None of the chosen bosses. Balrog 8830000 L3: 60/7/100, hp<=25, (-800,-600)-(800,250). | B | Potions deal their amount as damage (C) | S-M |

126 Slow, 129 Banish and 140 are already supported. For reference:
- Papulatus clock 126/1: 5/10/100, x80, ±300×120.
- Dodo 129/2: 50/1/80, count 1, (-64,-150)-(58,44).
- Timer 140/12: x1, 30/10, no hp gate.

## Immunity and reflect (141, 143-145)

**141 magic immunity** (Timer L3):
- Values: x1, hp<=50, 30/10, with a `mob` icon.
- It mirrors 140 as a self status: the boss takes no magic damage for `time`.
- Emulators refuse it while 140 is up, and the reverse.
- The runner's `physical` array is the hook; add a magic one. Cost S-M.

**143/144/145 reflect:**
- Levels:
  - Lilynouch 145/1: x2000, y1500, hp<=50, 60/10.
  - Oberon 143/4: x3000, y3000, hp<=60, 30/7.
  - 144/1: x10000, y10000, 80/20.
  - Balrog 145/3: x5000, y8000, hp<=95, 60/7.
- One emulator fixes the reflect and immunity to 10 and stores `x`.
- The pattern suggests `x` is a reflect rate in basis points (10000 = 100%) and `y` a cap per hit (C).
- Here: matching hits deal 0 to the boss and hurt the player for min(damage × rate × k, a scaled cap), rate-limited so a swarm can't one-shot. Cost M.

The runner heals a flat `x` for 114. One emulator's area heal is about x/1000 × a random 950-2000 per mob, which is more than a flat `x`.

## Mob attack `info/type` 3 and 4

How often each type appears across Mob.wz: type 0 has 636 nodes, 1 has 129, 2 has 110, 3 has 65 and 4 has 5. Types 3 and 4 are **area-warning strikes**: ground columns announced by `areaWarning` art, then struck at `attackAfter`.

`range` fields (A):
- `lt`/`rb`: the box of one column. Thanatos is -33..44 by -109..4, Lyka -40..40 by -200..0, Eliza -20..20 by -75..10.
- `start`: the leftmost column index, -3 to -15.
- `areaCount`: the length of the strip, 7-31 columns, usually 2·|start|+1.
- `attackCount`: how many columns are struck, 3-9.

| mob | attack | type | start / areaCount / attackCount | attackAfter | other fields |
|---|---|---|---|---|---|
| Thanatos 8170000 | attack1 | 3 | -5 / 9 / 5 | 1080 | effectAfter 720, elemAttr I, magic |
| Eliza 8220000 | attack1 | 3 | -9 / 15 / 4 | 1200 | `effect` frames are 4×4 blanks; magic |
| Lyka 8220006 | attack1 | 4 | -7 / 15 / 7 | 1260 | PADamage 720, hit `attach` |
| Horntail head | attack2 | 4 | -15 / 31 / 7 | 2660 | elemAttr I, deadlyAttack |

Other fields on these nodes:
- Always: `areaWarning` and `hit`.
- `effect` appears on only 12 of the 65 type-3 nodes, and never on type 4.
- Some carry `conMP`, `magic`, `elemAttr` or `PADamage` (explicit damage, for example Balrog 560).
- A few carry `disease` + `level` (for example Pink Bean and Zakum type-3 attacks, 123 and 128).
- Others carry `deadlyAttack`, `tremble` or `doFirst`.

The data doesn't say which columns get struck, or how 3 differs from 4. Proposal (C), one code path for both:
- columns are |lt.x - rb.x| wide and centred on the boss;
- `attackCount` columns are picked on a dedicated RNG stream, always including the one under the player, so the attack is dodgeable but never ignorable;
- the warning art plays at attack start and the damage lands at `attackAfter`.

Cost M.

The other chosen bosses carry only types 0, 1 and 2:
- None carries `disease` on an attack node.
- Gatekeeper's attack1 has PADamage 600 and effectAfter 720.
- Timer (type 1) and Snowman, Chimera and Dodo (type 2) have `bulletSpeed` 140.
- Papulatus clock's attack3 has an `effect0` of secondary strikes at random spots: effectType 1, randomPos, distance 300, delay 1100, box (-800,-350)-(800,250).
- Papulatus clock's attack1 has `deadlyAttack` and `doFirst`.

## Flying bosses

**Papulatus 8500002**, the revive of clock 8500001:
- Stances `fly`, `stand`, `hit1` and `die1`; no `attackN` and no skills.
- It attacks by touch only: bodyAttack, PADamage 800, MADamage 1000, speed 60, `firstAttack`.

**Crimson Balrog 8150000:**
- `fly`, flySpeed 10, no skills.
- attack1 is type 2: a ball, attackAfter 400, magic.
- attack2 is type 0: an effect, effectAfter 0, attackAfter 720, magic.

The attack nodes are ordinary; only the flight stance and free movement differ. `BossAttacks` skips a boss with no foothold (`swarm.fh[slot] < 0`). Let a `fly`-stance boss attack from its own position and reuse the swarm fliers' movement. Cost M.

## What `origin/spec-264-nautilus` did (base `main`, 6ac67b90)

### Stun 123

- `mob_skill_runner.gd` adds `SKILL_STUN`, `_stun_until`, `_stun_visual`, `is_stunned` and `stun_state`:
  - an in-area cast rolls `prop` on an isolated RNG;
  - success sets `_stun_until = now + time`;
  - a failed roll spends the interval, and Hidden skips the cast.
- `run_world.gd`:
  - adds `mob_status_rng` as stream 18;
  - `_step_player` swaps in an empty `MoveInput` while the player is stunned (gravity, knockback and damage go on);
  - potions stay usable, and `can_cast()` returns false;
  - `_play_final_attacks` clears its queue;
  - `player_state["stun"]` exists only while the stun is active.
- `basic_attack.gd` drops a swing that is in wind-up.
- `run_scene.gd` keeps `_stun_fx`, which repeats the `affected` art above the head.
- Tests: `test_player_stun.gd` (8 cases) and `test_player_stun_render.gd`.
- **Port hazard:** redesign already uses stream 18 for `ground_rng`, so Stun needs a new stream (19).

### final_form

- A `stages.json` boss entry carries `"final_form": <mob id>`, which must be in the boss's `info/revive`.
- `BossDirector.continue_final_form()` respawns the final form at the death position, in the same encounter:
  - same `boss_index`, `hp_mult` and steady flag;
  - the record's slot, identity, mob_id and anchor are updated;
  - the action state is reset and `mob_revives_spawned` is emitted.
- `RunWorld._on_boss_kill` calls it first and returns early, so the shell gets no reward and no `mark_dead`.
- `RunWorld.spawn_boss()` is factored out of `BossDirector.step`.
- `stage_roster.gd` adds the final form's id to `named_ids`, and its skills and summons to `mob_ids`.
- Both ids go in `balance.mob_skills.enabled_ids`.
- The branch splits King Clang's 7000 HP by `hp_mult` as 966 + 6034.
- Limitation: `entry.attacks` is per boss entry, not per form.
- Redesign's `_on_boss_kill` ends the encounter and spawns revives as offspring, so this has to be ported by hand.

## Not verified

Exact v83 client behaviour for Darkness, Weakness, Seduce and Undead, and the units of `x` for 125, 128, 131 and 143-145, couldn't be confirmed from open sources. They stay tier B/C and should be settled by how they feel in playtests.
