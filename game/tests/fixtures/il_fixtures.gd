extends RefCounted
## Shared deterministic I/L Skill.wz-shaped fixtures; recorded levels with linear interpolation between samples.

const RF := preload("res://tests/fixtures/run_fixtures.gd")


## value at `lv` from recorded {level: value} points, linear in between.
static func lerp_points(points: Dictionary, lv: int) -> float:
	var xs := points.keys()
	xs.sort()
	for i in xs.size() - 1:
		var a: int = xs[i]
		var b: int = xs[i + 1]
		if lv >= a and lv <= b:
			return lerpf(float(points[a]), float(points[b]), float(lv - a) / float(b - a))
	return float(points[xs.back()])


## Synthetic levels fixture.
static func levels(fields: Dictionary, extra: Callable = Callable()) -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		var node := {}
		for field: String in fields:
			node[field] = float(roundi(lerp_points(fields[field], lv)))
		if extra.is_valid():
			extra.call(node, lv)
		out[str(lv)] = node
	return out


## Synthetic box fixture.
static func box(node: Dictionary, half_w: float, up: float, down: float) -> void:
	node["lt"] = {"$v": [-half_w, -up]}
	node["rb"] = {"$v": [half_w, down]}


## Synthetic mastery fixture.
static func mastery() -> Dictionary:
	return {1: 1, 4: 2, 15: 5, 19: 7, 30: 10}


## Synthetic anim fixture.
static func anim(frames: int) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0, 0, 0, 40, 40], "delay": 100.0}
	return out


## Skill.wz-shaped books 220 (Cold Beam, Thunder Bolt) and 221 (Ice Strike, Thunder Spear) with the recorded levels.
static func books() -> Dictionary:
	var cold := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "i", "effect": anim(4), "hit": {"0": anim(6)},
		"level": levels({"mad": {1: 13, 4: 22, 15: 55, 19: 67, 30: 100}, "mastery": mastery(),
			"x": {1: -100, 30: -100}}, func(node: Dictionary, lv: int) -> void: node["time"] = 1.0 if lv < 19 else 2.0)}
	var thunder := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "l", "effect": anim(7), "hit": {"0": anim(9)},
		"level": levels({"mad": {1: 2, 4: 8, 15: 30, 19: 38, 30: 60}, "mastery": mastery(), "mobCount": {1: 6, 30: 6}},
			func(node: Dictionary, lv: int) -> void:
				box(node, 150.0 if lv < 19 else 170.0, 50.0 if lv < 19 else 70.0, 50.0 if lv < 19 else 70.0))}
	var strike := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "i", "action": {"0": "magic2"},
		"effect": anim(11), "hit": {"0": anim(6)},
		"level": levels({"mad": {1: 32, 4: 38, 15: 60, 19: 68, 30: 90}, "mastery": mastery(), "mobCount": {1: 6, 30: 6}},
			func(node: Dictionary, lv: int) -> void:
				node["time"] = 1.0 if lv < 19 else 2.0
				box(node, roundf(lerp_points({1: 110, 4: 120, 15: 150, 19: 170, 30: 200}, lv)),
					roundf(lerp_points({1: 82, 4: 90, 15: 112, 19: 127, 30: 150}, lv)),
					roundf(lerp_points({1: 83, 4: 90, 15: 113, 19: 128, 30: 150}, lv))))}
	var spear := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "l", "action": {"0": "magic1"},
		"effect": anim(15), "hit": {"0": anim(5)},
		"level": levels({"mad": {1: 80, 4: 100, 15: 135, 19: 145, 30: 170}, "mastery": mastery()})}
	return {"cold": cold, "thunder": thunder, "strike": strike, "spear": spear}


## Skill.wz/222.img/skill/2221006 with the recorded levels.
static func chain_node() -> Dictionary:
	return {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "l", "action": {"0": "chainlightning"},
		"effect": anim(12), "hit": {"0": anim(7)},
		"ball": {"0": anim(6), "1": anim(6), "2": anim(6)},
		"level": levels({"mad": {1: 103, 4: 112, 8: 124, 12: 136, 15: 145, 19: 157, 23: 166, 27: 174, 30: 180},
			"mastery": mastery()}, func(node: Dictionary, lv: int) -> void:
				node["mobCount"] = 2.0 + float((lv - 1) / 6))}


## Quiet shipped data for synthetic I/L rounds.
static func data() -> Dictionary:
	var data := RF.quiet_data()
	return data


## A fresh I/L round (Cold Beam and Teleport learned at rank 1) on the quiet stage, with `data` and the synthetic books.
static func round_world(p_data: Dictionary = {}, p_seed := 325) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, data() if p_data.is_empty() else p_data)
	var books := books()
	setup.job = 222
	setup.skill_imgs["220"].skill["2201004"] = books.cold
	setup.skill_imgs["220"].skill["2201005"] = books.thunder
	setup.skill_imgs["221"] = {"skill": {"2211002": books.strike, "2211003": books.spear}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.drain_events()
	return w


## Raw skill entries in one line fragment, for ownership checks.
static func skill_file(line: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/skills/%s.json" % line))
	return parsed.skills if parsed is Dictionary else {}

