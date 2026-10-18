class_name SpawnDirector
extends RefCounted
## Stage pacing and spawn positions (docs/GAME_DESIGN.md sections 4, 4.1; `data/survivor/stages.json`).
##
## Pacing: `rate` (mobs/s), `max_alive`, `hp` and `speed` interpolate linearly between the stage keyframes;
## the pool (mob id -> weight) is the one of the last keyframe at or before t. While alive < max_alive(t) the director
## spawns rate(t) mobs per second (a fractional accumulator, not banked while capped), each of a kind drawn by weight.
## Every `bursts.every` s a ring of count_min..count_max mobs (growing linearly over the stage) spawns around the view
## (allowed past max_alive up to the stage's hard_cap) and a `burst` event is emitted; every `elites.every` s one mob
## of the pool spawns as an elite (hp_mult x HP; RunWorld pays exp_mult x EXP). With a positive `post_duration_slope`
## the rate/max_alive/hp/speed keyframe slopes, the burst size and the elite frequency keep growing at that pace
## after the last keyframe until the clear (value_at, burst_count_at, elite_interval_at).
## An optional ordinary HP drop chance interpolates, with the global HP fallback and endpoint holding (normal MP has no
## stage values: one global chance, owner 2026-10-16).
##
## Positions (tier C): a random point on a floor outside the view grown by `margin` px, inside the map bounds and at
## least `min_player_dist` from the player, searched in three rings: within `band` px of the view (with `band_y` >= 0
## only that far above and below it: the floors beside the view, so mobs come in from the sides of the screen), within
## 3 x band, and anywhere within 0.9 x recycle_dist of the player. A point from which that mob's movement class can
## reach the player (NavGraph travel-cost field toward the player's point, NavGraph.route_cost) is preferred: each ring
## gets `attempts` samples looking for one, and only when no ring has one does the first valid unreachable point of the
## two inner rings serve. A point whose way to the player runs into a wall standing across a platform (_walled():
## FootholdMap.walk_blocked on each platform of the way, e.g. a buried stretch of floor) counts as unreachable. With
## `prefer_route` >= 0 a ring's samples first look for a direct point: one whose
## way to the player (route_cost, px) is at most half the view's width + `margin` + prefer_route, i.e. no longer than
## the walk in from a floor beside the view at most prefer_route px out (a floor the mob walks straight in on, or a
## platform above whose near end drops it next to the player), so the crowd comes at the player instead of queueing on a
## long platform that leads away from it; the ring's first reachable point serves when none is that direct.
## pick_spawn(world, k, side) with side -1/1 also prefers points on that side of the player (ahead of it).
## Flyers sample air in off-screen strips of the same rings inside map bounds, ignoring floors and NavGraph.
## Their spawn point has foothold -1; all kinds return foothold -2 when no valid point exists.
## A platform_share of ground placements first targets the player's floor, at least platform_min_dist away. When
## the entire platform fits in view these points may be visible; otherwise its off-screen portions are used.
##
## The view grown by `margin` (the rect spawns stay out of) is grown by `trail_margin` more on the side the player moves
## away from (horizontal speed > 1 px/s): the camera lags behind a running player (CameraRig: 125 px/s / 6 per s + its
## 8 px dead zone ~ 29 px), so that side of the screen shows more than the player-centred view.
##
## Relocation (silent, elites excepted; RunWorld.relocate_mob: the same mob with its HP, regen fade-in, a new
## mob_spawned event with `relocated_from`, counted in `relocated`), only ever from outside the view grown by margin +
## trail_margin on every side (right after the player turns, the camera still lags on the other side): a mob that has
## not come `stall_progress` px closer (MobSwarm.route_len) by moving itself (at least `stall_progress` px from where it
## last came closer; the player walking up to a mob stopped at a wall is not the mob's progress) for `stall_time` s in
## a row (a mob left behind by a player who runs away, walking a way that keeps getting longer, or stopped at a wall
## across its platform; a mob standing still on screen keeps counting, so it is moved as soon as it is off screen), and
## one farther than `recycle_dist` from the player or standing on a platform that cannot reach the player's outside the
## view grown by `band` for `recycle_time` s in a row (GAME_DESIGN 4), is moved to a fresh pick_spawn point ahead of
## the player (on the side it moves toward). Only when no point is found is it recycled (MobSwarm.despawn, counted in
## `recycled`).

