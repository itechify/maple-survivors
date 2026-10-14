extends RefCounted
## Synthetic maps and mob imgs for the sim-world tests (no Nexon data). Shapes mirror the cache JSON of
## docs/ASSET_PIPELINE.md 5.2: numbers are floats, vectors {"$v": [x, y]}, canvases {"$canvas": [...], ...}.


## Three tiers: ground G (0..1200 at y=0, two footholds), M1 (100..400) and M2 (700..1000) at y=-60, top T (350..750)
## at y=-120. Ends of M1/M2/T are open (floating); G's ends are the map edges. Returns segments for from_segments.
static func tiers_segments() -> Array:
	return [
		{"x1": 0.0, "y1": 0.0, "x2": 600.0, "y2": 0.0},
		{"x1": 600.0, "y1": 0.0, "x2": 1200.0, "y2": 0.0},
		{"x1": 100.0, "y1": -60.0, "x2": 400.0, "y2": -60.0},
		{"x1": 700.0, "y1": -60.0, "x2": 1000.0, "y2": -60.0},
		{"x1": 350.0, "y1": -120.0, "x2": 750.0, "y2": -120.0},
	]


## A cliff: lower floor L (0..200, y=0), a wall rising at x=200 to y=-50, upper floor U (200..500, y=-50).
## L's right end is blocked by the wall; U's left end is open (the wall hangs below it).
static func cliff_segments() -> Array:
	return [
		{"x1": 0.0, "y1": 0.0, "x2": 200.0, "y2": 0.0},
		{"x1": 200.0, "y1": 0.0, "x2": 200.0, "y2": -50.0},
		{"x1": 200.0, "y1": -50.0, "x2": 500.0, "y2": -50.0},
	]


## A solid block on the ground: floor G (0..600, y=0), the block's top floor B (200..400, y=-60), its sides (walls at
## x=200 and x=400 from y=-60 to -40) and its underside, a ceiling (x1 > x2) at y=-40. A hop straight up from under
## the block bumps into the underside; B can only be reached by hopping on from beside the block.
static func block_segments() -> Array:
	return [
		{"x1": 0.0, "y1": 0.0, "x2": 600.0, "y2": 0.0},
		{"x1": 200.0, "y1": -60.0, "x2": 400.0, "y2": -60.0},
		{"x1": 400.0, "y1": -60.0, "x2": 400.0, "y2": -40.0},
		{"x1": 400.0, "y1": -40.0, "x2": 200.0, "y2": -40.0},
		{"x1": 200.0, "y1": -40.0, "x2": 200.0, "y2": -60.0},
	]


## The same three tiers as a WZ-shaped map img: foothold/<layer>/<group>/<id> with 1-based ids and prev/next ids,
## plus a ladder, two spawn portals and an optional info/miniMap.
static func tiers_map_img(with_vr := false, with_minimap := false) -> Dictionary:
	var fh := {
		"1": {"1": _fh(0, 0, 600, 0, 0, 2), "2": _fh(600, 0, 1200, 0, 1, 0)},
		"2": {"3": _fh(100, -60, 400, -60, 0, 0), "4": _fh(700, -60, 1000, -60, 0, 0)},
		"3": {"5": _fh(350, -120, 750, -120, 0, 0)},
	}
	var img := {
		"info": {"version": 10.0, "bgm": "Bgm00/Test"},
		"foothold": {"1": fh},
		"ladderRope": {"1": {"l": 1.0, "uf": 1.0, "x": 380.0, "y1": -118.0, "y2": -62.0, "page": 1.0}},
		"portal": {
			"0": {"pn": "sp", "pt": 0.0, "x": 50.0, "y": -40.0},
			"1": {"pn": "sp", "pt": 0.0, "x": 500.0, "y": -200.0},
		},
	}
	if with_vr:
		img.info.merge({"VRLeft": -100.0, "VRTop": -500.0, "VRRight": 1300.0, "VRBottom": 200.0})
	if with_minimap:
		img["miniMap"] = {"canvas": {"$canvas": [0.0, 0.0, 0.0, 100.0, 80.0]}, "width": 1600.0, "height": 900.0,
			"centerX": 200.0, "centerY": 700.0, "mag": 4.0}
	return img


static func _fh(x1: float, y1: float, x2: float, y2: float, prev: int, next: int) -> Dictionary:
	return {"x1": x1, "y1": y1, "x2": x2, "y2": y2, "prev": float(prev), "next": float(next)}


