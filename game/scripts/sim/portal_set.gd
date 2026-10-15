class_name PortalSet
extends RefCounted
## Same-map links read from Map.wz's portal nodes. Activation consumes held Up near the player's feet and returns
## a destination; RunWorld places the player there. Other-map exits and unresolved target names are inert.

## Sentinel used by WZ portals whose target name refers to this map. tier A: original v83 portal data.
const NO_MAP := 999999999
## tier C: owner-chosen activation box, arrival lift and cooldown (docs/GAME_DESIGN.md section 3).
const TUNING_DEFAULTS := {"reach_x": 25.0, "reach_above": 100.0, "reach_below": 25.0,
	"arrival_lift": 30.0, "cooldown": 0.384}

## Resolved links in WZ order: {name, target, pos, target_pos}. Positions are canonical portal points.
var links: Array[Dictionary] = []
var tuning: Dictionary = TUNING_DEFAULTS.duplicate()
var cooldown_left := 0.0


## Reads same-map links, resolving tn against pn in the same map before any movement can activate them.
static func from_wz(map_img: Dictionary, map_id: int, options: Dictionary = {}) -> PortalSet:
	var s := PortalSet.new()
	s.tuning.merge(options, true)
	var root: Variant = map_img.get("portal", {})
	if not (root is Dictionary):
		return s
	var named := {}
	for key: String in root:
		var p: Variant = root[key]
		if p is Dictionary and not key.begins_with("$"):
			var name := String(p.get("pn", ""))
			if name != "":
				named[name] = p
	for key: String in root:
		var p: Variant = root[key]
		if not (p is Dictionary) or key.begins_with("$"):
			continue
		var tm := int(p.get("tm", NO_MAP))
		var target := String(p.get("tn", ""))
		if (tm != map_id and tm != NO_MAP) or target == "" or not named.has(target):
			continue
		var to: Dictionary = named[target]
		s.links.append({"name": String(p.get("pn", "")), "target": target,
			"pos": Vector2(float(p.get("x", 0)), float(p.get("y", 0))),
			"target_pos": Vector2(float(to.get("x", 0)), float(to.get("y", 0)))})
	return s


## Where a run starts: a random spawn portal (pn "sp", drawn with `rng`) dropped onto the floor below it; else the
## middle of the widest platform; else the centre of `bounds`.
static func start_point(map_img: Dictionary, fhm: FootholdMap, bounds: Rect2, rng: RandomNumberGenerator) -> Vector2:
	var pts: Array = []
	var portals: Variant = map_img.get("portal", {})
	if portals is Dictionary:
		for k: String in portals:
			var p: Variant = portals[k]
			if p is Dictionary and String(p.get("pn", "")) == "sp":
				pts.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))
	while not pts.is_empty():
		var i := rng.randi_range(0, pts.size() - 1)
		var p: Vector2 = pts[i]
		var f := fhm.find_below(p.x, p.y)
		if f >= 0:
			return Vector2(p.x, fhm.y_at(f, p.x))
		pts.remove_at(i)
	var best := -1
	for p in fhm.platform_count():
		var s := fhm.platform_span(p)
		if best < 0 or s.y - s.x > fhm.platform_span(best).y - fhm.platform_span(best).x:
			best = p
	if best < 0:
		return bounds.get_center()
	var mid := fhm.platform_span(best)
	var cx := (mid.x + mid.y) * 0.5
	var f := fhm.platform_fh_at(best, cx)
	return Vector2(cx, fhm.y_at(f, cx)) if f >= 0 else bounds.get_center()


## Counts down the cooldown and returns {portal, target, pos} for one warp, or {} when none activates.
func step(dt: float, feet: Vector2, up: bool) -> Dictionary:
	cooldown_left = maxf(0.0, cooldown_left - dt)
	if not up or cooldown_left > 0.0:
		return {}
	for link: Dictionary in links:
		var offset: Vector2 = feet - link.pos
		if absf(offset.x) <= float(tuning.reach_x) and offset.y >= -float(tuning.reach_above) \
				and offset.y <= float(tuning.reach_below):
			cooldown_left = float(tuning.cooldown)
			return {"portal": link.name, "target": link.target,
				"pos": link.target_pos - Vector2(0, float(tuning.arrival_lift))}
	return {}
