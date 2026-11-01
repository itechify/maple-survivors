extends RefCounted
## Shared synthetic WZ book for the Shadower Dark Sight / Assassinate tests (spec #425 SH11 #436): book 422 with Assassinate at
## levels 1..30 (the eight mapped levels carry the real v83 numbers, the others interpolate) and Dark Sight's book 400 level table
## (the real speed column). The real-cache tests compare these rows with the cache.

## Assassinate's mapped levels (rank 1..8 -> WZ levels 4 8 12 15 19 23 27 30), tier A, 4221001.
const A_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const A_DAMAGE := [230, 310, 380, 425, 485, 530, 570, 600]
const A_PROP := [38, 46, 54, 60, 68, 76, 84, 90]
const A_CRIT := [120, 140, 160, 175, 195, 215, 235, 250]
## Dark Sight's mapped levels (rank 1..8 -> WZ levels 3 5 8 10 13 15 18 20) and its speed penalty, tier A, 4001003.
const D_LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const D_SPEED := [-26, -22, -16, -12, -7, -5, -2, 0]


## The book 422 node ({"skill": {"4221001": ...}}) with Assassinate at all 30 levels.
static func book_node() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var at := A_LEVELS.find(lv)
		levels[str(lv)] = {"damage": A_DAMAGE[at] if at >= 0 else 170 + (lv - 1) * 15,
			"prop": A_PROP[at] if at >= 0 else 32 + (lv - 1) * 2, "criticalDamage": A_CRIT[at] if at >= 0 else 105 + (lv - 1) * 5,
			"attackCount": 3, "mobCount": 1, "time": 6, "lt": {"$v": [-100, -120]}, "rb": {"$v": [-10, 0]}}
	return {"skill": {"4221001": {"level": levels}}}


## Dark Sight's twenty levels: the real speed column, a session-scale `time` the Form never reads.
static func dark_sight_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 21):
		var at := D_LEVELS.find(lv)
		levels[str(lv)] = {"mpCon": 24 - lv, "time": 10 * lv, "speed": D_SPEED[at] if at >= 0 else -30 + (30 * (lv - 1)) / 19, "x": 1}
	return levels
