class_name WeaponInfo
extends RefCounted
## What the weapon swing (its reach, WeaponReach) and physical damage need to know about a weapon (docs/GAME_DESIGN.md
## 6.1.1; the automatic basic attack itself is gone, #284), from its original item id and its
## canonical Character.wz/Weapon info node: the weapon type (id / 10000), physical formula stats and multipliers, the
## afterimage (info/afterImage) with its hit-spark family, the canonical attack interval (info/attackSpeed) and the
## swing sound (info/sfx). Read by CombatMath, WeaponReach and DataRepo (which afterimage imgs a setup loads). The
## "basic" stance sets below are the stances a weapon swings in (reach boxes, physical skills' default stance).
## Pure: plain data in, values out.

## Weapon type (item id / 10000) of one-handed swords (Character.wz/Weapon/0130xxxx).
const TYPE_ONE_HANDED_SWORD := 130
## tier C: every weapon uses afterimage variant 0. Character.wz/Afterimage holds 11 (one-handed) to 17 (swordTS) variants,
## probably chosen by weapon level; the higher ones draw larger trails and boxes, and changing the boxes would change
## every swing's reach and timing, so level-scaled variants are left for a later ticket.
const AFTERIMAGE_VARIANT := "0"
## Weapon family of each v83 weapon type (item id / 10000; docs/adr/0005, GLOSSARY "Weapon family"). tier A: the
## type codes are Character.wz/Weapon's id blocks and the Skill.wz `weapon` field (type - 100). One- and two-handed
## swords, axes and blunt weapons share a family, so a Sword Mastery covers both.
const FAMILIES := {
	130: "sword", 131: "axe", 132: "blunt", 133: "dagger", 137: "wand", 138: "staff",
	140: "sword", 141: "axe", 142: "blunt", 143: "spear", 144: "polearm",
	145: "bow", 146: "crossbow", 147: "claw", 148: "knuckle", 149: "gun",
}
## tier B: Cosmic `isTwoHanded` (server reimplementation): every weapon type from 140 (two-handed swords, axes and
## blunt weapons, spears, polearms, bows, crossbows, claws, knuckles, guns) takes both hands, so no shield.
const FIRST_TWO_HANDED_TYPE := 140
## tier B: pre-Big-Bang SouthPerry/HS.net formula compilation and Cosmic WeaponType (v83-facts §5).
## Each row is [swing multiplier, stab multiplier, primary, secondary]. Hands/families use the helpers above.
const PHYSICAL := {
	130: [4.0, 4.0, "str", "dex"], 131: [4.4, 3.2, "str", "dex"], 132: [4.4, 3.2, "str", "dex"],
	133: [4.0, 4.0, "str", "dex"],
	140: [4.6, 4.6, "str", "dex"], 141: [4.8, 3.4, "str", "dex"], 142: [4.8, 3.4, "str", "dex"],
	143: [3.0, 5.0, "str", "dex"], 144: [5.0, 3.0, "str", "dex"],
	145: [3.4, 3.4, "dex", "str"], 146: [3.6, 3.6, "dex", "str"],
	147: [3.6, 3.6, "luk", "str+dex"], 148: [4.8, 4.8, "str", "dex"], 149: [3.6, 3.6, "dex", "str"],
	# tier C: preserve the existing wand/staff melee formula; §5 has no verified wand/staff physical row.
	137: [4.4, 3.2, "str", "dex"], 138: [4.4, 3.2, "str", "dex"],
}
## tier B (pre-Big-Bang client descriptions): the five one-handed swing/stab stances of the swords, axes, blunt weapons,
## daggers, wands and staves, in the order the basic-attack stream indexes them (a change reshuffles every seeded run).
const ACTIONS_ONE_HANDED: Array[String] = ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]
## tier A/C: two-handed swords, axes and blunt weapons carry swingT1-3 beside stabO1/2 in their item img (A); using all
## five as the basic-attack set is ours (C).
const ACTIONS_TWO_HANDED: Array[String] = ["swingT1", "swingT2", "swingT3", "stabO1", "stabO2"]
## Basic-attack stances by weapon type (item id / 10000). tier A: every action below exists in the representative
## weapon item of its type (Character.wz/Weapon), in the body (00002000.img) and, for melee, in its afterimage.
## tier C: which of those stances a family uses for the automatic attack is our choice (a Spear mostly stabs, a Pole
## Arm swings, a Brawler punches, a Claw throws with an overhand swing, a Bow and a Crossbow draw with shoot1 / shoot2,
## a Gun fires shoot1). A type not listed (and bare hands) uses ACTIONS_ONE_HANDED.
const BASIC_ACTIONS := {
	140: ACTIONS_TWO_HANDED, 141: ACTIONS_TWO_HANDED, 142: ACTIONS_TWO_HANDED,
	143: ["stabT1", "stabT2", "swingP1"], 144: ["swingP1", "swingP2", "swingT2"],
	145: ["shoot1"], 146: ["shoot2"], 147: ["swingO1", "swingO2", "swingO3"], 148: ["stabO1", "stabO2"], 149: ["shoot1"],
}
## Families that attack from a distance: their weapon stance is a "shoot" whatever the body stance is called (a Claw
## throws with swingO, and the ammo W.Att of #155 rides on the kind), and they have no melee afterimage box.
const RANGED_FAMILIES: Array[String] = ["bow", "crossbow", "claw", "gun"]
## tier C: reach in px of a ranged weapon stance: how far a target may be for the attack to start (the ammo projectile of
## #155 then flies this far plus survivor/ammo.json's overshoot); the target box is feet-relative and faces left like the
## afterimage boxes.
const RANGED_REACH := {"bow": 300.0, "crossbow": 300.0, "claw": 250.0, "gun": 250.0}
## tier C: preserve the existing bare-handed/unknown-weapon formula, including equipment-only PAD.
const BARE_PHYSICAL := [4.4, 3.2, "str", "dex"]
## tier B: Thief dagger uses the same LUK and STR+DEX formula as a claw (SouthPerry/Cosmic).
const THIEF_DAGGER_PHYSICAL := [3.6, 3.6, "luk", "str+dex"]


