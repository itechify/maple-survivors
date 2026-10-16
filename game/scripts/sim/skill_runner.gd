class_name SkillRunner
extends RefCounted
## Auto-casting (docs/GAME_DESIGN.md section 7). Every owned active skill counts its cooldown down; when it is ready
## and a living mob is within its range of the cast origin (the player's body, `RunWorld.cast_origin()`), it fires:
## a `cast` event, the player's cast stance, then
## - projectile skills: `count` shots, each aimed at the position (body centre) of a different target at cast time,
##   scheduled bosses first, then nearest (SpatialHash query; RunWorld.targets_before); with fewer targets than shots the extra shots reuse targets in order, aimed a
##   few px apart; each shot starts at RunWorld.shot_origin (the hand, cast_forward px toward its target);
## - instant skills: `attack_count` damage lines on each of the `count` nearest targets (Magic Claw: 2 lines).
## A ready skill without a target waits (it fires on the first tick one is in range). The cooldown restarts on cast.
## At most one skill fires per tick, oldest-ready first, paying its canonical MP cost. A short-MP skill remains
## ready and signals its waiting episode once; a later affordable skill may cast instead. Buffs need no mob target,
## stay out of the ready list while active, and use their canonical duration as the next readiness time.
## Stats come from Loadout.stats(), cached until Loadout.version changes.

## Vertical spacing of shots that reuse a target. tier C: ours.
const REUSE_SPREAD := 8.0

## skill key -> seconds until ready (<= 0 = ready).
var cooldowns := {}
## skill key -> the cooldown set at its last cast (absent before the first cast); the HUD sweep's denominator.
var cooldown_totals := {}
var casts := 0
## True if any skill cast during the latest step (cleared even when casting is blocked).
var fired_this_tick := false
## True while a ready, targeted skill is waiting for MP this tick (persistent presentation cue).
var waiting_mp := false

var _stats := {}
var _version := -1
var _buf := PackedInt32Array()
var _tgt := PackedInt32Array()
var _tgt_d := PackedFloat64Array()
var _shortages := {}
var _slow_serial := 0


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


## Whether `key` was ready with a target but short of MP at its latest cast scan (cleared by casting or losing it).
func is_waiting_mp(key: String) -> bool:
	return _shortages.has(key)


## Advances cooldowns and fires the oldest affordable ready skill with a target.
func step(dt: float, world: RunWorld) -> void:
	tick_cooldowns(dt, world)
	if world.can_cast():
		cast_ready(dt, world)


## Counts down every active skill, including while casting is blocked.
func tick_cooldowns(dt: float, world: RunWorld) -> void:
	fired_this_tick = false
	waiting_mp = false
	for key: String in world.loadout.order:
		if world.loadout.book.is_active(key):
			cooldowns[key] = float(cooldowns.get(key, 0.0)) - dt


## Fires one affordable skill, oldest-ready first; learned order breaks ties. Short MP never restarts cooldowns.
func cast_ready(dt: float, world: RunWorld) -> void:
	var lo := world.loadout
	var ready: Array[String] = []
	for key: String in lo.order:
		if lo.book.is_active(key) and not world.buffs.has(key) and float(cooldowns.get(key, 0.0)) <= 1e-6 \
				and String(stats_of(world, key).cast_rule) != "manual":
			ready.append(key)
	ready.sort_custom(func(a: String, b: String) -> bool:
		var ca := float(cooldowns.get(a, 0.0))
		var cb := float(cooldowns.get(b, 0.0))
		return ca < cb if ca != cb else lo.order.find(a) < lo.order.find(b))
	for key: String in ready:
		var cd := float(cooldowns.get(key, 0.0))
		var st := stats_of(world, key)
		var origin := world.cast_origin()
		var is_buff := String(st.kind) == "buff"
		var plan := _admit_cast(world, key, st, origin)
		if plan.is_empty():
			_shortages.erase(key)
			continue
		if not world.spend_mp(int(st.mp_cost)):
			waiting_mp = true
			if not _shortages.has(key):
				world.emit("mp_short", {"skill": key, "skill_id": int(st.skill_id), "required_mp": int(st.mp_cost),
					"mp": int(world.player_state.mp)})
			_shortages[key] = true
			continue
		_shortages.erase(key)
		cooldowns[key] = maxf(float(st.duration), float(st.buff_cooldown)) if is_buff else maxf(cd, -dt) + float(st.cooldown)
		cooldown_totals[key] = cooldowns[key]
		_resolve_cast(world, key, st, origin, plan)
		break


