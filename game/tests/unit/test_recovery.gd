extends TestCase
## Recovery's canonical costs, six-pulse HoT, HP threshold and cooldown through seeded RunWorld ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(rank_value: int, threshold: float = 0.5) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 1000
	data.balance.regen.hp = 0
	data.skills.skills.recovery.buff.hp_threshold = threshold
	var w := RunWorld.new(RF.setup("quiet", 13, data))
	RF.place_player(w, 400)
	w.learn_skill("recovery")
	w.loadout.set_rank("recovery", rank_value)
	w.drain_events()
	return w


func test_each_recovery_level_heals_six_pulses_including_the_expiry_tick() -> void:
	for example: Array in [[1, 4], [2, 8], [3, 12]]:
		var w := _world(example[0])
		w.take_hit(800, false, "", w.player.pos + Vector2(10, 0))
		w.god = true
		var hp := int(w.player_state.hp)
		w.step(DT, MoveInput.new())
		assert_eq(w.player_state.get("buffs", []).size(), 1, "low HP starts Recovery")
		if w.player_state.get("buffs", []).is_empty():
			continue
		w.drain_events()
		for pulse in range(1, 7):
			for i in 299:
				w.step(DT, MoveInput.new())
			assert_eq(w.player_state.hp, hp + (pulse - 1) * int(example[1]), "no healing before pulse %d" % pulse)
			w.step(DT, MoveInput.new())
			assert_eq(w.player_state.hp, hp + pulse * int(example[1]))
		assert_true(w.player_state.buffs.is_empty())
		var events := w.drain_events()
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "buff_pulse").size(), 6)
		assert_eq(events[-2].type, "buff_pulse", "sixth pulse precedes expiry at 30 seconds")
		assert_eq(events[-1].type, "buff_expired")


func test_recovery_threshold_is_data_driven_and_cooldown_is_120_seconds_from_cast() -> void:
	for threshold: float in [0.5, 0.8]:
		var w := _world(1, threshold)
		w.take_hit(400, false, "", w.player.pos + Vector2(10, 0))
		w.step(DT, MoveInput.new())
		assert_eq(w.player_state.buffs.size(), 0 if threshold == 0.5 else 1, "data changes the low-HP trigger")
	var w := _world(1)
	w.take_hit(800, false, "", w.player.pos + Vector2(10, 0))
	w.god = true
	w.step(DT, MoveInput.new())
	for i in 7200 - 1:
		w.step(DT, MoveInput.new())
	assert_true(w.player_state.buffs.is_empty(), "30 s HoT does not recast during the remaining cooldown")
	w.step(DT, MoveInput.new())
	assert_eq(w.player_state.buffs.size(), 1, "recasts at canonical 120 s when still below threshold")


func test_recovery_does_not_cast_on_a_rope_but_existing_healing_continues() -> void:
	var w := _world(3)
	RF.place_player(w, -100)
	w.step(DT, MoveInput.make(false, false, true))
	w.take_hit(800, false, "", w.player.pos + Vector2(10, 0))
	w.step(DT, MoveInput.new())
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	assert_true(w.player_state.buffs.is_empty())
	var hp := int(w.player_state.hp)
	# Cast first in a fresh run, then hold still on the rope for the full HoT.
	w = _world(3)
	w.take_hit(800, false, "", w.player.pos + Vector2(10, 0))
	RF.place_player(w, 400)
	w.step(DT, MoveInput.new())
	hp = int(w.player_state.hp)
	# Let the hit's movement lock end before grabbing; all six healing pulses still happen on the rope.
	for i in 20:
		w.step(DT, MoveInput.new())
	RF.place_player(w, -100)
	w.step(DT, MoveInput.make(false, false, true))
	for i in 1779:
		w.step(DT, MoveInput.new())
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	assert_eq(w.player_state.hp, hp + 72, "six canonical L3 pulses continue while hanging")
	assert_true(w.player_state.buffs.is_empty())

