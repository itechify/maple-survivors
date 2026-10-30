extends RefCounted
## Synthetic WZ book 522 for the Battleship tests (spec #384 C13 #397): the three skills with their real Skill.wz level rows, so the
## numbers a test reads are the tier A ones without needing the asset cache. A real-cache test compares them with the cache.

## Battleship 5221006 (10 levels): pdd = mdd = 10 x level (tier A).
## Cannon 5221007 damage by level 1..30 and bulletCount (3 up to level 10, 4 from level 11).
const CANNON_DAMAGE := [205, 210, 215, 220, 225, 230, 235, 240, 245, 250, 265, 270, 275, 280, 285, 290, 295, 300, 305, 310, 335, 340, 345,
	350, 355, 360, 365, 370, 375, 380]
## Torpedo 5221008 damage by level 1..30 and mobCount (4 up to level 10, 5 up to level 20, 6 from level 21).
const TORPEDO_DAMAGE := [390, 400, 410, 420, 430, 440, 450, 460, 470, 480, 540, 550, 560, 570, 580, 590, 600, 610, 620, 630, 690, 700, 710,
	720, 730, 740, 750, 760, 770, 780]


## The `skill_imgs["522"]` dictionary of the three skills.
static func book_node() -> Dictionary:
	var ship := {}
	for lv in range(1, 11):
		ship[str(lv)] = {"pdd": 10 * lv, "mdd": 10 * lv, "x": 1, "cooltime": 90, "time": 2100000}
	var cannon := {}
	var torpedo := {}
	for lv in range(1, 31):
		cannon[str(lv)] = {"damage": CANNON_DAMAGE[lv - 1], "bulletCount": 3 if lv <= 10 else 4, "range": 400}
		torpedo[str(lv)] = {"damage": TORPEDO_DAMAGE[lv - 1], "mobCount": 4 if lv <= 10 else 5 if lv <= 20 else 6,
			"lt": {"$v": [-400, -80]}, "rb": {"$v": [-10, 20]}}
	return {"skill": {"5221006": {"level": ship}, "5221007": {"level": cannon}, "5221008": {"level": torpedo}}}
