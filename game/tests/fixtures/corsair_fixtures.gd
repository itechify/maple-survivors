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
## A data patch (DataRepo.patch / a `data` merge) that makes job 522 unplayable: the refusal cases of the selection tests.
const UNPLAYABLE := {"jobs_survivor": {"jobs": {"522": {"playable": false}}}}


static func frames(n: int, delay := 120.0) -> Dictionary:
	var out := {}
	for k in n:
		out[str(k)] = {"delay": delay}
	return out


## Octopus 5211001 and Gaviota 5211002: the real summon shapes (ranges, balls, `attackAfter`, frame counts), a pad rising
## 84 -> 200 and 218 -> 450 over 30 levels, `time` 10 / 20 / 30 s.
static func summon_levels(first_pad: float, last_pad: float, cooltime: int) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 10 + lv / 2, "pad": roundf(first_pad + (last_pad - first_pad) * float(lv - 1) / 29.0),
			"time": 10 if lv < 12 else 20 if lv < 23 else 30, "cooltime": cooltime}
	return levels


## The 521 nodes of the two summons.
static func summons_skills() -> Dictionary:
	var octopus := {"icon": RF._canvas(32, 32), "level": summon_levels(84.0, 200.0, 10), "action": {"0": "octopus"},
		"hit": {"0": RF._anim(5, 120.0, 50, 38)},
		"summon": {"summoned": frames(12), "stand": frames(8), "die": frames(12),
			"attack1": {"0": {"delay": 120.0}, "1": {"delay": 120.0}, "2": {"delay": 120.0}, "3": {"delay": 120.0}, "4": {"delay": 120.0},
				"5": {"delay": 120.0}, "6": {"delay": 120.0}, "7": {"delay": 120.0}, "info": {
				"range": {"sp": {"$v": [-23, -18]}, "r": 300}, "ball": {"0": {}, "1": {}},
				"attackAfter": 480, "mobCount": 1, "bulletSpeed": 300}}}}
	var gaviota := {"icon": RF._canvas(32, 32), "level": summon_levels(218.0, 450.0, 5),
		"hit": {"0": RF._anim(13, 120.0, 77, 75), "1": RF._anim(4, 120.0, 46, 40)},
		"summon": {"summoned": frames(5), "fly": frames(5), "stand": frames(5), "die": frames(7, 150.0),
			"attack1": {"0": {"delay": 120.0}, "1": {"delay": 120.0}, "2": {"delay": 120.0}, "3": {"delay": 120.0}, "4": {"delay": 120.0},
				"5": {"delay": 120.0}, "6": {"delay": 120.0}, "info": {
				"range": {"lt": {"$v": [-80, -60]}, "rb": {"$v": [80, 60]}, "sp": {"$v": [-14, -29]}, "r": 400},
				"type": 1, "attackAfter": 1920, "mobCount": 3}}}}
	return {"5211001": octopus, "5211002": gaviota}


## Skill.wz/521.img 5211006 (Homing Beacon) with v83's endpoints: 30 levels, damage 148 -> 380 %, range 350, no `time` and no `x`.
static func beacon_levels() -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		out[str(lv)] = {"hs": "h%d" % lv, "mpCon": 20 + lv / 3, "range": 350,
			"damage": float(roundi(lerpf(148.0, 380.0, float(lv - 1) / 29.0)))}
	return out


## The two cones 5211004 (Flamethrower, burn) / 5211005 (Ice Splitter, freeze): the damage a STRING at every level like the WZ
## (82 -> 160 and 78 -> 130), mobCount 2 -> 6, time 3 -> 5 (burn) and 1 -> 3 (freeze), the front-only box lt (-350,-100) rb (0,0).
static func cones_skills() -> Dictionary:
	var skills := {}
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
	return skills


## Burst Fire 5210000 (damage 115 -> 210 %, three bullets, range 350), Homing Beacon 5211006 (148 -> 380 %, range 350) and the two
## cones 5211004 / 5211005 (the damage a STRING like the WZ's, mobCount 2 -> 6, the front-only box).
static func _book521() -> Dictionary:
	var skills := {}
	var burst := {}
	for lv in range(1, 21):
		burst[str(lv)] = {"hs": "h%d" % lv, "mpCon": 13 + lv / 2, "damage": 115.0 + 95.0 * float(lv - 1) / 19.0, "bulletCount": 3, "range": 350}
	skills["5210000"] = {"weapon": 49, "icon": RF._canvas(32, 32), "action": {"0": "triplefire"}, "level": burst,
		"hit": {"0": RF._anim(4, 60.0, 86, 49)}, "effect": RF._anim(8, 90.0, 60, 60)}
	skills["5211006"] = {"level": beacon_levels()}
	skills.merge(cones_skills())
	skills.merge(summons_skills())
	return {"skill": skills}


