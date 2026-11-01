class_name FootholdMap
extends RefCounted
## Foothold geometry of one map and the queries the movement code needs (docs/ARCHITECTURE.md 4.4).
##
## Footholds come from the map img (`foothold/<layer>/<group>/<id>/{x1,y1,x2,y2,prev,next,...}`) or from a synthetic
## segment list. Indices into the packed arrays are the foothold handles (`fh`); `-1` means none. WZ `prev`/`next` ids
## are translated to indices.
##
## Kinds (by direction, as in the client data): `x1 < x2` is a floor (walkable, landed on from above only),
## `x1 == x2` is a wall, `x1 > x2` is a ceiling/underside (never landed on; a body moving up through it from below is
## stopped, ceiling_hit; tier B, docs/research/prior-art.md 1b). A **platform** is a maximal chain of floors
## connected through `prev`/`next`; walls and ceilings break chains. A wall blocks horizontal motion at a point when it
## covers the point 1 px above the feet, so a wall hanging below a platform end (a skirt) lets you walk off while a
## wall rising above it blocks.
##
## Walls only stop bodies of platforms they belong to (wall_applies): a wall applies to platform p when it shares a
## foothold group with one of p's floors, is linked to one of them through prev/next, sits in group 0 or is
## cantThrough. Group numbers are compared without their layer. tier B: NoLifeStory physics.cpp collides a mover only
## with footholds of the group it last landed on, of group 0 or cantThrough; the linked wall is its ground-walk stop.
## So the face of one structure does not wall off another structure's floor passing in front of it (103010000: the
## layer-0 building walls at x -710 / 350 cross the layer-1 stairs and the layer-2 ground).

const NONE := -1
## Width of the x buckets used by find_below / find_landing / wall_hit.
const BUCKET_W := 32.0
## Tolerance for "on or below" comparisons (stored positions are float32).
const EPS := 0.01
## Walls are probed this far above the feet. tier C: ours (lets a wall hanging below a platform end be walked off).
const WALL_PROBE := 1.0

var x1 := PackedFloat32Array()
var y1 := PackedFloat32Array()
var x2 := PackedFloat32Array()
var y2 := PackedFloat32Array()
var layer := PackedInt32Array()
var group := PackedInt32Array()
## Index of the previous / next foothold, -1 = none.
var prev := PackedInt32Array()
var next := PackedInt32Array()
## Original WZ foothold id (or the list index for synthetic maps).
var ids := PackedInt32Array()
var cant_through := PackedByteArray()
var forbid_fall_down := PackedByteArray()
## Conveyor speed along the foothold in px/s (WZ `force`, 0 almost everywhere).
var force := PackedFloat32Array()
## Platform index per foothold, -1 for walls and ceilings.
var platform := PackedInt32Array()
## Per foothold: 1 when a floor has a wall within its x span (ends included) that covers the point WALL_PROBE px above
## its surface somewhere, i.e. ground movement on it may hit a wall and must call wall_hit; 0 for most floors (a skirt
## hanging below an end does not count) and for walls/ceilings.
var floor_wall := PackedByteArray()

## Per platform: leftmost/rightmost x, the footholds at both ends, highest/lowest surface y, whether each end is open
## (no wall rising above it, so walking off it means falling).
var plat_x1 := PackedFloat32Array()
var plat_x2 := PackedFloat32Array()
var plat_left_fh := PackedInt32Array()
var plat_right_fh := PackedInt32Array()
var plat_y_min := PackedFloat32Array()
var plat_y_max := PackedFloat32Array()
var plat_open_left := PackedByteArray()
var plat_open_right := PackedByteArray()
## Per platform: 1 when any of its floors has floor_wall set (walk_blocked can only be true there).
var plat_wall := PackedByteArray()
## Per (platform, wall slot): 1 when the wall stops bodies of that platform (wall_applies). Row p starts at
## p * _wall_count; _wall_slot maps a foothold index to its column (-1 for floors and ceilings).
var _wall_rel := PackedByteArray()
var _wall_slot := PackedInt32Array()
var _wall_count := 0

var _bounds := Rect2()
var _gx0 := 0.0
var _gn := 0
var _floor_start := PackedInt32Array()
var _floor_items := PackedInt32Array()
var _wall_start := PackedInt32Array()
var _wall_items := PackedInt32Array()
var _ceil_start := PackedInt32Array()
var _ceil_items := PackedInt32Array()