const DEFAULT_SPAWN := {
	"margin": 48.0,  # tier C: GAME_DESIGN 4, spawn outside the view + 48 px
	"band": 320.0,  # tier C: ours, spawn preferably at most this far outside the view
	"min_player_dist": 200.0,  # tier C: GAME_DESIGN 4
	"attempts": 12,  # tier C: ours, samples per ring
	"recycle_dist": 1300.0,  # tier C: ours
	"recycle_time": 3.0,  # tier C: ours
	"band_y": -1.0,  # tier C: ours, the first ring reaches only this far above and below the view (< 0 = band)
	"prefer_route": -1.0,  # tier C: ours, < 0 = any reachable point will do
	"stall_time": 0.0,  # tier C: ours, s without coming closer before an off-screen mob is relocated; 0 = never
	"stall_progress": 1.0,  # tier C: ours, px of route a mob must gain (and walk) to count as coming closer
	"trail_margin": 0.0,  # tier C: ours, extra margin on the side the player moves away from (camera lag); 0 = none
	"platform_share": 0.35,  # tier C: owner choice, share of ground placements that target the player's platform
	"platform_min_dist": 150.0,  # tier C: owner choice, minimum separation of a player-platform spawn
}
## Edges of a spawn point's way that _walled() follows looking for a wall across a platform (a bound; each edge of the
## way is strictly cheaper than the one before, so the way has no cycle).
const WALLED_HOPS := 8

var stage: Dictionary
var duration := 900.0
var hard_cap := 400
## Parsed keyframes: {t, rate, max_alive, hp, speed, kinds: PackedInt32Array, weights: PackedFloat32Array}.
var keyframes: Array = []
var params: Dictionary
var spawned := 0
var bursts := 0
var elites := 0
var recycled := 0
## Off-screen mobs moved to a fresh spawn point (see the class doc); not counted in `spawned` or `recycled`.
var relocated := 0
var next_burst := INF
var next_elite := INF

var _acc := 0.0
## Per mob slot: seconds far/unreachable in a row, seconds without coming closer, the shortest route_len seen and
## where the mob stood then.
var _far_t := PackedFloat32Array()
var _stall_t := PackedFloat32Array()
var _best_len := PackedFloat32Array()
var _anchor := PackedVector2Array()
## _walled_after() results per (graph, edge) for _walled_key: (time, player position, player platform).
var _walled_memo := {}
var _walled_key := Vector4(-1, 0, 0, -2)
var _floors := PackedInt32Array()
## Floor pieces per ring: [fh: PackedInt32Array, a: PackedFloat32Array, b: PackedFloat32Array, cum: PackedFloat32Array].
var _rings: Array = [[], [], []]
## (time, view position, the player's moving side) each ring was built for; rebuilt when it changes.
var _ring_key: Array = [Vector4(-1, 0, 0, 0), Vector4(-1, 0, 0, 0), Vector4(-1, 0, 0, 0)]


## Builds the director for a stages.json stage. `kind_index` maps mob id -> RunWorld.mob_kinds index; pool entries
## without a kind are dropped. `spawn_params` overrides DEFAULT_SPAWN (balance.json `spawn`), and the stage's own
## `spawn` overrides both (e.g. prefer_route per map).
static func create(p_stage: Dictionary, kind_index: Dictionary, spawn_params: Dictionary = {}) -> SpawnDirector:
	var d := SpawnDirector.new()
	d.stage = p_stage
	d.duration = float(p_stage.get("duration", 900.0))
	d.hard_cap = int(p_stage.get("hard_cap", 400))
	d.params = DEFAULT_SPAWN.duplicate()
	for k: String in spawn_params:
		if d.params.has(k):
			d.params[k] = spawn_params[k]
	var own: Variant = p_stage.get("spawn", {})
	if own is Dictionary:
		for k: String in own:
			if d.params.has(k):
				d.params[k] = own[k]
	for kf: Dictionary in p_stage.get("keyframes", []):
		var kinds := PackedInt32Array()
		var weights := PackedFloat32Array()
		var pool: Dictionary = kf.get("pool", {})
		for id_key: Variant in pool:
			var id := int(id_key)
			var w := float(pool[id_key])
			if kind_index.has(id) and w > 0.0:
				kinds.append(int(kind_index[id]))
				weights.append(w)
		d.keyframes.append({
			"t": float(kf.get("t", 0.0)), "rate": float(kf.get("rate", 0.0)),
			"max_alive": float(kf.get("max_alive", 0.0)), "hp": float(kf.get("hp", 1.0)),
			"speed": float(kf.get("speed", 1.0)),
			"kinds": kinds, "weights": weights,
		})
		if kf.has("normal_hp_drop_chance"):
			d.keyframes.back()["normal_hp_drop_chance"] = float(kf.normal_hp_drop_chance)
	d.keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	var bu: Dictionary = p_stage.get("bursts", {})
	if not bu.is_empty() and float(bu.get("every", 0.0)) > 0.0:
		d.next_burst = float(bu.get("first", bu.every))
	var el: Dictionary = p_stage.get("elites", {})
	if not el.is_empty() and float(el.get("every", 0.0)) > 0.0:
		d.next_elite = float(el.get("first", el.every))
	return d


