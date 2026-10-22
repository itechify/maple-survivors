extends TestCase
## Boss relocation on missing routes or stalled pursuit, and harmless fade-in, through seeded RunWorld ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 1000
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000}])
	var setup := RF.setup("quiet", 20, data)
	setup.map_img = RF.map_from_segments([
		{"x1": -1000, "y1": 200, "x2": 1000, "y2": 200},
		{"x1": -1000, "y1": -100, "x2": 1000, "y2": -100}], [Vector2(0, 200)])
	var w := RunWorld.new(setup)
	w.god = true
	for i in 30:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func test_no_route_and_no_progress_trigger_a_faded_platform_teleport_after_five_seconds() -> void:
	for no_route: bool in [false, true]:
		var w := _world()
		var slot := int(w.bosses.records[0].slot)
		w.mob_kinds[w.swarm.kind[slot]].move_speed = 0
		if no_route:
			w.player.place(Vector2(0, -100), w.fhm)
		var old_hp := w.swarm.hp[slot]
		var start := w.time
		for i in 290:
			w.step(DT, MoveInput.new())
			assert_true(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_teleported").is_empty())
		var faded := false
		var teleport := {}
		for i in 50:
			w.step(DT, MoveInput.new())
			faded = faded or w.swarm.alpha[slot] < 1.0
			for e: Dictionary in w.drain_events():
				if e.type == "boss_teleported":
					teleport = e
			if not teleport.is_empty():
				break
		assert_false(teleport.is_empty(), "stalled/no-route boss teleports")
		if teleport.is_empty():
			continue
		assert_true(faded, "relocation fades out rather than disappearing at full alpha")
		assert_near(float(teleport.time) - start, 5.3, 0.15, "five seconds of stall plus 300 ms fade-out")
		slot = int(teleport.mob)
		assert_eq(w.swarm.hp[slot], old_hp)
		assert_eq(w.fhm.platform_of(w.swarm.fh[slot]), w.player_platform())
		assert_near(Vector2(w.swarm.x[slot], w.swarm.y[slot]).distance_to(w.player.pos), 250, 1)
		w.player.place(Vector2(w.swarm.x[slot], w.swarm.y[slot]), w.fhm)
		w.god = false
		var hp := int(w.player_state.hp)
		for i in 17:
			w.step(DT, MoveInput.new())
			assert_eq(w.player_state.hp, hp, "fade-in is harmless")
		w.step(DT, MoveInput.new())
		assert_true(w.swarm.alpha[slot] >= 1.0)
		assert_true(int(w.player_state.hp) < hp, "opaque boss can touch the player")


func test_a_boss_that_closes_the_distance_or_is_already_at_the_player_does_not_teleport() -> void:
	var w := _world()
	for i in 60 * 12:
		w.step(DT, MoveInput.new())
		assert_true(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_teleported").is_empty(),
			"normal pursuit/contact never triggers the stuck-boss rule")