## Aerial Strike 5221003 (520 -> 1200 %, mobCount 6, box (-400,-500)..(400,100)) and Rapid Fire 5221004 (102 -> 170 %, range 350).
static func aerial_rapid_skills() -> Dictionary:
	var aerial := {}
	var rapid := {}
	for lv in range(1, 31):
		var t := float(lv - 1) / 29.0
		aerial[str(lv)] = {"hs": "h%d" % lv, "mpCon": 31 + lv, "damage": float(roundi(lerpf(520.0, 1200.0, t))), "mobCount": 6,
			"cooltime": 5, "lt": {"$v": [-400, -500]}, "rb": {"$v": [400, 100]}}
		rapid[str(lv)] = {"hs": "h%d" % lv, "mpCon": 6 + lv / 10, "damage": float(roundi(lerpf(102.0, 170.0, t))), "range": 350}
	return {
		"5221003": {"icon": RF._canvas(32, 32), "action": {"0": "airstrike"}, "level": aerial,
			"effect": RF._anim(10, 120.0, 50, 60), "effect0": RF._anim(30, 90.0, 400, 300), "effect1": RF._anim(14, 120.0, 800, 500),
			"hit": {"0": RF._anim(5, 120.0, 124, 109)}},
		"5221004": {"icon": RF._canvas(32, 32), "level": rapid, "prepare": RF._anim(9, 60.0, 74, 79),
			"keydown": RF._anim(8, 60.0, 121, 54), "keydownend": RF._anim(9, 60.0, 234, 137), "hit": {"0": RF._anim(3, 60.0, 84, 83)}}}


## 522.img: the Battleship's three skills plus Aerial Strike and Rapid Fire.
static func _book522() -> Dictionary:
	var book := SHIP.book_node()
	book.skill.merge(aerial_rapid_skills())
	return book


## `RF.skill_imgs()` (books 500 and 520: Double Shot, Dash, Invisible Shot, Recoil Shot, Grenade, Blank Shot and the Gunslinger
## passives) plus books 521 and 522: every Corsair pool skill and the Battleship's two subs are defined.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["521"] = _book521()
	imgs["522"] = _book522()
	return imgs


## `RF.setup(stage, seed, data)` for a Corsair: the five books, the basic-attack fixtures, the Pistol's stats and the body actions
## the pool's casts play, `job = 522`. The job is playable in the shipped data since C15.
static func setup(stage: String, p_seed: int, data: Dictionary) -> Dictionary:
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.skill_imgs = skill_imgs()
	out.equipment_info.merge({PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2", "triplefire", "doublefire", "fireburner", "coolingeffect", "homing", "airstrike", "octopus",
			"cannon", "torpedo", "rapidfire"]:
		out.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	out["job"] = 522
	return out


## A Corsair (job 522) holding a pistol on a map made of `segments` (opts.segments, default a flat floor at y = 0 from x 0 to 2000),
## standing at opts.x (400) facing right, mobs frozen with 4 x 10 px bodies, god mode, `key` the only skill learned at `rank_value`.
## `books` are skill-image nodes laid over the fixture books ({"521": {...}}); the other options are opts.seed (390), opts.pistol_pad (13),
## opts.zero_pdd (mobs take full damage), opts.two_maps (a second map so a transfer exists) and opts.body_actions (extra stances).
## The caller asserts `w.loadout.has(key)`.
static func quiet_corsair(key: String, rank_value: int, books: Dictionary, opts := {}) -> RunWorld:
	var data := RF.quiet_data()
	if opts.get("two_maps", false):
		data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", int(opts.get("seed", 390)), data))
	setup.equipment_info.merge({PISTOL: {"incPAD": int(opts.get("pistol_pad", 13)), "attackSpeed": 5, "tuc": 7}}, true)
	for action: String in opts.get("body_actions", []):
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.map_img = RF.map_from_segments(opts.get("segments", [{"x1": 0, "y1": 0, "x2": 2000, "y2": 0}]))
	for book_id: String in books:
		setup.skill_imgs[book_id] = books[book_id]
	setup["job"] = 522
	var w := RunWorld.new(setup)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
		if opts.get("zero_pdd", false):
			mk.pdd = 0
	w.player.place(Vector2(float(opts.get("x", 400.0)), 0), w.fhm)
	w.update_view()
	w.player.facing = 1
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Double Shot): only `key` casts
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w