## Builds the map from a map img root (cache JSON). Missing `foothold` gives an empty map.
static func from_wz(map_img: Dictionary) -> FootholdMap:
	var segs: Array = []
	var by_layer_id := {}
	var root: Variant = map_img.get("foothold", {})
	if not (root is Dictionary):
		root = {}
	for layer_key: String in root:
		var lay: Variant = root[layer_key]
		if layer_key.begins_with("$") or not (lay is Dictionary):
			continue
		for group_key: String in lay:
			var grp: Variant = lay[group_key]
			if group_key.begins_with("$") or not (grp is Dictionary):
				continue
			for id_key: String in grp:
				var f: Variant = grp[id_key]
				if id_key.begins_with("$") or not (f is Dictionary):
					continue
				var s := {
					"x1": float(f.get("x1", 0)), "y1": float(f.get("y1", 0)),
					"x2": float(f.get("x2", 0)), "y2": float(f.get("y2", 0)),
					"layer": int(layer_key), "group": int(group_key), "id": int(id_key),
					"wz_prev": int(f.get("prev", 0)), "wz_next": int(f.get("next", 0)),
					"cant_through": int(f.get("cantThrough", 0)) != 0,
					"forbid_fall_down": int(f.get("forbidFallDown", 0)) != 0,
					"force": float(f.get("force", 0)),
				}
				by_layer_id["%d:%d" % [s.layer, s.id]] = segs.size()
				segs.append(s)
	# WZ ids are unique per map in practice; prefer a match in the same layer, then any layer.
	var by_id := {}
	for i in segs.size():
		if not by_id.has(segs[i].id):
			by_id[segs[i].id] = i
	for s: Dictionary in segs:
		s["prev"] = _wz_link(s.wz_prev, s.layer, by_layer_id, by_id)
		s["next"] = _wz_link(s.wz_next, s.layer, by_layer_id, by_id)
	var m := FootholdMap.new()
	m._build(segs)
	return m


## Builds the map from a list of Dictionaries `{x1, y1, x2, y2}` with optional `prev`/`next` (indices into the list,
## -1 = none), `layer`, `group`, `id`, `cant_through`, `forbid_fall_down`, `force`. A segment without a `prev`
## (`next`) key is linked to the first other segment whose end (start) point coincides with its start (end) point.
static func from_segments(list: Array) -> FootholdMap:
	var segs: Array = []
	for i in list.size():
		var d: Dictionary = list[i]
		segs.append({
			"x1": float(d.get("x1", 0)), "y1": float(d.get("y1", 0)),
			"x2": float(d.get("x2", 0)), "y2": float(d.get("y2", 0)),
			"layer": int(d.get("layer", 0)), "group": int(d.get("group", 0)), "id": int(d.get("id", i)),
			"prev": int(d.get("prev", -2)), "next": int(d.get("next", -2)),
			"cant_through": bool(d.get("cant_through", false)),
			"forbid_fall_down": bool(d.get("forbid_fall_down", false)),
			"force": float(d.get("force", 0)),
		})
	for i in segs.size():
		var s: Dictionary = segs[i]
		if s.prev == -2:
			s.prev = -1
			for j in segs.size():
				if j != i and segs[j].x2 == s.x1 and segs[j].y2 == s.y1:
					s.prev = j
					break
		if s.next == -2:
			s.next = -1
			for j in segs.size():
				if j != i and segs[j].x1 == s.x2 and segs[j].y1 == s.y2:
					s.next = j
					break
	var m := FootholdMap.new()
	m._build(segs)
	return m


static func _wz_link(wz_id: int, lay: int, by_layer_id: Dictionary, by_id: Dictionary) -> int:
	if wz_id == 0:
		return NONE
	var key := "%d:%d" % [lay, wz_id]
	if by_layer_id.has(key):
		return by_layer_id[key]
	return by_id.get(wz_id, NONE)


## Number of footholds.
func count() -> int:
	return x1.size()


## True for vertical footholds (walls).
func is_wall(i: int) -> bool:
	return x1[i] == x2[i]


## True for walkable footholds (x1 < x2): the ones you stand on and land on from above.
func is_floor(i: int) -> bool:
	return x1[i] < x2[i]


## Surface y of foothold i at x (the line through the foothold; y1 for walls).
func y_at(i: int, x: float) -> float:
	var ax := x1[i]
	var bx := x2[i]
	if ax == bx:
		return y1[i]
	return y1[i] + (y2[i] - y1[i]) * (x - ax) / (bx - ax)


