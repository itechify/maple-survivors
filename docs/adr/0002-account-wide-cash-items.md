# Cash items belong to the account and are shared by every character

Meta-progression is NX, earned at the end of every round and kept on the account, spent in a v83-style Cash Shop
(decided by the owner in #34 triage on 2026-10-16). A cash item is bought once, never expires, can't be bought twice
and can be used by every character at the same time; nothing moves between a locker and one character as in v83.
Cash equipment is the main source of Fortune: every filled cash slot adds a fixed amount (an overall fills top and
bottom, a two-handed weapon cover fills weapon and shield), so which item fills a slot is purely about looks. Pet
upgrades also belong to the account and apply to whichever pet is out.

The account lives in the same save file as the character slots (format 3, migrated from format 2) so it shares the
atomic write, backup and corrupt-file handling, and the NX award at a death is written in the same save as the run
archive. A separate account file was rejected because two files can disagree after a crash.

## Considered options

- **v83 locker, one copy per item:** rejected; with three living characters it makes an item useless to two of them.
- **Fortune per item:** rejected; the best set would be one fixed outfit, and looks would cost power.
- **Extra character slots for NX:** dropped; three living characters are enough.

## Consequences

- Fortune from cash equipment is computed live each round and never written into the character, so it can't
  compound across rounds and changing an outfit takes effect at the next card draw.
- Cash items carry no other stats for now; other stats (e.g. meso drop rate) may be added later.
- Tool rounds (balance, playtests, `--run`) take an account file, record the NX a round would award and never
  credit it.
