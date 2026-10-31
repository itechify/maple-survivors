class_name SummonTurret
extends RefCounted
## The turret summon (spec #384 M9, GAME_DESIGN 7.121): a PlayerSummons ally with `summon.behavior: "turret"`. It is planted
## where it was called and never follows or teleports. It targets living monsters inside a circle of radius
## `info.range.r x area` around `(x + sp.x, y + sp.y)` (the WZ `sp` offset, mirrored with the ally's facing), nearest
## first, up to `mobCount` plus the `count` modifiers; at `attackAfter` into its attack animation it launches one
## `info.ball` per target at the target's body centre at `info.bulletSpeed` px/s, and each hit lands on arrival through
## RunWorld.hit_mob with the ally's cast stats. A target that has died by then is skipped.
##
## PlayerSummons keeps the lifecycle (spawn, `summon_count` spacing, recast replaces, expiry and `die`, map transfer) and
## calls `spawn_slot`, `step_slot` for each turret every tick and `step_balls` once; nothing here names a job, a skill or an
## id. The balls live in pooled arrays that `ProjectileRenderer` draws as they are (no per-ball Node). Pure sim: no nodes,
## no clock but `dt`, no RNG beyond the damage rolls hit_mob already makes.

## tier C: most balls in flight at once; a launch past the cap is dropped.
const MAX_BALLS := 32

var active := PackedByteArray()
## Draw identity: increments on every launch, including reuse between presentation frames.
var generation := PackedInt64Array()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
## Index into RunWorld.visual_paths of the looping ball animation.
var visual := PackedInt32Array()
## 1 when the sprite turns to the flight direction (every ball does).
var rotate := PackedByteArray()
var flight_left := PackedFloat64Array()
var target := PackedInt32Array()
## MobSwarm.identity of the target at launch: a reused slot is a different monster.
var target_id := PackedInt64Array()
var hit_visual := PackedInt32Array()
var strike_effect := PackedStringArray()
## Cast snapshots (cold metadata): the ball hits with the stats of the cast that called its turret, even after a recast.
var ball_stats: Array[Dictionary] = []
var _next_generation := 0
var _buf := PackedInt32Array()


## Balls in flight (test hook and perf overlay).
func ball_count() -> int:
	var n := 0
	for b in active.size():
		if active[b] != 0:
			n += 1
	return n


## Drops every ball (map transfer, Hidden, a dead caster).
func clear() -> void:
	active.fill(0)
	for b in ball_stats.size():
		ball_stats[b] = {} # drop the cast snapshots too


## Called once for each ally of a fresh cast: resolves the ball's art path into `d` (shared by the whole group) and plants
## the turret on the floor under its own x (a cast made in the air does not leave it hanging).
func spawn_slot(summons: PlayerSummons, i: int, _ordinal: int, world: RunWorld, d: Dictionary) -> void:
	# tier C: the turret's facing is the caster's at the moment it is called and never turns (a planted object).
	if not d.has("ball_visual"):
		d["ball_visual"] = world.visual_index("%s/%s/info/ball" % [d.path, d.attack])
	var floor_index := world.fhm.find_below(summons.x[i], summons.y[i])
	if floor_index >= 0:
		summons.y[i] = world.fhm.y_at(floor_index, summons.x[i]) # tier C: a planted object rests on the ground under the caster


## A turret has no dive to finish: the level `time` always ends it.
func holds_expiry(_i: int) -> bool:
	return false


## One tick of one turret: finish the summon-in, count down to the launch, and start the next attack when a target is
## inside the circle.
func step_slot(s: PlayerSummons, i: int, dt: float, world: RunWorld) -> void:
	var d := s.definitions[i]
	var away := world.is_hidden() or bool(world.player_state.dead)
	s.wait[i] -= dt
	if s.impact[i] >= 0.0:
		s.impact[i] -= dt
		if s.impact[i] <= 1e-6:
			s.impact[i] = -1.0
			if not away:
				_launch(s, i, world)
	var current := s.action[i]
	if current == "summoned":
		if s.age[i] >= float(d.durations.summoned):
			s.set_action(i, "stand")
	elif current == String(d.attack) and s.impact[i] < 0.0 and s.age[i] >= float(d.durations[d.attack]):
		s.set_action(i, "stand")
	if away or s.wait[i] > 1e-6:
		return
	if not any_target(s, i, world):
		return
	s.set_action(i, String(d.attack))
	s.impact[i] = float(d.info.get("attackAfter", 0.0)) / 1000.0
	s.wait[i] = maxf(float(d.attack_interval), maxf(float(d.durations[d.attack]), s.impact[i]))
	world.emit("summon_attack", {"skill": s.stats[i].skill, "slot": i, "pos": Vector2(s.x[i], s.y[i])})


## Flies every ball one tick and lands the ones whose flight time is over. Hidden or a dead caster drops them all.
func step_balls(dt: float, world: RunWorld) -> void:
	if active.is_empty():
		return
	if world.is_hidden() or bool(world.player_state.dead):
		clear()
		return
	for b in active.size():
		if active[b] == 0:
			continue
		flight_left[b] -= dt
		if flight_left[b] > 1e-6:
			x[b] += vx[b] * dt
			y[b] += vy[b] * dt
			continue
		active[b] = 0
		_land(b, world)


