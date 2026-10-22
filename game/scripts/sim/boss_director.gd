class_name BossDirector
extends RefCounted
## Scheduled bosses, shared action timing, pursuit teleports, lifecycle events and the run's boss-clear condition.

## tier C: survivor encounter defaults; balance.bosses supplies the design values.
const DEFAULT_RULES := {"warning_time": 3.0, "spawn_distance": 250.0,
	"min_spawn_distance": 150.0, "normal_spawn_mult": 0.5,
	"teleport_stall": 5.0, "teleport_fade": 0.3, "teleport_progress": 1.0}

var entries: Array = []
## Schedule-order records: boss_index, mob_id, slot, warned, arrival (planned arrival time: the schedule time, pushed
## back when no arrival point exists), spawn_time, death_time, dead, skipped (no mob img: never arrives, counts as done).
var records: Array = []
var rules: Dictionary = {}
var _actions: Array[Dictionary] = []
var _now := 0.0
var _action_view := {"actions": PackedStringArray(), "times": PackedFloat32Array(), "facings": PackedInt32Array()}
var _view_slots := PackedInt32Array()


func _init(p_entries: Array = [], p_rules: Dictionary = {}) -> void:
	entries = p_entries.duplicate(true)
	rules = DEFAULT_RULES.merged(p_rules, true)
	_view_slots.resize(entries.size())
	_view_slots.fill(-1)
	for index in entries.size():
		records.append({"boss_index": index, "mob_id": int(entries[index].mob_id), "slot": -1,
			"warned": false, "arrival": float(entries[index].time), "spawn_time": -1.0, "death_time": -1.0,
			"dead": false, "skipped": false,
			"stall": 0.0, "best_distance": INF, "anchor": Vector2.ZERO, "fading": false, "fade_left": 0.0,
			"teleports": 0})
		_actions.append({"action": "", "start": 0.0, "until": 0.0, "facing": -1})
		if entries[index].has("map_index"):
			records[index].map_index = int(entries[index].map_index)
			records[index].map_id = int(entries[index].get("map_id", 0))


## Arms only the entered map on the total round clock, keeping previous records for results.
func arm_map(world: RunWorld) -> void:
	for i in entries.size():
		if int(entries[i].get("map_index", -1)) == world.map_index:
			records[i].arrival = world.map_entered_at + float(entries[i].map_time)
			records[i].map_id = world.current_map_id()


## Whether this living, spawned boss can begin an attack or skill at the supplied sim time.
func can_act(index: int, now: float) -> bool:
	return index >= 0 and index < records.size() and float(records[index].spawn_time) >= 0.0 \
		and not bool(records[index].dead) and not bool(records[index].get("fading", false)) \
		and now >= float(_actions[index].until) - 1e-6




## Holds a canonical stance and facing for its duration; attacks and skills use the same action gate.
func begin_action(index: int, action: String, seconds: float, facing: int, now: float) -> void:
	if not can_act(index, now):
		return
	_now = now
	_actions[index] = {"action": action, "start": now, "until": now + maxf(0.0, seconds), "facing": facing}


## Updates the shared action clock before swarm movement and returns its per-slot presentation/lock snapshot.
func prepare_actions(world: RunWorld) -> Dictionary:
	_now = world.time
	return action_snapshot(world.swarm)


## Borrows reusable per-slot arrays for immediate read-only consumption; the next refresh updates the same view.
## Callers retaining history must duplicate it. Capacity changes alone resize buffers; death/expiry clears overrides.
func action_snapshot(swarm: MobSwarm) -> Dictionary:
	var actions: PackedStringArray = _action_view.actions
	var times: PackedFloat32Array = _action_view.times
	var facings: PackedInt32Array = _action_view.facings
	var capacity := swarm.capacity()
	if actions.size() != capacity:
		actions.resize(capacity)
		times.resize(capacity)
		facings.resize(capacity)
	for slot in _view_slots:
		if slot >= 0 and slot < capacity:
			actions[slot] = ""
			times[slot] = 0.0
			facings[slot] = 0
	_view_slots.fill(-1)
	for index in records.size():
		var record: Dictionary = records[index]
		var slot := int(record.slot)
		if slot < 0 or slot >= swarm.capacity() or bool(record.dead) or swarm.active[slot] == 0 \
				or swarm.identity[slot] != int(record.get("identity", -1)) \
				or _now >= float(_actions[index].until) - 1e-6:
			continue
		actions[slot] = String(_actions[index].action)
		times[slot] = maxf(0.0, _now - float(_actions[index].start))
		facings[slot] = int(_actions[index].facing)
		_view_slots[index] = slot
	return _action_view





