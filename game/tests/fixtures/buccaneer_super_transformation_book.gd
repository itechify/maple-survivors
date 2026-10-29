extends RefCounted
## Shared synthetic WZ book builders for Buccaneer tests and baseline fixtures.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const S_LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const S_DEFENCE := [43, 45, 48, 50, 53, 55, 58, 60]
const SUB_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const D_DAMAGE := [120, 160, 210, 240, 280, 330, 370, 400]
const N_DAMAGE := [240, 280, 370, 400, 440, 530, 570, 600]
const N_TARGETS := [2, 3, 3, 4, 5, 5, 6, 6]


## Builds this skill group’s canonical-shaped synthetic book.
static func book_node() -> Dictionary:
	var sup := {}
	for lv in range(1, 21):
		var at := S_LEVELS.find(lv)
		var defence: int = S_DEFENCE[at] if at >= 0 else 40 + lv
		sup[str(lv)] = {"morph": 1001, "time": 120, "speed": 40, "jump": 20, "pdd": defence, "mdd": defence,
			"cooltime": 430 - 10 * lv, "str": lv + 10}
	var demo := {}
	var snatch := {}
	for lv in range(1, 31):
		var at := SUB_LEVELS.find(lv)
		demo[str(lv)] = {"damage": D_DAMAGE[at] if at >= 0 else 90 + lv * 10, "attackCount": 8, "time": 1, "mobCount": 1,
			"lt": {"$v": [-300, -150]}, "rb": {"$v": [-20, 15]}}
		snatch[str(lv)] = {"damage": N_DAMAGE[at] if at >= 0 else 210 + lv * 12, "mobCount": N_TARGETS[at] if at >= 0 else 2,
			"time": 1, "lt": {"$v": [-300, -100]}, "rb": {"$v": [-50, 15]}}
	var anim := func(n: int) -> Dictionary: return RF._anim(n, 90.0, 16, 16)
	return {"skill": {
		"5121003": {"icon": RF._canvas(32, 32), "level": sup},
		"5121004": {"icon": RF._canvas(32, 32), "action": {"0": "demolition"}, "hit": {"0": anim.call(23)}, "level": demo},
		"5121005": {"icon": RF._canvas(32, 32), "action": {"0": "snatch"}, "effect": anim.call(10), "hit": {"0": anim.call(3)},
			"level": snatch}}}
