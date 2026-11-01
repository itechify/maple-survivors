extends RefCounted
## Synthetic assets for a whole Shadower (422) round with no asset cache (spec #425, SH13 #438): Skill.wz-shaped books for all nine
## pool skills, Assaulter and Assassinate (shapes and mapped-level endpoints are the v83 values the SH6-SH12 tests record; the art
## is bare frames) and a setup that wears a dagger. Used by the Shadower bot-scoring tests, the Skill-window test and the Shadower
## baseline oracle. 422 is playable since SH14 #439 (the shipped data).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BOOK := preload("res://tests/fixtures/dark_sight_book.gd")
## The creation dagger of a test Shadower: the Razor (v83 Item.wz 1332005, PAD 20), with the survivor test PAD of the Shadower tests.
const DAGGER := 1332005
## Band of Thieves' half-width, `x` and `mobCount` step with the level group of 6 (SH8 notes); the damage column is not monotone.
const BAND_DAMAGE := [110, 120, 130, 140, 150, 160]


static func _levels(count: int, fields: Callable) -> Dictionary:
	var out := {}
	for lv in range(1, count + 1):
		out[str(lv)] = fields.call(lv)
	return out


static func _box(left: float, top: float, right: float, bottom: float) -> Dictionary:
	return {"lt": {"$v": [left, top]}, "rb": {"$v": [right, bottom]}}


## Book 421: Assaulter (damage 210 -> 450, a 200 px dash, stun prop and seconds), Band of Thieves (a symmetric box, `x` selves and
## `mobCount` growing every six levels) and Meso Explosion (`attackCount` 10 -> 20, `x` 560 -> 1000, the forward box by level group).
static func book_421() -> Dictionary:
	var assaulter := _levels(30, func(lv: int) -> Dictionary:
		return {"damage": 210.0 + 8.0 * (lv - 1), "prop": 22.0 + 2.0 * (lv - 1), "time": 2.0 if lv < 10 else 3.0 if lv < 21 else 4.0,
			"mobCount": 1.0}.merged(_box(-200.0, -120.0, 0.0, 0.0)))
	var band := _levels(30, func(lv: int) -> Dictionary:
		var group := (lv - 1) / 6
		return {"hs": "h%d" % lv, "damage": float(BAND_DAMAGE[(lv - 1) % 6] + 10 * group), "x": 1.0 + group, "mobCount": 2.0 + group,
			"mpCon": 20.0}.merged(_box(-(130.0 + 5.0 * group), -50.0, 130.0 + 5.0 * group, 50.0)))
	var meso := _levels(30, func(lv: int) -> Dictionary:
		var group := 0 if lv <= 10 else 1 if lv <= 20 else 2
		var box := [Rect2(-200, -100, 200, 150), Rect2(-250, -110, 250, 160), Rect2(-300, -120, 300, 170)][group] as Rect2
		return {"x": roundf(500.0 + 500.0 * float(lv - 1) / 29.0), "attackCount": roundf(10.0 + 10.0 * float(lv - 1) / 29.0),
			"mobCount": 6.0, "mpCon": 10.0 + lv}.merged(_box(box.position.x, box.position.y, box.end.x, box.end.y)))
	return {"skill": {
		"4211002": {"icon": RF._canvas(32, 32), "action": {"0": "assaulter"}, "weapon": 33, "level": assaulter},
		"4211004": {"icon": RF._canvas(32, 32), "weapon": 33, "level": band},
		"4211006": {"icon": RF._canvas(32, 32), "level": meso}}}


## Book 422: Boomerang Step (2 / 3 / 4 monsters, two lines each, stun), Smokescreen (the cloud box grows with the level), Ninja Ambush
## (+-120 / 150 / 200 px, 4 / 8 / 12 s) and Assassinate (the Dark Sight sub-skill, from `dark_sight_book.gd`).
static func book_422() -> Dictionary:
	var step := _levels(30, func(lv: int) -> Dictionary:
		return {"hs": "h%d" % lv, "damage": 260.0 + 8.0 * (lv - 1), "attackCount": 2.0, "mobCount": 2.0 + float(lv > 10) + float(lv > 20),
			"prop": 32.0 + 2.0 * (lv - 1), "time": 2.0 + float(lv > 10) + float(lv > 20)}.merged(_box(-300.0, -110.0, 0.0, 0.0)))
	var smoke := _levels(30, func(lv: int) -> Dictionary:
		var half := 110.0 + 90.0 * float(lv - 1) / 29.0
		return {"hs": "h%d" % lv, "mpCon": 19.0, "time": 30.0 + float(lv), "cooltime": 600.0}.merged(_box(-half, -0.75 * half, half, 0.75 * half)))
	var ambush := _levels(30, func(lv: int) -> Dictionary:
		var extent := 120.0 if lv <= 10 else 150.0 if lv <= 20 else 200.0
		return {"hs": "h%d" % lv, "damage": roundf(lerpf(62.0, 100.0, (lv - 1) / 29.0)), "mobCount": 6.0,
			"time": 4.0 if lv <= 10 else 8.0 if lv <= 20 else 12.0}.merged(_box(-extent, -130.0, extent, 70.0)))
	var skills: Dictionary = BOOK.book_node().skill
	skills["4221007"] = {"icon": RF._canvas(32, 32), "weapon": 33, "level": step}
	skills["4221006"] = {"icon": RF._canvas(32, 32), "invisible": 1, "level": smoke}
	skills["4221004"] = {"icon": RF._canvas(32, 32), "level": ambush}
	return {"skill": skills}


## `RF.skill_imgs()` (book 400 with Double Stab and Dark Sight, book 420 with Steal and Savage Blow) plus books 421 and 422: all nine
## pool skills, Assaulter and Assassinate are defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["421"] = book_421()
	imgs["422"] = book_422()
	return imgs


## `RF.setup` for a Shadower round on `stage` with all four books, a dagger in `equipment_info`, the stances the Shadower skills
## use, and job 422 as `job`. `data` is the caller's copy of the real survivor data.
static func setup(stage: String, p_seed: int, data: Dictionary) -> Dictionary:
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info.merge({DAGGER: {"incPAD": 20, "attackSpeed": 4, "tuc": 7, "afterImage": "swordOS", "sfx": "swordS"}}, true)
	for action: String in ["assaulter", "assassination", "savage", "smokeshell", "alert", "alert3", "alert5", "prone2", "darksight",
			"stabO1", "stabO2", "swingO1", "swingO2"]:
		out.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	out["job"] = 422
	return out