## Next foothold index (-1 = none).
func next_of(i: int) -> int:
	return next[i]


## Previous foothold index (-1 = none).
func prev_of(i: int) -> int:
	return prev[i]


## Bounding box of every foothold (walls included).
func bounds() -> Rect2:
	return _bounds


## Platform of foothold i (-1 for walls and ceilings).
func platform_of(i: int) -> int:
	return platform[i] if i >= 0 and i < platform.size() else NONE


## Number of platforms.
func platform_count() -> int:
	return plat_x1.size()


## Horizontal extent of platform p: Vector2(min x, max x).
func platform_span(p: int) -> Vector2:
	return Vector2(plat_x1[p], plat_x2[p])


## Foothold at the left (side < 0) or right (side > 0) end of platform p.
func platform_end_fh(p: int, side: int) -> int:
	return plat_left_fh[p] if side < 0 else plat_right_fh[p]


## True when walking off that end of platform p means falling (no wall rises above the end point).
func platform_end_open(p: int, side: int) -> bool:
	return (plat_open_left[p] if side < 0 else plat_open_right[p]) != 0


## Foothold of platform p under x (x inside the span), or -1.
func platform_fh_at(p: int, x: float) -> int:
	var b := _bucket(x)
	if b < 0:
		return NONE
	for k in range(_floor_start[b], _floor_start[b + 1]):
		var i := _floor_items[k]
		if platform[i] == p and x >= x1[i] and x <= x2[i]:
			return i
	return NONE


## True when a wall of platform p (wall_applies) stands across its surface between xa and xb, so a walker going from one
## to the other stops at it (platforms do not split at such walls; on 103010000 the wall of a step at x -2290 stands on
## the layer-1 ground of its own group). Follows the chain from the foothold under min(xa, xb).
func walk_blocked(p: int, xa: float, xb: float) -> bool:
	if p < 0 or p >= plat_wall.size() or plat_wall[p] == 0:
		return false
	var lo := minf(xa, xb)
	var hi := maxf(xa, xb)
	var f := platform_fh_at(p, lo)
	var guard := 0
	while f >= 0 and guard < 4096:
		guard += 1
		if floor_wall[f] != 0:
			var a := maxf(lo, x1[f])
			var b := minf(hi, x2[f])
			if b > a:
				var ya := y_at(f, a)
				var yb := y_at(f, b)
				if wall_hit(a, ya, b, yb, p) >= 0 or wall_hit(b, yb, a, ya, p) >= 0:
					return true
		if x2[f] >= hi:
			break
		var g := next[f]
		if g < 0 or not is_floor(g):
			break
		f = g
	return false


## Slides a body standing on floor `fh` at `x` up to `distance` horizontal px toward `side` (-1 / 1) along its platform
## (moving attacks, docs/GAME_DESIGN.md 7.13), staying between the horizontal limits `lo` and `hi`. Follows the chain of
## floors across slopes (the surface y comes from the floor under the final x). It stops at the platform's edge
## (the end of the chain: it never walks off) and EPS (0.01 px) short of a wall that stands across the surface on the way (the
## same stop as ground walking). Total: a blocked or degenerate slide returns the start. Returns
## {"x", "y", "fh", "moved"} (moved = horizontal px actually covered, >= 0). tier C: ours.
func slide_along(fh: int, x: float, side: int, distance: float, lo: float, hi: float) -> Dictionary:
	var f := fh
	var cur := x
	var start := {"x": x, "y": y_at(fh, x) if fh >= 0 and fh < count() else 0.0, "fh": fh, "moved": 0.0}
	if fh < 0 or fh >= count() or not is_floor(fh) or side == 0 or distance <= 0.0:
		return start
	var dir := 1.0 if side > 0 else -1.0
	var target := clampf(x + dir * distance, lo, hi)
	if (target - x) * dir <= 0.0:
		return start
	var guard := 0
	while guard < 4096:
		guard += 1
		var seg_end := x2[f] if dir > 0.0 else x1[f]
		var stop := minf(target, seg_end) if dir > 0.0 else maxf(target, seg_end)
		if floor_wall[f] != 0:
			var w := wall_hit(cur, y_at(f, cur), stop, y_at(f, stop), platform[f])
			if w >= 0:
				var wx := x1[w] - dir * EPS
				cur = maxf(cur, wx) if dir > 0.0 else minf(cur, wx)
				break
		cur = stop
		if cur * dir >= target * dir:
			break
		var g := next[f] if dir > 0.0 else prev[f]
		if g < 0 or not is_floor(g):
			break
		f = g
	return {"x": cur, "y": y_at(f, cur), "fh": f, "moved": absf(cur - x)}


