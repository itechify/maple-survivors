# Character fixtures

`fp_arch_mage.json` is a committed character: a format-3 Arch Mage (F/P, job 212) wearing the gear of a real
headless Henesys bot character (spec #32, seed 1; `_doc` records the revision and options). It was converted from the
old format-2 file by spec #286 (`_doc.migration_286`): a format-3 character keeps only its job, look, equipment,
scrolls, mesos, cash, pet and `tiers_unlocked` (ADR 0006), so the level, skills, card ranks and AP it once carried are
gone. The fixtures of the unported job lines (Warrior, Thief, Bowman, Pirate, second-job Magician) were deleted with
job advancement (#284, #286).

Tool files of format 1 or 2 still load (`CharacterSnapshot.migrate` keeps the format-3 part). New fixtures come from
`tools/character_fixture.gd`, which writes the character a bot round leaves behind (its pickups, unlocked tiers).

`tier1_fp.json` (#293) is a synthetic, unscrolled format-3 tier-1 kit for paired pacing checks: a reqLevel-25
staff, reqLevel-30 hat, reqLevel-20 shoes and reqLevel-15 gloves, plus starter clothes. Item stats are canonical
base equipment stats, not survivor overrides; `_doc` records its purpose. No cash, pet or carried skills.
