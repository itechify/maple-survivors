extends RefCounted
## Shared synthetic WZ book builders for Buccaneer tests and baseline fixtures.

const T_LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const T_DEFENCE := [6, 10, 16, 20, 26, 30, 36, 40]
const S_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const S_DAMAGE := [310, 370, 430, 475, 535, 595, 655, 700]
const S_TARGETS := [4, 4, 5, 5, 5, 6, 6, 6]


## Builds this skill group’s canonical-shaped synthetic book.
static func book_node() -> Dictionary:
	var trans := {}
	for lv in range(1, 21):
		var at := T_LEVELS.find(lv)
		var defence: int = T_DEFENCE[at] if at >= 0 else 2 * lv
		trans[str(lv)] = {"morph": 1000, "time": 120, "speed": 40, "jump": 20, "pdd": defence, "mdd": defence,
			"cooltime": 530 - 8 * lv, "str": lv}
	var shock := {}
	for lv in range(1, 31):
		var at := S_LEVELS.find(lv)
		shock[str(lv)] = {"damage": S_DAMAGE[at] if at >= 0 else 265 + (lv - 1) * 15,
			"mobCount": S_TARGETS[at] if at >= 0 else 4, "lt": {"$v": [-330, -140]}, "rb": {"$v": [0, 20]}}
	return {"skill": {"5111005": {"level": trans}, "5111006": {"level": shock}}}
