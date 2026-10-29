extends RefCounted
## Shared deterministic Bishop Skill.wz-shaped fixtures for the core bolts (spec #372, BS5 #377): the recorded v83 values at
## WZ levels 1/4/8/12/15/19/23/27/30 (BS1 note), linear in between, so the eight ranks (levels 4 8 12 15 19 23 27 30) read exactly
## the recorded numbers.

const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")

## Rank 1..8 are these WZ levels (the default 30-level table, GAME_DESIGN 8).
const RANK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Recorded Skill.wz values at ranks 1..8 (BS1-373.md "Rank values").
const ARROW_MAD := [28, 36, 44, 50, 58, 66, 74, 80]
const RAY_MAD := [66, 74, 82, 88, 94, 98, 102, 105]
const ANGEL_MAD := [132, 144, 158, 170, 186, 205, 225, 240]
const MASTERY := [2, 3, 4, 5, 7, 8, 9, 10]
## Shining Ray's box half-width by WZ level: 150 to level 10, 160 at 11-20, 170 from 21 (BS1 correction 1).
const RAY_HALF_WIDTH := [150, 150, 160, 160, 160, 170, 170, 170]


static func _points(values: Array, first: float) -> Dictionary:
	var out := {1: first}
	for i in 8:
		out[RANK_LEVELS[i]] = values[i]
	return out


static func _mastery() -> Dictionary:
	return _points(MASTERY, 1)


## Skill.wz-shaped books: Holy Arrow (230), Shining Ray (231), Angel Ray (232) and the Cleric Teleport (130 to level 10, then +2 a level).
static func books() -> Dictionary:
	var arrow := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "h", "action": {"0": "shoot1"},
		"ball": IL.anim(3), "effect": IL.anim(7), "hit": {"0": IL.anim(3)},
		"level": IL.levels({"mad": _points(ARROW_MAD, 22), "mastery": _mastery()})}
	var ray := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "h", "action": {"0": "magic2"},
		"effect": IL.anim(11), "hit": {"0": IL.anim(2)},
		"level": IL.levels({"mad": _points(RAY_MAD, 60), "mastery": _mastery(), "mobCount": {1: 6, 30: 6}},
			func(node: Dictionary, lv: int) -> void:
				IL.box(node, 150.0 if lv <= 10 else 160.0 if lv <= 20 else 170.0, 50.0, 50.0))}
	var angel := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "h", "action": {"0": "shoot1"},
		"ball": {"0": {"$canvas": [0, 0, 0, 90, 19], "delay": 100.0}}, "effect": IL.anim(15), "hit": {"0": IL.anim(7)},
		"level": IL.levels({"mad": _points(ANGEL_MAD, 123), "mastery": _mastery()})}
	var teleport := {"icon": {"$canvas": [0, 0, 0, 32, 32]},
		"level": IL.levels({"range": {1: 130, 10: 130, 20: 150}, "mpCon": {1: 60, 20: 13}})}
	return {"arrow": arrow, "ray": ray, "angel": angel, "teleport": teleport}


## Setup of a Bishop (232) round on the quiet stage with the synthetic books; `p_data` is the data (Bishop made playable here, as the
## job is until BS10).
static func setup(p_data: Dictionary = {}, p_seed := 377) -> Dictionary:
	var data := RF.quiet_data() if p_data.is_empty() else p_data
	data.jobs_survivor.jobs["232"]["playable"] = true
	var setup := RF.setup("quiet", p_seed, data)
	var books := books()
	setup.job = 232
	setup.skill_imgs["230"].skill["2301005"] = books.arrow
	setup.skill_imgs["230"].skill["2301001"] = books.teleport
	setup.skill_imgs["231"] = {"skill": {"2311004": books.ray}}
	setup.skill_imgs["232"] = {"skill": {"2321007": books.angel}}
	return setup


## A fresh Bishop round (Holy Arrow and Teleport learned at rank 1) with the player standing at x = 200.
static func round_world(p_data: Dictionary = {}, p_seed := 377) -> RunWorld:
	var w := RunWorld.new(setup(p_data, p_seed))
	RF.place_player(w, 200)
	w.drain_events()
	return w
