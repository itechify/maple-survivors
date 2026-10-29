extends TestCase
## The autoplay bot's Bowmaster scoring and reach (spec #332, B12 #344). The data check runs on the shipped files; the card and
## reach checks run in a synthetic Bowmaster world (all ten books defined, a bow worn), so they need no cache.

const BF := preload("res://tests/fixtures/bowmaster_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func _world(p_seed := 344) -> RunWorld:
	var w := RunWorld.new(BF.setup("quiet", p_seed, RF.quiet_data()))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func test_every_pool_skill_of_all_three_jobs_has_explicit_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [212, 112, 312]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_ten_bowmaster_keys_are_the_pool() -> void:
	var data := DataRepo.load_all()
	var pool: Array = JobTree.from_data(data.jobs, data.jobs_survivor).skill_pool(312)
	assert_eq(pool.size(), 10)
	for key: String in ["arrow_blow", "bow_double_shot", "arrow_bomb", "strafe", "inferno", "arrow_rain", "dragons_breath",
			"hurricane", "silver_hawk", "phoenix"]:
		assert_true(key in pool, key)


func test_all_ten_pool_skills_are_defined_in_the_synthetic_world() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(312):
		assert_true(w.book.has(key), "%s has a definition and a book" % key)


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	var seen := 0
	for key: String in w.jobs.skill_pool(312):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty() and rank.is_empty(), "%s is offered" % key)
		if not learn.is_empty():
			seen += 1
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_true(seen >= 9, "the learn cards of the pool beyond the starting skill exist (%d)" % seen)


func test_the_two_summons_score_like_attacks_even_though_the_default_reads_them_as_non_attacks() -> void:
	var w := _world()
	for key: String in ["silver_hawk", "phoenix"]:
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		assert_false(learn.is_empty(), key)
		assert_eq(BotInput.card_score(w, learn), 100.0)
		assert_true(float(DataRepo.load_all().balance.bot.card_scores.get(key + "_new", -1)) == 100.0, "%s has its explicit entry, not only the pool default" % key)


func test_the_bot_picks_each_pool_skills_learn_card_over_passives_and_other_ranks() -> void:
	var w := _world()
	var rivals: Array = []
	for id: String in ["passive_might_new", "bow_double_shot_rank", "arrow_blow_rank"]:
		var c := w.upgrades.choice_card(id, w, "normal")
		if not c.is_empty():
			rivals.append(c)
	assert_false(rivals.is_empty(), "something to compete with")
	for key: String in w.jobs.skill_pool(312):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		if learn.is_empty():
			continue # the starting skill (Arrow Blow) is already learned
		var offer: Array = [rivals[0], learn] + rivals.slice(1)
		assert_eq(BotInput.pick_card_for(w, offer), key + "_new", "%s is taken when offered" % key)


func test_every_defined_skills_reach_is_known_and_a_burst_reads_as_its_range() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(312):
		var st: Dictionary = w.loadout.stats(key)
		if st.is_empty():
			continue
		var reach := SkillRunner.reach_of(st, w)
		if String(st.kind) == "summon":
			assert_eq(reach, 0.0, "%s: a follower is never a bot attack to kite with" % key)
		else:
			assert_true(reach > 0.0, "%s has a reach (%s)" % [key, reach])
	assert_eq(SkillRunner.reach_of(w.loadout.stats("hurricane"), w), 450.0, "a burst reads as its range")


func test_the_bowmaster_bot_kites_a_close_mob_and_never_presses_a_skill_key() -> void:
	var w := _world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill("hurricane")
	var m := RF.put_mob(w, 1110100, w.player.pos.x + 60, 195, 1.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	assert_true(m >= 0)
	var memo := {}
	var pressed := 0
	for tick in 120:
		var input := BotInput.decide(w, memo)
		if not input.skills_pressed.is_empty() or not input.skills_held.is_empty():
			pressed += 1
		w.step(1.0 / 60.0, input)
	assert_eq(pressed, 0, "312 has no mobility skill and every pool skill auto-casts")
