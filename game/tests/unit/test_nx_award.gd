extends TestCase
## The NX award of a finished round (#115, spec #34): clear_bonus[tier] (clears only) + per_level x levels gained +
## per_boss x bosses killed, paid on a clear or a death. Expected values are worked by hand from the config below,
## through RunWorld's public round-result seam (levels_gained / bosses_killed / nx_awarded).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CONFIG := {"clear_bonus": [100, 250], "per_level": 5, "per_boss": 40}


func _world(stage_in_tier: int = 0, with_boss := true) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance["nx_award"] = CONFIG.duplicate(true)
	data.stages["tiers"] = [["other"], ["other2"]]
	data.stages.tiers[stage_in_tier].append("quiet")
	if with_boss:
		RF.set_bosses(data.stages.stages.quiet, [
			{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0, "rewards": {"exp_mult": 1, "bonus_choices": 0}},
			{"time": 0.2, "mob_id": 2220000, "hp_mult": 1.0, "rewards": {"exp_mult": 1, "bonus_choices": 0}}])
	var w := RunWorld.new(RF.setup("quiet", 20, data))
	RF.place_player(w, 400)
	w.god = true
	for i in 20:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func _kill_boss(w: RunWorld, index: int) -> void:
	w.hit_mob(int(w.bosses.records[index].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func _gain_levels(w: RunWorld, count: int) -> void:
	for i in count:
		w.progression.add_exp(w.progression.exp_to_next())
	w.progression.queue.clear()


func _die(w: RunWorld) -> void:
	w.god = false
	w.upkeep.invincible_t = 0.0
	w.take_hit(1000000.0, false, "", w.player.pos + Vector2(20, 0), {"accuracy": 100000.0})
	assert_eq(w.state, RunWorld.DEAD)


func test_formula_pays_the_tier_clear_bonus_plus_levels_and_bosses() -> void:
	assert_eq(NxAward.compute(CONFIG, 0, true, 7, 2), 100 + 7 * 5 + 2 * 40)
	assert_eq(NxAward.compute(CONFIG, 1, true, 7, 2), 250 + 7 * 5 + 2 * 40)
	assert_eq(NxAward.compute(CONFIG, 0, true, 0, 0), 100, "a clear with no gains still pays the bonus")


func test_a_death_pays_the_same_without_the_clear_bonus() -> void:
	assert_eq(NxAward.compute(CONFIG, 1, false, 7, 2), 7 * 5 + 2 * 40)
	assert_eq(NxAward.compute(CONFIG, 0, false, 0, 0), 0)


func test_tiers_beyond_the_table_use_its_last_entry_and_a_missing_config_pays_nothing() -> void:
	assert_eq(NxAward.compute(CONFIG, 5, true, 0, 0), 250)
	assert_eq(NxAward.compute({}, 0, true, 9, 9), 0)
	assert_eq(NxAward.compute(CONFIG, 0, true, -3, -1), 100, "never a negative gain")


func test_tier_of_a_stage_is_its_index_in_the_stage_tiers() -> void:
	var stages := {"tiers": [["henesys", "ellinia"], ["sleepywood"]]}
	assert_eq(NxAward.tier_of(stages, "henesys"), 0)
	assert_eq(NxAward.tier_of(stages, "ellinia"), 0)
	assert_eq(NxAward.tier_of(stages, "sleepywood"), 1)
	assert_eq(NxAward.tier_of(stages, "elsewhere"), 0, "tool stages outside the tiers count as tier 1")


func test_world_counts_levels_gained_this_round_not_the_carried_level() -> void:
	var w := _world()
	assert_eq(w.levels_gained(), 0)
	_gain_levels(w, 3)
	assert_eq(w.levels_gained(), 3)
	var carried := w.character_snapshot()
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 21, data)
	setup.character = carried
	var next := RunWorld.new(setup)
	assert_eq(next.progression.level, w.progression.level)
	assert_eq(next.levels_gained(), 0, "a carried character starts the round with no gains")
	_gain_levels(next, 2)
	assert_eq(next.levels_gained(), 2)


func test_cleared_round_award_uses_the_stage_tier_levels_and_bosses() -> void:
	var w := _world(1)
	_gain_levels(w, 4)
	_kill_boss(w, 0)
	_kill_boss(w, 1)
	for i in 3:
		w.step(DT, MoveInput.new())
	RF.auto_choose(w) # the finale sweep's EXP adds one level, whose card must finish before the clear bonus
	assert_eq(w.state, RunWorld.CLEARED)
	assert_eq(w.bosses_killed(), 2)
	assert_eq(w.pickups.collected_exp, 240, "both canonical Mano EXP drops now settle")
	assert_eq(w.levels_gained(), 5)
	assert_eq(w.nx_awarded(), 250 + 5 * 5 + 2 * 40, "tier-2 stage: 250 + 25 + 80, including swept EXP")


func test_death_still_counts_bosses_killed_in_that_round_but_no_clear_bonus() -> void:
	var w := _world(0)
	_gain_levels(w, 2)
	_kill_boss(w, 0)
	assert_eq(w.bosses_killed(), 1)
	_die(w)
	assert_eq(w.nx_awarded(), 2 * 5 + 1 * 40, "10 + 40, and no tier-1 clear bonus")


func test_no_config_in_the_data_awards_nothing() -> void:
	var w := RF.quiet_world()
	w.balance.erase("nx_award")
	assert_eq(w.nx_awarded(), 0)