## Weapon type of an original item id (130 one-handed sword, 137 wand, ...).
@warning_ignore("integer_division")
static func type_of(weapon_id: int) -> int:
	return weapon_id / 10000


## Weapon family of an item id ("sword", "claw", ...); "" when bare-handed (0) or not a known weapon type.
static func family(weapon_id: int) -> String:
	return String(FAMILIES.get(type_of(weapon_id), "")) if weapon_id > 0 else ""


## Weapon family of a Skill.wz `weapon` code (type - 100: 30 one-handed sword, 47 claw, ...); "" when unknown.
static func family_of_skill_code(code: int) -> String:
	return String(FAMILIES.get(code + 100, ""))


## True for a two-handed weapon (it blocks the shield slot); false bare-handed or for a non-weapon id.
static func is_two_handed(weapon_id: int) -> bool:
	return FAMILIES.has(type_of(weapon_id)) and type_of(weapon_id) >= FIRST_TWO_HANDED_TYPE


## Attack kind of a canonical action; empty for a non-attack stance. "shot" is the Gun's own body stance.
static func attack_kind(action: String) -> String:
	for prefix: String in ["swing", "stab"]:
		if action.begins_with(prefix):
			return prefix
	if action.begins_with("shoot") or action.begins_with("shot") or action.begins_with("throw"):
		return "shoot"
	return ""


## True for a bow, crossbow, claw or gun (and nothing else, bare hands included).
static func is_ranged(weapon_id: int) -> bool:
	return family(weapon_id) in RANGED_FAMILIES


## The target box of a ranged family's weapon shot, feet-relative and facing left (RANGED_REACH wide); an empty Rect2
## for a melee weapon, whose box is its afterimage's.
static func ranged_box(weapon_id: int) -> Rect2:
	var reach := float(RANGED_REACH.get(family(weapon_id), 0.0))
	return Rect2(-reach, -70.0, reach - 5.0, 65.0) if reach > 0.0 else Rect2()


## The body stance a character holding this weapon stands in ("stand1", or "stand2" for most two-handed weapons), from
## the weapon item's info/stand. tier A: Character.wz/Weapon info/stand and info/walk (1 or 2, independent: the
## two-handed swords stand with stand2 and walk with walk1). Bare hands and synthetic infos use 1.
static func stand_stance(info: Dictionary) -> String:
	return "stand%d" % int(info.get("stand", 1))


## The walking body stance of this weapon ("walk1" or "walk2"); see stand_stance().
static func walk_stance(info: Dictionary) -> String:
	return "walk%d" % int(info.get("walk", 1))


## The body stances the automatic attack picks from, in index order: the weapon's family and handedness decide the
## row of BASIC_ACTIONS. Bare hands and unknown weapon ids get ACTIONS_ONE_HANDED.
static func basic_actions(weapon_id: int) -> PackedStringArray:
	return PackedStringArray(BASIC_ACTIONS.get(type_of(weapon_id), ACTIONS_ONE_HANDED))


## The body stance of a skill whose data says `"action": "weapon"` (Warrior Power Strike and Slash Blast, whose Skill.wz
## nodes name no action): the weapon's first basic-attack stance (basic_actions), so a sword swings (swingO1), a spear
## stabs (stabT1) and a two-handed sword uses its own swingT1; bare hands and unknown weapons use swingO1. tier C: ours.
static func skill_action(weapon_id: int) -> String:
	return String(basic_actions(weapon_id)[0])


