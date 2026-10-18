class_name WeaponInfo
extends RefCounted
## What the basic attack needs to know about a weapon (docs/GAME_DESIGN.md 6.1.1), from its original item id and its
## canonical Character.wz/Weapon info node: the weapon type (id / 10000), the swing formula's STR factor k, the
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
## tier B: Cosmic `isTwoHanded` (server reimplementation): every weapon type from 140 (two-handed swords, axes and
## blunt weapons, spears, polearms, bows, crossbows, claws, knuckles, guns) takes both hands, so no shield.
const FIRST_TWO_HANDED_TYPE := 140


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


## k of the physical swing bounds (STR x k + DEX) x WATK / 100 (tier B: pre-Big-Bang formula compilation): one-handed
## swords 4.0 for every stance, other weapons 3.2 for stabs and 4.4 for swings.
static func swing_k(weapon_id: int, action: String) -> float:
	return 4.0 if type_of(weapon_id) == TYPE_ONE_HANDED_SWORD else 3.2 if action.begins_with("stab") else 4.4


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