## Linearly interpolated keyframe value `field` ("rate", "max_alive", "hp", "speed") at time t.
func value_at(field: String, t: float) -> float:
	if keyframes.is_empty():
		return 0.0 if field == "rate" or field == "max_alive" else 1.0
	if t <= float(keyframes[0].t):
		return float(keyframes[0][field])
	for k in range(1, keyframes.size()):
		var b: Dictionary = keyframes[k]
		if t <= float(b.t):
			var a: Dictionary = keyframes[k - 1]
			var span := float(b.t) - float(a.t)
			var f := (t - float(a.t)) / span if span > 0.0 else 1.0
			return lerpf(float(a[field]), float(b[field]), f)
	var last: Dictionary = keyframes[keyframes.size() - 1]
	var slope_mult := float(stage.get("post_duration_slope", 0.0))
	if slope_mult > 0.0 and keyframes.size() >= 2:
		var previous: Dictionary = keyframes[keyframes.size() - 2]
		var span := float(last.t) - float(previous.t)
		if span > 0.0:
			var slope := (float(last[field]) - float(previous[field])) / span
			return maxf(0.0, float(last[field]) + slope * (t - float(last.t)) * slope_mult)
	return float(last[field])


## Spawns per second at t.
func rate_at(t: float) -> float:
	return value_at("rate", t)


## Ordinary HP potion chance: optional stage endpoints interpolate, missing endpoints use the global fallback.
## tier C: survivor supply tuning; probabilities clamp to [0, 1] and hold after the last frame, without spawn ramping.
func normal_hp_drop_chance_at(t: float, fallback: float) -> float:
	return _probability_curve_at("normal_hp_drop_chance", t, fallback)


func _probability_curve_at(field: String, t: float, fallback: float) -> float:
	if keyframes.is_empty():
		return clampf(fallback, 0.0, 1.0)
	var a: Dictionary = keyframes[0]
	var value := clampf(float(a.get(field, fallback)), 0.0, 1.0)
	if t <= float(a.t):
		return value
	for k in range(1, keyframes.size()):
		var b: Dictionary = keyframes[k]
		var next := clampf(float(b.get(field, fallback)), 0.0, 1.0)
		if t <= float(b.t):
			var span := float(b.t) - float(a.t)
			return lerpf(value, next, (t - float(a.t)) / span if span > 0.0 else 1.0)
		a = b
		value = next
	return value


## Actual ordinary spawn rate, reduced while a scheduled boss remains alive.
func effective_rate(world: RunWorld) -> float:
	return rate_at(world.time) * world.bosses.normal_spawn_multiplier()


## Alive target at t (rounded).
func max_alive_at(t: float) -> int:
	return roundi(value_at("max_alive", t))


## The keyframe whose pool is active at t ({} when none).
func pool_at(t: float) -> Dictionary:
	var cur: Dictionary = {}
	for kf: Dictionary in keyframes:
		if float(kf.t) <= t:
			cur = kf
	if cur.is_empty() and not keyframes.is_empty():
		cur = keyframes[0]
	return cur


## A kind index drawn by weight from the pool at t (-1 when the pool is empty).
func pick_kind(t: float, rng: RandomNumberGenerator) -> int:
	var kf := pool_at(t)
	if kf.is_empty():
		return -1
	var kinds: PackedInt32Array = kf.kinds
	var weights: PackedFloat32Array = kf.weights
	if kinds.is_empty():
		return -1
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for k in kinds.size():
		r -= weights[k]
		if r < 0.0:
			return kinds[k]
	return kinds[kinds.size() - 1]