## Finds a Teleport landing {pos, fh}, or {}. Vertical blinks choose the nearest floor strictly in that direction.
## tier C: horizontal blinks choose the furthest floor point within range and snap vertically by at most range;
## walls of platform `from_p` (the caster's, wall_applies; -1 = every wall) stop the blink at the existing collision
## epsilon. No unsupported air destination is returned.
func teleport_destination(origin: Vector2, direction: Vector2, distance: float, limits: Rect2,
		from_p: int = NONE) -> Dictionary:
	if distance <= 0.0 or direction == Vector2.ZERO:
		return {}
	var best := {}
	var best_score := INF
	var lo := bounds().position.x
	var hi := bounds().end.x
	if limits.has_area():
		lo = maxf(lo, limits.position.x)
		hi = minf(hi, limits.end.x)
	var horizontal := direction.x != 0.0
	var side := signf(direction.x)
	var target_x := clampf(origin.x + side * distance, lo, hi)
	if horizontal:
		var wall := wall_hit(origin.x, origin.y, target_x, origin.y, from_p)
		if wall >= 0:
			target_x = x1[wall] - side * EPS
	for f in count():
		if not is_floor(f):
			continue
		var x := origin.x
		if horizontal:
			x = clampf(target_x, maxf(lo, x1[f]), minf(hi, x2[f]))
			if x1[f] > hi or x2[f] < lo or (x - origin.x) * side <= EPS:
				continue
			if absf(x - origin.x) > absf(target_x - origin.x) + EPS:
				continue
		elif x < x1[f] or x > x2[f] or x < lo or x > hi:
			continue
		var y := y_at(f, x)
		if horizontal:
			var wall := wall_hit(origin.x, origin.y, x, y, from_p)
			if wall >= 0:
				x = x1[wall] - side * EPS
				if x < x1[f] or x > x2[f] or (x - origin.x) * side <= EPS:
					continue
				y = y_at(f, x)
		var dy := y - origin.y
		if absf(dy) > distance + EPS:
			continue
		if limits.has_area() and (y < limits.position.y or y > limits.end.y):
			continue
		if not horizontal and dy * direction.y <= EPS:
			continue
		if horizontal and wall_hit(origin.x, origin.y, x, y, from_p) >= 0:
			continue
		var score := absf(target_x - x) if horizontal else absf(dy)
		if score < best_score or (score == best_score and absf(dy) < absf(float(best.pos.y) - origin.y)):
			best_score = score
			best = {"pos": Vector2(x, y), "fh": f}
	return best


## The first floor at or below (x, y): the spanning floor with the smallest surface y >= y. Skips foothold `ignore`
## and every foothold of platform `ignore_platform`. Returns -1 when there is none.
func find_below(x: float, y: float, ignore: int = -1, ignore_platform: int = -1) -> int:
	var b := _bucket(x)
	if b < 0:
		return NONE
	var best := NONE
	var best_y := INF
	for k in range(_floor_start[b], _floor_start[b + 1]):
		var i := _floor_items[k]
		var ax := x1[i]
		var bx := x2[i]
		if x < ax or x > bx or i == ignore:
			continue
		if ignore_platform >= 0 and platform[i] == ignore_platform:
			continue
		var g := y1[i] + (y2[i] - y1[i]) * (x - ax) / (bx - ax)
		if g >= y - EPS and g < best_y:
			best_y = g
			best = i
	return best


## The floor a point moving from (xa, ya) to (xb, yb) lands on: it spans xb, the start was on or above its line and
## the end is on or below it. The highest such floor wins. Skips platform `ignore_platform`. -1 when none.
func find_landing(xa: float, ya: float, xb: float, yb: float, ignore_platform: int = -1) -> int:
	var b := _bucket(xb)
	if b < 0:
		return NONE
	var best := NONE
	var best_y := INF
	for k in range(_floor_start[b], _floor_start[b + 1]):
		var i := _floor_items[k]
		var ax := x1[i]
		var bx := x2[i]
		if xb < ax or xb > bx:
			continue
		if ignore_platform >= 0 and platform[i] == ignore_platform:
			continue
		var slope := (y2[i] - y1[i]) / (bx - ax)
		var gb := y1[i] + slope * (xb - ax)
		if yb < gb - EPS or gb >= best_y:
			continue
		var ga := y1[i] + slope * (clampf(xa, ax, bx) - ax)
		if ya > ga + EPS:
			continue
		best_y = gb
		best = i
	return best


