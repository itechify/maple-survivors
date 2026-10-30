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
## Each hit resolves live defence (PDD physical, MDD magic, none fixed), rolls damage and crit with `rng`, applies it through
## MobSwarm.apply_hit (pushed along the shot's direction), appends a `mob_hit` event, and records killed mob slots in
## `kills` for RunWorld (mob_died, EXP drop). `paths` is RunWorld.visual_paths (the `visual` and hit-visual indices
## point into it); `skill_names` maps the per-shot `skill` index to the survivor skill key.
##
## spawn(spec) keys: x, y, vx, vy (px/s), range, radius, visual (index into paths), hit_visual (index or -1),
## rotate (bool), dmg_min, dmg_max, damage_type (fixed/magic/physical; defaults from legacy magic bool), damage_pct
## (skill% / 100, default 1), element, crit, crit_mult, crit_damage_bonus (skill-% points), pierce,
## skill (survivor key), level (canonical skill level at cast). Defence is live at impact.
## Optional pierce_falloff is linear damage lost per previous contact (floor set by survivor combat data). impact_blast is a
## cast-time {box: Rect2, count: int, visual: String} that explodes at the first contact instead of piercing.

## Most mobs one shot can hit (1 + pierce is clamped to this).
const MAX_HITS := 16
## Shots die this far outside `bounds`.
const BOUNDS_MARGIN := 200.0

var active := PackedByteArray()
## Draw identity: increments on every spawn, including reuse between presentation frames.
var generation := PackedInt64Array()
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
## Per shot CombatMath.DAMAGE_FIXED / DAMAGE_MAGIC / DAMAGE_PHYSICAL (CombatMath.DAMAGE_TYPE_NAMES gives the name).
var damage_kind := PackedByteArray()
var damage_pct := PackedFloat64Array()
var crit_damage_bonus := PackedFloat64Array()
## Canonical attacking skill elemAttr; resistance is resolved against each target at impact.
var element := PackedStringArray()
var crit := PackedFloat32Array()
var crit_mult := PackedFloat32Array()
## Hits left before the shot dies (1 + pierce at spawn).
var hits_left := PackedInt32Array()
var hit_count := PackedInt32Array()
## Optional linear damage lost per earlier contact; 0 keeps the shipped full-damage pierce behaviour.
var pierce_falloff := PackedFloat64Array()
## Cast-time blast state; a zero target cap marks an ordinary shot. Rect2 components retain Vector2 precision.
var blast_position := PackedVector2Array()
var blast_size := PackedVector2Array()
var blast_count := PackedInt32Array()
var blast_visual := PackedStringArray()
## MAX_HITS logical mob identities per shot; slot reuse must not inherit a previous occupant's hit exclusion.
var hit_list := PackedInt64Array()
var hit_visual := PackedInt32Array()
var skill := PackedInt32Array()
## Canonical skill level at launch; later rank changes do not alter on-hit status parameters.
var level := PackedInt32Array()
## Shared cast receipts are cold metadata, never copied between shots of the same cast.
var meter_receipts: Array[Dictionary] = []
## Whole damage per second of the burn a hit of this shot applies (0: none), snapshotted at launch from the cast (B5).
var burn_pulse := PackedInt32Array()
## 1 for a shot an echo clone threw (EchoCast): its hits carry `echo` so they heal and earn nothing.
var echo := PackedByteArray()
const NO_RECEIPT := {}

## RunWorld.visual_paths (shared).
var paths: Array = []
## Survivor skill keys referenced by `skill`.
var skill_names := PackedStringArray()
var rng: RandomNumberGenerator
var bounds := Rect2()
var magic_defense_k := CombatMath.MAGIC_DEFENSE_K
## tier C: minimum per-contact multiplier, configured from balance.combat.pierce_floor by RunWorld.
var pierce_floor := 0.0
## Mob slots killed during the last step() (cleared at the start of each step).
var kills := PackedInt32Array()
var _halted := false
## Total damage dealt by every hit so far.
var dealt := 0

