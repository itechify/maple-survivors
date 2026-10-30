extends RefCounted
## Shared synthetic Corsair (522) worlds (spec #384, C14 #398): every pool skill defined, so the bot test, the Skill window model
## test and the baseline oracle play the whole pool with no asset cache. The books are the skill tickets' synthetic books, written
## out here once (v83 endpoints, linear between, bare art frames): 500 and 520 from the run fixtures (Double Shot, Dash, Invisible
## Shot, Recoil Shot, Grenade), 521 (C4 Burst Fire, C6 Octopus and Gaviota, C8 Homing Beacon, C9 Flamethrower and Ice Splitter) and
## 522 (C10 Aerial Strike and Rapid Fire, C13 the Battleship with its Cannon and Torpedo through `battleship_book.gd`).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SHIP := preload("res://tests/fixtures/battleship_book.gd")
## The creation weapon, the Pistol (v83 Item.wz 1492000).
const PISTOL := 1492000


static func _frames(n: int, delay := 120.0) -> Dictionary:
	var out := {}
	for k in n:
		out[str(k)] = {"delay": delay}
	return out


## Octopus 5211001 and Gaviota 5211002: the real summon shapes (ranges, balls, `attackAfter`, frame counts), a pad rising
## 84 -> 200 and 218 -> 450 over 30 levels, `time` 10 / 20 / 30 s.
static func _summon_levels(first_pad: float, last_pad: float, cooltime: int) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 10 + lv / 2, "pad": roundf(first_pad + (last_pad - first_pad) * float(lv - 1) / 29.0),
			"time": 10 if lv < 12 else 20 if lv < 23 else 30, "cooltime": cooltime}
	return levels


static func _summons() -> Dictionary:
	var octopus := {"icon": RF._canvas(32, 32), "level": _summon_levels(84.0, 200.0, 10), "action": {"0": "octopus"},
		"hit": {"0": RF._anim(5, 120.0, 50, 38)},
		"summon": {"summoned": _frames(12), "stand": _frames(8), "die": _frames(12),
			"attack1": {"0": {"delay": 120.0}, "1": {"delay": 120.0}, "2": {"delay": 120.0}, "3": {"delay": 120.0}, "4": {"delay": 120.0},
				"5": {"delay": 120.0}, "6": {"delay": 120.0}, "7": {"delay": 120.0}, "info": {
				"range": {"sp": {"$v": [-23, -18]}, "r": 300}, "ball": {"0": {}, "1": {}},
				"attackAfter": 480, "mobCount": 1, "bulletSpeed": 300}}}}
	var gaviota := {"icon": RF._canvas(32, 32), "level": _summon_levels(218.0, 450.0, 5),
		"hit": {"0": RF._anim(13, 120.0, 77, 75), "1": RF._anim(4, 120.0, 46, 40)},
		"summon": {"summoned": _frames(5), "fly": _frames(5), "stand": _frames(5), "die": _frames(7, 150.0),
			"attack1": {"0": {"delay": 120.0}, "1": {"delay": 120.0}, "2": {"delay": 120.0}, "3": {"delay": 120.0}, "4": {"delay": 120.0},
				"5": {"delay": 120.0}, "6": {"delay": 120.0}, "info": {
				"range": {"lt": {"$v": [-80, -60]}, "rb": {"$v": [80, 60]}, "sp": {"$v": [-14, -29]}, "r": 400},
				"type": 1, "attackAfter": 1920, "mobCount": 3}}}}
	return {"5211001": octopus, "5211002": gaviota}


