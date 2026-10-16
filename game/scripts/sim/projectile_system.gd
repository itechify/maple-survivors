class_name ProjectileSystem
extends RefCounted
## Shots in flight as pooled struct-of-arrays (docs/ARCHITECTURE.md 4.4, docs/GAME_DESIGN.md section 7).
##
## A shot flies straight at constant velocity (aimed by SkillRunner at the target's position at cast time), ignores
## terrain, and expires after `range` px of travel or outside `bounds` (grown by 200 px). Each tick its swept segment
## is tested against the body boxes (MobKind.hitbox_at grown by the shot radius) of live mobs near it, found through
## the SpatialHash (mob feet points; the query is padded by the largest body box). Mobs are hit in the order the
## segment enters them; a shot hits each mob at most once (per-shot already-hit list) and dies after 1 + pierce hits.
## The list stores logical identities, so relocation retains exclusion and a fresh occupant of a reused slot does not.
## Each hit rolls its damage (`dmg_min`..`dmg_max`, mob MDD when `magic`, crit) with `rng`, applies it through
## MobSwarm.apply_hit (pushed along the shot's direction), appends a `mob_hit` event, and records killed mob slots in
## `kills` for RunWorld (mob_died, EXP drop). `paths` is RunWorld.visual_paths (the `visual` and hit-visual indices
## point into it); `skill_names` maps the per-shot `skill` index to the survivor skill key.
##
## spawn(spec) keys: x, y, vx, vy (px/s), range, radius, visual (index into paths), hit_visual (index or -1),
## rotate (bool), dmg_min, dmg_max, magic (bool), element (canonical elemAttr), crit (chance), crit_mult, pierce,
## skill (survivor key), level (canonical level at cast).

## Most mobs one shot can hit (1 + pierce is clamped to this).
const MAX_HITS := 16
## Shots die this far outside `bounds`.
const BOUNDS_MARGIN := 200.0

var active := PackedByteArray()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
## Index into `paths` of the looping flight animation.
var visual := PackedInt32Array()
## 1 when the sprite turns to the velocity direction.
var rotate := PackedByteArray()
var range_left := PackedFloat32Array()
var radius := PackedFloat32Array()
var dmg_min := PackedFloat32Array()
var dmg_max := PackedFloat32Array()
var magic := PackedByteArray()
## Canonical attacking skill elemAttr; resistance is resolved against each target at impact.
var element := PackedStringArray()
var crit := PackedFloat32Array()
var crit_mult := PackedFloat32Array()
## Hits left before the shot dies (1 + pierce at spawn).
var hits_left := PackedInt32Array()
var hit_count := PackedInt32Array()
## MAX_HITS logical mob identities per shot; slot reuse must not inherit a previous occupant's hit exclusion.
var hit_list := PackedInt64Array()
var hit_visual := PackedInt32Array()
var skill := PackedInt32Array()
## Canonical skill level at launch; later rank changes do not alter on-hit status parameters.
var level := PackedInt32Array()

## RunWorld.visual_paths (shared).
var paths: Array = []
## Survivor skill keys referenced by `skill`.
var skill_names := PackedStringArray()
var rng: RandomNumberGenerator
var bounds := Rect2()
var magic_defense_k := CombatMath.MAGIC_DEFENSE_K
## Mob slots killed during the last step() (cleared at the start of each step).
var kills := PackedInt32Array()
## Total damage dealt by every hit so far.
var dealt := 0

var _free := PackedInt32Array()
var _hi := 0
var _count := 0
var _buf := PackedInt32Array()
var _cand := PackedInt32Array()
var _cand_t := PackedFloat32Array()


