extends TestCase
## Seeded finale boundaries: no extra combat tick, conserved loose loot and choices before character carry.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _reward_world(p_seed := 71) -> RunWorld:
	var w := RF.quiet_world(400.0, p_seed)
	w.loadout.order.clear()
	w.bosses = BossDirector.new([{"mob_id": 2220000, "time": 0.0}])
	w.bosses.records[0].dead = true
	w.bosses.records[0].spawn_time = 0.0
	w.bosses.records[0].death_time = 0.0
	w.pending_bonus_choices = 1
	w._advance_queue()
	return w


func _answer(w: RunWorld) -> void:
	assert_true(not w.pending_cards.is_empty(), "a normal reward is answerable")
	if not w.pending_cards.is_empty():
		assert_true(w.apply_choice(String(w.pending_cards[0].id)))


## Keeps every owned skill on its cooldown, so no auto-cast kills the lethal source first (an empty MP pool did this
## before MP was removed, #285).
func _hold_skills(w: RunWorld) -> void:
	for key: String in w.loadout.order:
		w.runner.cooldowns[key] = 1.0e9


func _lethal_contact(w: RunWorld) -> void:
	var slot := RF.put_mob(w, 100100, 400.0)
	w.swarm.alpha[slot] = 1.0
	w.swarm.state[slot] = MobSwarm.STAND
	w.mob_kinds[w.swarm.kind[slot]].move_speed = 0.0
	w.mob_kinds[w.swarm.kind[slot]].pad = 100000.0
	w.mob_kinds[w.swarm.kind[slot]].acc = 100000.0
	w._hp = 1.0
	_hold_skills(w)
	w.refresh_player_stats(false)


func _lethal_ball(w: RunWorld) -> int:
	w._hp = 1.0
	_hold_skills(w)
	w.refresh_player_stats(false)
	return w.mob_projectiles.spawn({"pos": w.player_body_center(), "velocity": Vector2(60, 0),
		"visual": 0, "range": 500.0, "mob": -1, "mob_id": 100100, "damage": 100000.0,
		"multiplier": 1.0, "accuracy": 100000.0, "magic": false, "element": "", "hit": "",
		"source_pos": w.player.pos + Vector2(-40, 0), "ordinary": true})


func test_last_answer_clears_before_lethal_contact_can_tick() -> void:
	var w := _reward_world()
	_lethal_contact(w)
	w.drain_events()
	var t := w.time
	_answer(w)
	assert_eq(w.state, RunWorld.CLEARED, "last answer settles synchronously")
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.time, t, "no post-objective combat tick")
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared").size(), 1)
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "player_hit"))


func test_last_answer_clears_before_a_pending_monster_ball_can_tick() -> void:
	var w := _reward_world(72)
	var ball := _lethal_ball(w)
	w.drain_events()
	_answer(w)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.mob_projectiles.active[ball], 1, "the ball never gets another damaging step")
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "player_hit"))


func test_death_before_the_boss_objective_is_met_is_unchanged() -> void:
	for ball in [false, true]:
		var w := RF.quiet_world(400.0, 72)
		w.bosses = BossDirector.new([{"mob_id": 2220000, "time": 300.0}])
		if ball:
			_lethal_ball(w)
		else:
			_lethal_contact(w)
		w.step(DT, MoveInput.new())
		assert_eq(w.state, RunWorld.DEAD)


func test_sweep_collects_every_pickup_kind_once_and_conserves_capped_exp() -> void:
	var w := _reward_world()
	w.pickups.tuning.max_active = 1
	var far := Vector2(1300, -500)
	w.pickups.spawn(far, 2, 4000000, w.player.pos)
	w.pickups.spawn(far, 3, 4000000, w.player.pos)
	w.spawn_meso(far, 123)
	var item := Equipment.create(1002001, {"reqLevel": 200, "incPDD": 7})
	w.spawn_equipment(far, item)
	var mesos := w.mesos
	w.drain_events()
	_answer(w)
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.pickups.active_count(), 0)
	assert_eq(w.pickups.collected_exp, 5)
	assert_eq(w.pickups.expired_exp, 0)
	assert_eq(w.progression.exp, 5)
	assert_eq(w.mesos, mesos + 123)
	assert_true(w.equipment.inventory.has(item) or w.equipment.worn.get("hat", {}) == item,
		"the exact equipment instance carries, with the ordinary auto-wear rule")
	assert_eq(w.equips_collected, 1)
	var settled := w.character_snapshot()
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_collected").size(), 3,
		"one merged EXP drop, one meso bundle and one equipment item; no potion pickups remain")
	for tick in 3:
		w.step(DT, MoveInput.new())
	assert_false(w.apply_choice("elixir"), "the answered reward cannot be replayed")
	assert_eq(w.character_snapshot(), settled)
	assert_eq(w.drain_events().size(), 0)


