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

`bowmaster_t2.json` is the Bowmaster (312) fixture (spec #332, B12 #344): a format-3 Bowmaster at the start of a round with tier 2
unlocked and the tier-1 bow kit worn: a Battle Bow (1452000, reqLevel 25, PAD 40), a Bowman-bit reqLevel-30 hat (1002163),
reqLevel-20 shoes (1072025), reqLevel-15 gloves (1082012) and the starter top and bottom, unscrolled. It is kit mode like
`fp_arch_mage.json`, so its `_doc` records the kit ids, label and revision, no seed or policy. Reproduce with
`tools/character_fixture.gd --job=312 --kit=1452000,1002163,1072025,1082012,1040002,1060002 --tiers=2 --label=spec332/ticket-344
--revision=<SHA> --out=<absolute path> --patch=<playable patch>` (the patch is needed until B13 flips `playable`; `_doc.patch`
records its file name). **The bow matters**: a Bowmaster with no bow in hand has no ammo and every run lists the arrow sprite
(`Item.wz/Consume/0000.img/00000000/bullet`) in `missing`; use this file for `--job=312 --character=<absolute path>` runs, `--stage=sleepywood`
checks and `--hub --job=312`.

`marksman_t2.json` is the Marksman (322) fixture (spec #360, MS10 #370): a format-3 Marksman at the start of a round with tier 2
unlocked and the tier-1 crossbow kit worn: a Balanche (1462003, reqLevel 22, PAD 39), the same Bowman-bit reqLevel-30 hat (1002163),
reqLevel-20 shoes (1072025) and reqLevel-15 gloves (1082012) as `bowmaster_t2.json`, and the starter top and bottom, unscrolled. Kit mode,
so its `_doc` records the kit ids, label and revision. Reproduce with `tools/character_fixture.gd --job=322
--kit=1462003,1002163,1072025,1082012,1040002,1060002 --tiers=2 --label=spec360/ticket-370 --revision=<SHA> --out=<absolute path>
(no playable patch: MS11 #371 flipped `playable`; the file was first generated with a patch and its `patch` key dropped when 322 shipped). **The crossbow matters**: a
Marksman with no crossbow in hand has no ammo and every run lists the bolt sprite (`Item.wz/Consume/0000.img/00000000/bullet`) in `missing`.
Use it for `--job=322 --character=<absolute path>` runs, `--stage=sleepywood` checks and `--hub --job=322`; `--job=212` with it is an error.

`dark_knight_t2.json` is the Dark Knight (132) fixture (spec #348, D10 #358): tier 2 unlocked and the equipment, inventory,
scrolls and mesos from a seed-1 Henesys bot clear. Reproduce with `tools/character_fixture.gd --job=132 --god --seed=1
--label=spec348/ticket-358 --revision=<SHA> --out=<absolute path>`; no playable patch is needed (D10 flipped `playable`). The
`_doc` records seed, policy, revision and invulnerability: this is a diagnostic clear to obtain equipment, not evidence that
the bot survives Henesys. The worn weapon is a Pole Arm (1442004), the equipment retains canonical stats. Use it for
`--stage=sleepywood --job=132 --character=<absolute dark_knight_t2.json>` or `--hub --job=132`.


`paladin_t2.json` is the Paladin (job 122) fixture (spec #308, P9 #317): a kit fixture like `fp_arch_mage.json`, a fresh Lv1
character with tier 2 unlocked wearing a Lv25 Mace (1322004, a blunt weapon), the all-job hat 1002001, gloves 1082002 and top
1040010 (the Warrior-bit pieces Hero's hub kit also uses) and the starter bottom and shoes, unscrolled. Reproduce with
`tools/character_fixture.gd --job=122 --kit=1322004,1002001,1082002,1040010,1060002 --tiers=2 --label=spec308/ticket-317
--revision=<SHA> --out=<absolute path>`; no playable patch is needed. The `_doc` records the kit ids, label and revision. Use it
for `--stage=sleepywood --job=122 --character=<absolute paladin_t2.json>` or `--hub --job=122`; `--job=212` with it is an error.

`bishop_t2.json` is the Bishop (job 232) twin (spec #372, BS9 #381): the same tier-1 kit as F/P's and tier 2, made by
`tools/character_fixture.gd --job=232 --kit=1382002,1002013,1072019,1082019,1040002,1060002 --tiers=2 --label=spec372/ticket-381
--patch=<json making 232 playable>` before BS10 enabled Bishop (its `_doc.patch` names the patch file, and its
`_doc.revision` is the integration tip it was made on; new generation uses shipped data without `--patch`). The worn equipment is identical
to `fp_arch_mage.json`'s (a Bishop wears the same wands and staves). `--hub --job=232` opens it through the job's `hub_kit`.
A `--character` of this file runs as a Bishop without a `--job` flag; an explicit different job (e.g. `--job=212`) is an error.

`buccaneer_t2.json` is the Buccaneer (512) fixture (spec #412, B11 #423): tier 2 unlocked and the tier-1 knuckle gear, inventory
and mesos from a seed-1 Henesys bot clear (the worn weapon is the Lv25 knuckle 1482003). Reproduce with `tools/character_fixture.gd --job=512 --god --seed=1 --label=spec412/ticket-423
--revision=<SHA> --out=<absolute path>`. No playable patch is needed. The `_doc` records seed, policy, revision and
invulnerability: this is a diagnostic clear to obtain equipment, not evidence that the bot survives Henesys. Use it for
`--stage=sleepywood --job=512 --character=<absolute buccaneer_t2.json>` or `--hub --job=512`. **It must wear a knuckle:
without one the weapon reach and `weapon_reach` skills have nothing to read.**

Buccaneer review cleanup (#412): the diagnostic tier-2 fixture excludes the default sword 1302000 and displaced default outfit 1072001/1060002/1040002; its worn knuckle kit and round loot are unchanged.
