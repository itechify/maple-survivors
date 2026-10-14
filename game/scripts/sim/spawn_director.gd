class_name SpawnDirector
extends RefCounted
## Stage pacing and spawn positions (docs/GAME_DESIGN.md sections 4, 4.1; `data/survivor/stages.json`).
##
## Pacing: `rate` (mobs/s), `max_alive`, `hp`, `speed` and `damage` interpolate linearly between the stage keyframes;
## the pool (mob id -> weight) is the one of the last keyframe at or before t. While alive < max_alive(t) the director
## spawns rate(t) mobs per second (a fractional accumulator, not banked while capped), each of a kind drawn by weight.
## Every `bursts.every` s a ring of count_min..count_max mobs (growing linearly over the stage) spawns around the view
## (allowed past max_alive up to the stage's hard_cap) and a `burst` event is emitted; every `elites.every` s one mob
## of the pool spawns as an elite (hp_mult x HP; RunWorld pays exp_mult x EXP).
##
## Positions (tier C): a random point on a floor outside the view grown by `margin` px, inside the map bounds and at
## least `min_player_dist` from the player, searched in three rings: within `band` px of the view, within 3 x band, and
## anywhere within 0.9 x recycle_dist of the player. A point whose platform can reach the player's platform (NavGraph
## of that mob's movement class) is preferred: each ring gets `attempts` samples looking for one, and only when no ring
## has one does the first valid unreachable point of the two inner rings serve. Recycling (MobSwarm.despawn, silent,
## elites excepted): a live mob farther than `recycle_dist` from the player, or one standing on a platform that cannot
## reach the player's and outside the view grown by `band`, for `recycle_time` s in a row (GAME_DESIGN 4: a mob that
## cannot reach the player is recycled once far off-screen).

const DEFAULT_SPAWN := {
	"margin": 48.0,  # tier C: GAME_DESIGN 4, spawn outside the view + 48 px
	"band": 320.0,  # tier C: ours, spawn preferably at most this far outside the view
	"min_player_dist": 200.0,  # tier C: GAME_DESIGN 4
	"attempts": 12,  # tier C: ours, samples per ring
	"recycle_dist": 1300.0,  # tier C: ours
	"recycle_time": 3.0,  # tier C: ours
}

var stage: Dictionary
var duration := 900.0
var hard_cap := 400
## Parsed keyframes: {t, rate, max_alive, hp, speed, damage, kinds: PackedInt32Array, weights: PackedFloat32Array}.
var keyframes: Array = []
var params: Dictionary
var spawned := 0
var bursts := 0
var elites := 0
var recycled := 0
var next_burst := INF
var next_elite := INF

var _acc := 0.0
var _far_t := PackedFloat32Array()
var _floors := PackedInt32Array()
## Floor pieces per ring: [fh: PackedInt32Array, a: PackedFloat32Array, b: PackedFloat32Array, cum: PackedFloat32Array].
var _rings: Array = [[], [], []]
## (time, view position) each ring was built for; rebuilt when it changes.
var _ring_key: Array = [Vector3(-1, 0, 0), Vector3(-1, 0, 0), Vector3(-1, 0, 0)]


## Builds the director for a stages.json stage. `kind_index` maps mob id -> RunWorld.mob_kinds index; pool entries
## without a kind are dropped. `spawn_params` overrides DEFAULT_SPAWN (balance.json `spawn`).
static func create(p_stage: Dictionary, kind_index: Dictionary, spawn_params: Dictionary = {}) -> SpawnDirector:
	var d := SpawnDirector.new()
	d.stage = p_stage
	d.duration = float(p_stage.get("duration", 900.0))
	d.hard_cap = int(p_stage.get("hard_cap", 400))
	d.params = DEFAULT_SPAWN.duplicate()
	for k: String in spawn_params:
		if d.params.has(k):
			d.params[k] = spawn_params[k]
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
			"speed": float(kf.get("speed", 1.0)), "damage": float(kf.get("damage", 1.0)),
			"kinds": kinds, "weights": weights,
		})
	d.keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	var bu: Dictionary = p_stage.get("bursts", {})
	if not bu.is_empty() and float(bu.get("every", 0.0)) > 0.0:
		d.next_burst = float(bu.get("first", bu.every))
	var el: Dictionary = p_stage.get("elites", {})
	if not el.is_empty() and float(el.get("every", 0.0)) > 0.0:
		d.next_elite = float(el.get("first", el.every))
	return d


## Linearly interpolated keyframe value `field` ("rate", "max_alive", "hp", "speed", "damage") at time t.
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
	return float(keyframes[keyframes.size() - 1][field])


## Spawns per second at t.
func rate_at(t: float) -> float:
	return value_at("rate", t)


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


