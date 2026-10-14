class_name SkillRunner
extends RefCounted
## Auto-casting (docs/GAME_DESIGN.md section 7). Every owned active skill counts its cooldown down; when it is ready
## and a living mob is within its range of the cast origin (the player's body, `RunWorld.cast_origin()`), it fires:
## a `cast` event, the player's cast stance, then
## - projectile skills: `count` shots, each aimed at the position (body centre) of a different target at cast time,
##   nearest first (SpatialHash query); with fewer targets than shots the extra shots reuse targets in order, aimed a
##   few px apart; each shot starts at RunWorld.shot_origin (the hand, cast_forward px toward its target);
## - instant skills: `attack_count` damage lines on each of the `count` nearest targets (Magic Claw: 2 lines).
## A ready skill without a target waits (it fires on the first tick one is in range). The cooldown restarts on cast.
## Stats come from Loadout.stats(), cached until Loadout.version changes.

## Vertical spacing of shots that reuse a target. tier C: ours.
const REUSE_SPREAD := 8.0

## skill key -> seconds until ready (<= 0 = ready).
var cooldowns := {}
var casts := 0
## True if any skill cast during the latest step (cleared even when casting is blocked).
var fired_this_tick := false

var _stats := {}
var _version := -1
var _buf := PackedInt32Array()
var _tgt := PackedInt32Array()
var _tgt_d := PackedFloat32Array()


func _init() -> void:
	_buf.resize(128)


## Cached resolved stats of `key` (refreshed when the loadout changed).
func stats_of(world: RunWorld, key: String) -> Dictionary:
	if world.loadout.version != _version:
		_stats.clear()
		_version = world.loadout.version
	if not _stats.has(key):
		_stats[key] = world.loadout.stats(key)
	return _stats[key]


## Advances cooldowns and fires every ready skill that has a target.
func step(dt: float, world: RunWorld) -> void:
	fired_this_tick = false
	tick_cooldowns(dt, world)
	if world.can_cast():
		cast_ready(dt, world)


## Counts down every active skill, including while casting is blocked.
func tick_cooldowns(dt: float, world: RunWorld) -> void:
	for key: String in world.loadout.order:
		if world.loadout.book.is_active(key):
			cooldowns[key] = float(cooldowns.get(key, 0.0)) - dt


## Fires ready skills with targets, preserving the existing cooldown carry and loadout order.
func cast_ready(dt: float, world: RunWorld) -> void:
	var lo := world.loadout
	for key: String in lo.order:
		if not lo.book.is_active(key):
			continue
		var cd := float(cooldowns.get(key, 0.0))
		if cd > 0.0:
			cooldowns[key] = cd
			continue
		cd = maxf(cd, -dt)
		var st := stats_of(world, key)
		var origin := world.cast_origin()
		var n := _find_targets(world, origin, float(st.range), int(st.count))
		if n == 0:
			cooldowns[key] = cd
			continue
		cooldowns[key] = cd + float(st.cooldown)
		_fire(world, key, st, origin, n)


## Fills the target buffer with up to `want` distinct live mobs whose body centre is within `rng_px` of `origin`,
## nearest first. Returns how many.
func _find_targets(world: RunWorld, origin: Vector2, rng_px: float, want: int) -> int:
	var s := world.swarm
	var n := world.mob_grid.query_radius(origin, rng_px + world.body_pad, _buf)
	_tgt.resize(0)
	_tgt_d.resize(0)
	var r2 := rng_px * rng_px
	for c in n:
		var m := _buf[c]
		if s.active[m] == 0:
			continue
		var ctr := world.mob_center(m)
		var d2 := ctr.distance_squared_to(origin)
		if d2 > r2:
			continue
		var at := _tgt.size()
		while at > 0 and _tgt_d[at - 1] > d2:
			at -= 1
		if at >= want:
			continue
		_tgt.insert(at, m)
		_tgt_d.insert(at, d2)
		if _tgt.size() > want:
			_tgt.resize(want)
			_tgt_d.resize(want)
	return _tgt.size()


func _fire(world: RunWorld, key: String, st: Dictionary, origin: Vector2, n: int) -> void:
	casts += 1
	fired_this_tick = true
	var first := world.mob_center(_tgt[0])
	world.face_toward(first.x)
	var level := int(st.level)
	var hv := world.visual_index(String(st.hit))
	world.emit("cast", {
		"skill": key, "skill_id": int(st.skill_id), "level": level, "pos": world.player.pos,
		"facing": world.player.facing, "action": String(st.action), "effect": String(st.effect),
	})
	world.start_action(String(st.action), float(st.action_time))
	if String(st.kind) == "projectile":
		var vis := world.visual_index(String(st.ball))
		var count := int(st.count)
		var speed := float(st.speed)
		for k in count:
			var m := _tgt[k % n]
			var reuse := floorf(float(k) / float(n))
			var aim := world.mob_center(m) + Vector2(0.0, REUSE_SPREAD * reuse * (1.0 if k % 2 == 0 else -1.0))
			var start := world.shot_origin(aim)
			var dir := (aim - start).normalized()
			if dir == Vector2.ZERO or signf(aim.x - start.x) != signf(aim.x - origin.x):
				# A target inside the reach of the hand: fly straight at it from the body instead.
				start = origin
				dir = (aim - origin).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2(world.player.facing, 0.0)
			world.projectiles.spawn({
				"x": start.x, "y": start.y, "vx": dir.x * speed, "vy": dir.y * speed,
				"range": float(st.range), "radius": float(st.radius), "visual": vis, "hit_visual": hv,
				"rotate": bool(st.rotate), "dmg_min": float(st.damage_min), "dmg_max": float(st.damage_max),
				"magic": bool(st.magic), "crit": float(st.crit), "crit_mult": float(st.crit_mult),
				"pierce": int(st.pierce), "skill": key,
			})
	else:
		var targets := mini(int(st.count), n)
		var lines := int(st.attack_count)
		for k in targets:
			var m := _tgt[k]
			for h in lines:
				if world.swarm.active[m] == 0:
					break
				world.hit_mob(m, st, hv)
