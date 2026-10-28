extends RefCounted
## Synthetic data for the sim-run tests (no Nexon data): Skill.wz-shaped skill imgs, Mob.wz-shaped mob imgs and a
## large multi-platform map, plus RunWorld setups built from them and the real game/data JSON (DataRepo).
##
## Canonical numbers are the v83 values recorded in docs/research/cosmic-data.md section 4 / 6 and
## docs/research/wz-inventory.md section 6 (level 1 and max level of each skill, the mob info rows); levels in between
## are filled in by linear interpolation (synthetic, labelled as such where tests rely on them).

const WF := preload("res://tests/fixtures/world_fixtures.gd")
## The weapon each removed job advancement wore (#284 removed advancement and its grants), by "<job>:<family>" for a
## multi-family first job and "<job>" otherwise (item stats tier A; the choice was tier C, spec #226). Tests and debug
## drivers of the unported lines stand their character with it through as_job.
const LEGACY_JOB_WEAPONS := {
	"100:sword": 1302077, "100:spear": 1432000, "100:blunt": 1322006, "100": 1302077,
	"200": 1372005,
	"300:bow": 1452051, "300:crossbow": 1462001, "300": 1452051,
	"400:claw": 1472061, "400:dagger": 1332063, "400": 1472061,
	"500:knuckle": 1482000, "500:gun": 1492000, "500": 1482000,
	"110:sword": 1302008, "110:axe": 1312005, "110": 1302008,
	"120:sword": 1302008, "120:blunt": 1322014, "120": 1302008,
	"130:spear": 1432002, "130:polearm": 1442001, "130": 1432002,
	"310": 1452005, "320": 1462000, "410": 1472008, "420": 1332012, "510": 1482004, "520": 1492004,
	"210": 1372005, "220": 1372005, "230": 1372005,
}


## Gives a synthetic stage an absolute boss schedule using the per-map schema; keeps its first map id.
static func set_bosses(stage: Dictionary, bosses: Array) -> void:
	var map_id := int(stage.get("maps", [{}])[0].get("map_id", 0))
	# Tier C: single-map probes retain a normal curve window; arbitrary multi-boss fixtures use absolute times.
	stage["map_seconds"] = 0 if bosses.size() > 1 else 300
	stage["maps"] = []
	for boss: Dictionary in bosses:
		stage.maps.append({"map_id": map_id, "boss": boss})
	if stage.maps.is_empty():
		stage.maps.append({"map_id": map_id, "boss": {}})


