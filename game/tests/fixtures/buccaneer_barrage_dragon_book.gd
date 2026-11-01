extends RefCounted
## Shared synthetic WZ book builders for Buccaneer tests and baseline fixtures.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const BARRAGE_DAMAGE := [106, 122, 148, 160, 176, 202, 218, 230]
const DRAGON_DAMAGE := [320, 380, 490, 535, 595, 705, 765, 810]
const DRAGON_MOBS := [4, 4, 5, 5, 5, 6, 6, 6]


## Builds this skill group’s canonical-shaped synthetic book.
static func book_node() -> Dictionary:
	var barrage := {}
	var dragon := {}
	for lv in range(1, 31):
		var i := LEVELS.find(lv)
		barrage[str(lv)] = {"damage": BARRAGE_DAMAGE[i] if i >= 0 else 100 + lv, "attackCount": 6, "mpCon": 10}
		dragon[str(lv)] = {"damage": DRAGON_DAMAGE[i] if i >= 0 else 300 + lv, "mobCount": DRAGON_MOBS[i] if i >= 0 else 4,
			"lt": {"$v": [-400, -100]}, "rb": {"$v": [25, 20]}, "mpCon": 50}
	var anim := func(n: int) -> Dictionary: return RF._anim(n, 60.0, 16, 16)
	return {"skill": {
		"5121007": {"icon": RF._canvas(32, 32), "action": {"0": "fist"}, "effect": anim.call(5),
			"hit": {"0": anim.call(12)}, "hit0": {"0": anim.call(9)}, "hit1": {"0": anim.call(17)}, "level": barrage},
		"5121001": {"icon": RF._canvas(32, 32), "action": {"0": "dragonstrike"}, "effect": anim.call(16),
			"hit": {"0": anim.call(13), "1": anim.call(13), "2": anim.call(13)},
			"tile": {"0": anim.call(13), "1": anim.call(13), "2": anim.call(13), "3": anim.call(13)}, "level": dragon}}}
