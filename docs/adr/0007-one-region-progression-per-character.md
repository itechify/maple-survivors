# One region progression per character replaces tiers

ADR 0006 kept two **tiers**. Tier 1 offered four regions at once, and clearing any of them unlocked tier 2 (Sleepywood).
The owner asked on 2026-10-30 for the map system to work like the reference `outthislife/azeroth-survivors-re`
(sixteen zones, ordered from the starting zones to the endgame). A new character starts with only one region open and
works through the others one at a time, in the order a v83 character levelled. The three-map round of spec #241 stays.

- **The progression.** `stages.json` holds one ordered list of regions, `progression`, which replaces `tiers`. The
  order follows where a v83 character hunted as it levelled: Henesys, Ellinia, Perion, Kerning City and Sleepywood on
  Victoria Island, then Ludibrium, Omega Sector, Korean Folk Town, Mu Lung, El Nath, Magatia, Zipangu, Leafre, the
  Phantom Forest, the Ludibrium Clocktower and the Temple of Time.
- **Unlocks are per character.** A character starts with the first region open. Clearing a region (its third map's
  boss dead and the round CLEARED) unlocks the next one. Every cleared region can be replayed. The character keeps the
  set of regions it has cleared, not a counter, so a region inserted into the list later doesn't shift anyone's unlocks.
  A character is one job (ADR 0006), so this is also per class.
- **No boss appears twice.** Across the whole progression every scheduled boss is a different v83 mini-boss, field
  boss or area boss. Two ids of the same monster (the two Blue Mushmoms) count as one boss.
- **Difficulty rises along the list.** Every round still starts at Lv1, so the character's level never tells the
  regions apart. What does is the monsters, the **drop band** each region carries (now per region, not per tier) and
  the equipment a character brings back. From Ludibrium on, monster rosters are Lv40-160 in v83, beyond anything a
  Lv1-55 round can fight at canonical strength. Those regions use a **level scale**: each monster's HP, damage,
  defence and EXP are rescaled from its own v83 level to the region's **effective level** at that point of the round,
  using reference curves of v83 ordinary monsters by level. The effective level rises a little from one region to the
  next. Canonical stats stay untouched in the cache; the scale is a survivor multiplier (tier C).
- **Map select is the progression list.** Every region is shown in order with its v83 level range, as the reference
  shows "Level 1-10". Locked regions are greyed and say which boss opens them, and cleared regions are marked. The
  first uncleared region is selected by default.

## Considered options

- **The reference's flat list, with every zone open:** rejected. The owner asked for gated progression, and our
  equipment and drop bands are long-term progression the reference doesn't have. A flat list would make every band
  reachable on the first day. We keep the reference's list shape, its level-ordered sequence and its per-zone level
  range.
- **Keep tiers and add more of them:** rejected. A tier with several regions is a choice the owner no longer wants at
  the start, and "clear any of them" lets a character skip most bosses.
- **Unlock on any map clear, or on map 1's boss:** rejected. The owner's rule is the last boss of the region.
- **Per-account unlocks:** rejected. ADR 0006 made a new job a new character with its own progress.
- **A counter of unlocked regions:** rejected. A key set survives reordering and new regions.
- **Canonical stats with hand-tuned opening ramps per stage (Sleepywood's #307 method) for every new region:**
  rejected. Eleven regions of hand-tuned ramps don't scale, and Lv100+ rosters can't be ramped from canonical HP
  without near-zero start multipliers. The level scale keeps each monster's toughness relative to its level, so a
  tanky monster stays tanky.
- **The reference's identical ladder for every zone (difficulty as flavour only):** rejected. With gating and drop
  bands, a later region has to be harder.
- **Expedition bosses (Zakum, Horntail, Pink Bean, Pianus) as finales:** left for later. Their multi-part bodies and
  attacks are a project of their own, and the owner asked for mini-bosses and field bosses.

## Consequences

- **Supersedes** the tier rule of ADR 0006 ("Clearing any region of tier N unlocks tier N+1") and its per-tier drop
  bands. Everything else in ADR 0006 holds.
- **Saves:** `tiers_unlocked` migrates to the cleared set. A character with tier 2 unlocked counts the first four
  regions as cleared, so it keeps Sleepywood; any other character keeps only Henesys.
- **Tools:** `balance.sh --tier=N` becomes `--chain=N`, which plays the first N regions in order, each clear feeding
  the next. `character_fixture.gd --tiers=2` keeps working as "the first four regions cleared". The regression smoke's
  "tier-1 stages" are the first four regions.
- **Henesys, Kerning City and Sleepywood keep their stage data.** Ellinia and Perion change bosses so that no boss
  repeats.
- **Later:** expedition-boss finales, a Nautilus region (no unused Victoria boss is left for it), card reroll and
  banish, account storage.