## The first wall crossed by a point moving from (xa, ya) to (xb, yb), or -1. A wall counts when the moving point,
## probed WALL_PROBE px above the feet, is within the wall's vertical extent where it crosses the wall's x. A point
## exactly on the wall line is only blocked when moving into it from its own side. With `p` >= 0 only walls that apply
## to platform p count (wall_applies: the mover stands on p, or last stood on it while airborne); -1 counts every wall.
func wall_hit(xa: float, ya: float, xb: float, yb: float, p: int = NONE) -> int:
	if xa == xb or _gn == 0:
		return NONE
	var lo := minf(xa, xb)
	var hi := maxf(xa, xb)
	var b0 := clampi(int(floor((lo - _gx0) / BUCKET_W)), 0, _gn - 1)
	var b1 := clampi(int(floor((hi - _gx0) / BUCKET_W)), 0, _gn - 1)
	var best := NONE
	var best_d := INF
	var right := xb > xa
	var row := p * _wall_count if p >= 0 and p < plat_x1.size() else -1
	for b in range(b0, b1 + 1):
		for k in range(_wall_start[b], _wall_start[b + 1]):
			var w := _wall_items[k]
			if row >= 0 and _wall_rel[row + _wall_slot[w]] == 0:
				continue
			var wx := x1[w]
			if right:
				if wx <= xa or wx > xb:
					continue
			elif wx >= xa or wx < xb:
				continue
			var yc := ya + (yb - ya) * (wx - xa) / (xb - xa) - WALL_PROBE
			var top := minf(y1[w], y2[w])
			var bot := maxf(y1[w], y2[w])
			if yc < top or yc > bot:
				continue
			var d := absf(wx - xa)
			if d < best_d:
				best_d = d
				best = w
	return best


## True when wall `w` stops bodies of platform `p` (see the header): it shares a group with one of p's floors, is
## linked to one of them, sits in group 0 or is cantThrough. Always true for p = -1 (no platform known).
func wall_applies(w: int, p: int) -> bool:
	if p < 0 or p >= plat_x1.size() or w < 0 or w >= count() or _wall_slot[w] < 0:
		return true
	return _wall_rel[p * _wall_count + _wall_slot[w]] != 0


## True for ceilings / undersides (x1 > x2).
func is_ceiling(i: int) -> bool:
	return x1[i] > x2[i]


## The ceiling a point moving up from (xa, ya) to (xb, yb) bumps into: it spans xb, the start was on or below its
## line and the end is above it. The lowest such ceiling (the first one met) wins. -1 when none or not moving up.
func ceiling_hit(xa: float, ya: float, xb: float, yb: float) -> int:
	if yb >= ya:
		return NONE
	var b := _bucket(xb)
	if b < 0:
		return NONE
	var best := NONE
	var best_y := -INF
	for k in range(_ceil_start[b], _ceil_start[b + 1]):
		var i := _ceil_items[k]
		var ax := x2[i]
		var bx := x1[i]
		if xb < ax or xb > bx:
			continue
		var slope := (y1[i] - y2[i]) / (bx - ax)
		var gb := y2[i] + slope * (xb - ax)
		if yb > gb + EPS or gb <= best_y:
			continue
		var ga := y2[i] + slope * (clampf(xa, ax, bx) - ax)
		if ya < ga - EPS:
			continue
		best_y = gb
		best = i
	return best


