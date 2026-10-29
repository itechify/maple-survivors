class_name BurstCast
extends RefCounted
## Fixed-tick channelled projectile casts. Owns only cold cast snapshots and logical target identities.
var _entries: Array[Dictionary] = []

## Drops unfinished bursts at a map boundary, without touching cooldowns or launched projectiles.
func clear() -> void:
	_entries.clear()

## Whether this skill still has shots scheduled, independently of its cooldown.
func has_skill(key: String) -> bool:
	for entry in _entries:
		if String(entry.key) == key:
			return true
	return false

## Seconds from admission to the last shot of a burst of resolved stats `st` (wind-up plus the gaps between its shots).
static func span(st: Dictionary, params: Dictionary) -> float:
	return maxf(0.0, float(params.get("wind_up", 0.0))) \
		+ maxi(0, int(st.get("count", 1)) - 1) * maxf(0.0, float(params.get("interval", 0.0)))

## Starts one burst and releases a zero-wind-up first shot on the admission tick.
func start(world: RunWorld, key: String, st: Dictionary, target: int) -> void:
	var params: Dictionary = world.book.def(key).get("burst", {})
	# tier C: unspecified wind-up/overshoot are zero, retarget defaults true; zero interval releases all due shots.
	var entry := {"key": key, "st": SkillRunner.cast_snapshot(st), "params": params.duplicate(true),
		"left": int(st.count), "age": 0.0, "next": maxf(0.0, float(params.get("wind_up", 0.0))),
		"target": target, "identity": world.swarm.identity[target]}
	_entries.append(entry)
	_release(world, entry)
	if int(entry.left) <= 0:
		_entries.erase(entry)

## Advances existing bursts before admitting new casts. Hidden and death cancel remaining shots (tier C).
func step(dt: float, world: RunWorld) -> void:
	if world.is_hidden() or bool(world.player_state.dead):
		clear()
		return
	var i := 0
	while i < _entries.size():
		var entry := _entries[i]
		entry.age = float(entry.age) + dt
		_release(world, entry)
		if int(entry.left) <= 0:
			_entries.remove_at(i)
		else:
			i += 1

func _release(world: RunWorld, entry: Dictionary) -> void:
	while int(entry.left) > 0 and float(entry.age) + 1e-9 >= float(entry.next):
		var st: Dictionary = entry.st
		var params: Dictionary = entry.params
		var origin := world.cast_origin()
		var target := int(entry.target)
		var reach := float(st.range) + maxf(0.0, float(params.get("overshoot", 0.0)))
		var valid := world.swarm.is_live(target) and world.swarm.identity[target] == int(entry.identity)
		if valid:
			valid = world.mob_center(target).distance_squared_to(origin) <= reach * reach
		if not valid:
			# tier C: no eligible replacement (or retarget disabled) drops the rest without refund.
			var plan := world.runner.prepare_cast(world, String(entry.key), st, origin) \
				if bool(params.get("retarget", true)) else {}
			if plan.is_empty():
				entry.left = 0
				return
			target = int(plan.targets[0])
			entry.target = target
			entry.identity = world.swarm.identity[target]
		world.runner.fire_shot(world, String(entry.key), st, origin, world.mob_center(target))
		entry.left = int(entry.left) - 1
		entry.next = float(entry.next) + maxf(0.0, float(params.get("interval", 0.0)))
