extends RefCounted
## Synthetic assets for a whole Bowmaster (312) round with no asset cache (spec #332, B12 #344): Skill.wz-shaped books for
## all ten pool skills (the endpoints are the v83 values the B7-B11 tests record; the art is bare frames) and a setup that
## wears a bow. Used by the bot-scoring tests and the Bowmaster baseline oracle. Bowmaster ships `playable: false` until B13,
## so `setup` flips it in the test's own data copy.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
## The Hunter's Bow a test Bowmaster holds: PAD 28, speed 6 (WeaponInfo family bow).
const BOW := 1452051


static func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"pad": 10.0 * lv, "prop": 40.0 + 2.0 * lv, "time": 60.0}
	return levels


static func _frames(count: int, delay: float) -> Dictionary:
	var node := {}
	for k in count:
		node[str(k)] = {"delay": delay}
	return node


## A follower's `summon` node: a body frame set and an attack with the info block the follower reads.
static func _summon_node(range_box: Array, attack_after: float, mob_count: int, attack_frames: Dictionary) -> Dictionary:
	var info := {"attackAfter": attack_after,
		"range": {"lt": {"$v": [range_box[0], range_box[1]]}, "rb": {"$v": [range_box[2], range_box[3]]}}}
	if mob_count > 0:
		info["mobCount"] = float(mob_count)
	var attack := attack_frames.duplicate()
	attack["info"] = info
	return {"summoned": _frames(5, 100.0), "fly": _frames(5, 90.0), "stand": _frames(5, 90.0), "attack1": attack,
		"die": _frames(5, 100.0)}


## RF.skill_imgs() (books 300, 310, 311 with Strafe, Inferno and Arrow Rain, and 312 with Dragon's Breath) plus Hurricane (3121004) and
## the two followers (3111005, 3121006), so all ten pool skills are defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var hurricane := {}
	for lv in range(1, 31):
		hurricane[str(lv)] = {"hs": "h%d" % lv, "mpCon": 6.0, "damage": float(roundi(lerpf(51.0, 100.0, float(lv - 1) / 29.0)))}
	imgs["312"].skill["3121004"] = {"icon": RF._canvas(32, 32), "ball": RF._anim(10, 30.0, 68, 19),
		"hit": {"0": RF._anim(3, 100.0, 56, 58)}, "level": hurricane}
	imgs["311"].skill["3111005"] = {"level": _levels(),
		"summon": _summon_node([-200, -150, 200, 150], 100.0, 0, {"0": {"delay": 100.0}, "1": {"delay": 600.0}})}
	imgs["312"].skill["3121006"] = {"level": _levels(), "elemAttr": "f",
		"summon": _summon_node([-100, -60, 100, 60], 360.0, 4, _frames(11, 120.0))}
	return imgs


## `RF.setup` for a Bowmaster round on `stage` with all ten books, a bow in `equipment_info`, shoot stances in the body, and
## job 312 playable in the data copy. `data` defaults to the real survivor data (the caller may pass `RF.quiet_data()`).
static func setup(stage: String, p_seed: int, data: Dictionary) -> Dictionary:
	data.jobs_survivor.jobs["312"]["playable"] = true
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		out.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	out["job"] = 312
	return out
