extends TestCase
## Synthetic fixed-tick flight/FX tests: no window, real WZ cache or wall clock required.

const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

class FxSink extends FxRenderer:
	var bursts := 0
	var anchor := Vector2.ZERO
	func play_repeating(_path: String, pos: Vector2, _seconds: float, _flip: bool = false,
			_follow: Node2D = null, _offset: Vector2 = Vector2.ZERO) -> int:
		anchor = pos
		return 0
	func play(_path: String, _pos: Vector2, _flip: bool = false, _follow: Node2D = null,
			_offset: Vector2 = Vector2.ZERO, _hold: bool = false, _delay: float = 0.0) -> int:
		bursts += 1
		return 1
	func place(_slot: int, pos: Vector2, _angle: float = 0.0) -> void:
		anchor = pos
	func stop(_slot: int) -> void:
		pass

class ClockScene extends RunScene:
	var landed := 0
	var hits := 0
	var landing_tick := -1
	func _read_input(_first: bool) -> MoveInput:
		return MoveInput.new()
	func handle_events(batch: Array) -> void:
		for event: Dictionary in batch:
			if event.type == "skill_thrown" or event.type == "skill_landed":
				super.handle_events([event])
			if event.type == "skill_landed":
				landed += 1
				landing_tick = roundi(world.time / DT)
			elif event.type == "mob_hit":
				hits += 1
	func _present(delta: float) -> void:
		_update_throws(delta)
	func _automation() -> void:
		pass


func _scene(speed: int, flight_speed: float = 0.0) -> ClockScene:
	var s := ClockScene.new()
	s.fx = FxSink.new()
	s._speed = speed
	s.world = CF.world({"cast": {"rule": "cluster"}, "ball": "ball", "burst": "burst"})
	RF.put_mob(s.world, 1110100, 350, 190, 10000)
	s.world.mob_grid.rebuild(s.world.swarm.x, s.world.swarm.y, s.world.swarm.active)
	var st := s.world.runner.stats_of(s.world, "synthetic")
	if flight_speed > 0.0:
		st.speed = flight_speed
	s.world.runner._throw(s.world, "synthetic", st,
		{"landing": Vector2(350, 190), "aim": Vector2(350, 170)})
	s.handle_events(s.world.drain_events())
	# Only the explicitly scheduled flight is under test.
	s.world.runner.cooldowns.synthetic = 1000.0
	return s


func test_grenade_burst_waits_for_sim_landing_after_a_hitch_and_choice_hold() -> void:
	var landing_tick := -1
	for speed in [1, 4, 8]:
		var s := _scene(speed, 200.0)
		s.advance_frame(0.5 * speed)
		assert_near(s.world.time, 4 * speed * DT, 1e-6, "catch-up cap unchanged")
		assert_eq(s.world.runner._flights.size(), 1, "flight remains pending at every tested speed")
		assert_eq((s.fx as FxSink).bursts, 0, "hitch cannot burst a pending flight")
		var before := s.world.time
		var anchor := (s.fx as FxSink).anchor
		s.world.state = RunWorld.CHOOSING_UPGRADE
		for frame in 5:
			s.advance_frame(0.5)
		assert_eq(s.world.time, before, "choice holds the sim")
		assert_eq((s.fx as FxSink).anchor, anchor, "choice holds gameplay-bearing flight")
		assert_eq((s.fx as FxSink).bursts, s.landed, "only landing events can burst")
		s.world.state = RunWorld.PLAYING
		for frame in 60:
			s.advance_frame(DT)
			assert_eq((s.fx as FxSink).bursts, s.landed)
			assert_eq(s.hits, s.landed, "damage and burst are on the same authoritative tick")
		assert_eq(s.landed, 1)
		if landing_tick < 0:
			landing_tick = s.landing_tick
		assert_eq(s.landing_tick, landing_tick, "render speed preserves the authoritative landing tick")
		assert_eq(s._throws.size(), 0)
		s.fx.free()
		s.free()


func test_grenade_lands_and_stops_its_ball_even_if_no_targets_remain() -> void:
	var s := _scene(1)
	s.world.swarm.despawn(0)
	for frame in 60:
		s.advance_frame(DT)
	assert_eq(s.hits, 0)
	assert_eq(s.landed, 1, "landing is independent of the damage target list")
	assert_eq((s.fx as FxSink).bursts, 1)
	assert_eq(s._throws.size(), 0)
	s.fx.free()
	s.free()


func test_final_attack_ammo_keeps_its_visual_only_frame_clock() -> void:
	var s := _scene(1)
	s._throws.clear()
	s._on_ammo_shot({"from": Vector2.ZERO, "to": Vector2(100, 0), "seconds": 0.2,
		"ball": "ammo", "rotate": true})
	s._update_throws(0.5)
	assert_eq(s._throws.size(), 0, "visual-only ammo completes without sim ticks")
	assert_eq((s.fx as FxSink).bursts, 0)
	s.fx.free()
	s.free()


func test_grenade_legacy_events_damage_and_rng_bytes_are_unchanged() -> void:
	var s := _scene(1)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for tick in 90:
		s.world.step(DT, MoveInput.new())
		var legacy: Array = []
		for event: Dictionary in s.world.drain_events():
			if event.type != "skill_landed":
				legacy.append(event)
		digest.update(var_to_bytes([legacy, s.world.player_state, s.world.swarm.hp,
			s.world.rng.state, s.world.final_rng.state, s.world.pirate_rng.state]))
	# Re-captured for #238: player_state.potions now carries cooldowns instead of stock.
	# Re-captured for #284 + #285: a fresh character is job 212, not the Beginner (job_id and the job-based accuracy in
	# player_state, so crit odds; no basic attack in the fixture world), and there is no MP (no MP fields or potion).
	# #293: selected EXP/cooldowns change player-state/event bytes; mechanic assertions remain unchanged.
	assert_eq(digest.finish().hex_encode(), "d57e2e920a7170e6a68ee0b8d6aa1299578590dd7c0b31d2d85e22f76678252d",
		"pre-fix legacy event/damage/RNG bytes; only the new landing event is excluded")
	s.fx.free()
	s.free()
