extends TestCase
## Advancement rewards through the public run queue, using seeded worlds and fixed simulation ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _level_window(job: int, level: int, seed_value: int = 53) -> RunWorld:
	var w := RF.quiet_world(400.0, seed_value)
	if job != 0:
		w.change_job(job)
	w.progression.level = level - 1
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	return w


func test_magician_advancement_teaches_nothing_and_preserves_normal_draw() -> void:
	var w := _level_window(0, 10)
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	var owned := w.loadout.order.duplicate()
	assert_true(w.apply_job(200))
	assert_eq(w.loadout.order, owned, "job change teaches no skill")
	var ids := w.pending_cards.map(func(c: Dictionary) -> String: return c.id)
	assert_eq(ids.size(), 3)
	assert_has(ids, "energy_bolt_new")
	assert_has(ids, "magic_claw_new", "canonical prerequisites are ignored")
	var draws := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "choice_pending")
	assert_true(bool(draws.back().get("advancement", false)))
	assert_true(w.apply_choice("energy_bolt_new"))
	assert_eq(w.progression.front(), 10, "extra draw does not consume the level")
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	draws = w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "choice_pending")
	assert_false(bool(draws.back().get("advancement", false)))
	assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_false(w.progression.has_pending())


func test_ninth_skill_of_either_kind_can_be_offered_and_learned() -> void:
	for slot in ["active", "passive"]:
		var data := RF.quiet_data()
		for i in 9:
			var key := "synthetic_%d" % i
			data.skills.skills[key] = {"skill_id": 2001004, "book": "200", "slot": slot,
				"kind": "projectile" if slot == "active" else "passive", "ranks": [1]}
		data.upgrades.cards.append({"id": "ninth", "kind": "skill_new", "skill": "synthetic_8",
			"requires": {"jobs": [200]}, "max_rank": 1})
		var w := RunWorld.new(RF.setup("quiet", 53, data))
		w.change_job(200)
		for i in 8:
			assert_true(w.learn_skill("synthetic_%d" % i))
		assert_has(w.upgrades.eligible(w), "ninth", "eight owned %s skills impose no cap" % slot)
		assert_eq(w.upgrades.apply("ninth", w), 1)
		assert_eq(w.loadout.rank("synthetic_8"), 1)


func test_second_jobs_add_mp_without_skills_and_keep_the_level_choice() -> void:
	for branch in [210, 220, 230]:
		var w := _level_window(200, 30, branch)
		assert_eq(w.state, RunWorld.CHOOSING_JOB)
		var owned := w.loadout.order.duplicate()
		var mp := int(w.player_state.max_mp)
		assert_true(w.apply_job(branch), "branch %d is playable" % branch)
		assert_eq(w.progression.job_id, branch)
		assert_eq(int(w.player_state.max_mp), mp + 475)
		assert_eq(w.loadout.order, owned)
		if branch == 210:
			assert_has(w.pending_cards.map(func(c: Dictionary) -> String: return c.id), "fire_arrow_new")
		else:
			assert_eq(w.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
		if not w.pending_cards.is_empty():
			assert_true(w.apply_choice(String(w.pending_cards[0].id)))
			assert_eq(w.progression.front(), 30)
			assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)


func test_declining_advancement_opens_only_the_normal_draw() -> void:
	var w := _level_window(200, 30)
	w.drain_events()
	assert_true(w.decline_job())
	var draws := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "choice_pending")
	assert_eq(draws.size(), 1)
	assert_false(bool(draws[0].get("advancement", false)))
	assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_false(w.progression.has_pending())


func test_bot_branches_are_seeded_cover_all_paths_and_can_be_forced() -> void:
	var seen := {}
	for seed_value in range(1, 13):
		var a := _level_window(200, 30, seed_value)
		var b := _level_window(200, 30, seed_value)
		BotInput.auto_choose(a)
		BotInput.auto_choose(b)
		assert_eq(a.progression.job_id, b.progression.job_id)
		seen[a.progression.job_id] = true
		for branch in [210, 220, 230]:
			var forced := _level_window(200, 30, seed_value)
			BotInput.auto_choose(forced, false, branch)
			assert_eq(forced.progression.job_id, branch)
	assert_eq(seen.size(), 3, "seeds 1..12 cover all branches")


func test_advancement_accepts_future_attack_cards_from_data_and_rolls_rarity() -> void:
	var data := RF.quiet_data()
	data.upgrades.rarity.weights = {"legendary": 1}
	for i in 4:
		var skill := "future_%d" % i
		data.skills.skills[skill] = data.skills.skills.energy_bolt.duplicate(true)
		data.upgrades.cards.append({"id": skill, "skill": skill, "kind": "skill_new", "power": true,
			"requires": {"jobs": [220]}, "max_rank": 1})
	var w := RunWorld.new(RF.setup("quiet", 53, data))
	w.change_job(200)
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_true(w.apply_job(220))
	assert_eq(w.pending_cards.size(), 4, "every attack is offered even beyond the usual three-card draw")
	for c: Dictionary in w.pending_cards:
		assert_eq(c.tier, "legendary")
		assert_eq(c.skill_level_next, 5)
	assert_true(w.apply_choice("future_3"))
	assert_eq(w.loadout.rank("future_3"), 5)
	assert_eq(w.card_tiers_picked.legendary, 1)
