extends TestCase
## Stage EXP pacing through seeded RunWorld kills, emitted rewards and ground pickups; canonical inputs are synthetic.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(frames: Array, stage_mult := 9.0, balance_mult := 1.5) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.exp_mult = balance_mult
	data.balance.player.skills = []
	data.stages.stages.quiet.exp_mult = stage_mult
	data.stages.stages.quiet.post_duration_slope = 0.25
	data.stages.stages.quiet.keyframes = frames
	var w := RunWorld.new(RF.setup("quiet", 27, data))
	RF.place_player(w, 400)
	w.god = true
	return w


func _advance(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


func _kill_exp(w: RunWorld, elite := false) -> Dictionary:
	var fh := w.fhm.find_below(-900, 190)
	var slot := w.spawn_mob(int(w.kind_of_id[100100]), Vector2(-900, w.fhm.y_at(fh, -900)), fh, 1.0, elite)
	return _hit_exp(w, slot)


func _hit_exp(w: RunWorld, slot: int) -> Dictionary:
	w.drain_events()
	w.hit_mob(slot, {"damage_min": 10000.0, "damage_max": 10000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	var result := {"reported": -1, "drops": 0, "total": 0}
	for event: Dictionary in w.drain_events():
		if event.type == "mob_died":
			result.reported = int(event.exp)
		elif event.type == "pickup_spawned" and event.get("kind") == "exp":
			result.drops += 1
			result.total += int(w.pickups.exp[int(event.pickup)])
	return result


func test_stage_exp_curve_interpolates_rounds_once_and_holds_beyond_last_frame() -> void:
	var w := _world([{"t": 0, "pool": {"100100": 1}, "exp_mult": 2.0},
		{"t": 10, "pool": {"100100": 1}, "exp_mult": 0.5}])
	assert_eq(_kill_exp(w), {"reported": 9, "drops": 1, "total": 9}, "canonical 3 × global 1.5 × stage 2; EXP is not a probability")
	var fh := w.fhm.find_below(500, 190)
	var waiting := w.spawn_mob(int(w.kind_of_id[100100]), Vector2(500, w.fhm.y_at(fh, 500)), fh, 1000.0, false)
	_advance(w, 300)
	assert_eq(_hit_exp(w, waiting), {"reported": 6, "drops": 1, "total": 6}, "kill time gives round(3 × 1.5 × 1.25)=6, although the mob spawned at stage 2")
	_advance(w, 900)
	assert_eq(_kill_exp(w), {"reported": 2, "drops": 1, "total": 2}, "last stage 0.5 holds at 20 s despite the post-duration spawn ramp")


func test_missing_exp_curve_endpoints_keep_the_stage_multiplier() -> void:
	var legacy := _world([{"t": 0, "pool": {"100100": 1}}, {"t": 10, "pool": {"100100": 1}}], 2.5, 1.0)
	assert_eq(_kill_exp(legacy), {"reported": 8, "drops": 1, "total": 8}, "absent curve preserves round(canonical 3 × stage 2.5)")
	_advance(legacy, 1200)
	assert_eq(_kill_exp(legacy), {"reported": 8, "drops": 1, "total": 8}, "legacy stage multiplier also holds after the last frame")
	var partial := _world([{"t": 0, "pool": {"100100": 1}, "exp_mult": 0.5},
		{"t": 10, "pool": {"100100": 1}}], 2.0, 1.0)
	_advance(partial, 300)
	assert_eq(_kill_exp(partial), {"reported": 4, "drops": 1, "total": 4}, "missing endpoint uses stage 2 before interpolation to 1.25")


func test_negative_exp_endpoints_clamp_before_interpolation_and_zero_emits_no_drop() -> void:
	var w := _world([{"t": 0, "pool": {"100100": 1}, "exp_mult": -2.0},
		{"t": 10, "pool": {"100100": 1}, "exp_mult": 2.0}], 9.0, 1.0)
	assert_eq(_kill_exp(w), {"reported": 0, "drops": 0, "total": 0}, "negative endpoint cannot emit negative EXP or a zero-value drop")
	_advance(w, 300)
	assert_eq(_kill_exp(w), {"reported": 3, "drops": 1, "total": 3}, "clamping endpoints 0 and 2 before interpolation gives multiplier 1")


func test_elite_exp_factor_applies_before_rounding_and_boss_reward_exp_bypasses_stage_curve() -> void:
	var elite := _world([{"t": 0, "pool": {"100100": 1}, "exp_mult": 0.5}], 9.0, 1.0)
	assert_eq(_kill_exp(elite, true), {"reported": 8, "drops": 1, "total": 8}, "round(3 × stage 0.5 × elite 5)=8, without intermediate rounding")
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.exp_mult = 7.0
	data.stages.stages.quiet.exp_mult = 9.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "pool": {"100100": 1}, "exp_mult": 0.0}]
	data.stages.stages.quiet.elites = {"exp_mult": 11.0}
	data.stages.stages.quiet.bosses = [{"time": 0.1, "mob_id": 2220000,
		"rewards": {"exp_mult": 2.5, "potions": {"hp": 3, "mp": 3}, "bonus_choices": 0}}]
	var boss_world := RunWorld.new(RF.setup("quiet", 27, data))
	boss_world.god = true
	var slot := -1
	for tick in 7:
		boss_world.step(DT, MoveInput.new())
		for event: Dictionary in boss_world.drain_events():
			if event.type == "boss_spawned":
				slot = int(event.mob)
	assert_true(slot >= 0, "the seeded scheduled boss arrives")
	if slot < 0:
		return
	boss_world.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	var reported := -1
	for event: Dictionary in boss_world.drain_events():
		if event.type == "mob_died":
			reported = int(event.exp)
	var total := 0
	for pickup in boss_world.pickups.capacity():
		if boss_world.pickups.active[pickup] != 0 and boss_world.pickups.kind[pickup] == PickupSystem.EXP:
			total += int(boss_world.pickups.exp[pickup])
	assert_eq(reported, 300, "canonical Mano 120 × reward 2.5 ignores ordinary/global/elite EXP multipliers")
	assert_eq(total, 300, "the boss shower conserves its independent EXP reward even with stage curve 0")