## The first x on the horizontal path from (xa, y) to xb where a floor rises to the path's height or a ceiling comes down
## to it, or NAN when the path is clear. A floor counts when the path starts on or above its line where the floor first
## meets the path and the floor is above the path at its far end (the body would end inside the ground); a ceiling
## counts the same from below. Surfaces the path runs under (a floor above it) or over (a ceiling below it) never
## count, platforms stay one-way. Walls are wall_hit's job. Used by Flash Jump, which keeps its height (#405 review).
func surface_crossing_x(xa: float, y: float, xb: float) -> float:
	if xa == xb or _gn == 0:
		return NAN
	var right := xb > xa
	var lo := minf(xa, xb)
	var hi := maxf(xa, xb)
	var b0 := clampi(int(floor((lo - _gx0) / BUCKET_W)), 0, _gn - 1)
	var b1 := clampi(int(floor((hi - _gx0) / BUCKET_W)), 0, _gn - 1)
	var best := NAN
	for pass_ceilings in 2:
		var start := _ceil_start if pass_ceilings == 1 else _floor_start
		var items := _ceil_items if pass_ceilings == 1 else _floor_items
		for b in range(b0, b1 + 1):
			for k in range(start[b], start[b + 1]):
				var i := items[k]
				var left := minf(x1[i], x2[i])
				var rightmost := maxf(x1[i], x2[i])
				var from_x := maxf(lo, left)
				var to_x := minf(hi, rightmost)
				if from_x > to_x:
					continue
				var enter_x := from_x if right else to_x
				var exit_x := to_x if right else from_x
				var ge := y_at(i, enter_x)
				var gx := y_at(i, exit_x)
				var crossing := false
				if pass_ceilings == 1:
					crossing = y >= ge - EPS and gx > y + EPS
				else:
					crossing = y <= ge + EPS and gx < y - EPS
				if not crossing:
					continue
				var hit_x := enter_x + (exit_x - enter_x) * (y - ge) / (gx - ge)
				if is_nan(best) or (hit_x < best if right else hit_x > best):
					best = hit_x
	return best


## The floor a point moving from (xa, ya) to (xb, yb) crosses from above inside the floor's span although xb lies past
## the floor's end, so find_landing (which tests the floor under xb only) misses it: a fall into the corner where a
## floor ends at a wall rising from it, whose wall probe at the crossing x is already below the wall's foot (#260).
## The highest such floor wins; skips platform `ignore_platform`. -1 when none. Land at corner_landing_x().
func find_corner_landing(xa: float, ya: float, xb: float, yb: float, ignore_platform: int = -1) -> int:
	if xa == xb or _gn == 0:
		return NONE
	var lo := minf(xa, xb)
	var hi := maxf(xa, xb)
	var best := NONE
	var best_y := INF
	for b in range(clampi(int(floor((lo - _gx0) / BUCKET_W)), 0, _gn - 1),
			clampi(int(floor((hi - _gx0) / BUCKET_W)), 0, _gn - 1) + 1):
		for k in range(_floor_start[b], _floor_start[b + 1]):
			var i := _floor_items[k]
			var ax := x1[i]
			var bx := x2[i]
			if xb >= ax and xb <= bx:
				continue # find_landing's case
			if ignore_platform >= 0 and platform[i] == ignore_platform:
				continue
			var s0 := maxf(ax, lo)
			var s1 := minf(bx, hi)
			if s0 > s1:
				continue
			# The part of the path over the floor, from the start side (near) to the end side (far).
			var near := s0 if xa < xb else s1
			var far := s1 if xa < xb else s0
			var slope := (y2[i] - y1[i]) / (bx - ax)
			var path := (yb - ya) / (xb - xa)
			var g_near := y1[i] + slope * (near - ax)
			var g_far := y1[i] + slope * (far - ax)
			if ya + path * (near - xa) > g_near + EPS or ya + path * (far - xa) < g_far - EPS:
				continue
			if g_far >= best_y:
				continue
			best_y = g_far
			best = i
	return best


## Where a body caught by find_corner_landing(…, xb, …) on floor `i` stands: xb pulled back inside the floor's span by
## EPS, off the end point (a point exactly on a wall line is not blocked by it, wall_hit).
func corner_landing_x(i: int, xb: float) -> float:
	return clampf(xb, x1[i] + EPS, x2[i] - EPS)


## The floor point nearest to `p` as (x, y, foothold), z = -1 on a map without floors. The x stays EPS inside the
## floor's span: an end point exactly on a wall line rising from it would not block walking off that end (#260).
func nearest_floor_point(p: Vector2) -> Vector3:
	var best := Vector3(p.x, p.y, NONE)
	var best_d := INF
	for f in count():
		if not is_floor(f):
			continue
		var cx := clampf(p.x, x1[f] + EPS, x2[f] - EPS)
		var cy := y_at(f, cx)
		var d := Vector2(cx - p.x, cy - p.y).length_squared()
		if d < best_d:
			best_d = d
			best = Vector3(cx, cy, f)
	return best


## True when any floor spans x (at any height).
func has_floor_at(x: float) -> bool:
	var b := _bucket(x)
	if b < 0:
		return false
	for k in range(_floor_start[b], _floor_start[b + 1]):
		var i := _floor_items[k]
		if x >= x1[i] and x <= x2[i]:
			return true
	return false


