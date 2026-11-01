extends TestCase
## The autoplay bot's I/L scoring and reach (spec #319, I11 #330; the I/L copy of H9 #305's test_hero_bot). The data-level checks run
## on the shipped files; the card and reach checks loop the I/L pool and skip a key whose skill is not defined yet (Chain Lightning,
## Blizzard and Big Bang, I8 #327 and I10 #329, were still in flight when this ticket landed), so they cover those automatically
## once they merge. Worlds are the I6 tests' synthetic books on the quiet stage.

const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CHAIN := preload("res://tests/unit/test_chain_cast.gd")
## The ten pool keys ticket I11 owns scores for (the pool minus Energy Bolt and Magic Claw, which F/P's block already scores).
const IL_KEYS := ["cold_beam", "thunder_bolt", "ice_strike", "thunder_spear", "element_composition_il", "ice_demon", "ifrit",
	"chain_lightning", "blizzard", "big_bang_il"]


func test_every_pool_skill_of_both_arch_mages_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [212, 222]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_ten_il_keys_are_exactly_the_pool_minus_the_two_shared_with_f_p() -> void:
	var pool: Array = DataRepo.load_all().jobs_survivor.jobs["222"].skill_pool
	var rest := pool.filter(func(key: String) -> bool: return not (key in ["energy_bolt", "magic_claw"]))
	rest.sort()
	var want := IL_KEYS.duplicate()
	want.sort()
	assert_eq(rest, want, "a pool change must come with its card scores")


func test_ifrit_and_blizzard_are_named_not_left_to_the_default_scorer() -> void:
	# Ifrit is a summon and Blizzard a ground field: the default scorer files neither under attacks, so only these entries take them.
	var scores: Dictionary = DataRepo.load_all().balance.bot.card_scores
	for key: String in ["ifrit", "blizzard", "chain_lightning", "big_bang_il", "element_composition_il"]:
		assert_true(scores.has(key + "_new") and scores.has(key + "_rank"), key)


## An I/L round on the quiet stage: I/L made playable in its own data, the bolts' synthetic books, the player at x=400.
func _il_world(seed_value := 330) -> RunWorld:
	var w: RunWorld = IL.round_world({}, seed_value)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func test_a_learn_card_of_every_defined_il_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _il_world()
	var seen := 0
	for key: String in w.jobs.skill_pool(222):
		if not w.book.has(key):
			continue # a skill of an I/L ticket not merged yet is inert (never offered)
		seen += 1
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty(), key + " has a learn card (a defined pool skill is offered)")
		if not learn.is_empty():
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_true(seen >= 7, "the bolts, Ice Demon, Element Composition and Ifrit are defined (%d of the pool)" % seen)
	assert_true(w.book.has("ifrit"), "Ifrit, a summon the default scorer would file with the passives, is checked")


func test_the_bot_prefers_a_new_il_attack_card_to_a_global_passive() -> void:
	var w := _il_world()
	for key: String in ["thunder_bolt", "ice_strike", "thunder_spear"]:
		var cards := [w.upgrades.choice_card(key + "_new", w, "normal"), w.upgrades.choice_card("passive_might_new", w, "normal")]
		assert_false(cards[0].is_empty(), key + " is offered")
		assert_eq(BotInput.pick_card_for(w, cards), key + "_new", "a new active beats a passive (%s)" % key)


func test_every_defined_il_skill_has_a_known_reach() -> void:
	var w := _il_world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	for key: String in w.jobs.skill_pool(222) + ["teleport_il"]:
		if not w.book.has(key):
			continue
		w.learn_skill(key)
		var st := w.loadout.stats(key)
		var reach := SkillRunner.reach_of(st, w)
		assert_true(reach >= 0.0, "%s reach %.0f" % [key, reach])
		if key == "teleport_il" or String(st.damage_type) == "none":
			assert_eq(reach, 0.0, "%s is not an attack" % key)
		elif String(st.cast_rule) == "chain":
			assert_true(reach > 0.0, "%s: a chain skill's reach is its acquire range, not 0 (the bot would never face a mob)" % key)


func test_an_il_with_the_bolts_kites_like_f_p_because_every_attack_reaches_past_the_kite_threshold() -> void:
	var w := _il_world()
	for key: String in ["cold_beam", "thunder_bolt", "ice_strike", "thunder_spear"]:
		w.learn_skill(key)
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	assert_true(profile.x >= kite_reach, "longest reach %.0f is a ranged reach (>= %.0f): no melee engage mode" % [profile.x, kite_reach])
	RF.put_mob(w, 100100, 470, 190, 100000.0)
	assert_true(BotInput.decide(w, {}).left, "a mob 70 px ahead: back away (kite), as the F/P bot does")


func test_a_chain_skill_reads_as_a_ranged_attack_and_the_bot_kites_with_it() -> void:
	# Chain Lightning (I8) is not defined yet: I4's synthetic chain skill stands in (acquire 450 px, the cast block's reach).
	var w: RunWorld = CHAIN.new()._world()
	w.god = true
	w.player.facing = 1
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	assert_eq(profile.x, CHAIN.ACQUIRE, "the bot reads the chain's acquire range as its reach")
	assert_true(profile.x >= kite_reach)
	RF.put_mob(w, 100100, w.player.pos.x + 70.0, 190, 100000.0)
	assert_true(BotInput.decide(w, {}).left, "a mob 70 px ahead: back away (kite)")


func test_without_its_entry_a_pool_skill_still_scores_like_an_attack() -> void:
	# Ifrit is a `summon`, which the default scorer once filed with the passives. Pool skills without a score override now default
	# to new 100 / rank 74 (spec #296 review), so the entries in jobs/il_arch_mage.json are the same numbers written out.
	var w := _il_world()
	var card := w.upgrades.choice_card("ifrit_new", w, "normal")
	assert_false(card.is_empty())
	assert_eq(BotInput.card_score(w, card), 100.0)
	w.balance.bot.card_scores.erase("ifrit_new")
	assert_eq(BotInput.card_score(w, card), 100.0, "the pool-skill default takes over")
