extends RefCounted
## Shared synthetic WZ book builders for Buccaneer tests and baseline fixtures.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const DAMAGE := [360, 440, 530, 590, 670, 760, 840, 900]
const MOBS := [2, 3, 3, 4, 5, 5, 6, 6]


## Builds this skill group’s canonical-shaped synthetic book.
static func book_node() -> Dictionary:
	var rows := {}
	for lv in range(1, 31):
		var i := LEVELS.find(lv)
		rows[str(lv)] = {"damage": DAMAGE[i] if i >= 0 else 300 + lv * 20, "mobCount": MOBS[i] if i >= 0 else 2 + lv / 8,
			"range": 200, "mpCon": 50}
	var anim := func(n: int) -> Dictionary: return RF._anim(n, 60.0, 16, 16)
	return {"skill": {"5121002": {"icon": RF._canvas(32, 32), "action": {"0": "eorb"}, "effect": anim.call(13),
		"effect0": anim.call(6), "hit": {"0": anim.call(7)}, "ball": RF._anim(1, 60.0, 60, 30), "level": rows}}}


## Builds Energy Drain’s synthetic book for the shared meter fixtures.
static func _drain_book() -> Dictionary:
	var rows := {}
	for lv in range(1, 21):
		rows[str(lv)] = {"damage": 270 + lv, "x": 12, "mobCount": 1, "lt": {"$v": [-200, -100]}, "rb": {"$v": [0, 0]}}
	return {"skill": {"5111004": {"level": rows}}}