## What the damage model sees for one swing of `action` with this weapon: "swing", "stab" or "shoot". A ranged family
## always shoots; everything else follows the stance name (attack_kind). tier B for the multipliers' swing/stab split.
static func basic_kind(weapon_id: int, action: String) -> String:
	return "shoot" if is_ranged(weapon_id) else attack_kind(action)


## Physical formula row for this weapon and job; Thief descendants use LUK daggers.
static func physical_formula(weapon_id: int, job_id: int) -> Array:
	if family(weapon_id) == "dagger" and Equipment.job_allows({"reqJob": Equipment.JOB_BIT_THIEF}, job_id):
		return THIEF_DAGGER_PHYSICAL
	return PHYSICAL.get(type_of(weapon_id), BARE_PHYSICAL)


## The weapon's canonical afterimage name ("swordOL", "mace", ...); "" when the info has none.
static func afterimage_name(info: Dictionary) -> String:
	return String(info.get("afterImage", ""))


## Cache path of an afterimage img: "Character.wz/Afterimage/swordOL.img".
static func afterimage_img_path(afterimage: String) -> String:
	return "Character.wz/Afterimage/%s.img" % afterimage


## WZ path of one afterimage frame of `action` in AFTERIMAGE_VARIANT.
static func afterimage_frame_path(afterimage: String, action: String, frame: int) -> String:
	return "%s/%s/%s/%d" % [afterimage_img_path(afterimage), AFTERIMAGE_VARIANT, action, frame]


## WZ path of the hit spark for a swing of this afterimage. tier C: hit.img only has two normal spark families, so
## every sword afterimage (swordOL, swordOS, swordTL, swordTS) uses the sword spark and every other weapon the mace
## spark; family 1 for swings and shots, 2 for stabs.
static func hit_spark_path(afterimage: String, action: String) -> String:
	var spark := ("sword" if afterimage.begins_with("sword") else "mace") + ("2" if action.begins_with("stab") else "1")
	return "Character.wz/Afterimage/hit.img/" + spark


## The v83 attack speed steps (Item.wz `info/attackSpeed`; lower is faster): the fastest, the normal step that bare
## hands and the Magician's weapons use, and the slowest. tier B (emulator RE; the speed words in InventoryModel).
const SPEED_FASTEST := 2
const NORMAL_SPEED := 6
const SPEED_SLOWEST := 9
## tier B: one speed step is 50 ms on the 800 ms normal action, so speed s takes 800 x (10 + s) / 16 ms. The table that
## action times and the swing interval are read from (docs/GAME_DESIGN.md "Constants and provenance").
const SPEED_DELAY_MS := {2: 600.0, 3: 650.0, 4: 700.0, 5: 750.0, 6: 800.0, 7: 850.0, 8: 900.0, 9: 950.0}


## The speed step of a weapon of step `base` under `boost` Booster steps: `boost` steps faster (lower), stopping at the
## fastest step (or at `base` itself when that is already faster) and at the slowest.
static func effective_speed(base: int, boost: int) -> int:
	return clampi(base - boost, mini(SPEED_FASTEST, base), maxi(SPEED_SLOWEST, base))


## Milliseconds of a normal action at speed step `step` (SPEED_DELAY_MS; a step off the table uses the same ratio).
static func speed_delay_ms(step: int) -> float:
	return float(SPEED_DELAY_MS.get(step, 800.0 * (10 + step) / 16.0))


## The fraction of a weapon's own action time left under `boost` Booster steps: exactly 1.0 without one, so the
## existing timing of every weapon is untouched. tier B: the ratio of the two table delays.
static func speed_factor(base: int, boost: int) -> float:
	if boost == 0:
		return 1.0
	return speed_delay_ms(effective_speed(base, boost)) / speed_delay_ms(base)


## Seconds between swings from the canonical attackSpeed, `boost` Booster steps faster. tier B: v83 weapon-speed
## interval, quantized upward to 30 ms.
static func attack_interval(info: Dictionary, boost: int = 0) -> float:
	var step := int(info.get("attackSpeed", 0))
	if boost != 0:
		step = effective_speed(step, boost)
	return ceilf(800.0 * (10 + step) / 16.0 / 30.0) * 0.03


## WZ path of the swing sound named by the canonical info/sfx.
static func sound_path(info: Dictionary) -> String:
	return "Sound.wz/Weapon.img/%s/Attack" % String(info.get("sfx", ""))


## Seconds before impact and for all numbered frames; tier C: missing/zero delays use 100 ms.
static func frame_times(node: Dictionary, impact_key: int = 0) -> Dictionary:
	var before := 0.0
	var total := 0.0
	for key: String in node:
		if key.is_valid_int():
			var delay := absf(float(node[key].get("delay", 100)))
			delay = (delay if delay > 0.0 else 100.0) / 1000.0
			total += delay
			if int(key) < impact_key:
				before += delay
	return {"before": before, "total": total}
