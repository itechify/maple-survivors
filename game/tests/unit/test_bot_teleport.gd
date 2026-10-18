extends TestCase
## Seeded autoplay escape decisions preserve combat MP and leave time for ordinary kiting.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _cornered_world(job := 210) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 200
	# Synthetic fixed pool makes reserve boundaries independent of advancement bonuses.
	data.jobs_survivor.jobs[str(job)].grants.max_mp = 0
	var setup := RF.setup("quiet", 60, data)
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	var w := RunWorld.new(setup)
	w.change_job(job)
	w.heal_fraction("mp", 1.0)
	w.learn_skill({210: "teleport_fp", 220: "teleport_il", 230: "teleport_cleric"}[job])
	w.player.place(Vector2(20, 0), w.fhm)
	RF.put_mob(w, 100100, 48, 0, 100000)
	w.drain_events()
	return w


func test_cornered_bot_keeps_quarter_pool_after_teleport_payment() -> void:
	for job: int in [210, 220, 230]:
		var w := _cornered_world(job)
		assert_eq(int(w.player_state.max_mp), 200)
		w.spend_mp(91) # 109 MP: paying 60 would leave 49, below the 50-MP reserve.
		assert_false(BotInput.decide(w, {}).skill_pressed("teleport"), "protect the reserve on every branch")
		w.heal_fraction("mp", 1.0)
		w.spend_mp(90) # Exactly 110 can pay and retain 50.
		var input := BotInput.decide(w, {})
		assert_true(input.skill_pressed("teleport"), "ample MP still permits the scripted corner escape")
		assert_true(input.right)
		w.step(DT, input)
		assert_eq(w.player.pos, Vector2(150, 0))
		assert_eq(int(w.player_state.mp), 47, "50 retained for combat; the starter attack then spends 3")


func test_bot_reserves_two_casts_of_most_expensive_learned_auto_attack() -> void:
	var w := _cornered_world(220)
	w.learn_skill("cold_beam")
	w.learn_skill("thunder_bolt")
	w.loadout.set_rank("thunder_bolt", 30) # Synthetic canonical endpoint: 40 MP per cast.
	w.spend_mp(61) # 139 - 60 = 79, less than two 40-MP casts (and greater than the 50-MP pool floor).
	assert_false(BotInput.decide(w, {}).skill_pressed("teleport"))
	w.heal_fraction("mp", 1.0)
	w.spend_mp(60)
	assert_true(BotInput.decide(w, {}).skill_pressed("teleport"), "exactly 80 MP retained is sufficient")


func test_bot_waits_five_simulation_seconds_between_escape_requests() -> void:
	var w := _cornered_world()
	# The mob is re-placed on the character every tick for five seconds; with the shrinking hit window (#88) that
	# would kill it. The test is about the escape cooldown, not about surviving the contact.
	w.god = true
	var memo := {}
	var input := BotInput.decide(w, memo)
	assert_true(input.skill_pressed("teleport"))
	w.step(DT, input)
	for tick in 299:
		# Keep the same emergency and ample MP; only elapsed fixed ticks should admit another escape.
		w.player.place(Vector2(20, 0), w.fhm)
		w.swarm.x[0] = 48
		w.swarm.y[0] = 0
		w.heal_fraction("mp", 1.0)
		input = BotInput.decide(w, memo)
		assert_false(input.skill_pressed("teleport") or input.skill_held("teleport"), "wait despite a persistent threat")
		w.step(DT, MoveInput.new())
	w.player.place(Vector2(20, 0), w.fhm)
	w.swarm.x[0] = 48
	w.swarm.y[0] = 0
	w.heal_fraction("mp", 1.0)
	input = BotInput.decide(w, memo)
	assert_true(input.skill_pressed("teleport"), "the same emergency permits another escape at five seconds")


func test_bot_saves_teleport_for_same_height_threats_or_a_surrounding_crowd() -> void:
	var w := _cornered_world()
	w.swarm.x[0] = 160 # 140 px away on the open side: ordinary kiting, not an imminent edge hit.
	assert_false(BotInput.decide(w, {}).skill_pressed("teleport"))
	w.swarm.x[0] = 48
	w.swarm.y[0] = -120 # A mob on another platform should not prompt an emergency blink.
	assert_false(BotInput.decide(w, {}).skill_pressed("teleport"))
	w.swarm.y[0] = 0
	w.player.place(Vector2(400, 0), w.fhm)
	w.swarm.x[0] = 450
	assert_true(BotInput.decide(w, {}).skill_pressed("teleport"), "imminent same-height threat away from edges")
	w.swarm.x[0] = 500
	assert_false(BotInput.decide(w, {}).skill_pressed("teleport"), "one distant mob leaves a retreat route")
	RF.put_mob(w, 100100, 300, 0, 100000)
	assert_true(BotInput.decide(w, {}).skill_pressed("teleport"), "mobs within flee distance on both sides corner the bot")