## Spawn count of the burst at t.
func burst_count_at(t: float) -> int:
	var bu: Dictionary = stage.get("bursts", {})
	var f := clampf(t / duration, 0.0, 1.0) if duration > 0.0 else 0.0
	return roundi(lerpf(float(bu.get("count_min", 20)), float(bu.get("count_max", 40)), f))


## One director tick: recycling, steady spawns, bursts, elites (RunWorld.spawn_mob does the spawning and events).
func step(dt: float, world: RunWorld) -> void:
	var t := world.time
	var swarm := world.swarm
	_recycle(dt, world)
	var cap := max_alive_at(t)
	var alive := swarm.alive_count()
	_acc += rate_at(t) * dt
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
		var n := mini(burst_count_at(t), maxi(0, hard_cap - swarm.alive_count()))
		bursts += 1
		world.emit("burst", {"count": n})
		for k in n:
			_spawn_one(world, t, false)
	if t >= next_elite:
		next_elite += float(stage.elites.every)
		if swarm.alive_count() < hard_cap and _spawn_one(world, t, true):
			elites += 1


## A spawn point for kind `k`: Vector3(x, y, foothold), or Vector3(0, 0, -1) when there is none (see the class comment).
func pick_spawn(world: RunWorld, k: int) -> Vector3:
	var rng := world.spawn_rng
	var mk: MobKind = world.mob_kinds[k]
	var nav := world.nav_jump if mk.can_jump else world.nav
	var target_p := world.player_platform()
	var inner := world.view.grow(float(params.margin))
	var min_d2 := float(params.min_player_dist) * float(params.min_player_dist)
	var far2 := float(params.recycle_dist) * float(params.recycle_dist) * 0.81
	var tries := int(params.attempts)
	var fallback := Vector3(0, 0, -1)
	for ring in 3:
		var pieces := _ring(world, ring)
		var fhs: PackedInt32Array = pieces[0]
		if fhs.is_empty():
			continue
		for attempt in tries:
			var p := _sample(world.fhm, pieces, rng)
			var pos := Vector2(p.x, p.y)
			if inner.has_point(pos) or not world.bounds.has_point(pos):
				continue
			var d2 := pos.distance_squared_to(world.player.pos)
			if d2 < min_d2 or (ring == 2 and d2 > far2):
				continue
			if nav == null or target_p < 0 or nav.reachable(world.fhm.platform_of(int(p.z)), target_p):
				return p
			if fallback.z < 0 and ring < 2:
				fallback = p
	return fallback


func _spawn_one(world: RunWorld, t: float, elite: bool) -> bool:
	var k := pick_kind(t, world.spawn_rng)
	if k < 0:
		return false
	var p := pick_spawn(world, k)
	if p.z < 0:
		return false
	var hp_mult := value_at("hp", t)
	if elite:
		hp_mult *= float(stage.get("elites", {}).get("hp_mult", 8.0))
	var i := world.spawn_mob(k, Vector2(p.x, p.y), int(p.z), hp_mult, elite)
	if i < 0:
		return false
	if _far_t.size() < world.swarm.capacity():
		_far_t.resize(world.swarm.capacity())
	_far_t[i] = 0.0
	spawned += 1
	return true


## The floor pieces of ring 0 (band), 1 (3 x band) or 2 (the whole bounds) for the current time and view: the floor
## parts inside the ring's rect minus the view grown by margin.
func _ring(world: RunWorld, ring: int) -> Array:
	var key := Vector3(world.time, world.view.position.x, world.view.position.y)
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
	var inner := world.view.grow(float(params.margin))
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


func _recycle(dt: float, world: RunWorld) -> void:
	var s := world.swarm
	if _far_t.size() < s.capacity():
		_far_t.resize(s.capacity())
	var lim := float(params.recycle_dist)
	var lim2 := lim * lim
	var wait := float(params.recycle_time)
	var p := world.player.pos
	var target_p := world.player_platform()
	var off := world.view.grow(float(params.band))
	for i in s.capacity():
		if s.active[i] == 0 or world.mob_elite[i] != 0:
			_far_t[i] = 0.0
			continue
		var dx := s.x[i] - p.x
		var dy := s.y[i] - p.y
		var gone := dx * dx + dy * dy > lim2
		if not gone and target_p >= 0 and s.fh[i] >= 0 and not off.has_point(Vector2(s.x[i], s.y[i])):
			var mk: MobKind = world.mob_kinds[s.kind[i]]
			var nav := world.nav_jump if mk.can_jump else world.nav
			gone = not nav.reachable(s.platform[i], target_p)
		if not gone:
			_far_t[i] = 0.0
			continue
		_far_t[i] += dt
		if _far_t[i] >= wait:
			_far_t[i] = 0.0
			s.despawn(i)
			recycled += 1
