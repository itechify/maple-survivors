class_name PlayerSummons
extends RefCounted
## Packed player-owned allies, shared by every skill with a summon block. SkillRunner owns map cleanup.
## Resolved cast snapshots are cold metadata; position, lifetime, attack and animation state use parallel arrays.
var active := PackedByteArray()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var left := PackedFloat64Array()
var facing := PackedInt32Array()
var age := PackedFloat64Array()
var action := PackedStringArray()
var wait := PackedFloat64Array()
var impact := PackedFloat64Array()
var stats: Array[Dictionary] = []
var definitions: Array[Dictionary] = []
var offsets := PackedFloat32Array()
var _buf := PackedInt32Array()

## Test hook: number of allies still able to attack.
func living_count() -> int:
	var count := 0
	for i in active.size():
		if active[i] != 0 and left[i] > 0.0:
			count += 1
	return count

## Removes map-local allies while preserving the runner's cooldowns.
func clear() -> void:
	active.fill(0)

## Calls allies using resolved rank stats; recasting replaces this skill's previous group.
func spawn(world: RunWorld, st: Dictionary) -> void:
	for i in active.size():
		if active[i] != 0 and stats[i].skill == st.skill:
			active[i] = 0
	var d: Dictionary = world.book.def(st.skill).summon.duplicate(true)
	var node: Dictionary = world.book.skill_node(st.skill).get("summon", {})
	var attack_node: Dictionary = node.get(String(d.attack), {})
	d["info"] = attack_node.get("info", {})
	d["durations"] = {}
	d["move"] = String(d.get("move", "move"))
	for a: String in ["summoned", "stand", String(d.move), String(d.attack), "die"]:
		d.durations[a] = WeaponInfo.frame_times(node.get(a, {})).total
	var count := maxi(1, roundi(world.loadout.skill_stat(st.skill, "summon_count", 1.0)))
	for ordinal in count:
		var i := active.find(0)
		if i < 0:
			i = active.size()
			active.append(0)
			x.append(0)
			offsets.append(0)
			y.append(0)
			left.append(0)
			facing.append(0)
			age.append(0)
			action.append("")
			wait.append(0)
			impact.append(-1)
			stats.append({})
			definitions.append({})
		active[i] = 1
		offsets[i] = ordinal * float(d.get("ordinal_spread", 36.0)) # tier C: per-ally spacing.
		x[i] = world.player.pos.x + offsets[i]
		y[i] = world.player.pos.y
		facing[i] = world.player.facing
		left[i] = maxf(0.0, world.loadout.skill_stat(st.skill, "duration", float(st.duration)))
		stats[i] = SkillRunner.cast_snapshot(st)
		definitions[i] = d
		action[i] = ""
		_set_action(i, "summoned")
		wait[i] = float(d.durations.summoned)
		impact[i] = -1.0
		world.emit("summon_spawn", {"skill": st.skill, "slot": i})

## Advances follow, windup, impact and expiry with fixed simulation ticks.
func step(dt: float, world: RunWorld) -> void:
	for i in active.size():
		if active[i] == 0:
			continue
		var d := definitions[i]
		age[i] += dt
		left[i] -= dt
		if left[i] <= 0.0:
			if action[i] != "die":
				_set_action(i, "die")
				impact[i] = -1.0
			if age[i] >= float(d.durations.die):
				active[i] = 0
			continue
		wait[i] -= dt
		if impact[i] >= 0.0:
			impact[i] -= dt
			if impact[i] <= 1e-6:
				impact[i] = -1.0
				if not world.is_hidden() and not bool(world.player_state.dead):
					_hit(i, world)
		if wait[i] > 1e-6:
			continue
		var pos := Vector2(x[i], y[i])
		var destination := world.player.pos + Vector2(offsets[i], 0) - Vector2(world.player.facing * float(d.follow_distance), 0)
		# tier C: one-pixel stand/move deadzone prevents animation flicker at the trailing point.
		var moved := pos.distance_to(destination) > 1.0
		if pos.distance_to(destination) > float(d.teleport_distance):
			pos = destination
		else:
			pos = pos.move_toward(destination, float(d.follow_speed) * dt)
		x[i] = pos.x
		y[i] = pos.y
		_set_action(i, String(d.move) if moved else "stand")
		if world.is_hidden() or bool(world.player_state.dead):
			continue
		var targets := _targets(i, world, true)
		if targets.is_empty():
			continue
		facing[i] = 1 if world.mob_center(targets[0]).x > x[i] else -1
		_set_action(i, String(d.attack))
		impact[i] = float(d.info.get("attackAfter", 0.0)) / 1000.0
		wait[i] = maxf(float(d.attack_interval), maxf(float(d.durations[d.attack]), impact[i]))
		world.emit("summon_attack", {"skill": stats[i].skill, "slot": i, "pos": pos})

