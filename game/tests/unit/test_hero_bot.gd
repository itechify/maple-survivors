extends TestCase
## The autoplay bot's Hero scoring and melee reach (spec #296, H9 #305). Data-level checks run on the shipped files; the
## card and reach checks need the Hero skills (H5-H8) and are below.


func test_every_pool_skill_of_both_jobs_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [212, 112]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_hero_scores_name_the_three_cards_the_default_scorer_would_undervalue() -> void:
	var scores: Dictionary = DataRepo.load_all().balance.bot.card_scores
	for key: String in ["panic", "coma", "monster_magnet"]:
		assert_true(scores.has(key + "_new") and scores.has(key + "_rank"), key)


const RF := preload("res://tests/fixtures/run_fixtures.gd")
## Brandish needs a WZ-shaped node (the synthetic fixture imports have no 112 book): a forward box 150 px ahead.
const BRANDISH_BOX := {"lt": {"$v": [-150, -110]}, "rb": {"$v": [-10, 0]}}


## A quiet Hero (112) world, Hero made playable in its own data, with the three core skills' art synthetic.
func _hero_world(seed_value := 305) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"].playable = true
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 150, "attackCount": 2, "mobCount": 1, "lt": BRANDISH_BOX.lt, "rb": BRANDISH_BOX.rb}
	setup.skill_imgs["112"] = {"skill": {"1121008": {"level": levels}}}
	setup["job"] = 112 # a round of the job from its start: its own start skills, none of the F/P ones
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func test_a_learn_card_of_every_defined_hero_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _hero_world()
	var pool: Array = w.jobs.skill_pool(112)
	var seen := 0
	for key: String in pool:
		if not w.book.has(key):
			continue # a skill of a Hero ticket not merged yet is inert (never offered)
		seen += 1
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		if not learn.is_empty():
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_true(seen >= 3, "the core melee skills are defined (%d of the pool)" % seen)


func test_a_meter_gated_finisher_scores_like_any_pool_skill() -> void:
	# A synthetic finisher: Power Strike's definition with a finisher meter block (before the fix BotInput scored it 0).
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"].playable = true
	data.skills.skills.slash_blast["meter"] = {"role": "finisher", "min": 5, "spend": "all", "damage_per_unit": 0.1}
	var setup := RF.with_basic_attack(RF.setup("quiet", 306, data))
	setup["job"] = 112
	var w := RunWorld.new(setup)
	var card := w.upgrades.choice_card("slash_blast_new", w, "normal")
	assert_false(card.is_empty(), "the finisher is offered")
	assert_eq(BotInput.card_score(w, card), 100.0)


func test_the_bot_prefers_a_hero_attack_card_to_a_global_passive_until_three_actives() -> void:
	var w := _hero_world()
	var cards: Array = []
	for id: String in ["slash_blast_new", "passive_might_new"]:
		cards.append(w.upgrades.choice_card(id, w, "normal"))
	assert_eq(BotInput.pick_card_for(w, cards), "slash_blast_new", "a new active beats a passive")


func test_a_hero_with_only_short_attacks_engages_instead_of_kiting() -> void:
	var w := _hero_world()
	for key: String in ["slash_blast", "brandish"]:
		w.learn_skill(key)
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	assert_true(profile.x > 0.0 and profile.x < kite_reach, "longest reach %.0f is a melee reach (< %.0f)" % [profile.x, kite_reach])
	var mob := RF.put_mob(w, 100100, 650, 190, 10000.0)
	var mi := BotInput.decide(w, {})
	assert_true(mi.right and not mi.left, "a mob 250 px ahead: walk toward it")
	w.swarm.x[mob] = 400.0 - 40.0
	mi = BotInput.decide(w, {})
	assert_true(mi.left and not mi.right, "a mob in reach behind: turn toward it")


func test_every_defined_hero_skill_has_a_known_reach_and_none_is_longer_than_the_kite_threshold() -> void:
	var w := _hero_world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	for key: String in w.jobs.skill_pool(112):
		if not w.book.has(key):
			continue
		w.learn_skill(key)
		var reach := SkillRunner.reach_of(w.loadout.stats(key), w)
		assert_true(reach >= 0.0 and reach < kite_reach, "%s reach %.0f" % [key, reach])


func test_pool_scoring_needs_no_per_skill_override() -> void:
	var w := _hero_world()
	w.balance.bot.card_scores.clear()
	for key: String in ["panic", "coma", "monster_magnet"]:
		assert_eq(BotInput.card_score(w, w.upgrades.choice_card(key + "_new", w, "normal")), 100.0)
		assert_eq(BotInput.card_score(w, w.upgrades.choice_card(key + "_rank", w, "normal")), 74.0)
