extends TestCase
## H11 job-local HP tuning through round startup and fixed-tick level growth.
const RF := preload("res://tests/fixtures/run_fixtures.gd")

func test_job_ap_row_can_set_starting_hp_without_changing_other_jobs() -> void:
	var data := RF.quiet_data()
	data.balance.player.ap["112"]["hp"] = 300
	for job in [112, 212]:
		var setup := RF.setup("quiet", 346, data)
		setup.job = job
		var w := RunWorld.new(setup)
		assert_eq(w.player_state.max_hp, 300 if job == 112 else 50)
		assert_eq(w.player_state.hp, w.player_state.max_hp)
		w.step(1.0 / 60.0, MoveInput.new())
		assert_eq(w.player_state.max_hp, 300 if job == 112 else 50)

func test_job_starting_hp_is_retained_when_a_real_pickup_applies_growth() -> void:
	var data := RF.quiet_data()
	data.balance.player.ap["112"]["hp"] = 300
	data.balance.growth["112"] = {"hp": 65}
	var setup := RF.setup("quiet", 346, data)
	setup.job = 112
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(1.0 / 60.0, MoveInput.new())
		if w.progression.level == 2:
			break
	assert_eq(w.progression.level, 2)
	assert_eq(w.player_state.max_hp, 365)
	assert_eq(w.player_state.hp, 300, "growth raises capacity, without refilling")