func _admit_cast(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> Dictionary:
	match String(st.cast_rule):
		"", "nearest":
			return _admit_nearest(world, key, st, origin)
		"box":
			return _admit_box(world, st)
		"crowd":
			return _admit_crowd(world, st)
		"hp_or_undead":
			return _admit_hp_or_undead(world, key, st)
		"manual":
			return {}
	return {}


func _admit_nearest(world: RunWorld, key: String, st: Dictionary, origin: Vector2) -> Dictionary:
	if String(st.kind) == "buff":
		if not world.can_start_buff(key, st):
			return {}
		if float(st.duration) > 0.0:
			return {"go": true}
	if _find_targets(world, origin, float(st.range), int(st.count)) == 0:
		return {}
	return {"targets": _tgt.duplicate()}


func _admit_box(world: RunWorld, st: Dictionary) -> Dictionary:
	if not bool(st.has_box):
		return {}
	var targets := world.skill_box_targets(st.box)
	# tier C: a box cast defaults to one eligible target; skill data may require a crowd.
	if targets.size() < maxi(1, int(st.cast_params.get("min_targets", 1))):
		return {}
	return {"targets": targets}


func _admit_hp_or_undead(world: RunWorld, key: String, st: Dictionary) -> Dictionary:
	var targets := PackedInt32Array()
	if bool(st.has_box):
		targets = world.skill_box_targets(st.box, func(slot: int) -> bool: return world.swarm.mob_kind(slot).undead)
	var heal: Dictionary = world.book.def(key).get("heal", {})
	var injured := float(world.player_state.hp) < float(world.player_state.max_hp) * float(heal.get("hp_threshold", 0.0))
	return {"targets": targets} if injured or not targets.is_empty() else {}


func _resolve_cast(world: RunWorld, key: String, st: Dictionary, origin: Vector2, plan: Dictionary) -> void:
	var targets: PackedInt32Array = plan.get("targets", PackedInt32Array())
	if String(st.cast_rule) in ["", "nearest"] and not targets.is_empty() and String(st.kind) != "buff":
		world.face_toward(world.mob_center(targets[0]).x)
	casts += 1
	fired_this_tick = true
	if String(st.cast_rule) in ["", "nearest"] and String(st.kind) == "buff":
		world.start_buff(key, st)
	world.emit("cast", {"skill": key, "skill_id": int(st.skill_id), "level": int(st.level),
		"pos": world.player.pos, "facing": world.player.facing, "action": String(st.action), "effect": String(st.effect)})
	world.start_action(String(st.action), float(st.action_time))
	match String(st.cast_rule):
		"box":
			_resolve_instant_targets(world, st, targets, int(st.mob_count), int(st.attack_count),
				world.visual_index(String(st.hit)))
		"crowd":
			_resolve_crowd(world, key, st, targets)
		"hp_or_undead":
			_resolve_hp_or_undead(world, key, st, targets)
		"", "nearest":
			if String(st.kind) != "buff":
				_resolve_nearest(world, key, st, origin, targets)


func _admit_crowd(world: RunWorld, st: Dictionary) -> Dictionary:
	if not bool(st.has_box):
		return {}
	var targets := world.skill_box_targets(st.box, func(slot: int) -> bool:
		return world.swarm.can_slow_cast(slot, _slow_serial))
	# tier C: survivor crowd threshold lives in the skill's cast block, before MP payment.
	if targets.size() < maxi(1, int(st.cast_params.get("min_targets", 1))):
		return {}
	return {"targets": targets}


func _resolve_crowd(world: RunWorld, key: String, st: Dictionary, targets: PackedInt32Array) -> void:
	_slow_serial += 1
	var params := {"x": world.book.canonical(key, int(st.level), "x"),
		"time": world.book.canonical(key, int(st.level), "time")}
	for i in mini(int(st.mob_count), targets.size()):
		world.swarm.apply_slow_cast(targets[i], _slow_serial, params, world.events)


func _resolve_instant_targets(world: RunWorld, st: Dictionary, targets: PackedInt32Array,
		limit: int, lines: int, hv: int) -> void:
	for i in mini(limit, targets.size()):
		var slot := targets[i]
		for line in lines:
			# Both queries return valid slots. Keep nearest's active-mask check; is_live adds only bounds checks.
			if world.swarm.active[slot] == 0:
				break
			world.hit_mob(slot, st, hv)


func _resolve_hp_or_undead(world: RunWorld, key: String, st: Dictionary, targets: PackedInt32Array) -> void:
	var heal: Dictionary = world.book.def(key).get("heal", {})
	var power := world.book.canonical(key, int(st.level), String(heal.get("field", "hp")))
	var lo := world.loadout
	var luk := float(world.player_state.luk)
	var recovery := CombatMath.heal_recovery_range(lo.int_stat, luk, lo.matk, power)
	world.restore_player("hp", floori(CombatMath.roll_range(recovery, world.rng)), key)
	var damage := CombatMath.heal_damage_range(lo.int_stat, luk, lo.matk, power, targets.size() + 1)
	var hit := st.duplicate()
	hit.damage_min = damage.x
	hit.damage_max = damage.y
	hit.magic = true
	hit.element = "h" # tier B: Heal's holy undead attack; canonical node has no elemAttr, research/cleric-heal.md.
	var hv := world.visual_index(String(st.hit))
	# tier C: ticket #57 requires every undead in the box, without the original six-target cap.
	for slot: int in targets:
		world.hit_mob(slot, hit, hv)


## Fills the target buffer with up to `want` distinct live mobs whose body centre is within `rng_px` of `origin`,
## scheduled bosses first, then nearest, then slot (RunWorld.targets_before). Returns how many.
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
		while at > 0 and world.targets_before(m, d2, _tgt[at - 1], _tgt_d[at - 1]):
			at -= 1
		if at >= want:
			continue
		_tgt.insert(at, m)
		_tgt_d.insert(at, d2)
		if _tgt.size() > want:
			_tgt.resize(want)
			_tgt_d.resize(want)
	return _tgt.size()


func _resolve_nearest(world: RunWorld, key: String, st: Dictionary, origin: Vector2, targets: PackedInt32Array) -> void:
	var n := targets.size()
	var hv := world.visual_index(String(st.hit))
	if String(st.kind) == "projectile":
		var vis := world.visual_index(String(st.ball))
		var count := int(st.count)
		var speed := float(st.speed)
		for k in count:
			var m := targets[k % n]
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
				"pierce": int(st.pierce), "skill": key, "level": int(st.level), "element": String(st.element),
			})
	else:
		_resolve_instant_targets(world, st, targets, int(st.count), int(st.attack_count), hv)