## A Physics.img root with every v83 value (doubles, flyJumpDec float).
static func physics_img_v83() -> Dictionary:
	return {
		"walkForce": 140000.0, "walkSpeed": 125.0, "walkDrag": 80000.0, "slipForce": 60000.0, "slipSpeed": 120.0,
		"floatDrag1": 100000.0, "floatDrag2": 10000.0, "floatCoefficient": 0.01, "swimForce": 120000.0,
		"swimSpeed": 140.0, "flyForce": 120000.0, "flySpeed": 200.0, "gravityAcc": 2000.0, "fallSpeed": 670.0,
		"jumpSpeed": 555.0, "maxFriction": 2.0, "minFriction": 0.05, "swimSpeedDec": 0.9,
		"flyJumpDec": 0.3499999940395355,
	}


static func _frame(w: float, h: float, delay: float, lt := Vector2(-18, -26), rb := Vector2(19, 0)) -> Dictionary:
	var fr := {"$canvas": [0.0, 0.0, 0.0, w, h], "origin": {"$v": [18.0, h]}, "head": {"$v": [-10.0, -20.0]},
		"lt": {"$v": [lt.x, lt.y]}, "rb": {"$v": [rb.x, rb.y]}}
	if delay > 0.0:
		fr["delay"] = delay
	return fr


## A snail-like mob img: speed -65, 5 move frames at 180 ms (+ zigzag), single stand frame without delay,
## die1 = 8 x 120 ms + 300 ms, no jump stance. With `jumper` a slime-like variant with a jump stance and speed -20.
static func mob_img(jumper := false) -> Dictionary:
	var move := {"zigzag": 1.0}
	for i in 5:
		move[str(i)] = _frame(37, 26, 180)
	var die := {}
	for i in 9:
		var fr := _frame(40, 30, 120 if i < 8 else 300)
		fr.erase("lt")
		fr.erase("rb")
		if i == 8:
			fr["a0"] = 255.0
			fr["a1"] = 0.0
		die[str(i)] = fr
	var img := {
		"info": {"level": 1.0, "maxHP": 8.0, "exp": 3.0, "PADamage": 12.0, "PDDamage": 0.0, "MADamage": 0.0,
			"MDDamage": 0.0, "acc": 20.0, "eva": 0.0, "speed": -65.0, "bodyAttack": 1.0, "pushed": 1.0,
			"undead": 0.0},
		"move": move,
		"stand": {"0": _frame(37, 26, 0)},
		"hit1": {"0": _frame(43, 33, 600)},
		"die1": die,
	}
	if jumper:
		img.info.speed = -20.0
		img.info.maxHP = 50.0
		img.info["elemAttr"] = "L3"
		img["jump"] = {"0": _frame(40, 40, 150)}
	return img


## Checks the MobSwarm invariants after one step; px/py/was_alive are copies of x/y/active taken before the step.
## Returns one line per violation: outside the bounds, not on its foothold (grounded), stale platform, crossed a wall,
## rose through a ceiling, or fell through a floor without landing.
static func swarm_violations(s: MobSwarm, m: FootholdMap, bounds: Rect2, px: PackedFloat32Array,
		py: PackedFloat32Array, was_alive: PackedByteArray, label: String) -> PackedStringArray:
	var out := PackedStringArray()
	var box := bounds.grow(0.05)
	for i in s.capacity():
		if s.state[i] == MobSwarm.FREE:
			continue
		var where := "%s mob %d at (%s, %s)" % [label, i, s.x[i], s.y[i]]
		if not box.has_point(Vector2(s.x[i], s.y[i])):
			out.append("outside bounds: " + where)
		var f := s.fh[i]
		if f >= 0:
			if absf(s.y[i] - m.y_at(f, s.x[i])) > 0.05 or s.x[i] < m.x1[f] - 0.05 or s.x[i] > m.x2[f] + 0.05:
				out.append("not on its foothold: " + where)
			if s.platform[i] != m.platform_of(f):
				out.append("platform out of date: " + where)
		if i < px.size() and was_alive[i] != 0:
			if m.wall_hit(px[i], py[i], s.x[i], s.y[i]) >= 0:
				out.append("crossed a wall: " + where)
			if s.y[i] < py[i] and m.ceiling_hit(px[i], py[i], s.x[i], s.y[i] + 0.06) >= 0:
				out.append("rose through a ceiling: " + where)
			if f < 0 and s.y[i] > py[i]:
				# Clearly (> 0.05 px) below a floor it started on or above; a takeoff from the surface is fine.
				var g := m.find_landing(px[i], py[i], s.x[i], s.y[i] - 0.06)
				if g >= 0:
					out.append("fell through foothold %d: %s" % [g, where])
	return out