func _bucket(x: float) -> int:
	var b := int(floor((x - _gx0) / BUCKET_W))
	return b if b >= 0 and b < _gn else NONE


func _build(segs: Array) -> void:
	var n := segs.size()
	for arr: Variant in [x1, y1, x2, y2, force]:
		arr.resize(n)
	for arr: Variant in [layer, group, prev, next, ids, platform]:
		arr.resize(n)
	cant_through.resize(n)
	forbid_fall_down.resize(n)
	for i in n:
		var s: Dictionary = segs[i]
		x1[i] = s.x1
		y1[i] = s.y1
		x2[i] = s.x2
		y2[i] = s.y2
		layer[i] = s.layer
		group[i] = s.group
		ids[i] = s.id
		prev[i] = s.prev if s.prev >= 0 and s.prev < n else NONE
		next[i] = s.next if s.next >= 0 and s.next < n else NONE
		cant_through[i] = 1 if s.cant_through else 0
		forbid_fall_down[i] = 1 if s.forbid_fall_down else 0
		force[i] = s.force
	_build_bounds()
	_build_grid()
	_build_platforms()
	_build_floor_walls()


func _build_bounds() -> void:
	var n := count()
	if n == 0:
		_bounds = Rect2()
		return
	var lx := INF
	var ly := INF
	var hx := -INF
	var hy := -INF
	for i in n:
		lx = minf(lx, minf(x1[i], x2[i]))
		hx = maxf(hx, maxf(x1[i], x2[i]))
		ly = minf(ly, minf(y1[i], y2[i]))
		hy = maxf(hy, maxf(y1[i], y2[i]))
	_bounds = Rect2(lx, ly, hx - lx, hy - ly)


func _build_grid() -> void:
	var n := count()
	if n == 0:
		_gn = 0
		_floor_start = PackedInt32Array([0])
		_wall_start = PackedInt32Array([0])
		_ceil_start = PackedInt32Array([0])
		return
	_gx0 = floor(_bounds.position.x / BUCKET_W) * BUCKET_W - BUCKET_W
	_gn = int(ceil((_bounds.end.x - _gx0) / BUCKET_W)) + 2
	_floor_start = PackedInt32Array()
	_floor_start.resize(_gn + 1)
	_floor_start.fill(0)
	_wall_start = PackedInt32Array()
	_wall_start.resize(_gn + 1)
	_wall_start.fill(0)
	_ceil_start = PackedInt32Array()
	_ceil_start.resize(_gn + 1)
	_ceil_start.fill(0)
	# Counting sort into CSR buckets: floors and ceilings go into every bucket they overlap, walls into the bucket of
	# their x.
	for i in n:
		if x1[i] < x2[i]:
			for b in range(_bucket(x1[i]), _bucket(x2[i]) + 1):
				_floor_start[b + 1] += 1
		elif x1[i] == x2[i]:
			_wall_start[_bucket(x1[i]) + 1] += 1
		else:
			for b in range(_bucket(x2[i]), _bucket(x1[i]) + 1):
				_ceil_start[b + 1] += 1
	for b in _gn:
		_floor_start[b + 1] += _floor_start[b]
		_wall_start[b + 1] += _wall_start[b]
		_ceil_start[b + 1] += _ceil_start[b]
	_floor_items = PackedInt32Array()
	_floor_items.resize(_floor_start[_gn])
	_wall_items = PackedInt32Array()
	_wall_items.resize(_wall_start[_gn])
	_ceil_items = PackedInt32Array()
	_ceil_items.resize(_ceil_start[_gn])
	var fcur := _floor_start.duplicate()
	var wcur := _wall_start.duplicate()
	var ccur := _ceil_start.duplicate()
	for i in n:
		if x1[i] < x2[i]:
			for b in range(_bucket(x1[i]), _bucket(x2[i]) + 1):
				_floor_items[fcur[b]] = i
				fcur[b] += 1
		elif x1[i] == x2[i]:
			var wb := _bucket(x1[i])
			_wall_items[wcur[wb]] = i
			wcur[wb] += 1
		else:
			for b in range(_bucket(x2[i]), _bucket(x1[i]) + 1):
				_ceil_items[ccur[b]] = i
				ccur[b] += 1


