class_name BossDirector
extends RefCounted
## Scheduled bosses, shared action timing, pursuit teleports, lifecycle events and the run's boss-clear condition.

## tier C: survivor encounter defaults; balance.bosses supplies the design values.
const DEFAULT_RULES := {"warning_time": 3.0, "spawn_distance": 250.0,
	"min_spawn_distance": 150.0, "normal_spawn_mult": 0.5,
	"teleport_stall": 5.0, "teleport_fade": 0.3, "teleport_progress": 1.0, "arrival_fallback": 15.0}

var entries: Array = []
## Schedule-order records: boss_index, mob_id, slot, warned, arrival (planned arrival time: the schedule time, pushed
## back when no arrival point exists), spawn_time, death_time, dead, skipped (no mob img: never arrives, counts as done),
## and, only once they apply (so records of runs that never need them keep their shape), postponed_since /
## relocate_since (when arrivals / the faded pursuit relocation started failing for want of a point; -1 = no longer)
## and fallback (true: arrived through the arrival_fallback rule) / form_time (the sim time a final form took over;
## `mob_id` is then the form's).
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
## so a boss always arrives exactly warning_time after its last warning (tier C). Postponing is bounded: see _point.
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
		var found := _point(world, float(record.get("postponed_since", -1.0)))
		var point: Vector3 = found.point
		if point.z < -1.0:
			_postpone(index, world)
			continue
		var slot := world.spawn_boss(int(entry.mob_id), index, Vector2(point.x, point.y), int(point.z),
			float(entry.get("hp_mult", 1.0)))
		if slot < 0:
			_postpone(index, world)
			continue
		# Tier C (#307): freeze the round opening damage at arrival, preserving encounter-specific scales.
		var ramp_damage := world.opening_multiplier("damage")
		entry["attack_dmg_mult"] = float(entry.get("attack_dmg_mult", entry.get("dmg_mult", 1.0))) * ramp_damage
		entry["dmg_mult"] = float(entry.get("dmg_mult", 1.0)) * ramp_damage
		# Tier C (#453): the level scale's damage ratios freeze at arrival too (HP, defence and EXP did, in spawn_mob).
		world.capture_boss_level_scale(index, int(entry.mob_id), record)
		record.slot = slot
		record.identity = world.swarm.identity[slot]
		record.spawn_time = world.time
		record.anchor = Vector2(world.swarm.x[slot], world.swarm.y[slot])
		var spawned := {"boss_index": index, "mob": slot, "mob_id": int(entry.mob_id),
			"pos": Vector2(world.swarm.x[slot], world.swarm.y[slot]), "time": world.time}
		if bool(found.fallback):
			record.fallback = true
			spawned.fallback = true
		world.emit("boss_spawned", spawned)


## Where a boss arrives or reappears: on the player's platform at spawn_distance (at least min_spawn_distance away),
## else anywhere on it within spawn_distance (a narrow platform). z < -1 when it has no point (the player is over no
## floor, or every point is walled off). Once that has kept failing for arrival_fallback s since `since` (>= 0), the
## floor point nearest the player stands in for the player with the same two tries, then that point itself (tier C,
## #260: a player stranded in a floorless void no longer postpones a boss forever). Returns {point: Vector3,
## fallback: bool (true when the arrival_fallback rule chose it)}.
func _point(world: RunWorld, since: float) -> Dictionary:
	var d := world.director
	var point := d.pick_player_platform(world, float(rules.min_spawn_distance), float(rules.spawn_distance), true)
	if point.z < -1.0:
		# A narrow platform can require a closer arrival; the warning and regen fade still apply.
		point = d.pick_player_platform(world, 0.0, float(rules.spawn_distance), true)
	if point.z >= -1.0 or since < 0.0 or world.time - since < float(rules.arrival_fallback) - 1e-6:
		return {"point": point, "fallback": false}
	var near := world.fhm.nearest_floor_point(world.player.pos)
	if near.z < 0.0:
		return {"point": point, "fallback": false}
	point = d.pick_player_platform(world, float(rules.min_spawn_distance), float(rules.spawn_distance), true, 0, near)
	if point.z < -1.0:
		point = d.pick_player_platform(world, 0.0, float(rules.spawn_distance), true, 0, near)
	return {"point": point if point.z >= -1.0 else near, "fallback": true}


