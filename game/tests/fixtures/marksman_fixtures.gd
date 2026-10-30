extends RefCounted
## Synthetic assets for a whole Marksman (322) round with no asset cache (spec #360, MS10 #370): Skill.wz-shaped books for all
## ten pool skills (the endpoints are the v83 values the MS5-MS9 tests record; the art is bare frames) and a setup that wears a
## crossbow. Used by the bot-scoring tests and the Marksman baseline oracle. Marksman ships `playable: false` until MS11 #371,
## so `setup` flips 322 playable in the data copy it is given (the test mirror; shipped data is untouched).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
## The Crossbow a test Marksman holds (the creation weapon, PAD 29, speed 6; WeaponInfo family crossbow).
const CROSSBOW := 1462001
## Skill.wz 322.img/skill/3221001/level/<n>/damage and mobCount for levels 1..30 (tier A, the v83 values Piercing Arrow's tests use).
const PIERCING_DAMAGE := [320, 340, 360, 380, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600, 620, 640, 660, 680, 700, 715,
	730, 745, 760, 775, 790, 805, 820, 835, 850]
const PIERCING_MOBS := [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]


## A follower's generic levels: pad = 10 x level, prop = 40 + 2 x level, time 60 s.
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


## RF.skill_imgs() (books 300 with Arrow Blow, 320 Iron Arrow, 321 Strafe, Blizzard and Arrow Eruption, 322 Dragon's Breath) plus
## Golden Eagle (3211005), Piercing Arrow (3221001), Frostprey (3221005) and Snipe (3221007), so all ten pool skills are defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["321"].skill["3211005"] = {"level": _levels(),
		"summon": _summon_node([-200, -150, 200, 150], 100.0, 0, {"0": {"delay": 100.0}, "1": {"delay": 600.0}})}
	imgs["322"].skill["3221005"] = {"level": _levels(), "elemAttr": "i",
		"summon": _summon_node([-100, -60, 100, 60], 1440.0, 4, _frames(11, 90.0))}
	var piercing := {}
	var snipe := {}
	for lv in range(1, 31):
		piercing[str(lv)] = {"hs": "h%d" % lv, "mpCon": 18.0, "damage": float(PIERCING_DAMAGE[lv - 1]), "mobCount": float(PIERCING_MOBS[lv - 1])}
		# v83 shape: the node holds mpCon and cooltime per level and the three art nodes; no damage, range, mobCount or weapon.
		snipe[str(lv)] = {"mpCon": 40.0 - lv * 0.9, "cooltime": 250.0 - lv * 8.0}
	imgs["322"].skill["3221001"] = {"level": piercing, "prepare": RF.anim(20, 60.0), "effect": RF.anim(5, 100.0),
		"ball": RF.anim(5, 100.0), "hit": {"0": RF.anim(6, 100.0)}}
	imgs["322"].skill["3221007"] = {"level": snipe, "effect": RF.anim(11, 60.0), "ball": RF.anim(9, 60.0), "hit": {"0": RF.anim(5, 0.0)}}
	return imgs


## `RF.setup` for a Marksman round on `stage` with all ten books, a crossbow in `equipment_info`, shoot stances in the body, and
## 322 playable in `data` (the mirror). `data` defaults to the real survivor data (the caller may pass `RF.quiet_data()`).
static func setup(stage: String, p_seed: int, data: Dictionary) -> Dictionary:
	data.jobs_survivor.jobs["322"]["playable"] = true # in this data copy only: MS11 ships the flip
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info.merge({CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7, "reqJob": 4}}, true)
	for action: String in ["shoot1", "shoot2"]:
		out.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	out["job"] = 322
	return out