func _init(capacity: int = 64, p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	_buf.resize(64)
	_grow(maxi(1, capacity))


## Number of slots (iterate and skip inactive).
func capacity() -> int:
	return active.size()


## Number of shots in flight.
func active_count() -> int:
	return _count


## Adds a shot (see the class comment for the spec keys); returns its slot.
func spawn(spec: Dictionary) -> int:
	if _free.is_empty():
		_grow(capacity() * 2)
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	active[i] = 1
	x[i] = float(spec.get("x", 0.0))
	y[i] = float(spec.get("y", 0.0))
	vx[i] = float(spec.get("vx", 0.0))
	vy[i] = float(spec.get("vy", 0.0))
	visual[i] = int(spec.get("visual", -1))
	rotate[i] = 1 if bool(spec.get("rotate", false)) else 0
	range_left[i] = float(spec.get("range", 400.0))
	radius[i] = float(spec.get("radius", 10.0))
	dmg_min[i] = float(spec.get("dmg_min", 1.0))
	dmg_max[i] = float(spec.get("dmg_max", spec.get("dmg_min", 1.0)))
	magic[i] = 1 if bool(spec.get("magic", false)) else 0
	element[i] = String(spec.get("element", ""))
	crit[i] = float(spec.get("crit", 0.0))
	crit_mult[i] = float(spec.get("crit_mult", 1.5))
	hits_left[i] = clampi(1 + int(spec.get("pierce", 0)), 1, MAX_HITS)
	hit_count[i] = 0
	hit_visual[i] = int(spec.get("hit_visual", -1))
	var key := String(spec.get("skill", ""))
	var si := skill_names.find(key)
	if si < 0:
		si = skill_names.size()
		skill_names.append(key)
	skill[i] = si
	level[i] = int(spec.get("level", 0))
	_count += 1
	_hi = maxi(_hi, i + 1)
	return i


## Removes shot i.
func despawn(i: int) -> void:
	if i < 0 or i >= capacity() or active[i] == 0:
		return
	active[i] = 0
	_count -= 1
	_free.append(i)
	while _hi > 0 and active[_hi - 1] == 0:
		_hi -= 1


## Moves every shot by dt, resolves hits against `swarm` through `grid` (rebuilt this tick from swarm.x/y/active),
## appends mob_hit events and fills `kills`. Optional defense/immunity arrays describe this impact tick.
## on_hit(slot, hit) runs once per damaging contact before apply_hit, with skill/level/magic/damage/element.
func step(dt: float, swarm: MobSwarm, grid: SpatialHash, events: Array, live_mdd: PackedFloat32Array = PackedFloat32Array(),
		physical_allowed: PackedByteArray = PackedByteArray(), on_hit: Callable = Callable()) -> void:
	kills.resize(0)
	var kinds: Array = swarm.kinds
	var pad := max_body_extent(kinds)
	var check_bounds := bounds.has_area()
	var lim := bounds.grow(BOUNDS_MARGIN)
	for i in _hi:
		if active[i] == 0:
			continue
		var ox := x[i]
		var oy := y[i]
		var nx := ox + vx[i] * dt
		var ny := oy + vy[i] * dt
		var travel := Vector2(nx - ox, ny - oy).length()
		var rad := radius[i]
		var mid := Vector2((ox + nx) * 0.5, (oy + ny) * 0.5)
		var n := grid.query_radius(mid, travel * 0.5 + rad + pad, _buf)
		# Candidates in the order the swept segment enters their (grown) body box.
		_cand.resize(0)
		_cand_t.resize(0)
		var base := i * MAX_HITS
		for c in n:
			var m := _buf[c]
			if swarm.active[m] == 0 or _already_hit(base, hit_count[i], swarm.identity[m]):
				continue
			var mk: MobKind = kinds[swarm.kind[m]]
			var box := mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m]).grow(rad)
			var t := segment_enter(ox, oy, nx, ny, box)
			if t < 0.0:
				continue
			var at := _cand_t.size()
			while at > 0 and _cand_t[at - 1] > t:
				at -= 1
			_cand.insert(at, m)
			_cand_t.insert(at, t)
		for c in _cand.size():
			var m := _cand[c]
			if swarm.active[m] == 0:
				continue
			_hit(i, m, swarm, events, live_mdd, physical_allowed, on_hit)
			if hits_left[i] <= 0:
				break
		if hits_left[i] <= 0:
			despawn(i)
			continue
		x[i] = nx
		y[i] = ny
		range_left[i] -= travel
		if range_left[i] <= 0.0 or (check_bounds and not lim.has_point(Vector2(nx, ny))):
			despawn(i)


## Entry parameter t in [0, 1] of the segment (ax, ay) -> (bx, by) into rect r (0 when it starts inside), or -1 when
## it misses (slab test).
static func segment_enter(ax: float, ay: float, bx: float, by: float, r: Rect2) -> float:
	var t0 := 0.0
	var t1 := 1.0
	var dx := bx - ax
	var dy := by - ay
	var lo := r.position
	var hi := r.end
	if absf(dx) < 1e-9:
		if ax < lo.x or ax > hi.x:
			return -1.0
	else:
		var ta := (lo.x - ax) / dx
		var tb := (hi.x - ax) / dx
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if absf(dy) < 1e-9:
		if ay < lo.y or ay > hi.y:
			return -1.0
	else:
		var ta := (lo.y - ay) / dy
		var tb := (hi.y - ay) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return t0 if t0 <= t1 else -1.0


