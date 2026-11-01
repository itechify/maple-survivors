extends TestCase
## Synthetic fixed-tick burst contracts through SkillRunner and the projectile pool.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

func _world(wind_up: float = 0.4, count: int = 3) -> RunWorld:
	var w := RunWorld.new(RF.setup("quiet", 336, RF.quiet_data()))
	RF.place_player(w, 200)
	w.loadout.order.clear()
	var d := w.book.def("energy_bolt").duplicate(true)
	d.cast = {"rule": "burst"}
	d.burst = {"interval": 0.1, "wind_up": wind_up, "retarget": true}
	d.count = count
	d.cooldown = 6.0
	d.range = 450.0
	w.book.defs["stream"] = d
	w.data.jobs_survivor.jobs["212"].skill_pool.append("stream")
	w.learn_skill("stream")
	_mob(w, 400)
	return w

func _mob(w: RunWorld, x: float) -> int:
	var m := RF.put_mob(w, 1110100, x, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _shots(w: RunWorld) -> int:
	return w.projectiles.active.count(1)

func _ticks(w: RunWorld, n: int) -> void:
	for i in n:
		w.runner.step(DT, w)

func test_wind_up_interval_and_single_cast_event() -> void:
	var w := _world()
	_ticks(w, 1)
	assert_eq(w.runner.casts, 1)
	assert_true(float(w.runner.cooldowns.stream) > 5.9)
	assert_eq(_shots(w), 0)
	_ticks(w, 23)
	assert_eq(_shots(w), 0)
	_ticks(w, 1)
	assert_eq(_shots(w), 1, "0.4 seconds after admission")
	_ticks(w, 5)
	assert_eq(_shots(w), 1)
	_ticks(w, 1)
	assert_eq(_shots(w), 2)
	_ticks(w, 6)
	assert_eq(_shots(w), 3)
	assert_eq(w.runner.casts, 1)

func test_moving_hand_and_current_target_aim_sticky_until_out_of_reach() -> void:
	var w := _world(0.0)
	var target := w.swarm.active.find(1)
	_ticks(w, 1)
	var near := _mob(w, 230)
	RF.place_player(w, 220)
	w.swarm.y[target] = 160
	_ticks(w, 6)
	var shot := 1
	var aim := w.mob_center(target)
	var hand := w.shot_origin(aim)
	assert_near(w.projectiles.x[shot], hand.x, 0.001)
	assert_near(w.projectiles.y[shot], hand.y, 0.001)
	var direction := (aim - hand).normalized()
	assert_near(w.projectiles.vy[shot], direction.y * float(w.loadout.stats("stream").speed), 0.01)
	w.swarm.x[target] = 1000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_ticks(w, 6)
	assert_eq(_shots(w), 3)
	assert_true(w.projectiles.vx[2] > 0, "replacement is the close mob on the right")
	assert_true(w.swarm.is_live(near))

func test_death_retargets_boss_first_then_no_target_drops_rest() -> void:
	var w := _world(0.0, 5)
	var first := w.swarm.active.find(1)
	_ticks(w, 1)
	_mob(w, 230)
	var boss := _mob(w, 100)
	w.mob_boss[boss] = 0
	w.swarm.despawn(first)
	_ticks(w, 6)
	assert_true(w.projectiles.vx[1] < 0, "scheduled boss before nearer ordinary mob")
	for i in w.swarm.active.size():
		if w.swarm.is_live(i):
			w.swarm.despawn(i)
	_ticks(w, 24)
	assert_eq(_shots(w), 2)
	assert_false(w.runner.bursts.has_skill("stream"))

func test_no_retarget_and_slot_reuse_do_not_keep_dead_target() -> void:
	var w := _world(0.0)
	w.book.defs.stream.burst.retarget = false
	var first := w.swarm.active.find(1)
	_ticks(w, 1)
	w.swarm.despawn(first)
	_mob(w, 300)
	_ticks(w, 12)
	assert_eq(_shots(w), 1)

func test_clear_death_and_hidden_cancel_unreleased_shots() -> void:
	for mode in ["clear", "dead", "hidden"]:
		var w := _world()
		_ticks(w, 1)
		match mode:
			"clear": w.runner.clear_pending()
			"dead": w.player_state.dead = true
			"hidden": w.buffs.start("hidden_test", {"skill_id": 0, "level": 1, "icon": "", "duration": 10.0, "buff_stat": "", "buff_value": 0.0, "hidden": true, "pulse_interval": 0.0})
		_ticks(w, 40)
		assert_eq(_shots(w), 0, mode)
		assert_false(w.runner.bursts.has_skill("stream"), mode)

func test_count_modifier_readiness_and_parallel_skills() -> void:
	var w := _world(0.0)
	w.loadout.add_skill_mod("stream", "count", "add", 1)
	var d: Dictionary = w.book.defs.stream.duplicate(true)
	w.book.defs["other"] = d
	w.data.jobs_survivor.jobs["212"].skill_pool.append("other")
	w.learn_skill("other")
	_ticks(w, 1)
	w.runner.cooldowns.stream = 0
	_ticks(w, 1)
	assert_eq(w.runner.casts, 2, "other skill starts while stream runs")
	assert_eq(_shots(w), 2)
	_ticks(w, 16)
	assert_eq(w.runner.casts, 2, "cooldown expired but stream still in flight")
	assert_eq(_shots(w), 6)
	w.runner.cooldowns.stream = 6
	_ticks(w, 1)
	assert_eq(_shots(w), 7, "count bonus adds the fourth arrow")

func test_rng_and_damage_match_single_nearest_shots_and_shared_meter_receipt() -> void:
	var a := _world(0.0)
	var b := _world(0.0)
	a.meter = PlayerMeter.new({"id": "test", "max": 10, "gain": {"event": "cast_landed", "amount": 1}})
	b.meter = PlayerMeter.new(a.meter.config)
	b.book.defs.stream.cast.rule = "nearest"
	b.book.defs.stream.count = 1
	_ticks(a, 1)
	_ticks(b, 1)
	for shot in 3:
		if shot > 0:
			_ticks(a, 6)
			b.runner.cooldowns.stream = 0
			_ticks(b, 1)
		# Damage rolls occur at impact, on the main stream, never at burst scheduling.
		for w in [a, b]:
			for tick in 90:
				w.projectiles.step(DT, w.swarm, w.mob_grid, w.events, PackedFloat32Array(), PackedByteArray(),
					func(_slot: int, hit: Dictionary) -> void: w.meter.landed(hit.get("meter_receipt", {}), w.events))
		assert_eq(a.rng.state, b.rng.state)
		assert_eq(a.swarm.hp, b.swarm.hp)
	assert_eq(a.meter.value, 1, "all burst impacts share the same receipt")
	assert_eq(b.meter.value, 3, "independent nearest casts earn independently")

func test_bot_reach_and_skill_text_use_resolved_count_and_duration() -> void:
	var w := _world()
	w.loadout.add_skill_mod("stream", "count", "add", 1)
	var st := w.loadout.stats("stream")
	assert_near(SkillRunner.reach_of(st, w), 450.0, 0.001)
	assert_true(w.runner.has_target(w, "stream", st, w.cast_origin()))
	assert_true("Fires 4 arrows over 0.7 s" in SkillText.new(w.book).level_line("stream", 1, st))

func test_single_shot_wind_up_and_snapshot_count() -> void:
	var w := _world(0.4, 1)
	_ticks(w, 1)
	w.loadout.add_skill_mod("stream", "count", "add", 5)
	_ticks(w, 24)
	assert_eq(_shots(w), 1, "Piercing Arrow shaped cast releases once")
	assert_false(w.runner.bursts.has_skill("stream"))

func test_admission_prefers_scheduled_boss_and_overshoot_only_retains() -> void:
	var w := _world(0.0)
	w.book.defs.stream.burst["overshoot"] = 50.0
	var boss := _mob(w, 100)
	w.mob_boss[boss] = 0
	_ticks(w, 1)
	assert_true(w.projectiles.vx[0] < 0)
	w.swarm.x[boss] = -275 # 475 px from body, outside acquisition but inside retention.
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_ticks(w, 6)
	assert_true(w.projectiles.vx[1] < 0)
	w.swarm.despawn(boss)
	for i in w.swarm.active.size():
		if w.swarm.is_live(i):
			w.swarm.x[i] = 675
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_ticks(w, 6)
	assert_eq(_shots(w), 2, "retarget never acquires in the overshoot margin")

func test_explicit_hand_launches_from_the_callers_current_origin() -> void:
	var w := _world()
	var st := w.loadout.stats("stream")
	w.runner.fire_shot(w, "stream", st, Vector2(300, 100), Vector2(400, 100), Vector2(310, 100))
	assert_near(w.projectiles.x[0], 310.0)
	assert_near(w.projectiles.y[0], 100.0)

func test_final_clear_cancels_unfinished_burst_without_another_runner_tick() -> void:
	var w := _world()
	_ticks(w, 1)
	w.drain_events()
	w.duration = 0.0
	w.bosses = BossDirector.new()
	for tick in 120:
		w.step(DT, MoveInput.new())
		RF.auto_choose(w)
	var ended := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "burst_end")
	assert_eq(w.state, RunWorld.CLEARED)
	assert_false(w.runner.bursts.has_skill("stream"))
	assert_eq(ended.size(), 1)
