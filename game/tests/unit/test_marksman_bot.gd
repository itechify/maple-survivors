extends TestCase
## The autoplay bot's Marksman scoring and reach (spec #360, MS10 #370). The data check runs on the shipped files; the card, reach
## and Snipe checks run in a synthetic Marksman world (all ten books defined, a crossbow worn), so they need no cache.

const MF := preload("res://tests/fixtures/marksman_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const POOL := ["iron_arrow", "arrow_blow", "strafe_crossbow", "dragons_breath_crossbow", "blizzard_crossbow", "arrow_eruption",
	"piercing_arrow", "snipe", "golden_eagle", "frostprey"]


func _world(p_seed := 370) -> RunWorld:
	var w := RunWorld.new(MF.setup("quiet", p_seed, RF.quiet_data()))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func _mob(w: RunWorld, dx: float, hp := 100000) -> int:
	var slot := RF.put_mob(w, 1110100, w.player.pos.x + dx, 195, 1.0)
	w.swarm.hp[slot] = hp
	w.swarm.max_hp[slot] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func test_every_pool_skill_of_all_playable_jobs_and_marksman_has_explicit_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [212, 112, 312, 322]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_ten_marksman_keys_are_the_pool() -> void:
	var data := DataRepo.load_all()
	var pool: Array = JobTree.from_data(data.jobs, data.jobs_survivor).skill_pool(322)
	assert_eq(pool.size(), 10)
	for key: String in POOL:
		assert_true(key in pool, key)


func test_all_ten_pool_skills_are_defined_in_the_synthetic_world() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(322):
		assert_true(w.book.has(key), "%s has a definition and a book" % key)


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	var seen := 0
	for key: String in w.jobs.skill_pool(322):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty() and rank.is_empty(), "%s is offered" % key)
		if not learn.is_empty():
			seen += 1
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_true(seen >= 9, "the learn cards of the pool beyond the starting skill exist (%d)" % seen)


func test_the_two_followers_score_like_attacks_even_though_the_default_reads_them_as_non_attacks() -> void:
	var w := _world()
	for key: String in ["golden_eagle", "frostprey"]:
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		assert_false(learn.is_empty(), key)
		assert_eq(BotInput.card_score(w, learn), 100.0)
		assert_true(float(DataRepo.load_all().balance.bot.card_scores.get(key + "_new", -1)) == 100.0, "%s has its explicit entry, not only the pool default" % key)


func test_the_bot_takes_all_ten_pool_skills_when_offered_over_passives_and_other_ranks() -> void:
	var w := _world()
	var rivals: Array = []
	for id: String in ["passive_might_new", "strafe_crossbow_rank", "iron_arrow_rank"]:
		var c := w.upgrades.choice_card(id, w, "normal")
		if not c.is_empty():
			rivals.append(c)
	assert_false(rivals.is_empty(), "something to compete with")
	var taken := 0
	for key: String in w.jobs.skill_pool(322):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		assert_false(learn.is_empty(), "%s has a learn card" % key)
		var offer: Array = [rivals[0], learn] + rivals.slice(1)
		assert_eq(BotInput.pick_card_for(w, offer), key + "_new", "%s is taken when offered" % key)
		taken += 1
	assert_eq(taken, 10, "all ten pool skills")


func test_every_defined_skills_reach_is_known_and_a_burst_reads_as_its_range() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(322):
		var st: Dictionary = w.loadout.stats(key)
		if st.is_empty():
			continue
		var reach := SkillRunner.reach_of(st, w)
		if String(st.kind) == "summon":
			assert_eq(reach, 0.0, "%s: a follower is never a bot attack to kite with" % key)
		else:
			assert_true(reach > 0.0, "%s has a reach (%s)" % [key, reach])
	w.learn_skill("piercing_arrow")
	w.learn_skill("snipe")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("piercing_arrow"), w), 450.0, "a burst reads as its range")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("snipe"), w), 450.0, "Snipe reaches 450 px")


func test_the_marksman_bot_kites_a_close_mob_and_never_presses_a_skill_key() -> void:
	var w := _world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill("piercing_arrow")
	_mob(w, 60)
	var memo := {}
	var pressed := 0
	for tick in 120:
		var input := BotInput.decide(w, memo)
		if not input.skills_pressed.is_empty() or not input.skills_held.is_empty():
			pressed += 1
		w.step(DT, input)
	assert_eq(pressed, 0, "322 has no mobility skill and every pool skill auto-casts")


func test_snipe_is_admitted_whenever_any_monster_is_in_reach_whatever_its_prefer_order() -> void:
	var w := _world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_true(w.learn_skill("snipe"))
	var st: Dictionary = w.loadout.stats("snipe")
	assert_eq(st.cast_params.get("prefer"), "max_hp", "the fixed-share nuke prefers the biggest monster")
	var origin: Vector2 = w.cast_origin()
	assert_false(w.runner.has_target(w, "snipe", st, origin), "no monster: nothing to fire at")
	_mob(w, 700) # beyond the 450 px reach
	assert_false(w.runner.has_target(w, "snipe", st, origin), "a monster beyond the reach is no target")
	var near := _mob(w, 300, 50)
	assert_true(w.runner.has_target(w, "snipe", st, origin), "prefer orders targets, it never refuses one: the bot does not hold fire")
	assert_false(w.runner.prepare_cast(w, "snipe", st, origin).is_empty(), "has_target agrees with admission")
	var big := _mob(w, 400, 900000)
	assert_true(w.runner.has_target(w, "snipe", st, origin))
	var plan := w.runner.prepare_cast(w, "snipe", st, origin)
	assert_eq((plan.targets as Array)[0], big, "admission puts the largest monster first")
	assert_true(near != big)


func test_a_bot_driven_marksman_with_snipe_alone_fires_at_a_lone_monster() -> void:
	var w := _world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_true(w.learn_skill("snipe"))
	w.refresh_player_stats()
	var slot := _mob(w, 300, 1000000)
	var memo := {}
	var snipes := 0
	for tick in 300:
		w.step(DT, BotInput.decide(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit" and e.get("skill", "") == "snipe" and int(e.mob) == slot:
				snipes += 1
	assert_true(snipes > 0, "Snipe landed on the monster the bot kited: the bot did not hold fire")
