class_name WeaponInfo
extends RefCounted
## What the basic attack needs to know about a weapon (docs/GAME_DESIGN.md 6.1.1), from its original item id and its
## canonical Character.wz/Weapon info node: the weapon type (id / 10000), physical formula stats and multipliers, the
## afterimage (info/afterImage) with its hit-spark family, the canonical attack interval (info/attackSpeed) and the
## swing sound (info/sfx). Read by CombatMath, BasicAttack and DataRepo (which afterimage imgs a setup loads).
## Pure: plain data in, values out.

## Weapon type (item id / 10000) of one-handed swords (Character.wz/Weapon/0130xxxx).
const TYPE_ONE_HANDED_SWORD := 130
## tier C: starter Sword/Wand use afterimage variant 0 (both are below required level 10).
const AFTERIMAGE_VARIANT := "0"
## Weapon family of each v83 weapon type (item id / 10000; docs/adr/0005, GLOSSARY "Weapon family"). tier A: the
## type codes are Character.wz/Weapon's id blocks and the Skill.wz `weapon` field (type - 100). One- and two-handed
## swords, axes and blunt weapons share a family, so a Sword Mastery covers both.
const FAMILIES := {
	130: "sword", 131: "axe", 132: "blunt", 133: "dagger", 137: "wand", 138: "staff",
	140: "sword", 141: "axe", 142: "blunt", 143: "spear", 144: "polearm",
	145: "bow", 146: "crossbow", 147: "claw", 148: "knuckle", 149: "gun",
}
## What the Skill window calls each family when a skill needs it ("Weapon : Pole Arm"). tier C: ours, v83 item names.
const FAMILY_LABELS := {
	"sword": "Sword", "axe": "Axe", "blunt": "Blunt weapon", "dagger": "Dagger", "wand": "Wand", "staff": "Staff",
	"spear": "Spear", "polearm": "Pole Arm", "bow": "Bow", "crossbow": "Crossbow", "claw": "Claw",
	"knuckle": "Knuckle", "gun": "Gun",
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


## Display name of a weapon family ("Claw", "Pole Arm"); "Bare hands" for "".
static func family_label(family: String) -> String:
	return String(FAMILY_LABELS.get(family, family)) if family != "" else "Bare hands"


## True for a two-handed weapon (it blocks the shield slot); false bare-handed or for a non-weapon id.
static func is_two_handed(weapon_id: int) -> bool:
	return FAMILIES.has(type_of(weapon_id)) and type_of(weapon_id) >= FIRST_TWO_HANDED_TYPE


## Attack kind of a canonical action; empty for a non-attack stance.
static func attack_kind(action: String) -> String:
	for prefix: String in ["swing", "stab"]:
		if action.begins_with(prefix):
			return prefix
	if action.begins_with("shoot") or action.begins_with("throw"):
		return "shoot"
	return ""


## Physical formula row for this weapon and job; Thief descendants use LUK daggers.
static func physical_formula(weapon_id: int, job_id: int) -> Array:
	if family(weapon_id) == "dagger" and Equipment.job_allows({"reqJob": 8}, job_id):
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


## WZ path of the hit spark for a swing of this afterimage. tier C: the normal swing/stab spark families matching the
## imported afterimage names (sword for swordOL, else mace; family 1 for swings, 2 for stabs).
static func hit_spark_path(afterimage: String, action: String) -> String:
	var spark := ("sword" if afterimage == "swordOL" else "mace") + ("2" if action.begins_with("stab") else "1")
	return "Character.wz/Afterimage/hit.img/" + spark


## Seconds between swings from the canonical attackSpeed. tier B: v83 weapon-speed interval, quantized upward to 30 ms.
static func attack_interval(info: Dictionary) -> float:
	return ceilf(800.0 * (10 + int(info.get("attackSpeed", 0))) / 16.0 / 30.0) * 0.03


## WZ path of the swing sound named by the canonical info/sfx.
static func sound_path(info: Dictionary) -> String:
	return "Sound.wz/Weapon.img/%s/Attack" % String(info.get("sfx", ""))