## Burst Fire 5210000 (damage 115 -> 210 %, three bullets, range 350), Homing Beacon 5211006 (148 -> 380 %, range 350) and the two
## cones 5211004 / 5211005 (the damage a STRING like the WZ's, mobCount 2 -> 6, the front-only box).
static func _book521() -> Dictionary:
	var skills := {}
	var burst := {}
	for lv in range(1, 21):
		burst[str(lv)] = {"hs": "h%d" % lv, "mpCon": 13 + lv / 2, "damage": 115.0 + 95.0 * float(lv - 1) / 19.0, "bulletCount": 3, "range": 350}
	skills["5210000"] = {"weapon": 49, "icon": RF._canvas(32, 32), "action": {"0": "triplefire"}, "level": burst,
		"hit": {"0": RF._anim(4, 60.0, 86, 49)}, "effect": RF._anim(8, 90.0, 60, 60)}
	var beacon := {}
	for lv in range(1, 31):
		beacon[str(lv)] = {"hs": "h%d" % lv, "mpCon": 20 + lv / 3, "range": 350,
			"damage": float(roundi(lerpf(148.0, 380.0, float(lv - 1) / 29.0)))}
	skills["5211006"] = {"level": beacon}
	for key: String in ["flamethrower", "ice_splitter"]:
		var fire: bool = key == "flamethrower"
		var levels := {}
		for lv in range(1, 31):
			var t := clampf(float(lv - 4) / 26.0, 0.0, 1.0)
			levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 25, "itemConsume": 2331000 if fire else 2331001,
				"damage": str(roundi((82.0 if fire else 78.0) + t * (78.0 if fire else 52.0))),
				"mobCount": 2 + roundi(t * 4.0), "time": (3 + roundi(t * 2.0)) if fire else (1 + roundi(t * 2.0)),
				"lt": {"$v": [-350, -100]}, "rb": {"$v": [0, 0]}}
		skills["5211004" if fire else "5211005"] = {"weapon": 49, "elemAttr": "f" if fire else "i", "icon": RF._canvas(32, 32),
			"action": {"0": "fireburner" if fire else "coolingeffect"}, "level": levels,
			"effect": RF._anim(15 if fire else 13, 90.0, 60, 60), "effect_ship": RF._anim(15 if fire else 13, 90.0, 60, 60),
			"hit": {"0": RF._anim(5, 90.0, 40, 40)}}
	skills.merge(_summons())
	return {"skill": skills}


## Aerial Strike 5221003 (520 -> 1200 %, mobCount 6, box (-400,-500)..(400,100)), Rapid Fire 5221004 (102 -> 170 %, range 350) and the
## Battleship's three skills.
static func _book522() -> Dictionary:
	var aerial := {}
	var rapid := {}
	for lv in range(1, 31):
		var t := float(lv - 1) / 29.0
		aerial[str(lv)] = {"hs": "h%d" % lv, "mpCon": 31 + lv, "damage": float(roundi(lerpf(520.0, 1200.0, t))), "mobCount": 6,
			"cooltime": 5, "lt": {"$v": [-400, -500]}, "rb": {"$v": [400, 100]}}
		rapid[str(lv)] = {"hs": "h%d" % lv, "mpCon": 6 + lv / 10, "damage": float(roundi(lerpf(102.0, 170.0, t))), "range": 350}
	var book := SHIP.book_node()
	book.skill["5221003"] = {"icon": RF._canvas(32, 32), "action": {"0": "airstrike"}, "level": aerial,
		"effect": RF._anim(10, 120.0, 50, 60), "effect0": RF._anim(30, 90.0, 400, 300), "effect1": RF._anim(14, 120.0, 800, 500),
		"hit": {"0": RF._anim(5, 120.0, 124, 109)}}
	book.skill["5221004"] = {"icon": RF._canvas(32, 32), "level": rapid, "prepare": RF._anim(9, 60.0, 74, 79),
		"keydown": RF._anim(8, 60.0, 121, 54), "keydownend": RF._anim(9, 60.0, 234, 137), "hit": {"0": RF._anim(3, 60.0, 84, 83)}}
	return book


## `RF.skill_imgs()` (books 500 and 520: Double Shot, Dash, Invisible Shot, Recoil Shot, Grenade, Blank Shot and the Gunslinger
## passives) plus books 521 and 522: every Corsair pool skill and the Battleship's two subs are defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["521"] = _book521()
	imgs["522"] = _book522()
	return imgs


## `RF.setup(stage, seed, data)` for a Corsair: the five books, the basic-attack fixtures, the Pistol's stats and the body actions
## the pool's casts play, `job = 522`. The shipped data has the job unplayable until C15; the caller flips it in its own `data` copy.
static func setup(stage: String, p_seed: int, data: Dictionary) -> Dictionary:
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info.merge({PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2", "triplefire", "doublefire", "fireburner", "coolingeffect", "homing", "airstrike", "octopus",
			"cannon", "torpedo", "rapidfire"]:
		out.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	out["job"] = 522
	return out
