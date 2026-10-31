# Survivor-genre progression replaces v83 progression

Until now the game tried to make progression faithful to v83: a character carried level, EXP, AP and skills from
round to round, advanced jobs at Lv10 and Lv30, learned passive-heavy skill trees, and wore equipment gated by level,
job and stats. It made the game a MapleStory simulator with swarms instead of a survivor game with MapleStory in it.
Most cards were passives and buffs, and the Warrior line had 3 actives in 29 skills. Levels and builds were tied
to a chained run, and each new job tier needed another tier of maps before it could even be reached.

From now on **MapleStory supplies the look, sound, monsters, maps and skills** (their animations and their WZ numbers
where useful), and **progression follows the survivor genre**. The in-run loop follows the reference
`outthislife/azeroth-survivors-re` (6 active slots, 6 passive slots, a fixed class pool, Lv1 every run). Per-character tier
progression and equipment are this game's own (the reference has neither). Decided by the owner in the 2026-10-27
grilling.

- **A character is one 4th job**, chosen at creation from the twelve v83 4th jobs (Hero, Paladin, Dark Knight, F/P
  and I/L Arch Mage, Bishop, Bowmaster, Marksman, Night Lord, Shadower, Buccaneer, Corsair). Beginner is no longer
  playable. There is no job advancement.
- **Every round starts at Lv1** with the job's starting skill in slot 1. A round is still a stage's three maps with
  one boss each (spec #241).
- **Skills:** each job has a hand-picked **skill pool** of actives from its whole 1st-4th job lineage, all
  auto-cast. A character fills at most **6 active skill slots** and **6 passive skill slots**. The passive slots draw
  from job-neutral **common passives** (Maple-named stat boosts). Job-specific passives and buffs are never in a pool.
- **Ranks 1-8** map to fixed WZ skill levels through a survivor-data table, so damage, mob count and attack count
  still come from WZ. Every card adds exactly one rank. A card for an active skill also rolls **rarity** (Fortune still
  applies), and its rarity attaches a **rarity bonus** to the rank. After rank 8 a skill keeps appearing as **Mastery
  cards** (a rarity bonus only, with diminishing returns), so an active skill never fully maxes. Common passives cap at
  rank 5 and never roll rarity.
- **No MP.** Skills are gated by their cooldown only. **No level-gap penalties:** the level difference between monster
  and character changes neither hit chance nor damage.
- **Damage keeps the Maple formula** with automatic AP, now in a single stat row per job.
- **Tiers unlock per character.** *(Superseded by [ADR 0007](0007-one-region-progression-per-character.md): one ordered
  region progression, and clearing a region unlocks the next.)* Every round is standalone, from the Free Market and back.
  Clearing any region of tier N unlocks tier N+1 for that character. Cleared tiers can be replayed.
- **No permadeath.** Death ends the round only. The character keeps its tier unlocks (superseded by ADR 0007: its cleared regions), its equipment, and the mesos and
  items picked up that round.
- **Equipment** keeps only its job-class requirement. Level and stat requirements are gone. `reqLevel` becomes the
  item's tier signal: each tier has a **drop band**, so lower tiers drop worse equipment (superseded by ADR 0007: each
  region carries its own drop band). Equipment, inventory and
  mesos belong to the character (no account storage). The upgrade path is unchanged: v83 scrolls, with the Free Market
  selling scrolls and buying equipment back.
- **Weapons don't gate skills.** Each job lists its allowed weapon families; drops roll only from them.
- **Manual mobility** (Teleport, Flash Jump, Dash) is on a skill key from Lv1, outside the slots.

## Considered options

- **Keep v83 progression and add 3rd/4th job:** rejected. It needs ever more tiers before a job is even seen, and it
  multiplies the passive-heavy cards that make level-ups dull.
- **Skill pool from the 4th job alone:** rejected. A 4th job has about 3-4 actives; the lineage gives 8-12 without
  inventing skills.
- **Active slots only, no passive track:** rejected. Once 6 actives are taken, level-ups repeat.
- **Rarity as cosmetic (the reference) or as a rank jump (+1/+2/+3):** rejected. The first throws away a system
  players already enjoy, and the second maxes an 8-rank skill in two cards.
- **No characters, an account with a job pick per round:** rejected. Names, looks, slots and creation are part of the
  Maple feel, and a new job = a new character gives per-job tier progress for free.
- **Permadeath:** rejected. With equipment as the long-term progression, a death would wipe everything.
- **Account-wide equipment storage:** rejected for now. It would make a new character's tier 1 trivial.
- **Dropping Maple stats for survivor stats:** rejected. Equipment's STR/INT/W.Att/M.Att and scrolls would need
  translating, and `combat_math` already works.
- **A new mode beside the old system, behind a flag:** rejected. It doubles the test and balance surface.

## Consequences

F/P (212, default) and Hero (112) are playable; #306 records the QA gates for the orchestrator’s `redesign` merge readiness decision.

- **Supersedes:**
  - ADR 0001: the chained run, carried level, EXP and skills, final-tier victory, and run-ending death.
  - ADR 0002: mesos ending with the run, and drops filtered by character level.
  - ADR 0005: weapon-gated skills, weapon paths, and carried attacks. How ammo tiers step without branches is left to the first ranged-job
    spec. *Settled by spec #332 (ticket #335, ruling D9): `survivor/ammo.json` schedules are keyed by the exact job and
    step at the round's level (GAME_DESIGN 7.41).*
- **Still holds:**
  - ADR 0002: shops sell only scrolls.
  - ADR 0003: account cash items. Fortune still comes from cash equipment.
  - ADR 0005: no MISS, and endless ammo.
- **Implementation:** the change replaces the old system in place, on the long-lived `redesign` branch. A vertical
  slice (F/P Arch Mage) comes first, then Hero, then the other ten jobs one spec at a time. `redesign` merges to `main`
  (and so to GitHub Pages) once F/P and Hero are both playable.
- **Saves:** old saves are not migrated. Save format 3 moves old slots to the run history.
- **Removed systems:** job advancement and its windows, the advancement draw, weapon paths, carried attacks, MP
  (potions, Magic Guard, the MP pouch and MP ALERT, MP-short tracking), level-gap rules, AP splits by path, and
  equipment level and stat requirements.
- **Pacing:** the slice may set first-pass pacing (an EXP curve for about 75 picks per round, common passive values,
  rarity bonus sizes), all tier C. The frozen balance pass waits until most new systems are in, and uses the reserved
  701-730 seeds.
- **Later:** a tier rework with fewer starting choices (closer to the reference), more tiers and drop bands, card
  reroll and banish, and account storage are all left for later specs.
