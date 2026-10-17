# A run is a series of rounds with one persistent character

A single 15:00 stage capped a character in the mid-30s, so later jobs could never be reached. A run is now one
character playing one stage per tier, round after round, with level, EXP, job, AP stats, skills and potions carried
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

## Consequences

- Quitting mid-round loses that round's progress, and the pause menu has to say so.
- Single rounds outside a run (playtests, balance runs) are tool-only one-off rounds that never touch the character
  slots or the best results.
