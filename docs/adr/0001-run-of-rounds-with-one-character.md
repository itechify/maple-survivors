# A run is a series of rounds with one persistent character

> **Superseded by ADR 0006** (2026-10-27) on the `redesign` branch, and landed by #286 (save format 3): rounds are
> standalone, every round starts at Lv1, tiers unlock per character and death ends only the round. A character now
> keeps only its identity and belongings (name, look, job, equipment, inventory, scrolls, mesos, cash, pet, unlocked
> tiers); the run snapshot with a next stage and seed is gone, and the hub is where saves happen. Format 1 and 2
> characters are not migrated: they move to the history. The rule against saving live simulation state still holds,
> and so does "quitting mid-round loses that round" (Quit round ends it like a death and keeps the pickups).

A single 15:00 stage capped a character in the mid-30s, so later jobs could never be reached. A run is now one
character playing one stage per tier, round after round, with level, EXP, job, AP stats and skills carried
over, and HP and MP refilled at every round boundary. Death ends the run, and clearing the last tier is a victory
(decided by the owner on 2026-10-15, refined in #32 triage on 2026-10-16).

The run is saved only at round boundaries, never mid-round. The run snapshot holds the character plus the next
round's stage and seed, so quitting mid-round and continuing replays that same round from its start. The round
simulation stays one deterministic world per round that takes the carried character in as plain data and gives it
back at the end. Saving the live simulation was rejected: it would tie the save format to every simulation detail,
and it would let a player quit until a bad seed went away.

Amended in the #33 triage (2026-10-16): the carried character also holds its mesos, worn equipment and inventory
(spare equipment and scrolls). Equipment changed or scrolled mid-round is lost with the rest of that round's progress
if the player quits and continues. Mesos, equipment and scrolls end with the run (ADR 0002).

Amended by spec #237 (2026-10-21): potions are unlimited on independent per-kind cooldowns. Their item tiers derive
from the character's level; neither stock nor cooldowns carry between rounds. Every round starts with both kinds ready.

Amended by spec #241 (2026-10-21): each stage is a region's ordered three maps, and a round plays all three.
Each map's boss arrives 300 seconds after entering it; killing it and finishing its choices transfers to the next
map automatically. HP, MP, buffs, cooldowns and accumulated results carry within the round; boss-inflicted statuses
and map entities clear. Only the third map clear ends the round. Saves remain at round boundaries: Save & quit
on map 2 or 3 and Continue replays from map 1 with the same seed and boundary character. A map transfer is not a
save boundary. This preserves the original decision against serializing live simulation state.

## Consequences

- Quitting mid-round loses that round's progress, and the pause menu has to say so.
- Single rounds outside a run (playtests, balance runs) are tool-only one-off rounds that never touch the character
  slots or the best results.
