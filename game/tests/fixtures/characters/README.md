# Character fixtures

`fp_arch_mage.json` is the F/P fixture: a format-3 Arch Mage (F/P, job 212) at the start of a round, with
tier 2 unlocked and the tier-1 equipment kit worn: a reqLevel-25 staff (1382002), a reqLevel-30 hat (1002013), reqLevel-20
shoes (1072019), reqLevel-15 gloves (1082019) and the starter top and bottom. The items are unscrolled, with canonical
base stats and no survivor overrides. A format-3 character keeps only its job, look, equipment, scrolls, mesos, cash, pet
and `tiers_unlocked` (ADR 0006), so there is no level, skill list or AP to carry; every round starts at Lv1. It is the
character for Sleepywood checks (`--stage=sleepywood --character=<this file>`), paired with a fresh character (the starter
wand only) to show what gear is worth, and the base of the `--hub` test kit.

`il_arch_mage_t2.json` is the I/L Arch Mage (job 222) twin (spec #319, I11): the same tier-1 kit and tier 2, made by
`tools/character_fixture.gd --job=222 --kit=1382002,1002013,1072019,1082019,1040002,1060002 --tiers=2 --label=spec319/ticket-330
--patch=<json making 222 playable>` while I/L is `playable: false` (its `_doc.patch` names the patch file; from I12 on the
flag is not needed). `--hub --job=222` opens it. A `--character` of this file runs as an I/L whatever `--job` says, and
`--job=212` with it is an error.

`tools/character_fixture.gd --kit=1382002,1002013,1072019,1082019,1040002,1060002 --tiers=2` reproduces it exactly (its
`_doc` records the ids, the revision and the label). The tool's other modes write the character a real bot round leaves
behind (its pickups, the tier its clear unlocks) and convert older files. Tool files of format 1 or 2 still load
(`CharacterSnapshot.migrate` keeps the format-3 part). The fixtures of the unported job lines and of the second jobs were
deleted with job advancement (#284, #286, #294).

`hero_t2.json` is the Hero (112) fixture: tier 2 unlocked and the tier-1 equipment, inventory, scrolls and mesos
from a seed-1 Henesys bot clear. Reproduce with `tools/character_fixture.gd --job=112 --god --seed=1
--label=spec296/ticket-306 --revision=<SHA> --out=<absolute path>`. No playable patch is needed. The `_doc` records
seed, policy, revision and invulnerability: this is a diagnostic clear to obtain equipment, not evidence that the bot
survives Henesys. The worn weapon is a two-handed axe (1412006); the equipment retains canonical stats. Use it for
`--stage=sleepywood --job=112 --character=<absolute hero_t2.json>` or `--hub --job=112`.

`bishop_t2.json` is the Bishop (job 232) twin (spec #372, BS9 #381): the same tier-1 kit as F/P's and tier 2, made by
`tools/character_fixture.gd --job=232 --kit=1382002,1002013,1072019,1082019,1040002,1060002 --tiers=2 --label=spec372/ticket-381
--patch=<json making 232 playable>` while Bishop is `playable: false` (its `_doc.patch` names the patch file, and its
`_doc.revision` is the integration tip it was made on; BS10 can re-make it without `--patch`). The worn equipment is identical
to `fp_arch_mage.json`'s (a Bishop wears the same wands and staves). `--hub --job=232` opens it through the job's `hub_kit`.
A `--character` of this file runs as a Bishop whatever `--job` says, and `--job=212` with it is an error.