func test_swept_exp_resolves_its_level_cards_before_snapshot_without_combat() -> void:
	var w := _reward_world()
	var job := w.job_id()
	w.progression.level = 9
	w.refresh_player_stats(false)
	w.pickups.spawn(Vector2(1300, -500), w.progression.exp_to_next(), 4000000, w.player.pos)
	_lethal_ball(w)
	var t := w.time
	w.drain_events()
	_answer(w)
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "swept EXP uses the ordinary level queue (no job window, #284)")
	assert_eq(w.progression.level, 10)
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "stage_cleared"))
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the frozen choice admits no combat tick")
	_answer(w)
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.time, t)
	var snapshot := w.character_snapshot()
	assert_eq(int(snapshot.level), 10)
	assert_eq(int(snapshot.job_id), job, "the job never changes")
	assert_eq(int(snapshot.exp), 0)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared").size(), 1)
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "player_hit"))


func test_full_inventory_reuses_blocked_pickup_rule_without_stalling_clear() -> void:
	var w := _reward_world()
	while w.equipment.inventory.size() < w.inventory_slots():
		w.equipment.inventory.append(Equipment.create(1002001, {}))
	var item := Equipment.create(1002002, {"incPDD": 7})
	var drop := w.spawn_equipment(Vector2(1300, -500), item)
	w.spawn_meso(Vector2(1300, -500), 17)
	var mesos := w.mesos
	w.drain_events()
	_answer(w)
	assert_eq(w.state, RunWorld.CLEARED, "a full tab cannot soft-lock settlement")
	assert_eq(w.equipment.inventory.size(), w.inventory_slots())
	assert_eq(w.pickups.active[drop], 1, "the existing full-tab rule leaves equipment on the ground")
	assert_eq(w.equips_collected, 0)
	assert_eq(w.mesos, mesos + 17)
	var blocked := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_blocked")
	assert_eq(blocked.size(), 1)
	if blocked.size() == 1:
		assert_eq(blocked[0].reason, "inventory_full")


func test_sweep_reuses_room_freed_by_ordinary_equipment_auto_wear() -> void:
	var w := _reward_world()
	w.balance.player.inventory_slots = 1
	w.equipment.inventory.clear()
	w.equipment.worn.erase("hat")
	w.spawn_equipment(Vector2(1300, -500), Equipment.create(1002001, {}))
	w.spawn_equipment(Vector2(1400, -500), Equipment.create(1002002, {}))
	_answer(w)
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.equips_collected, 2, "auto-wear frees room for the second pickup without a combat tick")
	assert_eq(w.pickups.active_count(), 0)
	assert_eq(w.equipment.inventory.size(), 1)


func test_distant_final_boss_shower_and_ordinary_drops_are_paid_together() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000,
		"rewards": {"bonus_choices": 1, "exp_mult": 0.05, "exp_drops": 2, "potions": {"hp": 2, "mp": 3}}}])
	var w := RunWorld.new(RF.setup("quiet", 73, data))
	RF.place_player(w, 400)
	w.god = true
	for tick in 6:
		w.step(DT, MoveInput.new())
	var boss := int(w.bosses.records[0].slot)
	w.swarm.x[boss] = 1300
	w.hit_mob(boss, {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	w.spawn_meso(Vector2(1400, -100), 111)
	w.pickups.spawn(Vector2(1400, -100), 3, 4000000, w.player.pos)
	var expected_exp := 0
	var expected_mesos := w.mesos
	for slot in w.pickups.capacity():
		if w.pickups.active[slot] != 0:
			expected_exp += w.pickups.exp[slot]
			expected_mesos += w.pickups.meso[slot]
	assert_true(expected_exp > 3, "the boss shower exists before settlement")
	w._end_tick()
	_answer(w)
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.pickups.active_count(), 0)
	assert_eq(w.pickups.collected_exp, expected_exp)
	assert_eq(w.mesos, expected_mesos)


func test_warp_keeps_clear_emitted_by_the_last_answer_before_another_tick() -> void:
	var scene := RunScene.new()
	scene.world = _reward_world()
	scene.world.drain_events()
	scene._warp(60.0)
	assert_eq(scene.world.state, RunWorld.CLEARED)
	assert_eq(scene.world.time, 0.0)
	assert_eq(scene._warp_end_events.filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared").size(), 1,
		"a clear emitted from auto_choose must still reach presentation")
	scene.free()


func test_balance_harness_observes_choice_only_settlement_without_counting_a_tick() -> void:
	var w := _reward_world()
	w.progression.level = 9
	w.refresh_player_stats(false)
	w.balance.run_time_cap = DT
	w.pickups.spawn(Vector2(1300, -500), w.progression.exp_to_next(), 4000000, w.player.pos)
	var report: Dictionary = preload("res://tools/balance_run.gd").run_one(w, "first", 71, -1.0, 60.0)
	assert_eq(report.state, "CLEARED")
	assert_eq(report.time, 0.0)
	assert_eq(report.reach.get("10"), 0.0, "the sweep's level event is observed")
	assert_false(report.has("mp_short_seconds"), "no MP-wait field (#285)")