var _free := PackedInt32Array()
var _hi := 0
var _count := 0
var _buf := PackedInt32Array()
var _cand := PackedInt32Array()
var _cand_t := PackedFloat32Array()
## High-water scratch storage; only the nearest blast_count - 1 targets are retained, sorted by body distance/slot.
var _blast_targets := PackedInt32Array()
var _blast_distance := PackedFloat64Array()


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
	generation[i] += 1
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
	damage_kind[i] = CombatMath.damage_type_code(
		CombatMath.damage_type_of(String(spec.get("damage_type", "")), bool(spec.get("magic", false))))
	damage_pct[i] = float(spec.get("damage_pct", 1.0))
	crit_damage_bonus[i] = float(spec.get("crit_damage_bonus", 0.0))
	element[i] = String(spec.get("element", ""))
	crit[i] = float(spec.get("crit", 0.0))
	crit_mult[i] = float(spec.get("crit_mult", 1.5))
	hits_left[i] = clampi(1 + int(spec.get("pierce", 0)), 1, MAX_HITS)
	hit_count[i] = 0
	meter_receipts[i] = spec.get("meter_receipt", NO_RECEIPT)
	burn_pulse[i] = int(spec.get("burn_pulse", 0))
	echo[i] = 1 if bool(spec.get("echo", false)) else 0
	pierce_falloff[i] = maxf(0.0, float(spec.get("pierce_falloff", 0.0)))
	blast_count[i] = 0
	blast_visual[i] = ""
	if spec.has("impact_blast"):
		var blast: Dictionary = spec.impact_blast
		if not blast.is_empty():
			var box: Rect2 = blast.box
			blast_position[i] = box.position
			blast_size[i] = box.size
			blast_count[i] = maxi(1, int(blast.count))
			blast_visual[i] = String(blast.visual)
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
## Optional on_kill(slot) resolves a kill immediately; returning true stops all remaining damage this step.
func step(dt: float, swarm: MobSwarm, grid: SpatialHash, events: Array, live_mdd: PackedFloat32Array = PackedFloat32Array(),
		physical_allowed: PackedByteArray = PackedByteArray(), on_hit: Callable = Callable(),
		live_pdd: PackedFloat32Array = PackedFloat32Array(), on_kill: Callable = Callable()) -> void:
	kills.resize(0)
	_halted = false
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
			if blast_count[i] > 0:
				_blast(i, m, swarm, grid, events, live_mdd, physical_allowed, on_hit, live_pdd, on_kill)
			else:
				_hit(i, m, swarm, events, live_mdd, physical_allowed, on_hit, live_pdd, on_kill)
			if _halted:
				return
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


## Shared instant/projectile hit: physical defence on bounds, roll, skill%, crit, element, final rounding.
## Legacy calls infer fixed/magic from is_magic; explicit damage_type selects physical. Returns damage and crit0/1.
static func roll_damage(lo: float, hi: float, is_magic: bool, defense: float, k: float, crit_chance: float, cmult: float,
		r: RandomNumberGenerator, element_mult: float = 1.0, damage_type: String = "", damage_pct: float = 1.0,
		crit_damage_bonus: float = 0.0,
		damage_multiplier: float = 1.0) -> Vector2i:
	if element_mult <= 0.0:
		return Vector2i.ZERO
	var dtype := CombatMath.damage_type_of(damage_type, is_magic)
	if dtype == "physical":
		var defended := CombatMath.physical_defense(Vector2(lo, hi), defense)
		lo = defended.x
		hi = defended.y
	var dmg := r.randf_range(lo, hi) if hi > lo else lo
	if dtype == "magic":
		dmg = CombatMath.apply_defense(dmg, defense, k)
	var is_crit := CombatMath.roll_crit(crit_chance, r)
	# tier B: Critical Shot/Throw add skill-% points instead of multiplying the skill's damage (SouthPerry).
	if is_crit and crit_damage_bonus > 0.0:
		dmg *= damage_pct + crit_damage_bonus / 100.0
	else:
		dmg *= damage_pct
		if is_crit:
			dmg *= cmult
	# tier A: element weakness/resistance is 1.5/0.5 (Cold Beam String.wz); round the final hit once.
	return Vector2i(maxi(1, roundi(dmg * element_mult * damage_multiplier)), 1 if is_crit else 0)


func _hit(i: int, m: int, swarm: MobSwarm, events: Array, live_mdd: PackedFloat32Array, physical_allowed: PackedByteArray,
		on_hit: Callable, live_pdd: PackedFloat32Array, on_kill: Callable) -> void:
	if hit_count[i] < MAX_HITS:
		hit_list[i * MAX_HITS + hit_count[i]] = swarm.identity[m]
		hit_count[i] += 1
	hits_left[i] -= 1
	_damage(i, m, swarm, events, live_mdd, physical_allowed, on_hit, live_pdd, on_kill,
		maxf(pierce_floor, 1.0 - pierce_falloff[i] * (hit_count[i] - 1)))


