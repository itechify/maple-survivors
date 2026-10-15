extends TestCase
## Stumpy's canonical-shaped projectile, delayed slam and heal through a fixed-tick seeded world.
const SF := preload("res://tests/fixtures/stumpy_fixtures.gd")
const DT := 1.0 / 60.0


func _projectile(w: RunWorld) -> Dictionary:
	for tick in 600:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "mob_projectile_spawned":
				return event
	fail("Stumpy should launch the canonical type2 ball after its windup")
	return {}


func test_stumpy_projectile_uses_wz_speed_and_range_then_expires() -> void:
	var w := RunWorld.new(SF.setup())
	w.god = true
	var event := _projectile(w)
	if event.is_empty():
		return
	assert_near(float(event.speed), 233.333333, 1e-4, "140 bulletSpeed uses the documented 600 ms unit interpretation")
	assert_eq(event.range, 200.0)
	var slot := int(event.proj)
	var from := Vector2(w.mob_projectiles.x[slot], w.mob_projectiles.y[slot])
	w.player.place(Vector2(-1800, 0), w.fhm)
	for tick in 10:
		w.step(DT, MoveInput.new())
	var to := Vector2(w.mob_projectiles.x[slot], w.mob_projectiles.y[slot])
	assert_near(to.distance_to(from), 38.888889, 0.01, "ten ticks of straight travel")
	for tick in 45:
		w.step(DT, MoveInput.new())
	assert_eq(w.mob_projectiles.active_count(), 0, "200 px travel range bounds its flight")


func test_stumpy_projectile_contact_uses_take_hit_and_preserves_source() -> void:
	var w := RunWorld.new(SF.setup())
	var launch := _projectile(w)
	if launch.is_empty():
		return
	var hit := {}
	for tick in 60:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "player_hit":
				hit = event
		if not hit.is_empty():
			break
	assert_false(hit.is_empty())
	if hit.is_empty():
		return
	assert_eq(hit.mob_id, 3220000)
	assert_true(hit.boss)
	assert_eq(hit.source_kind, "projectile")
	assert_between(int(hit.damage), 123, 146)
	assert_eq(int(w.player_state.hp), 300 - int(hit.damage))


func _heal_world(seed_value: int = 2402) -> RunWorld:
	var w := RunWorld.new(SF.heal_setup(seed_value))
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func test_stumpy_heal_waits_for_interval_hp_gate_and_canonical_effect_delay() -> void:
	var w := _heal_world()
	var slot := int(w.bosses.records[0].slot)
	# Full HP prevents casting even after the canonical first interval.
	for tick in 1800:
		w.step(DT, MoveInput.new())
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "boss_skill" and e.skill_id == 114))
	w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	var before := w.swarm.hp[slot]
	w.drain_events()
	w.step(DT, MoveInput.new())
	var cast_time := w.time
	var cast := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_skill" and e.skill_id == 114)
	assert_eq(cast.size(), 1, "eligible heal casts once its interval is ready and HP is at/below80%")
	for tick in 89:
		w.step(DT, MoveInput.new())
		assert_eq(w.swarm.hp[slot], before, "effectAfter1500ms delays restoration")
	w.step(DT, MoveInput.new())
	var healed := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_healed")
	assert_eq(healed.size(), 1)
	if healed.is_empty():
		return
	assert_between(int(healed[0].amount), 200, 700, "documented uniform interpretation of canonical y/x bounds")
	assert_eq(w.swarm.hp[slot], before + int(healed[0].amount))
	assert_near(float(healed[0].time) - cast_time, 1.5, DT)


func _heal_trace(seed_value: int) -> Array:
	var w := _heal_world(seed_value)
	var slot := int(w.bosses.records[0].slot)
	w.hit_mob(slot, {"damage_min": 1500.0, "damage_max": 1500.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	w.drain_events()
	var trace: Array = []
	for tick in 63 * 60:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "boss_skill" and event.skill_id == 114:
				trace.append({"cast": snappedf(w.time, 0.001)})
			elif event.type == "mob_healed":
				trace.append({"heal": int(event.amount), "time": snappedf(float(event.time), 0.001)})
	return trace


func test_heal_interval_and_random_amount_replay_are_deterministic() -> void:
	var first := _heal_trace(2403)
	assert_eq(first, _heal_trace(2403))
	assert_ne(first, _heal_trace(2404), "independent skill RNG varies amounts with the run seed")
	assert_eq(first.size(), 4, "two casts and two resolutions")
	if first.size() == 4:
		assert_eq(first[0].cast, 30.5)
		assert_eq(first[2].cast, 60.5)
		assert_eq(first[1].time, 32.0)
		assert_eq(first[3].time, 62.0)
		assert_between(first[1].heal, 200, 700)
		assert_between(first[3].heal, 200, 700)


func test_stumpy_slam_reuses_delayed_grounded_handler() -> void:
	var w := RunWorld.new(SF.setup(["attack1"]))
	var start := {}
	for tick in 180:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "boss_attack" and event.phase == "start":
				start = event
		if not start.is_empty():
			break
	assert_false(start.is_empty())
	if start.is_empty():
		return
	assert_near(float(start.impact_time) - float(start.time), 1.5, 1e-6)
	assert_eq(start.area.size, Vector2(543, 172))
	var hp := int(w.player_state.hp)
	for tick in 89:
		w.step(DT, MoveInput.new())
		assert_eq(int(w.player_state.hp), hp)
	w.step(DT, MoveInput.new())
	assert_between(hp - int(w.player_state.hp), 123, 146)