## Spawn count of the burst at t: count_min..count_max over the stage duration; past the duration (a stage with a
## positive `post_duration_slope`) the count keeps that slope at post_duration_slope pace (tier C).
func burst_count_at(t: float) -> int:
	var bu: Dictionary = stage.get("bursts", {})
	var lo := float(bu.get("count_min", 20))
	var hi := float(bu.get("count_max", 40))
	if duration <= 0.0:
		return roundi(lo)
	if t <= duration:
		return roundi(lerpf(lo, hi, clampf(t / duration, 0.0, 1.0)))
	var slope_mult := float(stage.get("post_duration_slope", 0.0))
	return roundi(hi + maxf(0.0, (hi - lo) / duration * (t - duration) * slope_mult))


## Seconds until the next elite after one at t: `elites.every`, shortened after the last keyframe of a stage with a
## positive `post_duration_slope` in proportion to the extrapolated spawn rate (every x rate(last) / rate(t)), so
## elites stay the same share of the growing steady stream until the clear (tier C).
func elite_interval_at(t: float) -> float:
	var every := float(stage.get("elites", {}).get("every", 0.0))
	if keyframes.is_empty() or float(stage.get("post_duration_slope", 0.0)) <= 0.0:
		return every
	var last_t := float(keyframes[keyframes.size() - 1].t)
	if t <= last_t:
		return every
	var base := rate_at(last_t)
	var now := rate_at(t)
	return every * base / now if base > 0.0 and now > base else every


## One director tick: recycling, steady spawns, bursts, elites (RunWorld.spawn_mob does the spawning and events).
func step(dt: float, world: RunWorld) -> void:
	var t := world.time
	var swarm := world.swarm
	if not world.is_hidden():
		_recycle(dt, world)  # Hidden (#194): no mob has a route to the character, so none is "gone" or stalled.
	var cap := mini(max_alive_at(t), hard_cap)
	var alive := swarm.alive_count()
	_acc += effective_rate(world) * dt
	while _acc >= 1.0 and alive < cap:
		_acc -= 1.0
		if _spawn_one(world, t, false):
			alive += 1
		else:
			break
	if alive >= cap:
		_acc = minf(_acc, 1.0)
	if t >= next_burst:
		next_burst += float(stage.bursts.every)
		# tier C: bursts are normal spawns, so they also run at half size while a boss lives (GAME_DESIGN 4.3).
		var count := roundi(burst_count_at(t) * world.bosses.normal_spawn_multiplier())
		var n := mini(count, maxi(0, hard_cap - swarm.alive_count()))
		bursts += 1
		world.emit("burst", {"count": n})
		for k in n:
			_spawn_one(world, t, false)
	if t >= next_elite:
		next_elite += elite_interval_at(t)
		if swarm.alive_count() < hard_cap and _spawn_one(world, t, true):
			elites += 1


