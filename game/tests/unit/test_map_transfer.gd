extends TestCase
## Fixed-tick seeded map boundaries through RunWorld's transfer, choice and event APIs.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _setup(seconds := 300.0) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.mesos.boss_drops = 0
	var stage: Dictionary = data.stages.stages.quiet
	stage.erase("map_id")
	stage.erase("bosses")
	stage.map_seconds = 300.0
	stage.maps = []
	var setup := RF.setup("quiet", 244, data)
	setup.map_imgs = []
	for i in 3:
		stage.maps.append({"map_id": 100000000 + i, "pool": "curve",
			"boss": {"mob_id": 100100, "time": seconds, "rewards": {"bonus_choices": 0, "exp_mult": 0.0}}})
		setup.map_imgs.append(RF.map_from_segments([
			{"x1": -2000, "y1": i * 200, "x2": 2000, "y2": i * 200}],
			[Vector2(-500, i * 200 - 10), Vector2(500, i * 200 - 10)]))
	setup.map_img = setup.map_imgs[0]
	return setup


func test_map_clock_starts_at_the_scheduled_curve_offset() -> void:
	var w := RunWorld.new(_setup())
	assert_true(w.has_method("curve_time"), "the binding curve clock exists")
	assert_true(w.has_method("current_map_id"), "the binding map identity exists")
	if not w.has_method("curve_time") or not w.has_method("current_map_id"):
		return
	assert_eq(w.call("current_map_id"), 100000000)
	assert_eq(w.call("curve_time"), 0.0)
	w.time = 420.0
	w.set("map_index", 1)
	w.set("map_entered_at", 410.0)
	assert_eq(w.call("curve_time"), 310.0, "slow kills do not push the next map's curve ahead")


func _ticks(w: RunWorld, count: int) -> void:
	for tick in count:
		w.step(DT, MoveInput.new())


func _kill(w: RunWorld) -> void:
	var slot := int(w.bosses.records[w.map_index].slot)
	assert_true(slot >= 0, "the current map's boss arrived")
	if slot >= 0:
		w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
			"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func test_next_boss_waits_three_hundred_seconds_from_entry_after_fast_or_slow_kill() -> void:
	for kill_at in [310, 420]:
		var w := RunWorld.new(_setup())
		w.god = true
		assert_eq(w.bosses.records.size(), 3)
		if w.bosses.records.size() != 3:
			continue
		_ticks(w, kill_at * 60)
		assert_eq(w.bosses.live_count(), 1, "future maps do not arm bosses")
		_kill(w)
		w.step(DT, MoveInput.new())
		assert_true(w.transfer_pending)
		assert_near(w.time, float(kill_at), 1e-6, "the kill admits no extra combat tick")
		w.advance_map()
		assert_eq(w.map_index, 1)
		assert_eq(w.current_map_id(), 100000001)
		assert_near(w.curve_time(), 300.0, 1e-6)
		assert_near(float(w.bosses.records[1].arrival), float(kill_at + 300), 1e-6)
		_ticks(w, 300 * 60 - 1)
		assert_eq(w.bosses.live_count(), 0)
		w.step(DT, MoveInput.new())
		assert_near(float(w.bosses.records[1].spawn_time), float(kill_at + 300), 1e-6)
		assert_eq(w.bosses.records[1].map_index, 1)
		assert_eq(w.bosses.records[1].map_id, 100000001)


func test_boss_kill_freezes_both_directions_and_sweeps_before_choices_once() -> void:
	var setup := _setup(0.1)
	setup.data.stages.stages.quiet.maps[0].boss.rewards = {"bonus_choices": 1, "exp_mult": 2.0}
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 60)
	w.god = false
	var ordinary := RF.put_mob(w, 100100, w.player.pos.x)
	w.swarm.alpha[ordinary] = 1.0
	var hp := w.swarm.hp[ordinary]
	w.pickups.spawn(Vector2(1300, -500), 2, 4000000, w.player.pos)
	w.spawn_meso(Vector2(1300, -500), 123)
	var item := Equipment.create(1002001, {"reqLevel": 200})
	w.spawn_equipment(Vector2(1300, -500), item)
	w.progression.level = 9
	w.refresh_player_stats(false)
	w.pickups.spawn(Vector2(1400, -500), w.progression.exp_to_next(), 4000000, w.player.pos)
	var before_hp: int = w.player_state.hp
	_kill(w)
	assert_eq(w.take_hit(100000.0, false, "", w.player.pos, {"source_kind": "boss_attack"}), 0)
	w.hit_mob(ordinary, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.hp[ordinary], hp, "later same-tick attack lines cannot damage mobs")
	var t := w.time
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_false(w.transfer_pending)
	w.advance_map()
	assert_eq(w.map_index, 0, "the boss reward must be answered before transfer")
	assert_eq(w.mesos, 123)

	assert_eq(w.equips_collected, 1)
	assert_eq(w.pickups.active_count(), 0, "the sweep precedes every choice")
	var swept := w.pickups.collected_exp
	assert_true(swept > 2, "includes the boss shower")
	assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	assert_true(w.apply_job(200))
	assert_true(w.choice_advancement)
	RF.auto_choose(w)
	assert_true(w.transfer_pending)
	assert_eq(w.time, t)
	assert_eq(w.kills, 1, "ordinary mobs vanish without kill credit")
	assert_eq(w.swarm.alive_count(), 0)
	assert_eq(w.pickups.collected_exp, swept)
	assert_true(int(w.player_state.hp) >= before_hp, "only progression may refill HP")
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "map_cleared").size(), 1)
	for tick in 120:
		w.step(DT, MoveInput.new())
	assert_eq(w.time, t)
	assert_eq(w.drain_events(), [])
	assert_eq(w.pickups.collected_exp, swept)
	assert_eq(w.mesos, 123)


func test_projectile_boss_kill_stops_piercing_blasts_and_later_shots_in_the_same_tick() -> void:
	for blast in [false, true]:
		var w := RunWorld.new(_setup(0.1))
		w.god = true
		_ticks(w, 60)
		var boss := int(w.bosses.records[0].slot)
		w.swarm.x[boss] = 0.0
		w.swarm.y[boss] = 0.0
		var ordinary := RF.put_mob(w, 100100, 70.0, -10.0)
		w.swarm.alpha[ordinary] = 1.0
		var spec := {"x": -20.0, "y": -10.0, "vx": 6000.0, "range": 500.0,
			"dmg_min": 1000000.0, "dmg_max": 1000000.0, "pierce": 3}
		if blast:
			spec.impact_blast = {"box": Rect2(-200, -100, 400, 200), "count": 6, "visual": ""}
		w.projectiles.spawn(spec)
		w.projectiles.spawn(spec)
		w.drain_events()
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		assert_true(w.transfer_pending)
		assert_eq(w.kills, 1)
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit").size(), 1,
			"the killing line is the last damaging event, including a shell's secondary blast targets")
