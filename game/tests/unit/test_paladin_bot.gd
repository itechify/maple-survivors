extends TestCase
## The autoplay bot's Paladin scoring and reach (spec #308, P9 #317). Data-level checks run on the shipped files; the card and
## reach checks loop the Paladin pool on a synthetic world (PaladinFixtures books, the quiet stage), so they cover a pool change.

const PF := preload("res://tests/fixtures/paladin_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CHARGES := ["fire_charge", "ice_charge", "thunder_charge", "holy_charge"]


func test_every_pool_skill_of_hero_paladin_and_f_p_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [112, 122, 212]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_paladin_keys_not_shared_with_hero_are_scored_in_the_paladin_line_file() -> void:
	var own: Dictionary = DataRepo.load_json("res://data/survivor/jobs/paladin.json").balance.bot.card_scores
	var keys := PF.POOL.filter(func(k: String) -> bool: return not (k in ["power_strike", "slash_blast"]))
	for key: String in keys:
		assert_eq(float(own.get(key + "_new", -1)), 100.0, key)
		assert_eq(float(own.get(key + "_rank", -1)), 74.0, key)
	assert_eq(own.size(), keys.size() * 2, "exactly the pool's own keys: a pool change must come with its card scores")
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json").bot.card_scores
	for key: String in keys:
		assert_false(shared.has(key + "_new"), "no shared score for a Paladin skill (%s)" % key)


func test_a_learn_card_of_every_defined_paladin_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := PF.round_world()
	var seen := 0
	for key: String in w.jobs.skill_pool(122):
		if not w.book.has(key):
			continue
		seen += 1
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		if key != "power_strike":
			assert_false(learn.is_empty(), key + " has a learn card (a defined pool skill is offered)")
		if not learn.is_empty():
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_eq(seen, 8, "all eight pool skills are defined")


func test_the_bot_prefers_a_new_charge_or_blast_card_to_a_global_passive() -> void:
	var w := PF.round_world()
	for key: String in CHARGES + ["blast", "monster_magnet_paladin"]:
		var cards := [w.upgrades.choice_card(key + "_new", w, "normal"), w.upgrades.choice_card("passive_might_new", w, "normal")]
		assert_false(cards[0].is_empty(), key + " is offered")
		assert_eq(BotInput.pick_card_for(w, cards), key + "_new", "a new active beats a passive (%s)" % key)


func test_every_defined_paladin_skill_has_a_known_reach() -> void:
	var w := PF.round_world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	var seen := {}
	for key: String in w.jobs.skill_pool(122) + ["rush_paladin"]:
		if not w.book.has(key):
			continue
		w.learn_skill(key)
		var st := w.loadout.stats(key)
		var reach := SkillRunner.reach_of(st, w)
		seen[key] = reach
		assert_true(reach >= 0.0 and reach < kite_reach, "%s reach %.0f is under the kite threshold %.0f" % [key, reach, kite_reach])
		if key in CHARGES or key == "monster_magnet_paladin" or key == "rush_paladin":
			assert_eq(reach, 0.0, "%s is not a reach attack for the bot (a Form, a pull, a dash)" % key)
	assert_true(seen.has("blast") and float(seen.blast) > 0.0, "Blast reaches as far as the held weapon swings (rule weapon_reach)")
	assert_eq(seen.blast, seen.power_strike, "Blast and Power Strike read the same weapon reach: both are weapon_reach casts")


func test_a_paladin_with_only_short_attacks_engages_instead_of_kiting() -> void:
	var w := PF.round_world()
	for key: String in ["power_strike", "slash_blast", "blast"] + CHARGES:
		if w.book.has(key) and not w.loadout.has(key):
			w.learn_skill(key)
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	assert_true(profile.x > 0.0 and profile.x < kite_reach, "longest reach %.0f is a melee reach (< %.0f)" % [profile.x, kite_reach])
	var mob := RF.put_mob(w, 100100, 650, 190, 10000.0)
	var mi := BotInput.decide(w, {})
	assert_true(mi.right and not mi.left, "a mob 250 px ahead: walk toward it")
	w.swarm.x[mob] = 400.0 - 70.0 # past the Rush escape distance (60 px), inside the weapon reach
	mi = BotInput.decide(w, {})
	assert_true(mi.left and not mi.right, "a mob in reach behind: turn toward it")


func test_the_bots_rush_escape_is_heros_for_a_paladin() -> void:
	var w := PF.round_world()
	assert_eq(w.manual_skill("rush"), "rush_paladin", "Rush is on the skill key")
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "no mob: no dash")
	RF.put_mob(w, 100100, 430, 190, 100000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	assert_true(BotInput.decide(w, {}).skill_pressed("rush"), "a mob within 60 px: the Rush escape fires, as Hero's")
	var hero := PF.round_world()
	assert_eq(float(hero.book.def("rush_paladin").rush.bot_threat_distance),
		float(DataRepo.load_all().skills.skills.rush_hero.rush.bot_threat_distance), "the same threat distance as rush_hero")


func test_pool_scoring_needs_no_per_skill_override() -> void:
	var w := PF.round_world()
	w.balance.bot.card_scores.clear()
	for key: String in ["blast", "monster_magnet_paladin", "holy_charge", "fire_charge"]:
		assert_eq(BotInput.card_score(w, w.upgrades.choice_card(key + "_new", w, "normal")), 100.0)
		assert_eq(BotInput.card_score(w, w.upgrades.choice_card(key + "_rank", w, "normal")), 74.0)