func _warn(index: int, world: RunWorld) -> void:
	records[index].warned = true
	world.emit("boss_warning", {"boss_index": index, "mob_id": int(entries[index].mob_id), "time": world.time})


## No arrival point this tick: arrive warning_time from now, after a fresh warning.
func _postpone(index: int, world: RunWorld) -> void:
	if float(records[index].get("postponed_since", -1.0)) < 0.0:
		records[index].postponed_since = world.time
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
		var found := _point(world, float(record.get("relocate_since", -1.0)))
		var point: Vector3 = found.point
		if point.z < -1:
			if float(record.get("relocate_since", -1.0)) < 0.0:
				record.relocate_since = world.time
			return
		if record.has("relocate_since"):
			record.relocate_since = -1.0
		if bool(found.fallback):
			record.fallback = true
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


## Seconds between casts of MobSkill `skill_id` for boss `index`: its stage entry's `skill_intervals`
## {"<skill id>": seconds} override (tier C, e.g. Shade's Banish 15 s, #256), else `fallback` (the canonical WZ interval).
func skill_interval(index: int, skill_id: int, fallback: float) -> float:
	var overrides: Variant = entries[index].get("skill_intervals", {})
	if overrides is Dictionary and (overrides as Dictionary).has(str(skill_id)):
		return float(overrides[str(skill_id)])
	return fallback


## Survivor reward configuration: each scheduled entry may override the shared boss reward defaults.
func reward_config(index: int) -> Dictionary:
	var defaults: Dictionary = rules.get("rewards", {})
	return defaults.merged(entries[index].get("rewards", {}), true) if index >= 0 and index < entries.size() else defaults


## A scheduled boss's final form (stages.json `final_form`, one of the shell's canonical `info/revive` mobs): when the
## shell in `source` dies, the SAME encounter carries on with the form at `pos`: same boss_index, steady flag and
## attacks, HP `final_form_hp_mult` (default: the entry's hp_mult, tier C). The shell pays no reward and is not marked
## dead; only the form's death ends the encounter. Returns false (nothing happens, ordinary death rules apply) when the
## entry has no final form, the dying mob already is the form, the form is not in the shell's revive list, or no slot is
## free. The shell's other revive entries are not spawned.
func continue_final_form(index: int, source: int, pos: Vector2, world: RunWorld) -> bool:
	if index < 0 or index >= entries.size():
		return false
	var entry: Dictionary = entries[index]
	var final_id := int(entry.get("final_form", 0))
	var record: Dictionary = records[index]
	if final_id <= 0 or int(record.mob_id) == final_id or bool(record.dead):
		return false
	var revive: Dictionary = world.mob_img(int(record.mob_id)).get("info", {}).get("revive", {})
	if not final_id in StageRoster.list_ids(revive):
		return false
	var hp_mult := float(entry.get("final_form_hp_mult", entry.get("hp_mult", 1.0)))
	var slot := world.spawn_boss(final_id, index, pos, world.swarm.fh[source], hp_mult)
	if slot < 0:
		return false
	var shell_id := int(record.mob_id)
	record.slot = slot
	record.identity = world.swarm.identity[slot]
	record.mob_id = final_id
	# The swap time: skill schedules start from it (MobSkillRunner), and telemetry reports it as `form_time`.
	record.form_time = world.time
	world.mob_skills.reset_boss(index)
	# Tier C (#453): the form freezes its own level-scale damage at its own arrival (its HP, defence and EXP were
	# captured by spawn_boss); `level_scale_at` keeps the encounter's first arrival.
	world.capture_boss_level_scale(index, final_id, record)
	record.anchor = pos
	record.stall = 0.0
	record.best_distance = INF
	_actions[index] = {"action": "", "start": world.time, "until": world.time, "facing": -1}
	world.emit("mob_revives_spawned", {"boss_index": index, "mob": source, "mob_id": shell_id, "pos": pos,
		"revives": [{"mob": slot, "mob_id": final_id}], "time": world.time})
	return true