## Whether this stage has an encounter schedule (empty schedules retain duration-based clears).
func has_bosses() -> bool:
	return not entries.is_empty()


## Whether the entered map's encounters finished, retaining the missing-image skip rule of all_dead().
func map_done(map_index: int) -> bool:
	var found := false
	for record: Dictionary in records:
		if int(record.get("map_index", -1)) != map_index:
			continue
		found = true
		if not bool(record.dead) and not bool(record.skipped):
			return false
	return found


## Fires each warning and places each due boss on the player's reachable platform, with regen fade-in. A boss whose
## mob img is missing is skipped at its arrival time with a run warning (it never blocks the clear); when no arrival
## point exists on the arrival tick, the arrival is postponed by the warning lead and a fresh warning fires at once,
## so a boss always arrives exactly warning_time after its last warning (tier C).
func step(world: RunWorld, dt: float = 0.0) -> void:
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var record: Dictionary = records[index]
		if world.map_sequence_enabled() and int(entry.get("map_index", -1)) != world.map_index:
			continue
		if bool(record.dead) or bool(record.skipped):
			continue
		if float(record.spawn_time) >= 0.0:
			_track_pursuit(index, world, dt)
			continue
		var arrival := float(record.arrival)
		var known := world.kind_of_id.has(int(entry.mob_id))
		if known and not bool(record.warned) and world.time >= arrival - float(rules.warning_time) - 1e-6:
			_warn(index, world)
		if world.time < arrival - 1e-6:
			continue
		if not known:
			record.skipped = true
			world.warnings.append("boss %d (%d) has no mob img: skipped so the stage can clear" % [
				index, int(entry.mob_id)])
			continue
		var point := world.director.pick_player_platform(world, float(rules.min_spawn_distance),
			float(rules.spawn_distance), true)
		if point.z < -1.0:
			# A narrow platform can require a closer arrival; the warning and regen fade still apply.
			point = world.director.pick_player_platform(world, 0.0, float(rules.spawn_distance), true)
		if point.z < -1.0:
			_postpone(index, world)
			continue
		var slot := world.spawn_mob(int(world.kind_of_id[int(entry.mob_id)]), Vector2(point.x, point.y),
			int(point.z), float(entry.get("hp_mult", 1.0)), false)
		if slot < 0:
			_postpone(index, world)
			continue
		world.mob_boss[slot] = index
		# Scheduled bosses never flinch or get pushed, whatever their WZ info/boss flag (spec; tier C rule).
		world.swarm.steady[slot] = 1
		record.slot = slot
		record.identity = world.swarm.identity[slot]
		record.spawn_time = world.time
		record.anchor = Vector2(world.swarm.x[slot], world.swarm.y[slot])
		world.emit("boss_spawned", {"boss_index": index, "mob": slot, "mob_id": int(entry.mob_id),
			"pos": Vector2(world.swarm.x[slot], world.swarm.y[slot]), "time": world.time})


func _warn(index: int, world: RunWorld) -> void:
	records[index].warned = true
	world.emit("boss_warning", {"boss_index": index, "mob_id": int(entries[index].mob_id), "time": world.time})


## No arrival point this tick: arrive warning_time from now, after a fresh warning.
func _postpone(index: int, world: RunWorld) -> void:
	records[index].arrival = world.time + float(rules.warning_time)
	_warn(index, world)