## A spawn point for kind `k`: Vector3(x, y, foothold), with foothold -1 for flyers; z=-2 when none is found.
## side -1/1: prefer points on that side of the player (a direct point on the other side still beats an indirect one).
func pick_spawn(world: RunWorld, k: int, side: int = 0) -> Vector3:
	var rng := world.spawn_rng
	var mk: MobKind = world.mob_kinds[k]
	if mk.flies:
		return _pick_air_spawn(world, side)
	if float(params.platform_share) > 0.0 and rng.randf() < float(params.platform_share):
		var on_platform := pick_player_platform(world, -1.0, -1.0, false, side)
		if on_platform.z >= 0:
			return on_platform
	var nav := world.nav_jump if mk.can_jump else world.nav
	var target_p := world.player_platform()
	var px := world.player.pos.x
	var inner := screen_rect(world)
	var min_d2 := float(params.min_player_dist) * float(params.min_player_dist)
	var far2 := float(params.recycle_dist) * float(params.recycle_dist) * 0.81
	var tries := int(params.attempts)
	var route_max := INF
	if float(params.get("prefer_route", -1.0)) >= 0.0:
		route_max = world.view.size.x * 0.5 + float(params.margin) + float(params.prefer_route)
	if nav != null and target_p >= 0:
		nav.prepare_target(target_p, px, -1 if mk.can_jump else world.player_low_platform())
	var fallback := Vector3(0, 0, -2)
	for ring in 3:
		var pieces := _ring(world, ring)
		var fhs: PackedInt32Array = pieces[0]
		if fhs.is_empty():
			continue
		var direct := Vector3(0, 0, -1)
		var reach := Vector3(0, 0, -1)
		for attempt in tries:
			var p := _sample(world.fhm, pieces, rng)
			var pos := Vector2(p.x, p.y)
			if inner.has_point(pos) or not world.bounds.has_point(pos):
				continue
			var d2 := pos.distance_squared_to(world.player.pos)
			if d2 < min_d2 or (ring == 2 and d2 > far2):
				continue
			var ahead := side == 0 or (p.x - px) * side > 0.0
			if nav == null or target_p < 0:
				if ahead:
					return p
				if direct.z < 0:
					direct = p
				continue
			var q := world.fhm.platform_of(int(p.z))
			var cost := nav.route_cost(q, p.x)
			if cost < INF and _walled(world, nav, q, p.x, target_p):
				cost = INF  # a wall across its platform stands between the point and its way on (buried floor)
			if cost < INF:
				if cost <= route_max:
					if ahead:
						return p
					if direct.z < 0:
						direct = p
				elif reach.z < 0:
					reach = p
			elif fallback.z < 0 and ring < 2:
				fallback = p
		if direct.z >= 0:
			return direct
		if reach.z >= 0:
			return reach
	return fallback


## True when every floor of the player's current platform fits inside the logical view.
func player_platform_visible(world: RunWorld) -> bool:
	var p := world.player_platform()
	if p < 0:
		return false
	var m := world.fhm
	return m.plat_x1[p] >= world.view.position.x and m.plat_x2[p] <= world.view.end.x \
		and m.plat_y_min[p] >= world.view.position.y and m.plat_y_max[p] <= world.view.end.y


## Places on the player's platform (z=-2 when impossible). A preferred distance supports boss relocations;
## allow_visible permits them in view even on a long platform. Normal spawns are visible only on a fully visible floor.
func pick_player_platform(world: RunWorld, min_distance := -1.0, preferred_distance := -1.0,
		allow_visible := false, side := 0) -> Vector3:
	var p := world.player_platform()
	if p < 0:
		return Vector3(0, 0, -2)
	var m := world.fhm
	var visible := allow_visible or player_platform_visible(world)
	var distance := float(params.platform_min_dist) if min_distance < 0.0 else min_distance
	var fhs := PackedInt32Array()
	var aa := PackedFloat32Array()
	var bb := PackedFloat32Array()
	var cum := PackedFloat32Array()
	var total := 0.0
	var px := world.player.pos.x
	for f in m.count():
		if m.platform_of(f) != p:
			continue
		var a := maxf(m.x1[f], world.bounds.position.x)
		var b := minf(m.x2[f], world.bounds.end.x)
		var parts: Array = [Vector2(a, minf(b, px - distance)), Vector2(maxf(a, px + distance), b)]
		for part: Vector2 in parts:
			if part.y <= part.x:
				continue
			var ranges: Array = [part] if visible else _outside_rect(m, f, part, screen_rect(world))
			for r: Vector2 in ranges:
				if r.y <= r.x:
					continue
				total += r.y - r.x
				fhs.append(f)
				aa.append(r.x)
				bb.append(r.y)
				cum.append(total)
	if fhs.is_empty():
		return Vector3(0, 0, -2)
	if preferred_distance >= distance:
		var points: Array[Vector3] = []
		for i in fhs.size():
			for direction: int in [-1, 1]:
				var x := px + direction * preferred_distance
				var pos := Vector2(x, m.y_at(fhs[i], x))
				if x >= aa[i] and x <= bb[i] and (side == 0 or direction == side) \
						and world.bounds.has_point(pos) and not m.walk_blocked(p, px, x):
					points.append(Vector3(pos.x, pos.y, fhs[i]))
		if not points.is_empty():
			return points[world.spawn_rng.randi_range(0, points.size() - 1)]
	var fallback := Vector3(0, 0, -2)
	for attempt in int(params.attempts):
		var point := _sample(m, [fhs, aa, bb, cum], world.spawn_rng)
		if not world.bounds.has_point(Vector2(point.x, point.y)) or m.walk_blocked(p, px, point.x):
			continue
		if not visible and screen_rect(world).has_point(Vector2(point.x, point.y)):
			continue
		if side == 0 or (point.x - px) * side > 0.0:
			return point
		fallback = point
	return fallback