## Skill.wz-shaped imgs keyed by book ("000", "200", "210", "220") like setup.skill_imgs.
static func skill_imgs() -> Dictionary:
	var snails := {}
	var fix := [10.0, 25.0, 40.0]
	var mp := [3.0, 5.0, 7.0]
	for lv in 3:
		snails[str(lv + 1)] = {"hs": "h%d" % (lv + 1), "mpCon": mp[lv], "fixdamage": fix[lv],
			"ball": _anim(3, 90.0, 32, 35), "hit": {"0": _anim(6, 90.0, 76, 79)}}
	var b000 := {"skill": {
		"0001000": {"icon": _canvas(32, 32), "level": snails},
		"0001001": {"icon": _canvas(32, 32), "effect": _anim(13, 90.0, 50, 100),
			"level": _levels(3, {"mpCon": [5.0, 15.0], "x": [4.0, 12.0], "time": [30.0, 30.0], "cooltime": [120.0, 120.0]})},
		"0001002": {"icon": _canvas(32, 32), "effect": _anim(12, 90.0, 60, 100),
			"level": _levels(3, {"mpCon": [4.0, 10.0], "speed": [10.0, 20.0],
				"time": [4.0, 12.0], "cooltime": [60.0, 60.0]})},
	}}
	var b200 := {"skill": {
		"2000000": {"icon": _canvas(32, 32), "level": _levels(16, {})},
		"2000001": {"icon": _canvas(32, 32), "level": _levels(10, {"x": [2.0, 20.0], "y": [1.0, 10.0]})},
		"2001002": {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(12, 100.0, 60, 60),
			"level": _levels(20, {"time": [111.0, 600.0], "mpCon": [6.0, 12.0], "x": [11.0, 80.0]})},
		"2001003": {"icon": _canvas(32, 32), "action": {"0": "alert2"},
			"level": _levels(20, {"time": [54.0, 400.0], "mpCon": [8.0, 16.0], "pdd": [2.0, 40.0]})},
		"2001004": {"icon": _canvas(32, 32), "ball": _anim(4, 80.0, 33, 33),
			"hit": {"0": _anim(3, 90.0, 60, 60), "1": _anim(3, 90.0, 60, 60)},
			"level": _levels(20, {"mpCon": [6.0, 14.0], "mad": [20.0, 55.0], "mastery": [1.0, 10.0]})},
		"2001005": {"icon": _canvas(32, 32), "req": {"2001004": 1.0}, "hit": {"0": _anim(5, 120.0, 80, 80)},
			"effect": _anim(4, 80.0, 86, 80),
			"CharLevel": {"10": {"hit": {"0": _anim(5, 120.0, 80, 80)}, "effect": _anim(8, 80.0, 86, 80)}},
			"level": _levels(20, {"mpCon": [10.0, 20.0], "mad": [11.0, 40.0], "mastery": [1.0, 10.0],
				"attackCount": [2.0, 2.0]})},
	}}
	var b210 := {"skill": {
		"2101004": {"icon": _canvas(32, 32), "elemAttr": "f", "action": {"0": "shoot1"},
			"ball": _anim(3, 30.0, 84, 20), "hit": {"0": _anim(5, 90.0, 60, 60)},
			"level": _levels(30, {"mpCon": [14.0, 28.0], "mad": [33.0, 120.0], "mastery": [1.0, 10.0]})},
	}}
	# #55: separate Poison Breath fixture; endpoints are v83 facts, intermediate levels are synthetic interpolation.
	b210.skill["2101005"] = {"icon": _canvas(32, 32), "elemAttr": "s", "action": {"0": "swingO3"},
		"effect": _anim(5, 100.0, 98, 99), "ball": _anim(2, 100.0, 41, 26),
		"hit": {"0": _anim(6, 90.0, 136, 124)},
		"level": _levels(30, {"mpCon": [10.0, 20.0], "mad": [12.0, 70.0], "mastery": [1.0, 10.0],
			"prop": [31.0, 60.0], "time": [4.0, 40.0]})}
	var thunder_levels := _levels(30, {"mpCon": [20.0, 40.0], "mad": [2.0, 60.0],
		"mastery": [1.0, 10.0], "mobCount": [6.0, 6.0]})
	for level: String in thunder_levels:
		# Synthetic box interpolation, like the numeric endpoint interpolation above.
		var extent := lerpf(150.0, 170.0, float(int(level) - 1) / 29.0)
		thunder_levels[level].lt = {"$v": [-extent, -(extent - 100.0)]}
		thunder_levels[level].rb = {"$v": [extent, extent - 100.0]}
	var b220 := {"skill": {
		"2201004": {"icon": _canvas(32, 32), "elemAttr": "i", "effect": _anim(4, 100.0, 70, 80),
			"hit": {"0": _anim(5, 100.0, 80, 80)},
			"level": _levels(30, {"mpCon": [12.0, 24.0], "mad": [13.0, 100.0], "mastery": [1.0, 10.0],
				"x": [-100.0, -100.0], "time": [1.0, 2.0]})},
		"2201005": {"icon": _canvas(32, 32), "elemAttr": "l", "effect": _anim(7, 100.0, 90, 90),
			"hit": {"0": _anim(5, 100.0, 80, 80)}, "level": thunder_levels},
	}}
	# #58 support fixtures: synthetic interpolation of canonical endpoints, separate from attack fixtures above.
	for branch: int in [210, 220]:
		var book: Dictionary = b210 if branch == 210 else b220
		book.skill[str(branch * 10000 + 1001)] = {"icon": _canvas(32, 32), "action": {"0": "alert2"},
			"effect": _anim(4, 100.0, 60, 80),
			"level": _levels(20, {"mpCon": [10.0, 20.0], "time": [10.0, 200.0], "mad": [1.0, 20.0]})}
		var slow_levels := _levels(20, {"mpCon": [8.0, 16.0], "time": [2.0, 40.0],
			"x": [-2.0, -40.0], "mobCount": [6.0, 6.0]})
		for level: String in slow_levels:
			var extent := lerpf(200.0, 250.0, float(int(level) - 1) / 19.0)
			slow_levels[level].lt = {"$v": [-extent, -150.0]}
			slow_levels[level].rb = {"$v": [extent, 150.0]}
		book.skill[str(branch * 10000 + 1003)] = {"icon": _canvas(32, 32), "action": {"0": "alert2"},
			"effect": _anim(4, 100.0, 60, 80), "mob": _anim(4, 100.0, 60, 80), "level": slow_levels}
	var support_230 := {"skill": {
		"2301003": {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(4, 100.0, 60, 80),
			"level": _levels(20, {"mpCon": [15.0, 30.0], "time": [15.0, 300.0], "x": [11.0, 30.0]})},
		"2301004": {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(4, 100.0, 60, 80),
			"level": _levels(20, {"mpCon": [12.0, 24.0], "time": [10.0, 200.0],
				"acc": [1.0, 20.0], "eva": [1.0, 20.0], "pdd": [1.0, 20.0], "mdd": [1.0, 20.0]})},
	}}
	# Cleric-only fixture block (#57): synthetic intermediate nodes, with original-v83 endpoints.
	var heal_levels := _levels(30, {"mpCon": [12.0, 24.0], "hp": [10.0, 300.0], "mobCount": [6.0, 6.0]})
	for level: String in heal_levels:
		var extent := lerpf(250.0, 300.0, float(int(level) - 1) / 29.0)
		heal_levels[level].lt = {"$v": [-extent, -(extent - 100.0)]}
		heal_levels[level].rb = {"$v": [extent, extent - 100.0]}
	var b230 := {"skill": {
		"2301005": {"icon": _canvas(32, 32), "elemAttr": "h", "action": {"0": "shoot1"},
			"ball": _anim(3, 100.0, 70, 20), "hit": {"0": _anim(7, 100.0, 60, 60)},
			"effect": _anim(7, 100.0, 70, 80),
			"level": _levels(30, {"mpCon": [12.0, 24.0], "mad": [22.0, 80.0], "mastery": [1.0, 10.0]})},
		"2301002": {"icon": _canvas(32, 32), "action": {"0": "alert2"},
			"effect": _anim(10, 100.0, 50, 100), "hit": {"0": _anim(7, 100.0, 50, 60)}, "level": heal_levels},
	}}
	b230.skill.merge(support_230.skill)
	# Warrior book (#163): the original v83 level-1 and top-level values (Skill.wz/100.img), levels between interpolated.
	var slash_levels := _levels(20, {"hpCon": [8.0, 16.0], "mpCon": [6.0, 14.0], "damage": [72.0, 130.0],
		"range": [130.0, 150.0], "mobCount": [6.0, 6.0]})
	var b100 := {"skill": {
		"1000000": {"icon": _canvas(32, 32), "level": _levels(16, {"hp": [3.0, 50.0]})},
		"1000001": {"icon": _canvas(32, 32), "level": _levels(10, {"x": [4.0, 40.0], "y": [3.0, 30.0]})},
		"1001003": {"icon": _canvas(32, 32), "action": {"0": "alert2"},
			"level": _levels(20, {"time": [75.0, 300.0], "mpCon": [8.0, 15.0], "pdd": [2.0, 40.0]})},
		"1001004": {"icon": _canvas(32, 32), "hit": {"0": _anim(2, 90.0, 69, 74)}, "effect": _anim(6, 50.0, 164, 156),
			"CharLevel": {"10": {"hit": {"0": _anim(5, 150.0, 110, 146)}, "effect": _anim(6, 90.0, 228, 215)}},
			"level": _levels(20, {"mpCon": [4.0, 12.0], "damage": [165.0, 260.0]})},
		"1001005": {"icon": _canvas(32, 32), "hit": {"0": _anim(2, 70.0, 104, 83), "1": _anim(2, 70.0, 83, 91)},
			"effect": _anim(5, 90.0, 74, 52),
			"CharLevel": {"10": {"hit": {"0": _anim(4, 90.0, 95, 126)}, "effect": _anim(5, 90.0, 74, 52)}},
			"level": slash_levels},
	}}
	# #199: independently recorded v83 Bowman endpoints; intermediate rows are synthetic linear interpolation.
	var bowman := {
		"3000000": {"level": _levels(16, {"x": [1.0, 16.0]})},
		"3000001": {"level": _levels(20, {"prop": [12.0, 40.0], "damage": [105.0, 200.0]})},
		"3000002": {"level": _levels(8, {"range": [15.0, 120.0]})},
		"3001003": {"level": _levels(20, {"time": [70.0, 300.0], "mpCon": [8.0, 16.0],
			"acc": [1.0, 20.0], "eva": [1.0, 20.0]})},
		"3001004": {"level": _levels(20, {"mpCon": [7.0, 14.0], "damage": [190.0, 260.0]})},
		"3001005": {"level": _levels(20, {"mpCon": [10.0, 16.0], "damage": [92.0, 130.0], "bulletCount": [2.0, 2.0]})},
	}
	bowman["3001003"].level["20"].acc = "20"  # tier A: the original Focus max-level field is a string.
	var imgs := {"000": b000, "100": b100, "200": b200, "210": b210, "220": b220, "230": b230,
		"300": {"skill": bowman}}
	# #301: synthetic Brandish endpoint interpolation; fixed canonical geometry and two lines.
	var brandish_levels := _levels(30, {"damage": [135.0, 260.0], "attackCount": [2.0, 2.0], "mobCount": [1.0, 3.0]})
	for row: Dictionary in brandish_levels.values():
		row.lt = {"$v": [-150.0, -110.0]}
		row.rb = {"$v": [-10.0, 0.0]}
	imgs["112"] = {"skill": {"1121008": {"level": brandish_levels}}}
	# #202: v83 Hunter endpoints; intermediate rows are synthetic linear interpolation, no proprietary art.
	var bomb_levels := _levels(30, {"mpCon": [14.0, 28.0], "x": [72.0, 130.0], "prop": [31.0, 60.0],
		"time": [2.0, 6.0], "mobCount": [6.0, 6.0]})
	for level: String in bomb_levels:
		var extent := lerpf(130.0, 150.0, float(int(level) - 1) / 29.0)
		bomb_levels[level].lt = {"$v": [-extent, -100.0]}
		bomb_levels[level].rb = {"$v": [extent, 100.0]}
	imgs["310"] = {"skill": {
		"3100000": {"level": _levels(20, {"mastery": [1.0, 10.0], "x": [1.0, 20.0]})},
		"3100001": {"level": _levels(30, {"prop": [2.0, 60.0], "damage": [105.0, 250.0]})},
		"3101002": {"level": _levels(20, {"hpCon": [29.0, 10.0], "mpCon": [29.0, 10.0],
			"time": [10.0, 200.0], "x": [-2.0, -2.0]})},
		"3101003": {"level": _levels(20, {"range": [130.0, 150.0], "damage": [105.0, 200.0],
			"mobCount": [2.0, 6.0], "prop": [13.0, 70.0], "mpCon": [8.0, 15.0]})},
		"3101005": {"level": bomb_levels},
	}}
	# #203: Iron Arrow's independently recorded v83 endpoints, synthetic intermediate rows and art.
	imgs["320"] = {"skill": {"3201005": {"weapon": 46, "ball": _anim(3, 90.0, 61, 24),
		"level": _levels(30, {"mpCon": [23.0, 28.0], "damage": [122.0, 180.0], "mobCount": [6.0, 6.0]})}}}
	imgs["320"].skill["3201003"] = {"weapon": 46, "level": _levels(20, {
		"mpCon": [8.0, 15.0], "prop": [13.0, 70.0], "mobCount": [2.0, 6.0],
		"damage": [105.0, 200.0], "range": [130.0, 150.0]})}
	var crossbow_mastery := {}
	for lv in range(1, 21):
		crossbow_mastery[str(lv)] = {"mastery": float(ceili(lv / 2.0)), "x": float(lv)}
	imgs["320"].skill["3200000"] = {"level": crossbow_mastery}
	imgs["320"].skill["3200001"] = {"level": _levels(30, {"prop": [2.0, 60.0], "damage": [105.0, 250.0]})}
	imgs["320"].skill["3201002"] = {"level": _levels(20, {"hpCon": [29.0, 10.0], "mpCon": [29.0, 10.0],
		"time": [10.0, 200.0], "x": [-2.0, -2.0]})}
	# Teleport: synthetic intermediate levels between the recorded v83 endpoint facts, shared across branch IDs.
	for pair: Array in [["210", "2101002"], ["220", "2201002"], ["230", "2301001"]]:
		if not imgs.has(pair[0]):
			imgs[pair[0]] = {"skill": {}}
		imgs[pair[0]].skill[pair[1]] = {"icon": _canvas(32, 32),
			"level": _levels(20, {"mpCon": [60.0, 13.0], "range": [130.0, 150.0]})}
	# MP Eater's three branch copies (#59). Synthetic tables match the independently cache-checked endpoints.
	for job: int in [210, 220, 230]:
		var book := str(job)
		if not imgs.has(book):
			imgs[book] = {"skill": {}}
		imgs[book].skill[str(job * 10000)] = {"level": _levels(20, {"prop": [11.0, 30.0], "x": [21.0, 40.0]})}
	# #186: original v83 endpoints, synthetic linear interpolation between them. No proprietary art.
	# #207: original Thief endpoints; intermediate fixture levels are synthetic interpolation.
	imgs["400"] = {"skill": {
		"4000000": {"level": _levels(20, {"x": [1.0, 20.0], "y": [1.0, 20.0]})},
		"4001002": {"level": _levels(20, {"mpCon": [5.0, 10.0], "time": [7.0, 60.0],
			"x": [-1.0, -20.0], "y": [-1.0, -20.0]})}, # synthetic intermediate levels; cache tests check the real table.
		"4001334": {"weapon": 33, "level": _levels(20, {"mpCon": [8.0, 14.0],
			"damage": [98.0, 140.0], "attackCount": [2.0, 2.0]})},
		"4001344": {"weapon": 47, "level": _levels(20, {"mpCon": [8.0, 16.0],
			"damage": [58.0, 150.0], "bulletCount": [2.0, 2.0]})},
	}}
	# #209: synthetic canonical-shaped Keen Eyes levels, +25px per rank (tier A, independently cache-checked).
	imgs["400"].skill["4000001"] = {"level": _levels(8, {"range": [25.0, 200.0]})}
	var pirate := {"5000000": {"level": _levels(20, {"x": [1.0, 20.0], "y": [1.0, 20.0]})}}
	# tier A: Dark Sight's original numeric level table; speed changes step size after level 12.
	var dark_sight := {}
	var dark_sight_speed := [-30, -28, -26, -24, -22, -20, -18, -16, -14, -12, -10, -8, -7, -6, -5, -4, -3, -2, -1, 0]
	for i in 20:
		dark_sight[str(i + 1)] = {"mpCon": 24 - i, "time": 10 * (i + 1), "speed": dark_sight_speed[i], "x": 1}
	imgs["400"].skill["4001003"] = {"level": dark_sight}
	for entry: Array in [["5001001", 6, 14, 156, 270, 1, 1, [-74, -30], [-20, 10]],
			["5001002", 8, 16, 114, 190, 3, 6, [-81, -71], [-5, 0]]]:
		var levels := _levels(20, {"mpCon": [float(entry[1]), float(entry[2])],
			"damage": [float(entry[3]), float(entry[4])], "mobCount": [float(entry[5]), float(entry[6])]})
		for node: Dictionary in levels.values():
			node.lt = {"$v": entry[7]}
			node.rb = {"$v": entry[8]}
		pirate[entry[0]] = {"level": levels}
	pirate["5001003"] = {"weapon ": 49, "level": _levels(20, {"mpCon": [4.0, 7.0],
		"damage": [61.0, 80.0], "bulletCount": [2.0, 2.0], "range": [215.0, 350.0]})}
	# #188: Dash 5001005's real levels 1-10 as [mpCon, x (speed), y (jump), time] (Skill.wz/500.img).
	var dash_levels := {}
	var dash_rows := [[14, 12, 1, 4], [13, 14, 2, 4], [12, 16, 3, 8], [11, 18, 4, 8], [10, 20, 5, 12], [9, 22, 6, 12],
		[8, 24, 7, 16], [7, 26, 8, 16], [6, 28, 9, 20], [5, 30, 10, 20]]
	for i in dash_rows.size():
		var row: Array = dash_rows[i]
		dash_levels[str(i + 1)] = {"hs": "h%d" % (i + 1), "mpCon": row[0], "x": row[1], "y": row[2], "time": row[3]}
	pirate["5001005"] = {"level": dash_levels}
	imgs["500"] = {"skill": pirate}
	# #189: the Brawler's and Gunslinger's passives and boosters, original v83 values (Skill.wz/510.img, 520.img): Improve
	# MaxHP x 3..30; masteries N = ceil(level / 2) and x = level (Gun Mastery also has y = 10 * level, unused here);
	# boosters x -2, time 10..200 s, hpCon and mpCon 29..10.
	var mastery := func(with_y: bool) -> Dictionary:
		var levels := _levels(20, {"x": [1.0, 20.0]})
		for lv in range(1, 21):
			levels[str(lv)].mastery = float(ceili(lv / 2.0))
			if with_y:
				levels[str(lv)].y = float(10 * lv)
		return levels
	var booster_levels := _levels(20, {"time": [10.0, 200.0], "mpCon": [29.0, 10.0], "hpCon": [29.0, 10.0],
		"x": [-2.0, -2.0]})
	# #191: the Brawler's attacks, original v83 tables (Skill.wz/510.img 5101002-5101004): the stepwise mpCon pairs/fives/fours,
	# Backspin's box (0,-50)..(140,0) behind the facing, Double Uppercut's string-typed attackCount/time without a box, and
	# Corkscrew's reach lt.x -100..-200 (two levels per 10 px, then 190 and 200).
	var backspin_levels := {}
	var uppercut_levels := {}
	var corkscrew_levels := {}
	for lv in range(1, 21):
		backspin_levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 12.0 + 2.0 * floorf((lv - 1) / 2.0), "damage": 80.0 + 8.0 * lv,
			"time": 1.0, "lt": {"$v": [0.0, -50.0]}, "rb": {"$v": [140.0, 0.0]}, "mobCount": 3.0}
		uppercut_levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 15.0 + 5.0 * floorf((lv - 1) / 5.0), "damage": 90.0 + 10.0 * lv,
			"attackCount": "2", "time": "1"}
		var reach := 200.0 if lv == 20 else 100.0 + 10.0 * floorf((lv - 1) / 2.0)
		corkscrew_levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 20.0 + 4.0 * floorf((lv - 1) / 4.0), "damage": 120.0 + 15.0 * lv,
			"mobCount": 3.0, "lt": {"$v": [-reach, -50.0]}, "rb": {"$v": [0.0, 0.0]}}
	imgs["510"] = {"skill": {
		# #193: Brawler MP Recovery 5101005, original endpoints (x 10, y 55 -> 100, cooltime 70 -> 25), linear between.
		"5101005": {"level": _levels(10, {"x": [10.0, 10.0], "y": [55.0, 100.0], "cooltime": [70.0, 25.0]})},
		"5100000": {"icon": _canvas(32, 32), "level": _levels(10, {"x": [3.0, 30.0], "y": [2.0, 20.0]})},
		"5100001": {"icon": _canvas(32, 32), "skillType": 1, "level": mastery.call(false)},
		"5101006": {"icon": _canvas(32, 32), "skillType": 2, "action": {"0": "alert2"},
			"effect": _anim(4, 90.0, 60, 40), "level": booster_levels.duplicate(true)},
		"5101002": {"icon": _canvas(32, 32), "action": {"0": "backspin"}, "effect": _anim(4, 90.0, 80, 60),
			"hit": {"0": _anim(3, 60.0, 40, 40)}, "mob": _anim(3, 100.0, 66, 18), "level": backspin_levels},
		"5101003": {"icon": _canvas(32, 32), "action": {"0": "doubleupper"}, "effect": _anim(4, 90.0, 80, 60),
			"hit": {"0": _anim(3, 60.0, 40, 40), "1": _anim(3, 60.0, 40, 40)}, "mob": _anim(3, 100.0, 66, 18),
			"level": uppercut_levels},
		"5101004": {"icon": _canvas(32, 32), "action": {"0": "screw"}, "effect": _anim(4, 90.0, 80, 60),
			"hit": {"0": _anim(3, 60.0, 40, 40)}, "level": corkscrew_levels}}}
	imgs["520"] = {"skill": {
		"5200000": {"icon": _canvas(32, 32), "skillType": 1, "level": mastery.call(true)},
		"5201003": {"icon": _canvas(32, 32), "skillType": 2, "action": {"0": "alert2"},
			"effect": _anim(4, 90.0, 60, 40), "level": booster_levels.duplicate(true)}}}
	# #192: the Gunslinger attacks, original v83 endpoints (Skill.wz/520.img), linear between: Invisible Shot 5201001 (mpCon
	# 10-25, damage 75-170, 3 mobs, box (-250,-80)..(-10,40)), Grenade 5201002 (mpCon 15-27, damage 45-140, mobCount 3-6,
	# blast box (-50,-50)..(50,20)), Blank Shot 5201004 (mpCon 10-25, damage 63-120, prop 43-100, time 1-4, box
	# (-250,-80)..(-20,30)) and Recoil Shot 5201006 (mpCon 14-26, damage 70-260, recoil range 115-250). The gun ones carry
	# the WZ weapon code 49.
	var boxed := func(fields: Dictionary, lt: Array, rb: Array) -> Dictionary:
		var levels := _levels(20, fields)
		for node: Dictionary in levels.values():
			node.lt = {"$v": lt}
			node.rb = {"$v": rb}
		return levels
	imgs["520"].skill["5201001"] = {"weapon": 49, "icon": _canvas(32, 32), "hit": {"0": _anim(4, 60.0, 50, 50)},
		"level": boxed.call({"mpCon": [10.0, 25.0], "damage": [75.0, 170.0], "mobCount": [3.0, 3.0]}, [-250, -80], [-10, 40])}
	imgs["520"].skill["5201002"] = {"icon": _canvas(32, 32), "ball": _anim(8, 30.0, 31, 31), "special": _anim(4, 120.0, 100, 80),
		"hit": {"0": _anim(4, 120.0, 50, 50)},
		"level": boxed.call({"mpCon": [15.0, 27.0], "damage": [45.0, 140.0], "mobCount": [3.0, 6.0]}, [-50, -50], [50, 20])}
	imgs["520"].skill["5201004"] = {"weapon": 49, "action": {"0": "fake"}, "icon": _canvas(32, 32),
		"hit": {"0": _anim(4, 120.0, 50, 50)}, "effect": _anim(4, 90.0, 60, 40),
		"level": boxed.call({"mpCon": [10.0, 25.0], "damage": [63.0, 120.0], "prop": [43.0, 100.0], "time": [1.0, 4.0],
			"mobCount": [3.0, 3.0]}, [-250, -80], [-20, 30])}
	imgs["520"].skill["5201006"] = {"weapon": 49, "action": {"0": "backstep"}, "icon": _canvas(32, 32),
		"effect": _anim(4, 120.0, 100, 100),
		"level": _levels(20, {"mpCon": [14.0, 26.0], "damage": [70.0, 260.0], "range": [115.0, 250.0]})}
	# #194: Oak Barrel 5101007, the v83 level values; the other second-job skills of the line add their own entries.
	imgs["510"].skill["5101007"] = oak_barrel_skill()
	# Warrior second job (spec #165): one block per ticket, in ticket order.
	for book: String in ["110", "120", "130"]:
		imgs[book] = {"skill": {}}
	_warrior_weapon_skill_imgs(imgs) # #181
	# Page Threaten (#183): the v83 endpoints of Skill.wz/120.img (x = y = -1..-20, time 44..120, mpCon 12/20 with the
	# L11 step, six targets, the box widening at L11); levels between are interpolated. The node has no prop.
	var threaten_levels := _levels(20, {"mpCon": [12.0, 20.0], "time": [44.0, 120.0], "x": [-1.0, -20.0],
		"y": [-1.0, -20.0], "mobCount": [6.0, 6.0]})
	for level: String in threaten_levels:
		var wide := int(level) > 10
		threaten_levels[level].lt = {"$v": [-300.0 if wide else -250.0, -200.0 if wide else -150.0]}
		threaten_levels[level].rb = {"$v": [300.0 if wide else 250.0, 200.0 if wide else 150.0]}
	imgs["120"].skill["1201006"] = {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(7, 100.0, 86, 160),
		"mob": _anim(8, 70.0, 30, 17).merged({"pos": 2.0, "repeat": 1.0}), "level": threaten_levels}
	# Warrior second job, Rage and Power Guard (#182): the v83 level-1 and top-level values, levels between interpolated.
	for pair: Array in [["110", "1101006", 20, {"mpCon": [12.0, 20.0], "time": [46.0, 160.0], "pad": [3.0, 12.0], "pdd": [-3.0, -12.0]}],
			["110", "1101007", 30, {"mpCon": [15.0, 30.0], "x": [11.0, 40.0], "time": [3.0, 90.0]}],
			["120", "1201007", 30, {"mpCon": [15.0, 30.0], "x": [11.0, 40.0], "time": [3.0, 90.0]}]]:
		imgs[pair[0]].skill[pair[1]] = {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "level": _levels(pair[2], pair[3])}
	# Spearman buffs (#184): the v83 level-1 and top-level values of Iron Will and Hyper Body, levels between interpolated.
	imgs["130"].skill["1301006"] = {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(16, 90.0, 60, 90),
		"level": _levels(20, {"time": [15.0, 300.0], "mpCon": [12.0, 24.0], "pdd": [1.0, 20.0], "mdd": [1.0, 20.0]})}
	imgs["130"].skill["1301007"] = {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(11, 90.0, 60, 90),
		"level": _levels(30, {"time": [10.0, 300.0], "mpCon": [20.0, 60.0], "x": [2.0, 60.0], "y": [2.0, 60.0]})}
	# #212: v83 Thief branch mastery and critical endpoints; synthetic art, exact mastery steps.
	imgs["410"] = {"skill": {"4100000": {"level": mastery.call(true)},
		"4100001": {"level": _levels(30, {"prop": [21.0, 50.0], "damage": [113.0, 200.0]})}}}
	imgs["420"] = {"skill": {"4200000": {"level": mastery.call(false)}}}
	for entry: Array in [["410", "4101003", "4101004"], ["420", "4201002", "4201003"]]:
		imgs[entry[0]].skill[entry[1]] = {"level": booster_levels.duplicate(true)}
		var haste := _levels(20, {"time": [10.0, 200.0], "speed": [2.0, 40.0], "jump": [1.0, 20.0]})
		for lv in range(1, 21):
			haste[str(lv)].mpCon = 15.0 if lv <= 10 else 30.0
		imgs[entry[0]].skill[entry[2]] = {"level": haste}
	for entry: Array in [["410", "4100002"], ["420", "4200001"]]:
		imgs[entry[0]].skill[entry[1]] = {"level": _levels(20, {"time": [29.0, 10.0], "hp": [3.0, 60.0], "mp": [1.0, 20.0]})}
	# #213: canonical Drain levels (tier A); no canonical ball, hit or action node.
	var drain_levels := _levels(30, {"x": [16.0, 45.0], "damage": [102.0, 160.0]})
	for lv in range(1, 31):
		drain_levels[str(lv)].mpCon = 12.0 if lv <= 15 else 24.0
	imgs["410"].skill["4101005"] = {"weapon": 47.0, "level": drain_levels}
	# #214: exact v83 Savage Blow steps; synthetic art, no decoded assets.
	var savage := {}
	var savage_damage := [40,44,48,52,56,60,64,68,72,74,60,62,64,66,68,70,72,74,76,78,71,72,73,74,75,76,77,78,79,80]
	for lv in range(1, 31):
		savage[str(lv)] = {"mpCon": 15 if lv <= 10 else 18 if lv <= 20 else 27,
			"damage": savage_damage[lv - 1], "attackCount": 4 if lv <= 10 else 5 if lv <= 20 else 6}
	imgs["420"].skill["4201005"] = {"weapon": 33, "action": {"0": "savage"}, "level": savage}
	# #214: exact v83 Steal values, including its rank-16 MP step; no weapon requirement.
	var steal := {}
	for lv in range(1, 31):
		steal[str(lv)] = {"mpCon": 12 if lv <= 15 else 24, "damage": 40 + 2 * lv, "prop": 10 + lv}
	imgs["420"].skill["4201004"] = {"action": "swingO2", "level": steal}
	# #290: T1 damage endpoints interpolated synthetically; timing/boxes below are deliberate test values, no WZ art.
	for spec: Array in [[2111002, 60, 120, 6, "f"], [2111003, 32, 90, 0, "s"],
			[2111006, 80, 150, 1, ""], [2121001, 160, 450, 6, ""],
			[2121003, 62, 120, 6, "f"], [2121006, 133, 210, 1, "s"], [2121007, 330, 570, 15, "f"]]:
		var book := str(int(spec[0]) / 10000)
		if not imgs.has(book):
			imgs[book] = {"skill": {}}
		var levels := _levels(30, {"mad": [float(spec[1]), float(spec[2])], "mastery": [1.0, 10.0],
			"time": [4.0, 40.0], "prop": [41.0, 70.0]})
		if int(spec[3]) > 1:
			for node: Dictionary in levels.values():
				node.mobCount = int(spec[3])
				node.lt = {"$v": [-200.0, -150.0]}
				node.rb = {"$v": [200.0, 150.0]}
		imgs[book].skill[str(spec[0])] = {"elemAttr": spec[4], "level": levels}
	# #291: synthetic summon frames/info, canonical endpoint facts from T1.
	imgs["212"].skill["2121005"] = {"elemAttr": "i",
		"level": _levels(30, {"mad": [153.0, 270.0], "mastery": [10.0, 10.0], "time": [15.0, 160.0]}),
		"summon": {"attack1": {"info": {"mobCount": 3.0, "attackAfter": 1080.0,
			"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}}
	return imgs


## Skill.wz/510.img/skill/5101007 (Oak Barrel): the v83 level values (tier A, read from the owner's files), synthetic art.
static func oak_barrel_skill() -> Dictionary:
	var mp := [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
	var time := [12, 14, 16, 18, 20, 22, 24, 26, 28, 30]
	var prop := [37, 34, 31, 28, 25, 22, 19, 16, 13, 10]
	var cooltime := [35, 35, 30, 30, 25, 25, 20, 20, 15, 15]
	var levels := {}
	for i in 10:
		levels[str(i + 1)] = {"hs": "h%d" % (i + 1), "mpCon": float(mp[i]), "time": float(time[i]),
			"prop": float(prop[i]), "cooltime": float(cooltime[i]), "morph": 1002.0}
	return {"icon": _canvas(32, 32), "effect": _anim(10, 90.0, 60, 80), "affected": _anim(5, 150.0, 100, 90),
		"level": levels}


## Spec #165 ticket #181: the Warrior second-job Masteries, Final Attacks and Boosters (books 110, 120, 130). The level
## tables are the exact v83 formulas read from Skill.wz (mastery step ceil(level / 2) with accuracy x = level; Final
## Attack prop 2 x level and damage 100 + 5 x level; Booster hpCon = mpCon = 30 - level, time 10 x level, x -2); only
## the art is synthetic.
static func _warrior_weapon_skill_imgs(imgs: Dictionary) -> void:
	for book: String in ["110", "120", "130"]:
		var base := int(book) * 10000
		var skills: Dictionary = imgs[book].skill
		for offset: int in [0, 1]:
			var mastery := {}
			for lv in range(1, 21):
				mastery[str(lv)] = {"hs": "h%d" % lv, "mastery": float(ceili(lv / 2.0)), "x": float(lv)}
			skills[str(base + offset)] = {"icon": _canvas(32, 32), "level": mastery}
			var final := {}
			for lv in range(1, 31):
				final[str(lv)] = {"hs": "h%d" % lv, "prop": float(2 * lv), "damage": float(100 + 5 * lv)}
			skills[str(base + 2 + offset)] = {"icon": _canvas(32, 32), "hit": {"0": _anim(3, 90.0, 167, 92)},
				"level": final}
			var booster := {}
			for lv in range(1, 21):
				booster[str(lv)] = {"hs": "h%d" % lv, "hpCon": float(30 - lv), "mpCon": float(30 - lv),
					"time": float(10 * lv), "x": -2.0}
			skills[str(base + 1004 + offset)] = {"icon": _canvas(32, 32), "action": {"0": "alert2"},
				"effect": _anim(9, 90.0, 44, 12), "level": booster}


## Canonical info rows of the stage mobs (cosmic-data.md section 6).
const MOB_INFO := {
	100100: {"level": 1, "maxHP": 8, "exp": 3, "PADamage": 12, "PDDamage": 0, "MDDamage": 0, "speed": -65},
	100101: {"level": 2, "maxHP": 15, "exp": 4, "PADamage": 17, "PDDamage": 0, "MDDamage": 0, "speed": -50},
	120100: {"level": 2, "maxHP": 20, "exp": 5, "PADamage": 17, "PDDamage": 0, "MDDamage": 0, "speed": -30},
	130101: {"level": 4, "maxHP": 40, "exp": 8, "PADamage": 27, "PDDamage": 3, "MDDamage": 10, "speed": -50},
	210100: {"level": 6, "maxHP": 50, "exp": 10, "PADamage": 32, "PDDamage": 5, "MDDamage": 10, "speed": -20,
		"jump": true},
	1210100: {"level": 7, "maxHP": 75, "exp": 15, "PADamage": 37, "PDDamage": 5, "MDDamage": 20, "speed": 0,
		"jump": true},
	1210102: {"level": 8, "maxHP": 80, "exp": 15, "PADamage": 42, "PDDamage": 0, "MDDamage": 10, "speed": 0,
		"jump": true},
	1110100: {"level": 15, "maxHP": 250, "exp": 26, "PADamage": 82, "PDDamage": 12, "MDDamage": 40, "speed": -20},
	9300063: {"level": 6, "maxHP": 60, "exp": 22, "PADamage": 22, "PDDamage": 5, "MDDamage": 20, "flySpeed": -28},
	9300062: {"level": 8, "maxHP": 80, "exp": 10, "PADamage": 25, "PDDamage": 5, "MDDamage": 30, "flySpeed": -30},
	9300064: {"level": 11, "maxHP": 155, "exp": 22, "PADamage": 35, "PDDamage": 10, "MDDamage": 40, "flySpeed": -50},
	2300100: {"level": 20, "maxHP": 300, "exp": 33, "PADamage": 85, "PDDamage": 20, "MDDamage": 20, "flySpeed": 5},
	# Boss reference facts from the owner's v83 dumps; all frames remain synthetic snail-like art.
	2220000: {"level": 20, "maxHP": 2000, "exp": 120, "PADamage": 90, "PDDamage": 20,
		"MDDamage": 30, "speed": -40, "acc": 60, "boss": 1, "pushed": 1},
	3220000: {"level": 35, "maxHP": 7000, "exp": 405, "PADamage": 125, "PDDamage": 50,
		"MDDamage": 70, "speed": -60, "acc": 80, "boss": 1, "pushed": 1},
	6130101: {"level": 60, "maxHP": 20000, "exp": 1200, "PADamage": 200, "PDDamage": 320,
		"MDDamage": 320, "speed": 5, "acc": 150, "boss": 1, "pushed": 1000},
	9400205: {"level": 90, "maxHP": 200000, "exp": 10000, "PADamage": 450, "PDDamage": 810,
		"MDDamage": 520, "speed": -20, "acc": 220, "boss": 1, "pushed": 1000},
	9300003: {"level": 40, "maxHP": 8000, "exp": 800, "PADamage": 130, "PDDamage": 160,
		"MDDamage": 160, "speed": -20, "acc": 140, "pushed": 300},
	6220000: {"level": 65, "maxHP": 31000, "exp": 810, "PADamage": 190, "PDDamage": 190,
		"MDDamage": 220, "speed": -30, "acc": 150, "boss": 1, "pushed": 1500},
}


## Mob.wz-shaped img for one of MOB_INFO's ids (snail-like frames; a jump stance for jumpers).
static func mob_img(id: int) -> Dictionary:
	var info: Dictionary = MOB_INFO[id]
	var img := WF.mob_img(bool(info.get("jump", false)))
	var i: Dictionary = img.info
	for k: String in info:
		if k != "jump":
			i[k] = float(info[k])
	if not bool(info.get("jump", false)):
		img.erase("jump")
	if info.has("flySpeed"):
		img.fly = img.move
		img.erase("move")
		img.erase("stand")
	return img


## setup.mob_imgs for every MOB_INFO id.
static func mob_imgs() -> Dictionary:
	var out := {}
	for id: int in MOB_INFO:
		out[id] = mob_img(id)
	# Tier C: synthetic stand-in for #241's explicit Sanctuary pool; never a canonical Cold Eye stat fixture.
	out[4230100] = mob_img(100100)
	return out


## A 4000 x ~950 px map shaped like a v83 hunting ground: ground with a pit and a raised block, three tiers of floating
## platforms 120-140 px apart (too high for a mob hop, so they are reached by dropping or by spawning there), one low
## step 60 px above the ground (a jump edge), two ladders and spawn portals on the ground. WZ-shaped
## (foothold/<layer>/<group>/<id> with prev/next ids).
static func big_map_img() -> Dictionary:
	var segs: Array = []
	_chain(segs, [Vector2(-1000, 200), Vector2(0, 200), Vector2(900, 200)])
	segs.append([Vector2(900, 200), Vector2(900, 260)])
	_chain(segs, [Vector2(900, 260), Vector2(1100, 260)])
	segs.append([Vector2(1100, 260), Vector2(1100, 200)])
	_chain(segs, [Vector2(1100, 200), Vector2(1800, 200)])
	segs.append([Vector2(1800, 200), Vector2(1800, 150)])
	_chain(segs, [Vector2(1800, 150), Vector2(2200, 150)])
	segs.append([Vector2(2200, 150), Vector2(2200, 200)])
	_chain(segs, [Vector2(2200, 200), Vector2(2600, 220), Vector2(3000, 200)])
	_chain(segs, [Vector2(2350, 150), Vector2(2550, 150)])
	var y := 80.0
	for tier in 3:
		for p in 6:
			var x0 := -900.0 + p * 650.0 + tier * 90.0
			var w := 260.0 + 40.0 * ((p + tier) % 3)
			var pts: Array = [Vector2(x0, y)]
			for s in 4:
				pts.append(Vector2(x0 + w * (s + 1) / 4.0, y - 6.0 * ((s + p) % 2)))
			_chain(segs, pts)
		y -= 140.0
	var fh := {}
	for i in segs.size():
		var s: Array = segs[i]
		fh[str(i + 1)] = {"x1": s[0].x, "y1": s[0].y, "x2": s[1].x, "y2": s[1].y, "prev": 0.0, "next": 0.0}
	for i in segs.size():
		for j in segs.size():
			if i != j and segs[i][1] == segs[j][0]:
				fh[str(i + 1)].next = float(j + 1)
				fh[str(j + 1)].prev = float(i + 1)
	return {
		"info": {"version": 10.0, "bgm": "Bgm00/Test"},
		"foothold": {"1": {"0": fh}},
		"ladderRope": {
			"1": {"l": 1.0, "uf": 1.0, "x": 1200.0, "y1": 82.0, "y2": 198.0, "page": 1.0},
			"2": {"l": 0.0, "uf": 1.0, "x": -100.0, "y1": 82.0, "y2": 198.0, "page": 1.0},
		},
		"portal": {
			"0": {"pn": "sp", "pt": 0.0, "x": 400.0, "y": 180.0},
			"1": {"pn": "sp", "pt": 0.0, "x": 1500.0, "y": 180.0},
		},
	}


## A RunWorld setup on the synthetic map with the real game data files.
static func setup(stage := "henesys", p_seed := 12345, data: Dictionary = {}) -> Dictionary:
	return {
		"map_img": big_map_img(),
		"physics_img": WF.physics_img_v83(),
		"mob_imgs": mob_imgs(),
		"skill_imgs": skill_imgs(),
		"equipment_info": {1302000: {"incPAD": 17.0, "attackSpeed": 4.0},
			1372005: {"incPAD": 15.0, "incMAD": 23.0, "attackSpeed": 6.0}},
		# Synthetic item nodes with independently verified v83 restore amounts.
		"item_info": {2000000: {"spec": {"hp": 50}}, 2000001: {"spec": {"hp": 150}},
			2000002: {"spec": {"hp": 300}}, 2022003: {"spec": {"hp": 1000}}, 2001001: {"spec": {"hp": 2000}}},
		"ammo_info": ammo_info(),
		"data": data if not data.is_empty() else DataRepo.load_all(),
		"stage": stage,
		"seed": p_seed,
		"view_size": Vector2(800, 600),
	}


## The ammo items of survivor/ammo.json as setup.ammo_info carries them ({id: {incPAD}}): the v83 Item.wz values, written
## out so tests do not need the asset cache.
static func ammo_info() -> Dictionary:
	var pads := {2070015: 15, 2070001: 17, 2070002: 19, 2070003: 21, 2070004: 23, 2070005: 25, 2070006: 27,
		2060000: 0, 2060001: 1, 2060002: 2, 2060003: 4, 2061000: 0, 2061001: 1, 2061002: 2, 2061003: 4,
		2330000: 10, 2330001: 12, 2330002: 14}
	var out := {}
	for id: int in pads:
		out[id] = {"incPAD": pads[id]}
	return out


## Level nodes 1..n; fields maps name -> [value at level 1, value at level n] (linear in between, rounded).
static func _levels(n: int, fields: Dictionary) -> Dictionary:
	var out := {}
	for lv in range(1, n + 1):
		var node := {"hs": "h%d" % lv}
		var f := float(lv - 1) / float(maxi(1, n - 1))
		for k: String in fields:
			var ab: Array = fields[k]
			node[k] = float(roundi(lerpf(float(ab[0]), float(ab[1]), f)))
		out[str(lv)] = node
	return out


static func _canvas(w: int, h: int) -> Dictionary:
	return {"$canvas": [0.0, 0.0, 0.0, float(w), float(h)], "origin": {"$v": [0.0, float(h)]}}


static func _anim(frames: int, delay: float, w: int, h: int) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0.0, 0.0, 0.0, float(w), float(h)], "origin": {"$v": [w / 2.0, h / 2.0]},
			"delay": delay}
	return out


static func _chain(segs: Array, pts: Array) -> void:
	for i in pts.size() - 1:
		segs.append([pts[i], pts[i + 1]])


## The kiting bot (BotInput.decide, game/scripts/sim/bot_input.gd); `memo` keeps its state between ticks.
static func bot_input(w: RunWorld, memo: Dictionary) -> MoveInput:
	return BotInput.decide(w, memo)


## Basic-attack bounds after live PDD, for the examples that predate the physical hit path (LUK 0):
## the physical weapon bounds of the stance `action`, then CombatMath.physical_defense.
static func physical_bounds(str_stat: int, dex_stat: int, watk: float, weapon_id: int, action: String,
		pdd: float) -> Vector2:
	return CombatMath.physical_defense(CombatMath.physical_damage_range(str_stat, dex_stat, 0.0, watk, weapon_id,
		WeaponInfo.attack_kind(action)), pdd)


## Resolves an open card window like BotInput (BotInput.pick_card_for's card).
static func auto_choose(w: RunWorld) -> void:
	BotInput.auto_choose(w)
	if w.transfer_pending:
		w.advance_map()


## Adds canonical-shaped weapon afterimage and body timing data to `setup` so the held weapon has a swing reach
## (WeaponReach: weapon_reach skills, Final Attack spread) on the synthetic map. Returns `setup`.
static func with_basic_attack(setup: Dictionary) -> Dictionary:
	setup.equipment_info = {
		1302000: {"incPAD": 17.0, "attackSpeed": 4.0, "afterImage": "swordOL", "sfx": "swordL"},
		1372005: {"incPAD": 15.0, "incMAD": 23.0, "attackSpeed": 6.0, "afterImage": "mace", "sfx": "mace"},
		# The Warrior's Lv 10 grants (spec #151 owner change): the Beginner Warrior's sword is worn, the spear and the
		# Steel Pipe wait in the Equip tab.
		1302077: {"reqJob": 1, "reqLevel": 10, "reqSTR": 35, "incPAD": 30.0, "attackSpeed": 4.0, "afterImage": "swordOS",
			"sfx": "swordS"},
		1432000: {"reqJob": 13, "reqLevel": 10, "incPAD": 32.0, "attackSpeed": 8.0, "afterImage": "spear", "sfx": "spear"},
		1322006: {"reqJob": 0, "reqLevel": 10, "incPAD": 29.0, "attackSpeed": 5.0, "afterImage": "mace", "sfx": "mace"}}
	setup.body_img = {}
	var images := {"0": {}}
	for action: String in WeaponReach.ACTIONS:
		setup.body_img[action] = {"0": {"delay": 300.0}, "1": {"delay": 150.0}, "2": {"delay": 350.0}}
		images["0"][action] = {"lt": {"$v": [-88.0, -62.0]}, "rb": {"$v": [-18.0, -6.0]},
			"2": {"0": {"$canvas": [0, 0, 0, 40, 30], "delay": 200.0}}}
	setup.afterimage_imgs = {"swordOL": images, "swordOS": images, "spear": images, "mace": images}
	return setup


## Real game data with a quiet synthetic stage, a five-MP/zero-Blue resource fixture and single-projectile attacks.
## Combat tests can place every mob themselves and opt into resources/coverage independently of balance tuning.
static func quiet_data() -> Dictionary:
	var data := DataRepo.load_all()
	data.skills.skills.three_snails.count = 1
	data.skills.skills.energy_bolt.count = 1
	var stages: Dictionary = data.stages.stages
	var pool := {}
	for id: int in MOB_INFO:
		pool[str(id)] = 1.0
	stages["quiet"] = {
		"maps": [{"map_id": 0, "boss": {}}], "name": "quiet", "duration": 900.0, "hard_cap": 400,
		"keyframes": [{"t": 0.0, "rate": 0.0, "max_alive": 0.0, "hp": 1.0, "speed": 1.0, "pool": pool}],
		"bursts": {}, "elites": {},
	}
	return data


## A RunWorld on the synthetic map with the "quiet" stage, the player standing on the ground at x.
static func quiet_world(x := 400.0, p_seed := 7) -> RunWorld:
	var w := RunWorld.new(setup("quiet", p_seed, quiet_data()))
	place_player(w, x)
	return w


## The character of `w` for a test to edit: its format-3 snapshot plus `level` and `base_attributes` (a copy of the world's
## base stats), the round state that no longer travels with a character (#286). Pass the edited dictionary to `world_from`.
static func character_with_round_state(w: RunWorld) -> Dictionary:
	var character := w.character_snapshot()
	character["level"] = w.progression.level
	character["base_attributes"] = w._base_stats.duplicate()
	return character


## A world of `setup` whose character is `character` (a format-3 snapshot, JSON-safe) and whose round starts at the `level`
## and `base_attributes` that dictionary may carry (extra keys are ignored on load; see character_with_round_state).
static func world_from(setup: Dictionary, character: Dictionary) -> RunWorld:
	setup.character = character
	var w := RunWorld.new(setup)
	if character.has("level"):
		w.progression.level = int(character.level)
	for stat: String in character.get("base_attributes", {}):
		w._base_stats[stat] = int(character.base_attributes[stat])
	w.refresh_player_stats()
	return w


## Stands `w`'s character as job `job_id` (RunWorld.set_job) wearing the weapon its removed advancement granted
## (LEGACY_JOB_WEAPONS, `family` picking a multi-family first job's), when the job had one. Learns no skill.
static func as_job(w: RunWorld, job_id: int, family := "") -> void:
	w.set_job(job_id)
	var weapon := int(LEGACY_JOB_WEAPONS.get("%d:%s" % [job_id, family], LEGACY_JOB_WEAPONS.get(str(job_id), 0)))
	if weapon > 0 and w.weapon_id() != weapon:
		w.wear_new_item(weapon)


## Stands `w`'s character as job `job_id` without changing its equipment (RunWorld.set_job).
static func change_job_bare(w: RunWorld, job_id: int) -> void:
	w.set_job(job_id)


## Stands the player on the first floor at or below (x, y) (default: the ground) and refreshes the view.
static func place_player(w: RunWorld, x: float, y := 190.0) -> void:
	var f := w.fhm.find_below(x, y)
	w.player.place(Vector2(x, w.fhm.y_at(f, x)), w.fhm)
	w.update_view()


## Spawns mob `mob_id` standing on the first floor at or below (x, y) (default: the ground); returns its slot.
static func put_mob(w: RunWorld, mob_id: int, x: float, y := 190.0, hp_mult := 1.0, elite := false) -> int:
	var f := w.fhm.find_below(x, y)
	return w.spawn_mob(int(w.kind_of_id[mob_id]), Vector2(x, w.fhm.y_at(f, x)), f, hp_mult, elite)


## A WZ-shaped map img from segment Dictionaries {x1, y1, x2, y2} (ends that touch are linked), with optional spawn
## portals at `portals` (Vector2 list).
static func map_from_segments(list: Array, portals: Array = []) -> Dictionary:
	var fh := {}
	for i in list.size():
		var s: Dictionary = list[i]
		fh[str(i + 1)] = {"x1": float(s.x1), "y1": float(s.y1), "x2": float(s.x2), "y2": float(s.y2),
			"prev": 0.0, "next": 0.0}
	for i in list.size():
		for j in list.size():
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			if i != j and float(a.x2) == float(b.x1) and float(a.y2) == float(b.y1):
				fh[str(i + 1)].next = float(j + 1)
				fh[str(j + 1)].prev = float(i + 1)
	var po := {}
	for k in portals.size():
		po[str(k)] = {"pn": "sp", "pt": 0.0, "x": portals[k].x, "y": portals[k].y}
	return {"info": {}, "foothold": {"1": {"0": fh}}, "portal": po}