func _build_platforms() -> void:
	var n := count()
	# Union-find over floor-to-floor links in both directions (links may be asymmetric in real data).
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	for i in n:
		if not is_floor(i):
			continue
		for j: int in [next[i], prev[i]]:
			if j >= 0 and is_floor(j):
				var ra := _find_root(parent, i)
				var rb := _find_root(parent, j)
				if ra != rb:
					parent[maxi(ra, rb)] = mini(ra, rb)
	var root_to_p := {}
	platform.fill(NONE)
	for i in n:
		if not is_floor(i):
			continue
		var r := _find_root(parent, i)
		if not root_to_p.has(r):
			root_to_p[r] = root_to_p.size()
		platform[i] = root_to_p[r]
	var pc := root_to_p.size()
	for arr: Variant in [plat_x1, plat_x2, plat_y_min, plat_y_max]:
		arr.resize(pc)
	for arr: Variant in [plat_left_fh, plat_right_fh]:
		arr.resize(pc)
		arr.fill(NONE)
	plat_open_left.resize(pc)
	plat_open_right.resize(pc)
	plat_x1.fill(INF)
	plat_x2.fill(-INF)
	plat_y_min.fill(INF)
	plat_y_max.fill(-INF)
	for i in n:
		var p := platform[i]
		if p < 0:
			continue
		if x1[i] < plat_x1[p]:
			plat_x1[p] = x1[i]
			plat_left_fh[p] = i
		if x2[i] > plat_x2[p]:
			plat_x2[p] = x2[i]
			plat_right_fh[p] = i
		plat_y_min[p] = minf(plat_y_min[p], minf(y1[i], y2[i]))
		plat_y_max[p] = maxf(plat_y_max[p], maxf(y1[i], y2[i]))
	_build_wall_relevance()
	for p in pc:
		plat_open_left[p] = 0 if _end_blocked(p, plat_x1[p], y1[plat_left_fh[p]], -1.0) else 1
		plat_open_right[p] = 0 if _end_blocked(p, plat_x2[p], y2[plat_right_fh[p]], 1.0) else 1


## Fills the platform x wall table behind wall_applies.
func _build_wall_relevance() -> void:
	var n := count()
	_wall_slot.resize(n)
	_wall_slot.fill(NONE)
	_wall_count = 0
	for i in n:
		if is_wall(i):
			_wall_slot[i] = _wall_count
			_wall_count += 1
	var pc := plat_x1.size()
	_wall_rel.resize(pc * _wall_count)
	_wall_rel.fill(0)
	# Groups present on each platform, and the walls linked to its floors.
	var plat_groups: Array[Dictionary] = []
	plat_groups.resize(pc)
	for p in pc:
		plat_groups[p] = {}
	for i in n:
		var p := platform[i]
		if p < 0:
			continue
		plat_groups[p][group[i]] = true
		for j: int in [next[i], prev[i]]:
			if j >= 0 and is_wall(j):
				_wall_rel[p * _wall_count + _wall_slot[j]] = 1
	for w in n:
		if not is_wall(w):
			continue
		var c := _wall_slot[w]
		var everyone := group[w] == 0 or cant_through[w] != 0
		for p in pc:
			if everyone or plat_groups[p].has(group[w]):
				_wall_rel[p * _wall_count + c] = 1


## Flags floors that have a wall within their x span whose vertical extent reaches the band a walker's wall probe
## sweeps on them (with a float32 margin; wall_hit decides).
func _build_floor_walls() -> void:
	var n := count()
	floor_wall.resize(n)
	floor_wall.fill(0)
	for i in n:
		if not is_floor(i):
			continue
		var lo := minf(y1[i], y2[i]) - WALL_PROBE - 0.05
		var hi := maxf(y1[i], y2[i]) - WALL_PROBE + 0.05
		for b in range(_bucket(x1[i]), _bucket(x2[i]) + 1):
			for k in range(_wall_start[b], _wall_start[b + 1]):
				var w := _wall_items[k]
				if x1[w] < x1[i] or x1[w] > x2[i] or not wall_applies(w, platform[i]):
					continue
				if maxf(y1[w], y2[w]) < lo or minf(y1[w], y2[w]) > hi:
					continue
				floor_wall[i] = 1
	plat_wall.resize(plat_x1.size())
	plat_wall.fill(0)
	for i in n:
		if floor_wall[i] != 0 and platform[i] >= 0:
			plat_wall[platform[i]] = 1


## True when a wall of platform p at the end point (x, y) rises above the feet (it would stop a walker heading `dir`).
func _end_blocked(p: int, x: float, y: float, dir: float) -> bool:
	return wall_hit(x - dir * 0.5, y, x + dir * 0.5, y, p) >= 0


static func _find_root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
