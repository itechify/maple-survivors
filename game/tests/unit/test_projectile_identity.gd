extends TestCase
## Piercing shots follow logical mob identity across natural death, pool reuse and world relocation.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(seed_value: int = 778) -> RunWorld:
	var w := RF.quiet_world(400.0, seed_value)
	w.god = true
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	w.drain_events()
	return w


func _target(w: RunWorld, id: int, x: float) -> int:
	var slot := RF.put_mob(w, id, x, 190, 20)
	w.mob_kinds[w.swarm.kind[slot]].move_speed = 0.0
	return slot


func _shot(w: RunWorld, mob: int, damage: float, damage_max: float = 0.0) -> int:
	var kind: MobKind = w.mob_kinds[w.swarm.kind[mob]]
	var body := kind.hitbox_at(w.swarm.x[mob], w.swarm.y[mob], w.swarm.facing[mob])
	return w.projectiles.spawn({"x": body.get_center().x, "y": body.get_center().y,
		"vx": 400.0, "vy": 0.0, "range": 1000.0, "radius": 10.0,
		"dmg_min": damage, "dmg_max": damage_max if damage_max > 0.0 else damage,
		"pierce": 1, "magic": false, "skill": "three_snails"})


func test_piercing_shell_can_hit_a_fresh_mob_reusing_a_naturally_freed_slot() -> void:
	var w := _world()
	var first := _target(w, 100100, 550)
	var shot := _shot(w, first, 1000.0)
	w.step(DT, MoveInput.new())
	assert_eq(w.swarm.state[first], MobSwarm.DIE)
	for tick in 120:
		if w.swarm.state[first] == MobSwarm.FREE:
			break
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.state[first], MobSwarm.FREE, "the ordinary death animation returns the original slot")
	assert_eq(w.projectiles.active[shot], 1, "the piercing shell still has range and one hit left")
	var fresh := _target(w, 100101, w.projectiles.x[shot] + 80.0)
	assert_eq(fresh, first, "exercise actual free-list reuse")
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[fresh], 0, "new occupant is a different mob and can be hit")
	assert_eq(w.projectiles.active[shot], 0, "second logical-mob hit consumes the remaining pierce")
	assert_eq(w.kills, 2)


func test_relocation_preserves_once_per_mob_exclusion_and_the_remaining_pierce() -> void:
	var w := _world()
	var target := _target(w, 100100, 550)
	var shot := _shot(w, target, 1.0)
	w.step(DT, MoveInput.new())
	var hp := w.swarm.hp[target]
	var identity := w.swarm.identity[target]
	var fh := w.fhm.find_below(650, 190)
	var moved := w.relocate_mob(target, Vector2(650, w.fhm.y_at(fh, 650)), fh)
	assert_eq(w.swarm.identity[moved], identity, "moving an existing entity retains its logical identity")
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[moved], hp, "the same shell cannot hit this relocated mob a second time")
	assert_eq(w.projectiles.active[shot], 1, "repeat contact did not consume the last pierce")
	var fresh := _target(w, 100101, w.projectiles.x[shot] + 80.0)
	var fresh_hp := w.swarm.hp[fresh]
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[fresh], fresh_hp - 1, "the unused pierce still hits a different entity")
	assert_eq(w.projectiles.active[shot], 0)


func _trace(seed_value: int) -> Dictionary:
	var w := _world(seed_value)
	var first := _target(w, 100100, 550)
	var original_identity := w.swarm.identity[first]
	var shot := _shot(w, first, 10.0, 20.0)
	w.step(DT, MoveInput.new())
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	var fh := w.fhm.find_below(650, 190)
	var moved := w.relocate_mob(first, Vector2(650, w.fhm.y_at(fh, 650)), fh)
	var moved_identity := w.swarm.identity[moved]
	for tick in 30:
		w.step(DT, MoveInput.new())
	hits.append_array(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit"))
	w.swarm.despawn(moved)
	var fresh := _target(w, 100101, w.projectiles.x[shot] + 80.0)
	for tick in 30:
		w.step(DT, MoveInput.new())
	hits.append_array(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit"))
	return {"hits": hits, "identities": [original_identity, moved_identity, w.swarm.identity[fresh]],
		"hp": w.swarm.hp[fresh], "shots": w.projectiles.active_count()}


func test_seeded_twins_replay_hit_exclusion_through_relocation_and_slot_reuse() -> void:
	var trace := _trace(971)
	assert_eq(trace, _trace(971))
	assert_eq(trace.hits.size(), 2, "one original entity hit and one fresh entity hit")
	assert_eq(trace.identities[0], trace.identities[1])
	assert_true(trace.identities[2] > trace.identities[0])
	assert_eq(trace.shots, 0)
	for event: Dictionary in trace.hits:
		assert_between(int(event.damage), 10, 20, "seeded damage rolls remain within the supplied range")


func test_fresh_identities_are_unique_after_pool_growth_and_reuse() -> void:
	var w := _world()
	var original_capacity := w.swarm.capacity()
	var identities := {}
	var previous := 0
	var first := -1
	for i in original_capacity + 1:
		var slot := _target(w, 100100, 1500)
		if first < 0:
			first = slot
		var identity := w.swarm.identity[slot]
		assert_true(identity > previous, "new logical spawns increase their identity")
		assert_false(identities.has(identity))
		identities[identity] = true
		previous = identity
	assert_true(w.swarm.capacity() > original_capacity)
	assert_true(identities.has(w.swarm.identity[first]), "growing the pool retained its first occupant's identity")
	w.swarm.despawn(first)
	var fresh := _target(w, 100100, 1500)
	assert_eq(fresh, first)
	assert_true(w.swarm.identity[fresh] > previous)
	assert_false(identities.has(w.swarm.identity[fresh]))
