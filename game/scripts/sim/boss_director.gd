class_name BossDirector
extends RefCounted
## Scheduled touch-only bosses, their warning/arrival/death events and the run's boss-clear condition.

## tier C: survivor encounter defaults; balance.bosses supplies the design values.
const DEFAULT_RULES := {"warning_time": 3.0, "spawn_distance": 250.0,
	"min_spawn_distance": 150.0, "normal_spawn_mult": 0.5}

var entries: Array = []
## Schedule-order records: boss_index, mob_id, slot, warned, spawn_time, death_time, dead.
var records: Array = []
var rules: Dictionary = {}


func _init(p_entries: Array = [], p_rules: Dictionary = {}) -> void:
	entries = p_entries.duplicate(true)
	rules = DEFAULT_RULES.merged(p_rules, true)
	for index in entries.size():
		records.append({"boss_index": index, "mob_id": int(entries[index].mob_id), "slot": -1,
			"warned": false, "spawn_time": -1.0, "death_time": -1.0, "dead": false})


## Whether this stage has an encounter schedule (empty schedules retain duration-based clears).
func has_bosses() -> bool:
	return not entries.is_empty()


## Fires each warning and places each due boss on the player's reachable platform, with regen fade-in.
func step(world: RunWorld) -> void:
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var record: Dictionary = records[index]
		if float(record.spawn_time) >= 0.0 or bool(record.dead):
			continue
		var arrival := float(entry.time)
		if not bool(record.warned) and world.time >= arrival - float(rules.warning_time) - 1e-6:
			record.warned = true
			world.emit("boss_warning", {"boss_index": index, "mob_id": int(entry.mob_id), "time": world.time})
		if world.time < arrival - 1e-6 or not world.kind_of_id.has(int(entry.mob_id)):
			continue
		var point := world.director.pick_player_platform(world, float(rules.min_spawn_distance),
			float(rules.spawn_distance), true)
		if point.z < -1.0:
			# A narrow platform can require a closer arrival; the warning and regen fade still apply.
			point = world.director.pick_player_platform(world, 0.0, float(rules.spawn_distance), true)
		if point.z < -1.0:
			continue
		var slot := world.spawn_mob(int(world.kind_of_id[int(entry.mob_id)]), Vector2(point.x, point.y),
			int(point.z), float(entry.get("hp_mult", 1.0)), false)
		if slot < 0:
			continue
		world.mob_boss[slot] = index
		record.slot = slot
		record.spawn_time = world.time
		world.emit("boss_spawned", {"boss_index": index, "mob": slot, "mob_id": int(entry.mob_id),
			"pos": Vector2(world.swarm.x[slot], world.swarm.y[slot]), "time": world.time})


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


## True only after every scheduled boss has spawned and died.
func all_dead() -> bool:
	if records.is_empty():
		return false
	for record: Dictionary in records:
		if not bool(record.dead):
			return false
	return true


## Multiplier for ordinary spawning while at least one boss is alive.
func normal_spawn_multiplier() -> float:
	return float(rules.normal_spawn_mult) if live_count() > 0 else 1.0


## Explicit damage multiplier for a scheduled boss's hits.
func damage_multiplier(index: int) -> float:
	return float(entries[index].get("dmg_mult", 1.0)) if index >= 0 and index < entries.size() else 1.0