## A blast consumes the projectile at its first contact. Select before hits move or kill any targets.
## tier C: the primary always takes one slot; splash is nearest to its body, then slot. No recursive blasts.
func _blast(i: int, primary: int, swarm: MobSwarm, grid: SpatialHash, events: Array,
		live_mdd: PackedFloat32Array, physical_allowed: PackedByteArray, on_hit: Callable,
		live_pdd: PackedFloat32Array, on_kill: Callable) -> void:
	var anchor := Vector2(swarm.x[primary], swarm.y[primary])
	var box := Rect2(blast_position[i] + anchor, blast_size[i])
	var n := grid.query_radius(box.get_center(), box.size.length() * 0.5 + max_body_extent(swarm.kinds), _buf)
	var limit := mini(maxi(0, blast_count[i] - 1), n)
	if _blast_targets.size() < limit:
		var size := maxi(limit, maxi(16, _blast_targets.size() * 2))
		_blast_targets.resize(size)
		_blast_distance.resize(size)
	var count := 0
	var centre := swarm.mob_kind(primary).hitbox_at(anchor.x, anchor.y, swarm.facing[primary]).get_center()
	for c in n:
		var m := _buf[c]
		if m == primary or swarm.active[m] == 0:
			continue
		var body := swarm.mob_kind(m).hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m])
		if not box.intersects(body):
			continue
		var distance := centre.distance_squared_to(body.get_center())
		var at := count
		while at > 0 and (_blast_distance[at - 1] > distance or
				(_blast_distance[at - 1] == distance and _blast_targets[at - 1] > m)):
			at -= 1
		if at >= limit:
			continue
		var end := mini(count, limit - 1)
		while end > at:
			_blast_targets[end] = _blast_targets[end - 1]
			_blast_distance[end] = _blast_distance[end - 1]
			end -= 1
		_blast_targets[at] = m
		_blast_distance[at] = distance
		count = mini(count + 1, limit)
	events.append({"type": "skill_impact", "skill": skill_names[skill[i]], "pos": anchor,
		"effect": blast_visual[i]})
	_damage(i, primary, swarm, events, live_mdd, physical_allowed, on_hit, live_pdd, on_kill)
	for k in count:
		_damage(i, _blast_targets[k], swarm, events, live_mdd, physical_allowed, on_hit, live_pdd, on_kill)
	hits_left[i] = 0


func _damage(i: int, m: int, swarm: MobSwarm, events: Array, live_mdd: PackedFloat32Array,
		physical_allowed: PackedByteArray, on_hit: Callable, live_pdd: PackedFloat32Array, on_kill: Callable,
		multiplier: float = 1.0) -> void:
	if _halted:
		return
	# tier C: immune contact consumes a shell/pierce hit, without a damage roll or mob_hit event.
	var kind := damage_kind[i]
	var is_magic := kind == CombatMath.DAMAGE_MAGIC
	if not is_magic and m < physical_allowed.size() and physical_allowed[m] == 0:
		return
	var mk: MobKind = swarm.kinds[swarm.kind[m]]
	var defense := (float(live_pdd[m]) if m < live_pdd.size() else float(mk.pdd)) \
		if kind == CombatMath.DAMAGE_PHYSICAL else (float(live_mdd[m]) if m < live_mdd.size() else float(mk.mdd))
	var roll := roll_damage(dmg_min[i], dmg_max[i], is_magic, defense, magic_defense_k, crit[i],
		crit_mult[i], rng, swarm.element_multiplier(m, element[i]),
		CombatMath.DAMAGE_TYPE_NAMES[kind], damage_pct[i], crit_damage_bonus[i],
		multiplier)
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
		var hit := {"skill": skill_names[skill[i]], "level": level[i], "magic": is_magic,
			"damage": roll.x, "element": element[i], "damage_type": CombatMath.DAMAGE_TYPE_NAMES[kind]}
		if not meter_receipts[i].is_empty():
			hit["meter_receipt"] = meter_receipts[i]
		if burn_pulse[i] > 0:
			hit["burn_pulse"] = burn_pulse[i]
		if echo[i] != 0:
			hit["echo"] = true
		on_hit.call(m, hit)
	if swarm.apply_hit(m, roll.x, dir):
		kills.append(m)
		if on_kill.is_valid():
			_halted = bool(on_kill.call(m))


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
	for arr: Variant in [active, rotate, damage_kind, echo]:
		arr.resize(n)
	for arr: Variant in [x, y, vx, vy, range_left, radius, dmg_min, dmg_max, crit, crit_mult, damage_pct, crit_damage_bonus, pierce_falloff]:
		arr.resize(n)
	for arr: Variant in [visual, hits_left, hit_count, hit_visual, skill, level, blast_count, burn_pulse]:
		arr.resize(n)
	hit_list.resize(n * MAX_HITS)
	meter_receipts.resize(n)
	generation.resize(n)
	element.resize(n)
	blast_position.resize(n)
	blast_size.resize(n)
	blast_visual.resize(n)
	for i in range(n - 1, old - 1, -1):
		active[i] = 0
		_free.append(i)