func _track_pursuit(index: int, world: RunWorld, dt: float) -> void:
	var record: Dictionary = records[index]
	var slot := int(record.slot)
	var s := world.swarm
	if slot < 0 or s.active[slot] == 0:
		return
	if bool(record.fading):
		record.fade_left = maxf(0.0, float(record.fade_left) - dt)
		s.alpha[slot] = float(record.fade_left) / maxf(dt, float(rules.teleport_fade))
		if float(record.fade_left) > 1e-6:
			return
		var point := world.director.pick_player_platform(world, float(rules.min_spawn_distance),
			float(rules.spawn_distance), true)
		if point.z < -1:
			point = world.director.pick_player_platform(world, 0.0, float(rules.spawn_distance), true)
		if point.z < -1:
			return
		slot = world.relocate_mob(slot, Vector2(point.x, point.y), int(point.z))
		record.fading = false
		record.stall = 0.0
		record.best_distance = INF
		record.anchor = Vector2(point.x, point.y)
		record.teleports = int(record.teleports) + 1
		world.emit("boss_teleported", {"boss_index": index, "mob": slot, "mob_id": int(record.mob_id),
			"pos": Vector2(point.x, point.y), "time": world.time})
		return
	if s.alpha[slot] < 1.0:
		return
	if not can_act(index, world.time):
		# tier C: an intentional windup/skill stance is not a failed pursuit attempt.
		record.stall = 0.0
		record.anchor = Vector2(s.x[slot], s.y[slot])
		return
	var pos := Vector2(s.x[slot], s.y[slot])
	if world.is_hidden():
		# Hidden (#194): nobody to pursue, so the boss neither stalls nor teleports to the character.
		record.stall = 0.0
		record.best_distance = INF
		record.anchor = pos
		return
	var distance := float(s.route_len[slot])
	var moved := pos.distance_to(record.anchor)
	var progress := float(rules.teleport_progress)
	if distance <= float(s.tuning.stop_dist) or (distance < float(record.best_distance) - progress and moved >= progress):
		record.stall = 0.0
		record.best_distance = distance
		record.anchor = pos
		return
	if is_inf(float(record.best_distance)) and not is_inf(distance):
		record.best_distance = distance
	record.stall = float(record.stall) + dt
	if float(record.stall) >= float(rules.teleport_stall) - 1e-6:
		record.fading = true
		record.fade_left = float(rules.teleport_fade)
		s.fading_out[slot] = 1
		# The first fade-out tick is already harmless; the rest of the ramp runs on subsequent ticks.
		s.alpha[slot] = maxf(0.0, 1.0 - dt / maxf(dt, float(rules.teleport_fade)))


## Marks a scheduled boss dead exactly once, before the world considers ending the run.
func mark_dead(index: int, slot: int, pos: Vector2, world: RunWorld) -> void:
	if index < 0 or index >= records.size() or bool(records[index].dead):
		return
	var record: Dictionary = records[index]
	record.dead = true
	record.death_time = world.time
	world.emit("boss_died", {"boss_index": index, "mob": slot, "mob_id": int(record.mob_id),
		"pos": pos, "time": world.time})


## Number of spawned bosses still alive, including those the player has left behind.
func live_count() -> int:
	var count := 0
	for record: Dictionary in records:
		if float(record.spawn_time) >= 0.0 and not bool(record.dead):
			count += 1
	return count


## Scheduled bosses killed so far.
func dead_count() -> int:
	var count := 0
	for record: Dictionary in records:
		if bool(record.dead):
			count += 1
	return count


## True only after every scheduled boss has spawned and died (or was skipped for a missing mob img).
func all_dead() -> bool:
	if records.is_empty():
		return false
	for record: Dictionary in records:
		if not bool(record.dead) and not bool(record.skipped):
			return false
	return true


## Multiplier for ordinary spawning while at least one boss is alive.
func normal_spawn_multiplier() -> float:
	return float(rules.normal_spawn_mult) if live_count() > 0 else 1.0


## Explicit damage multiplier for a scheduled boss's hits.
func damage_multiplier(index: int) -> float:
	return float(entries[index].get("dmg_mult", 1.0)) if index >= 0 and index < entries.size() else 1.0


## Survivor reward configuration: each scheduled entry may override the shared boss reward defaults.
func reward_config(index: int) -> Dictionary:
	var defaults: Dictionary = rules.get("rewards", {})
	return defaults.merged(entries[index].get("rewards", {}), true) if index >= 0 and index < entries.size() else defaults
