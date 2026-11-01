# Equipment drops from monsters, and Free Market shops sell only scrolls

> **Partly superseded by ADR 0006** (2026-10-27): mesos and equipment stay with the character instead of ending with
> the run, and drops follow the tier's drop band instead of the character's level; equipment has no level or stat
> requirement, only the job class (#292), and a job lists the weapon families it can receive. Shops still sell only scrolls.

v83 towns had NPC shops that sold equipment and potions. Ours sell neither. Equipment comes only from monster drops,
always wearable by the character's current job, and the Free Market's NPC shops sell only scrolls (one NPC per
success rate: 100%, 60%, 10%, and the dark 70%/30%). Mesos therefore buy one thing: the chance to improve the
equipment the character found. Decided by the owner in the #33 triage on 2026-10-16, replacing the spec's original
plan of shops selling potions and equipment, so that the main Free Market activity is buying scrolls to upgrade the
equipment a run has found.

## Considered options

- **Shops sell equipment (the original spec):** dropped in favour of drops plus scrolls, above.
- **Shops sell potions:** rejected. The current model uses unlimited potions on independent per-kind cooldowns
  (owner, spec #237, 2026-10-21), with tiers derived from level (spec #225).

## Consequences

- Every piece of equipment is an instance with its own rolled stats, remaining upgrade slots and scroll count, so
  saves store item instances, not just item ids.
- Drops are filtered to the character's job line and all-job equipment, so other classes' equipment never drops and
  the shops stock only scrolls that fit what can drop.
- Selling spare equipment back to any shop (at its v83 sell price) is the second source of mesos.
- A failed dark scroll can destroy worn equipment, the weapon included; a character without a weapon fights
  bare-handed, as in v83.
- The meso drop multiplier is survivor data, so NX upgrades (#34) can raise it later.
