extends TestCase
## The headless profiler must execute production ticks, including Final Attack, Hidden and current physical defense.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const PR := preload("res://tools/profile_run.gd")
const DT := 1.0 / 60.0


func _world(mode: String) -> RunWorld:
	var w := CF.ranged_final(1452004, 310, 40)
	var mob := RF.put_mob(w, 1110100, w.player.pos.x + 60, w.player.pos.y, 1000000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	if mode == "final":
		w.hit_mob(mob, {"skill": "fixture", "damage_type": "physical", "damage_min": 100.0,
			"damage_max": 100.0, "crit": 0.0, "crit_mult": 1.5}, -1)
		assert_eq(w._final_queue.size(), 1, "guaranteed queued Final Attack")
	elif mode == "hidden":
		w.mob_kinds[w.swarm.kind[mob]].move_speed = 100.0
		w.start_buff("hidden_fixture", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 0.5,
			"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
		assert_true(w.is_hidden())
	else:
		w.mob_kinds[w.swarm.kind[mob]].pdd = 100
		assert_true(w.swarm.apply_status(mob, "threatened", {"x": 0, "y": -90, "time": 2}, w.events))
		assert_eq(w.mob_defense(mob, false), 10.0)
		w.projectiles.spawn({"x": w.swarm.x[mob], "y": w.swarm.y[mob] - 10, "vx": 600,
			"range": 600, "radius": 1, "dmg_min": 100, "dmg_max": 100, "damage_type": "physical",
			"skill": "fixture", "crit": 0.0})
	w.drain_events()
	return w


## Freeze every script-owned state field plus native RNG state, replacing object identities with traversal indices.
func _plain(value: Variant, seen: Dictionary) -> Variant:
	if value is RandomNumberGenerator:
		return ["rng", value.seed, value.state]
	if value is Object:
		if seen.has(value):
			return ["ref", seen[value]]
		seen[value] = seen.size()
		var fields := {}
		for property: Dictionary in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields[property.name] = _plain(value.get(property.name), seen)
		return fields
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_plain(item, seen))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _plain(value[key], seen)
		return out
	if value is Callable:
		return value.is_valid()
	return value


func _compare(mode: String) -> void:
	var normal := _world(mode)
	var profiled := _world(mode)
	var acc := PackedInt64Array()
	acc.resize(PR.PARTS.size())
	var coverage := {}
	for tick in 90:
		var input := MoveInput.make(tick >= 45, tick < 45)
		normal.step(DT, input)
		PR._timed_step(profiled, DT, input, acc)
		var events := normal.drain_events()
		var instrumented_events := profiled.drain_events()
		assert_true(var_to_bytes(instrumented_events) == var_to_bytes(events), "%s event bytes tick %d" % [mode, tick])
		for event: Dictionary in events:
			coverage[event.type] = true
		var a := var_to_bytes(_plain(normal, {}))
		var b := var_to_bytes(_plain(profiled, {}))
		if a != b:
			fail("%s full state/RNG bytes diverged at tick %d" % [mode, tick])
			return
	if mode == "final":
		assert_has(coverage, "final_attack")
		assert_has(coverage, "ammo_shot")
	elif mode == "hidden":
		assert_has(coverage, "buff_expired")
	else:
		assert_has(coverage, "mob_hit")
	assert_eq(normal.time, profiled.time)


func test_profile_tick_drains_queued_final_attacks_identically() -> void:
	_compare("final")


func test_profile_tick_propagates_hidden_identically() -> void:
	_compare("hidden")


func test_profile_tick_uses_live_projectile_pdd_identically() -> void:
	_compare("pdd")