static func _outside_rect(m: FootholdMap, f: int, part: Vector2, rect: Rect2) -> Array:
	var a := maxf(part.x, rect.position.x)
	var b := minf(part.y, rect.end.x)
	if a >= b:
		return [part]
	var slope := (m.y2[f] - m.y1[f]) / (m.x2[f] - m.x1[f])
	if slope == 0.0:
		if m.y1[f] < rect.position.y or m.y1[f] > rect.end.y:
			return [part]
	else:
		var top := m.x1[f] + (rect.position.y - m.y1[f]) / slope
		var bottom := m.x1[f] + (rect.end.y - m.y1[f]) / slope
		a = maxf(a, minf(top, bottom))
		b = minf(b, maxf(top, bottom))
	if a >= b:
		return [part]
	return [Vector2(part.x, a), Vector2(b, part.y)]


## Flyers can reach any air point, so sample the off-screen strips directly without footholds or NavGraph.
func _pick_air_spawn(world: RunWorld, side: int) -> Vector3:
	var inner := screen_rect(world)
	var distance := float(params.min_player_dist)
	var far := float(params.recycle_dist) * 0.9
	var fallback := Vector3(0, 0, -2)
	for ring in 3:
		var band := float(params.band) * (1.0 if ring == 0 else 3.0)
		var outer := inner.grow(band).intersection(world.bounds) if ring < 2 else world.bounds
		if not outer.has_area():
			continue
		var left := clampf(inner.position.x, outer.position.x, outer.end.x)
		var right := clampf(inner.end.x, outer.position.x, outer.end.x)
		var top := clampf(inner.position.y, outer.position.y, outer.end.y)
		var bottom := clampf(inner.end.y, outer.position.y, outer.end.y)
		var strips := [Rect2(outer.position, Vector2(left - outer.position.x, outer.size.y)),
			Rect2(Vector2(right, outer.position.y), Vector2(outer.end.x - right, outer.size.y)),
			Rect2(Vector2(left, outer.position.y), Vector2(right - left, top - outer.position.y)),
			Rect2(Vector2(left, bottom), Vector2(right - left, outer.end.y - bottom))]
		var area := 0.0
		for strip: Rect2 in strips:
			area += strip.get_area()
		if area <= 0.0:
			continue
		for attempt in int(params.attempts):
			var choice := world.spawn_rng.randf() * area
			for strip: Rect2 in strips:
				choice -= strip.get_area()
				if choice >= 0.0 or not strip.has_area():
					continue
				var pos := Vector2(world.spawn_rng.randf_range(strip.position.x, strip.end.x),
					world.spawn_rng.randf_range(strip.position.y, strip.end.y))
				var d := pos.distance_to(world.player.pos)
				if inner.has_point(pos) or not world.bounds.has_point(pos) or d < distance or (ring == 2 and d > far):
					break
				var p := Vector3(pos.x, pos.y, -1)
				if side == 0 or (pos.x - world.player.pos.x) * side > 0.0:
					return p
				fallback = p
				break
		if fallback.z == -1:
			return fallback
	return fallback


## True when a wall standing across a platform stops a mob from x on platform q somewhere along its way to the player
## (FootholdMap.walk_blocked): on each platform of the way, between where it lands (or starts) and the takeoff of its
## next edge, and on the player's platform between its landing and the player's x (at most WALLED_HOPS edges are
## followed).
func _walled(world: RunWorld, nav: NavGraph, q: int, x: float, target_p: int) -> bool:
	if q == target_p:
		return world.fhm.walk_blocked(q, x, world.player.pos.x)
	var e := nav.best_edge(q, x)
	if e < 0:
		return false
	if world.fhm.walk_blocked(q, x, nav.take[e]):
		return true
	return _walled_after(world, nav, e, target_p)