func _set_action(i: int, value: String) -> void:
	if action[i] != value:
		action[i] = value
		age[i] = 0.0

func _box(i: int) -> Rect2:
	var r: Dictionary = definitions[i].info.get("range", {})
	var lt: Array = r.get("lt", {}).get("$v", [0, 0])
	var rb: Array = r.get("rb", {}).get("$v", [0, 0])
	var scale := float(stats[i].area)
	return Rect2(Vector2(float(lt[0]), float(lt[1])) * scale,
		Vector2(float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])) * scale)

func _targets(i: int, world: RunWorld, both_sides: bool) -> PackedInt32Array:
	var pos := Vector2(x[i], y[i])
	var box := _box(i)
	var mirrored := Rect2(Vector2(-box.end.x, box.position.y), box.size)
	var query := box.merge(mirrored) if both_sides else (mirrored if facing[i] > 0 else box)
	query.position += pos
	var n := world.mob_grid.query_rect(query.grow(world.body_pad), _buf)
	var matches: Array[int] = []
	for c in n:
		var m := _buf[c]
		if world.swarm.active[m] == 0:
			continue
		var body := world.swarm.mob_kind(m).hitbox_at(world.swarm.x[m], world.swarm.y[m], world.swarm.facing[m])
		if query.intersects(body, true):
			matches.append(m)
	# Opt-in `summon.priority_status` (tier C reading of the WZ attack `priority`): after scheduled bosses (they take no
	# statuses), monsters running that status come before the rest. Without the key the sort is the shared one, untouched.
	var priority := MobSwarm.STATUS_NAMES.find(String(definitions[i].get("priority_status", "")))
	matches.sort_custom(func(a: int, b: int) -> bool:
		if priority >= 0:
			var boss := world.is_scheduled_boss(a)
			if boss != world.is_scheduled_boss(b):
				return boss
			var marked := world.swarm.status_time(a, priority) > 0.0
			if marked != (world.swarm.status_time(b, priority) > 0.0):
				return marked
		return world.targets_before(a, world.mob_center(a).distance_squared_to(pos),
			b, world.mob_center(b).distance_squared_to(pos)))
	return PackedInt32Array(matches)


## The strike's target count before `count` modifiers: the attack node's `info.mobCount`, or, with the opt-in `summon.count_field`,
## that field of the cast's mapped level (Bahamut: 3, 6 at level 30).
func _base_count(i: int, world: RunWorld) -> float:
	var field := String(definitions[i].get("count_field", ""))
	var fallback := float(definitions[i].info.get("mobCount", 1))
	return world.book.canonical(String(stats[i].skill), int(stats[i].level), field, fallback) if field != "" else fallback

func _hit(i: int, world: RunWorld) -> void:
	var st := stats[i]
	var targets := _targets(i, world, false)
	var count := maxi(1, roundi(world.loadout.skill_stat(st.skill, "count", _base_count(i, world))))
	for t in mini(count, targets.size()):
		for line in int(st.attack_count):
			if world.swarm.active[targets[t]] == 0:
				break
			world.hit_mob(targets[t], st, world.visual_index(st.hit))
