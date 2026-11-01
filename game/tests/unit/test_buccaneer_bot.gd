extends TestCase
## The autoplay bot's Buccaneer scoring, reach and engagement (spec #412, B11 #423; the Buccaneer copy of test_hero_bot). Data checks
## run on the shipped files; the card and reach checks use the synthetic books of `buccaneer_fixtures.gd` (every pool skill defined) on
## the quiet stage and need no cache. BC6/BC7 noted that a meter-gated skill scored 0 for the bot; H9 #305 fixed that in `card_score`,
## and the explicit `card_scores` rows of jobs/buccaneer.json pin it: Energy Drain and Energy Orb are taken like any pool skill.

const BF := preload("res://tests/fixtures/buccaneer_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const POOL := ["flash_fist", "somersault_kick", "backspin_blow", "double_uppercut", "corkscrew_blow", "barrage", "dragon_strike",
	"energy_drain", "energy_orb", "transformation", "super_transformation"]


func test_every_pool_skill_of_every_playable_job_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in tree.playable_jobs():
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_eleven_buccaneer_keys_are_exactly_the_pool_and_the_rows_live_in_the_line_file() -> void:
	var data := DataRepo.load_all()
	assert_eq(data.jobs_survivor.jobs["512"].skill_pool, POOL, "a pool change must come with its card scores")
	var line: Dictionary = DataRepo.load_json("res://data/survivor/jobs/buccaneer.json").balance.bot.card_scores
	var keys: Array = line.keys()
	keys.sort()
	var want: Array = []
	for key: String in POOL:
		want.append(key + "_new")
		want.append(key + "_rank")
	want.sort()
	assert_eq(keys, want, "exactly the pool's pair, nothing shared edited")


func test_the_finishers_the_forms_and_dragon_strike_are_named_not_left_to_the_default_scorer() -> void:
	var scores: Dictionary = DataRepo.load_all().balance.bot.card_scores
	for key: String in ["energy_drain", "energy_orb", "transformation", "super_transformation", "dragon_strike"]:
		assert_true(scores.has(key + "_new") and scores.has(key + "_rank"), key)


## A Buccaneer round on the quiet stage with every pool skill defined (the shipped data has 512 playable), the player at x = 400
## facing right, invulnerable.
func _world(seed_value := 423) -> RunWorld:
	var data := RF.quiet_data()
	var w := RunWorld.new(BF.setup("quiet", seed_value, data))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	for key: String in POOL:
		assert_true(w.book.has(key), key + " is defined by the fixtures")
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty(), key + " has a learn card")
		if not learn.is_empty():
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")


func test_the_finishers_score_like_attacks_even_without_the_explicit_rows() -> void:
	# The bot's meter-gated score was 0 before H9 #305; the pool default takes over if the rows are ever removed.
	var w := _world()
	w.balance.bot.card_scores.clear()
	for key: String in ["energy_drain", "energy_orb"]:
		assert_eq(BotInput.card_score(w, w.upgrades.choice_card(key + "_new", w, "normal")), 100.0, key)
		assert_eq(BotInput.card_score(w, w.upgrades.choice_card(key + "_rank", w, "normal")), 74.0, key)


func test_the_bot_prefers_each_new_pool_skill_to_a_global_passive() -> void:
	var w := _world()
	for key: String in POOL:
		var cards := [w.upgrades.choice_card(key + "_new", w, "normal"), w.upgrades.choice_card("passive_might_new", w, "normal")]
		assert_false(cards[0].is_empty(), key + " is offered")
		assert_eq(BotInput.pick_card_for(w, cards), key + "_new", "a new active beats a passive (%s)" % key)


## The form subs (Shockwave 330 px, Demolition and Snatch 300 px) are not checked here: they fire only inside a form and are never
## in the loadout order the reach profile reads, so their longer boxes cannot make the bot kite.
func test_finishers_forms_and_dragon_strike_have_no_reach_and_every_other_skill_is_melee_ranged() -> void:
	var w := _world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	for key: String in POOL + ["dash"]:
		assert_true(w.book.has(key), key)
		w.learn_skill(key)
		var reach := SkillRunner.reach_of(w.loadout.stats(key), w)
		assert_true(reach >= 0.0 and reach < kite_reach, "%s reach %.0f is below the kite threshold %.0f" % [key, reach, kite_reach])
		if key in ["energy_drain", "energy_orb", "transformation", "super_transformation", "dragon_strike", "dash"]:
			assert_eq(reach, 0.0, "%s counts no reach (finisher, form, buff or bot.reach 0)" % key)


func test_a_buccaneer_with_the_whole_pool_in_its_loadout_walks_toward_a_mob() -> void:
	var w := _world()
	for key: String in POOL:
		w.learn_skill(key)
	var learned := POOL.filter(func(key: String) -> bool: return w.loadout.has(key))
	assert_true(learned.size() >= 6, "the six active slots are full (%d learned)" % learned.size())
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	assert_true(profile.x > 0.0 and profile.x < kite_reach, "longest reach %.0f is a melee reach (< %.0f)" % [profile.x, kite_reach])
	var mob := RF.put_mob(w, 100100, 650, 190, 10000)
	var mi := BotInput.decide(w, {})
	assert_true(mi.right and not mi.left, "a mob 250 px ahead: walk toward it")
	w.swarm.x[mob] = 400.0 - 40.0
	mi = BotInput.decide(w, {})
	assert_true(mi.left and not mi.right, "a mob in reach behind: turn toward it")
	w.swarm.x[mob] = 400.0 + 40.0
	mi = BotInput.decide(w, {})
	assert_false(mi.left, "a mob 40 px ahead: the bot does not back away (no kiting)")


func test_dash_is_pressed_by_its_manual_rule_and_potions_are_still_drunk() -> void:
	var w := _world()
	assert_true(w.loadout.has("dash"), "Dash is learned at the start (mobility slot)")
	var ps := w.player_state
	ps.hp = int(float(ps.max_hp) * 0.1)
	RF.put_mob(w, 100100, 440, 190, 10000)
	var mi := BotInput.decide(w, {})
	assert_true(mi.skill_pressed("dash"), "low HP with a mob close: Dash is pressed")
	assert_true(mi.drink_hp, "and the HP potion is drunk")
	ps.hp = int(ps.max_hp)
	mi = BotInput.decide(w, {})
	assert_false(mi.skill_pressed("dash"), "healthy and not surrounded: no Dash")
	assert_false(mi.drink_hp, "and no potion")
