extends RefCounted
## Synthetic assets for a whole Night Lord (412) round with no asset cache (spec #383, NL11 #410): Skill.wz-shaped books for all
## eight pool skills and Flash Jump (the endpoints are the v83 values the NL6-NL10 tests record; the art is bare frames) and a setup
## that wears a claw. Used by the bot-scoring tests and the Night Lord baseline oracle. 412 ships `playable: true` since NL12 #411;
## `setup` still sets it in the caller's data copy, so a fixture world does not depend on the shipped flag.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
## The Garnier a test Night Lord holds: the creation claw (v83 Item.wz 1472000, PAD 10), with the survivor test PAD of the NL tests.
const CLAW := 1472000


static func _levels(count: int, fields: Callable) -> Dictionary:
	var out := {}
	for lv in range(1, count + 1):
		out[str(lv)] = fields.call(lv)
	return out


## Book 411: Avenger (damage 65 -> 180, mobCount 4 / 5 / 6), Shadow Partner (x / y / time), Shadow Meso (moneyCon 135 -> 570 and
## its three art tiers) and Flash Jump (20 levels holding only mpCon).
static func book_411() -> Dictionary:
	var avenger := _levels(30, func(lv: int) -> Dictionary:
		return {"hs": "h%d" % lv, "damage": roundf(lerpf(65.0, 180.0, (lv - 1) / 29.0)),
			"mobCount": 4.0 if lv <= 10 else 5.0 if lv <= 20 else 6.0, "bulletConsume": 3.0})
	var partner := _levels(30, func(lv: int) -> Dictionary:
		return {"hs": "h%d" % lv, "x": roundf(lerpf(20.0, 80.0, (lv - 1) / 29.0)), "y": roundf(lerpf(21.0, 50.0, (lv - 1) / 29.0)),
			"time": 60.0 if lv <= 10 else 120.0 if lv <= 20 else 180.0})
	var meso := _levels(30, func(lv: int) -> Dictionary:
		var tier := 0 if lv <= 10 else 1 if lv <= 20 else 2
		return {"hs": "h%d" % lv, "moneyCon": roundf(135.0 + 435.0 * float(lv - 1) / 29.0), "prop": float(1 + lv / 4), "x": 50.0,
			"ball": RF._anim(4, 100.0, [87, 87, 91][tier], [33, 33, 34][tier]),
			"hit": {"0": RF._anim(3, 100.0, [61, 67, 98][tier], 61)}})
	var flash := _levels(20, func(lv: int) -> Dictionary: return {"mpCon": float(60 - 3 * (lv - 1))})
	return {"skill": {
		"4111005": {"icon": RF._canvas(32, 32), "level": avenger},
		"4111002": {"icon": RF._canvas(32, 32), "level": partner},
		"4111004": {"icon": RF._canvas(32, 32), "req": {"4111001": 5}, "level": meso},
		"4111006": {"icon": RF._canvas(32, 32), "level": flash}}}


## Book 412: Triple Throw (damage 102 -> 150, bulletCount 3), Ninja Storm (a +-100 / 150 / 200 px box) and Ninja Ambush
## (+-120 / 150 / 200 px, 4 / 8 / 12 s).
static func book_412() -> Dictionary:
	var triple := _levels(30, func(lv: int) -> Dictionary:
		return {"hs": "h%d" % lv, "damage": roundf(lerpf(102.0, 150.0, (lv - 1) / 29.0)), "bulletCount": 3.0})
	var storm := _levels(30, func(lv: int) -> Dictionary:
		var extent := 100.0 if lv <= 10 else 150.0 if lv <= 20 else 200.0
		return {"hs": "h%d" % lv, "damage": roundf(lerpf(42.0, 80.0, (lv - 1) / 29.0)),
			"prop": roundf(lerpf(42.0, 100.0, (lv - 1) / 29.0)), "mobCount": 6.0, "time": 1.0,
			"range": 200.0 if lv == 30 else 150.0, "lt": {"$v": [-extent, -70.0]}, "rb": {"$v": [extent, 30.0]}})
	var ambush := _levels(30, func(lv: int) -> Dictionary:
		var extent := 120.0 if lv <= 10 else 150.0 if lv <= 20 else 200.0
		return {"hs": "h%d" % lv, "damage": roundf(lerpf(62.0, 100.0, (lv - 1) / 29.0)), "mobCount": 6.0,
			"time": 4.0 if lv <= 10 else 8.0 if lv <= 20 else 12.0, "lt": {"$v": [-extent, -130.0]}, "rb": {"$v": [extent, 70.0]}})
	return {"skill": {
		"4121007": {"weapon": 47, "level": triple},
		"4121008": {"weapon": 47, "level": storm},
		"4121004": {"level": ambush}}}


## `RF.skill_imgs()` (book 400 with Lucky Seven, book 410 with Drain) plus books 411 and 412: all eight pool skills and Flash Jump
## are defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["411"] = book_411()
	imgs["412"] = book_412()
	return imgs


## `RF.setup` for a Night Lord round on `stage` with all four books, a claw in `equipment_info`, the stances the claw skills
## use, and job 412 made playable in `data` (the caller's copy). `data` defaults to the real survivor data.
static func setup(stage: String, p_seed: int, data: Dictionary) -> Dictionary:
	data.jobs_survivor.jobs["412"]["playable"] = true # in this copy only: NL12 ships the flip
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info.merge({CLAW: {"incPAD": 22, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2", "swingO1", "avenger", "alert", "alert3", "ninjastorm"]:
		out.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	out["job"] = 412
	return out