## Rolls one hit of shot i's damage spec on mob m: Vector2i(damage, crit 0/1). Shared with instant skills through
## roll_damage().
static func roll_damage(lo: float, hi: float, is_magic: bool, mdd: float, k: float, crit_chance: float, cmult: float,
		r: RandomNumberGenerator, element_mult: float = 1.0) -> Vector2i:
	if element_mult <= 0.0:
		return Vector2i.ZERO
	var dmg := r.randf_range(lo, hi) if hi > lo else lo
	if is_magic:
		dmg = CombatMath.apply_defense(dmg, mdd, k)
	var is_crit := CombatMath.roll_crit(crit_chance, r)
	if is_crit:
		dmg *= cmult
	# tier A: element weakness/resistance is 1.5/0.5 (Cold Beam String.wz); round the final hit once.
	return Vector2i(maxi(1, roundi(dmg * element_mult)), 1 if is_crit else 0)


func _hit(i: int, m: int, swarm: MobSwarm, events: Array, live_mdd: PackedFloat32Array, physical_allowed: PackedByteArray,
		on_hit: Callable) -> void:
	if hit_count[i] < MAX_HITS:
		hit_list[i * MAX_HITS + hit_count[i]] = swarm.identity[m]
		hit_count[i] += 1
	hits_left[i] -= 1
	# tier C: immune contact consumes a shell/pierce hit, without a damage roll or mob_hit event.
	if magic[i] == 0 and m < physical_allowed.size() and physical_allowed[m] == 0:
		return
	var mk: MobKind = swarm.kinds[swarm.kind[m]]
	var defense := float(live_mdd[m]) if m < live_mdd.size() else float(mk.mdd)
	var roll := roll_damage(dmg_min[i], dmg_max[i], magic[i] != 0, defense, magic_defense_k, crit[i],
		crit_mult[i], rng, mk.element_multiplier(element[i]))
	var dir := 1 if vx[i] >= 0.0 else -1
	var head := Vector2(swarm.x[m], swarm.y[m] + mk.hitbox.position.y)
	var hv := hit_visual[i]
	events.append({
		"type": "mob_hit", "mob": m, "mob_id": mk.id, "damage": roll.x, "crit": roll.y != 0, "pos": head,
		"hit_visual": String(paths[hv]) if hv >= 0 and hv < paths.size() else "",
		"skill": skill_names[skill[i]],
	})
	dealt += roll.x
	if roll.x > 0 and on_hit.is_valid():
		on_hit.call(m, {"skill": skill_names[skill[i]], "level": level[i], "magic": magic[i] != 0,
			"damage": roll.x, "element": element[i]})
	if swarm.apply_hit(m, roll.x, dir):
		kills.append(m)


func _already_hit(base: int, n: int, identity: int) -> bool:
	for k in n:
		if hit_list[base + k] == identity:
			return true
	return false


## Largest distance from a mob's feet to a corner of its body box, over every kind (the hash query padding).
static func max_body_extent(kinds: Array) -> float:
	var e := 0.0
	for mk: MobKind in kinds:
		var h := mk.hitbox
		e = maxf(e, maxf(Vector2(h.position.x, h.position.y).length(), Vector2(h.end.x, h.position.y).length()))
		e = maxf(e, maxf(Vector2(h.position.x, h.end.y).length(), Vector2(h.end.x, h.end.y).length()))
	return e + 1.0


func _grow(n: int) -> void:
	var old := capacity()
	if n <= old:
		return
	for arr: Variant in [active, rotate, magic]:
		arr.resize(n)
	for arr: Variant in [x, y, vx, vy, range_left, radius, dmg_min, dmg_max, crit, crit_mult]:
		arr.resize(n)
	for arr: Variant in [visual, hits_left, hit_count, hit_visual, skill, level]:
		arr.resize(n)
	hit_list.resize(n * MAX_HITS)
	element.resize(n)
	for i in range(n - 1, old - 1, -1):
		active[i] = 0
		_free.append(i)