## _walled() for the way on from edge e's landing (WALLED_HOPS - 1 more edges). It depends only on e while the
## player (its position, platform, and so the cost field) stays put, so it is kept until the tick, the player's position
## or its platform changes (a burst of relocations samples the same edges many times).
func _walled_after(world: RunWorld, nav: NavGraph, e0: int, target_p: int) -> bool:
	var at_key := Vector4(world.time, world.player.pos.x, world.player.pos.y, target_p)
	if at_key != _walled_key:
		_walled_key = at_key
		_walled_memo.clear()
	var key := Vector2i(0 if nav == world.nav else 1, e0)
	if _walled_memo.has(key):
		return _walled_memo[key]
	var out := false
	var at := nav.take[e0] if nav.e_lo[e0] < nav.e_hi[e0] else nav.e_x_to[e0]  # a straight-up hop lands where it took off
	var p := nav.e_to[e0]
	for hop in WALLED_HOPS - 1:
		var e := nav.best_edge(p, at) if p != target_p else -1
		if e < 0:
			out = world.fhm.walk_blocked(p, at, world.player.pos.x) if p == target_p else false
			break
		if world.fhm.walk_blocked(p, at, nav.take[e]):
			out = true
			break
		at = nav.take[e] if nav.e_lo[e] < nav.e_hi[e] else nav.e_x_to[e]
		p = nav.e_to[e]
	_walled_memo[key] = out
	return out


func _spawn_one(world: RunWorld, t: float, elite: bool) -> bool:
	var k := pick_kind(t, world.spawn_rng)
	if k < 0:
		return false
	var p := pick_spawn(world, k)
	if p.z < -1:
		return false
	var hp_mult := value_at("hp", t)
	if elite:
		hp_mult *= float(stage.get("elites", {}).get("hp_mult", 8.0))
	var i := world.spawn_mob(k, Vector2(p.x, p.y), int(p.z), hp_mult, elite)
	if i < 0:
		return false
	_fit(world.swarm.capacity())
	_far_t[i] = 0.0
	_stall_t[i] = 0.0
	_best_len[i] = INF
	spawned += 1
	return true


## The rect ordinary ring placements stay out of: the view grown by `margin`, and by
## `trail_margin` more on the side the player moves away from (see the class doc).
func screen_rect(world: RunWorld) -> Rect2:
	var r := world.view.grow(float(params.margin))
	var tr := float(params.get("trail_margin", 0.0))
	var vx := world.player.vel.x
	if tr > 0.0 and absf(vx) > 1.0:
		r = r.grow_side(SIDE_LEFT if vx > 0.0 else SIDE_RIGHT, tr)
	return r


## The floor pieces of ring 0 (band), 1 (3 x band) or 2 (the whole bounds) for the current time and view: the floor
## parts inside the ring's rect minus screen_rect().
func _ring(world: RunWorld, ring: int) -> Array:
	var vx := world.player.vel.x
	var key := Vector4(world.time, world.view.position.x, world.view.position.y,
		0.0 if absf(vx) <= 1.0 else signf(vx))
	if _ring_key[ring] == key and not _rings[ring].is_empty():
		return _rings[ring]
	_ring_key[ring] = key
	var m := world.fhm
	if _floors.is_empty():
		for f in m.count():
			if m.is_floor(f):
				_floors.append(f)
	var fhs := PackedInt32Array()
	var aa := PackedFloat32Array()
	var bb := PackedFloat32Array()
	var cum := PackedFloat32Array()
	var band := float(params.band) * (1.0 if ring == 0 else 3.0)
	var outer := world.bounds if ring == 2 else world.view.grow(band).intersection(world.bounds)
	if ring == 0 and float(params.get("band_y", -1.0)) >= 0.0:
		var by := float(params.band_y)
		outer = world.view.grow_individual(band, by, band, by).intersection(world.bounds)
	var inner := screen_rect(world)
	var total := 0.0
	for f in _floors:
		var a := maxf(m.x1[f], outer.position.x)
		var b := minf(m.x2[f], outer.end.x)
		if b <= a:
			continue
		var ya := m.y_at(f, a)
		var yb := m.y_at(f, b)
		if maxf(ya, yb) < outer.position.y or minf(ya, yb) > outer.end.y:
			continue
		var parts: Array = []
		if maxf(ya, yb) >= inner.position.y and minf(ya, yb) <= inner.end.y:
			# Overlaps the view's height: keep only the parts left and right of it.
			if a < inner.position.x:
				parts.append(Vector2(a, minf(b, inner.position.x)))
			if b > inner.end.x:
				parts.append(Vector2(maxf(a, inner.end.x), b))
		else:
			parts.append(Vector2(a, b))
		for part: Vector2 in parts:
			if part.y - part.x < 1.0:
				continue
			total += part.y - part.x
			fhs.append(f)
			aa.append(part.x)
			bb.append(part.y)
			cum.append(total)
	_rings[ring] = [fhs, aa, bb, cum]
	return _rings[ring]