## The circle's centre: the ally plus the WZ `sp` offset (left-facing art is the WZ native, so a right-facing turret mirrors x).
static func centre(s: PlayerSummons, i: int) -> Vector2:
	var r: Dictionary = s.definitions[i].info.get("range", {})
	var sp: Array = r.get("sp", {}).get("$v", [0, 0])
	return Vector2(s.x[i] - float(sp[0]) * s.facing[i], s.y[i] + float(sp[1]))


## The circle's radius in px: `info.range.r` scaled by the cast's `area`.
static func radius(s: PlayerSummons, i: int) -> float:
	return float(s.definitions[i].info.get("range", {}).get("r", 0.0)) * float(s.stats[i].area)


## Living monsters whose body box touches the circle, nearest centre first (RunWorld.targets_before: bosses, and marked
## monsters once the mark lands, ahead of the swarm).
func targets_in_circle(s: PlayerSummons, i: int, world: RunWorld) -> PackedInt32Array:
	var matches := _in_circle(s, i, world, false)
	world.sort_targets_by_distance(matches, centre(s, i))
	return PackedInt32Array(matches)


## Whether any living monster touches the circle: the same test as targets_in_circle, but it stops at the first one and
## builds no list (a ready turret with nothing in reach checks this every tick).
func any_target(s: PlayerSummons, i: int, world: RunWorld) -> bool:
	return not _in_circle(s, i, world, true).is_empty()


func _in_circle(s: PlayerSummons, i: int, world: RunWorld, first_only: bool) -> Array[int]:
	var c := centre(s, i)
	var r := radius(s, i)
	var matches: Array[int] = []
	var n := world.mob_grid.query_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0).grow(world.body_pad), _buf)
	for k in n:
		var m := _buf[k]
		if world.swarm.active[m] == 0:
			continue
		var body := world.swarm.mob_kind(m).hitbox_at(world.swarm.x[m], world.swarm.y[m], world.swarm.facing[m])
		var near := Vector2(clampf(c.x, body.position.x, body.end.x), clampf(c.y, body.position.y, body.end.y))
		if near.distance_squared_to(c) <= r * r:
			matches.append(m)
			if first_only:
				break
	return matches


## The ball line of the card / Skill window text (SkillText), or "" when the attack node has no range.
static func describe(book: SkillBook, key: String, attack: String, area: float) -> String:
	var info: Dictionary = book.skill_node(key).get("summon", {}).get(attack, {}).get("info", {})
	var radius_px: float = float(info.get("range", {}).get("r", 0.0)) * area
	if radius_px <= 0.0:
		return ""
	return "Stays where it is called and fires a ball at monsters within %d px" % roundi(radius_px)


func _launch(s: PlayerSummons, i: int, world: RunWorld) -> void:
	var st := s.stats[i]
	var d := s.definitions[i]
	var targets := targets_in_circle(s, i, world)
	var count := maxi(1, roundi(world.loadout.skill_stat(st.skill, "count", s.base_count(i, world))))
	var origin := centre(s, i)
	var speed := maxf(1.0, float(d.info.get("bulletSpeed", 0.0)))
	# tier C: a ball is a straight line with no hit test on the way: it lands on the target it was launched at.
	for t in mini(count, targets.size()):
		var b := _free_ball()
		if b < 0:
			return
		var m := targets[t]
		var aim := world.mob_center(m)
		var delta := aim - origin
		active[b] = 1
		_next_generation += 1
		generation[b] = _next_generation
		x[b] = origin.x
		y[b] = origin.y
		var heading := delta.normalized() if delta != Vector2.ZERO else Vector2(float(s.facing[i]), 0.0)
		vx[b] = heading.x * speed
		vy[b] = heading.y * speed
		visual[b] = int(d.ball_visual)
		rotate[b] = 1
		flight_left[b] = delta.length() / speed
		target[b] = m
		target_id[b] = world.swarm.identity[m]
		hit_visual[b] = world.visual_index(st.hit)
		strike_effect[b] = String(d.strike_effect)
		ball_stats[b] = st


func _land(b: int, world: RunWorld) -> void:
	var m := target[b]
	if world.swarm.active[m] == 0 or world.swarm.identity[m] != target_id[b]:
		return # tier C: a target that died (or whose slot was reused) in flight is skipped
	var st := ball_stats[b]
	if strike_effect[b] != "":
		world.emit("summon_strike", {"skill": st.skill, "slot": -1, "mob": m,
			"pos": world.mob_center(m), "effect": strike_effect[b]})
	for line in int(st.attack_count):
		if world.swarm.active[m] == 0:
			break
		world.hit_mob(m, st, hit_visual[b])


func _free_ball() -> int:
	var b := active.find(0)
	if b >= 0:
		return b
	if active.size() >= MAX_BALLS:
		return -1
	active.append(0)
	generation.append(0)
	x.append(0)
	y.append(0)
	vx.append(0)
	vy.append(0)
	visual.append(-1)
	rotate.append(0)
	flight_left.append(0)
	target.append(-1)
	target_id.append(0)
	hit_visual.append(-1)
	strike_effect.append("")
	ball_stats.append({})
	return active.size() - 1