static func _sample(m: FootholdMap, pieces: Array, rng: RandomNumberGenerator) -> Vector3:
	var fhs: PackedInt32Array = pieces[0]
	var aa: PackedFloat32Array = pieces[1]
	var bb: PackedFloat32Array = pieces[2]
	var cum: PackedFloat32Array = pieces[3]
	var r := rng.randf() * cum[cum.size() - 1]
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if cum[mid] > r:
			hi = mid
		else:
			lo = mid + 1
	var xx := rng.randf_range(aa[lo], bb[lo])
	return Vector3(xx, m.y_at(fhs[lo], xx), fhs[lo])


## Relocation (see the class doc): far, unreachable and stalled off-screen mobs move to a fresh point ahead.
func _recycle(dt: float, world: RunWorld) -> void:
	var s := world.swarm
	_fit(s.capacity())
	var lim := float(params.recycle_dist)
	var lim2 := lim * lim
	var wait := float(params.recycle_time)
	var stall := float(params.get("stall_time", 0.0))
	var gain := float(params.get("stall_progress", 1.0))
	var p := world.player.pos
	var target_p := world.player_platform()
	var off := world.view.grow(float(params.band))
	# A mob is only moved from outside the view grown by margin + trail_margin on both sides: the camera can lag on
	# either side (it is still catching up after the player turns).
	var vis := world.view.grow(float(params.margin) + float(params.get("trail_margin", 0.0)))
	var side := 0
	if absf(world.player.vel.x) > 1.0:
		side = 1 if world.player.vel.x > 0.0 else -1
	for i in s.capacity():
		if s.active[i] == 0 or world.mob_elite[i] != 0 or world.mob_boss[i] >= 0:
			_far_t[i] = 0.0
			_stall_t[i] = 0.0
			_best_len[i] = INF
			continue
		var pos := Vector2(s.x[i], s.y[i])
		var move := false
		if stall > 0.0:
			var rl := s.route_len[i]
			# Coming closer means a shorter way left *and* the mob itself having moved since it last came closer: the
			# player walking up to a mob stopped at a wall shortens its way without the mob moving. On screen any
			# movement counts, and a mob standing still there (at a wall, or at the player) keeps counting; it is
			# only ever moved once off screen.
			var moved := pos.distance_squared_to(_anchor[i]) >= gain * gain
			if (_best_len[i] == INF and rl < INF) or (moved and (rl < _best_len[i] - gain or vis.has_point(pos))):
				_best_len[i] = rl
				_anchor[i] = pos
				_stall_t[i] = 0.0
			elif vis.has_point(pos):
				_stall_t[i] += dt
			else:
				_stall_t[i] += dt
				move = _stall_t[i] >= stall
		var dx := pos.x - p.x
		var dy := pos.y - p.y
		var gone := dx * dx + dy * dy > lim2
		if not gone and target_p >= 0 and s.fh[i] >= 0 and not off.has_point(pos):
			gone = s.route_len[i] == INF  # no way to the player from its platform (MobSwarm's travel-cost field)
		if gone:
			_far_t[i] += dt
			move = move or _far_t[i] >= wait
		else:
			_far_t[i] = 0.0
		if not move:
			continue
		var at := pick_spawn(world, s.kind[i], side)
		var j := world.relocate_mob(i, Vector2(at.x, at.y), int(at.z)) if at.z >= -1 else -1
		if j < 0:
			s.despawn(i)
			recycled += 1
			j = i
		else:
			relocated += 1
		_fit(s.capacity())
		_far_t[j] = 0.0
		_stall_t[j] = 0.0
		_best_len[j] = INF


func _fit(n: int) -> void:
	if _far_t.size() >= n:
		return
	var old := _far_t.size()
	_far_t.resize(n)
	_stall_t.resize(n)
	_best_len.resize(n)
	_anchor.resize(n)
	for i in range(old, n):
		_far_t[i] = 0.0
		_stall_t[i] = 0.0
		_best_len[i] = INF
