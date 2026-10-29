extends TestCase
## The autoplay bot with a Dark Knight (spec #348 DK-9, D10 #358): explicit card scores for the pool, the Beholder taken like
## any other pool skill, and a melee reach profile that ignores the long skills that pay HP (Dragon Fury 241 px and Dragon Roar 400 px are
## longer than `engage.kite_reach`, 220 px, yet the knight must walk toward a mob like Hero). Synthetic assets, no cache.

const DKF := preload("res://tests/fixtures/dark_knight_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SPEAR := 1432000
const HP_SKILLS := ["dragon_fury", "dragon_roar"]


## A quiet Dark Knight (132) world on the flat synthetic stage, god mode, facing right at x 400.
func _world(seed_value := 358) -> RunWorld:
	var data := RF.quiet_data()
	var setup := DKF.setup("quiet", seed_value, data)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func _learn_whole_pool(w: RunWorld) -> void:
	for key: String in w.jobs.skill_pool(132):
		assert_true(w.book.has(key), key + " is defined")
		w.learn_skill(key)


func test_every_pool_key_of_132_has_an_explicit_new_100_and_rank_74_score() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var pool: Array = JobTree.from_data(data.jobs, data.jobs_survivor).skill_pool(132)
	assert_eq(pool.size(), 8)
	for key: String in pool:
		assert_eq(float(scores.get(key + "_new", -1)), 100.0, key + " learn card")
		assert_eq(float(scores.get(key + "_rank", -1)), 74.0, key + " rank card")


func test_the_scores_come_from_the_dark_knight_line_file_not_the_shared_list() -> void:
	var line: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/jobs/dark_knight.json"))
	var own: Dictionary = line.balance.bot.card_scores
	assert_eq(own.size(), 16, "two entries for each of the eight pool keys")
	var shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/balance.json")).bot.card_scores
	assert_false(shared.has("dragon_fury_new"), "the shared balance.json lists no Dark Knight key")


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74_the_beholder_too() -> void:
	var w := _world()
	var seen := 0
	for key: String in w.jobs.skill_pool(132):
		assert_true(w.book.has(key), key + " is defined")
		seen += 1
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		assert_false(learn.is_empty(), key + " learn card is offered")
		assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
	assert_eq(seen, 8)
	w.learn_skill("beholder")
	var rank := w.upgrades.choice_card("beholder_rank", w, "normal")
	assert_false(rank.is_empty())
	assert_eq(BotInput.card_score(w, rank), 74.0, "Beholder rank card")


func test_a_new_active_beats_a_passive() -> void:
	var w := _world()
	var cards: Array = []
	for id: String in ["dragon_fury_new", "passive_might_new"]:
		cards.append(w.upgrades.choice_card(id, w, "normal"))
	assert_eq(BotInput.pick_card_for(w, cards), "dragon_fury_new")


# --- DK-9: the reach ignores skills that pay HP -----------------------------------------------------------------------

func test_dragon_fury_and_roar_carry_an_hp_cost_and_reach_past_the_kite_threshold() -> void:
	var w := _world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	for key: String in HP_SKILLS:
		w.learn_skill(key)
		assert_true(int(w.loadout.stats(key).hp_cost) > 0, key + " pays HP")
		# At the top rank (the spec quotes 241 px and 400 px).
		var box := w.loadout.stats(key, 8).box as Rect2
		assert_true(-box.position.x > kite_reach, "%s box edge %.0f is past %.0f" % [key, -box.position.x, kite_reach])


func test_the_reach_profile_skips_an_hp_paying_skill_past_the_kite_threshold() -> void:
	var w := _world()
	w.learn_skill("spear_crusher")
	var crusher := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	assert_true(crusher.x > 0.0 and crusher.x < float(w.balance.bot.engage.kite_reach))
	w.learn_skill("dragon_fury")
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x, crusher.x, "Dragon Fury (241 px, an HP cost) does not lengthen the reach")
	w.learn_skill("dragon_roar")
	w.loadout.set_rank("dragon_roar", 8)
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x, crusher.x, "nor does Dragon Roar at rank 8 (400 px, a cost and a gate)")


func test_a_knight_whose_only_attacks_pay_hp_and_reach_far_has_no_profile() -> void:
	var w := _world()
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	w.learn_skill("dragon_fury")
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)), Vector2.ZERO, "nothing the bot positions for")


func test_an_hp_gate_alone_is_enough_to_skip_the_reach() -> void:
	var data := RF.quiet_data()
	data.skills.skills.dragon_roar.erase("hp_cost")
	var w := RunWorld.new(DKF.setup("quiet", 358, data))
	RF.place_player(w, 400)
	w.learn_skill("spear_crusher")
	var crusher := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	w.learn_skill("dragon_roar")
	w.loadout.set_rank("dragon_roar", 8)
	var st := w.loadout.stats("dragon_roar")
	assert_eq(int(st.hp_cost), 0, "no cost left")
	assert_true(float(st.hp_gate) > 0.0, "the gate stays")
	assert_true(SkillRunner.reach_of(st, w) >= float(w.balance.bot.engage.kite_reach), "and the box is long")
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x, crusher.x, "the gate alone keeps it out of the profile")


func test_a_short_hp_paying_skill_still_counts() -> void:
	# Hero's Slash Blast (a flat HP cost, 132 px) is a melee attack the bot positions for: the rule only skips long ones.
	var w := _world()
	w.learn_skill("slash_blast")
	assert_true(int(w.loadout.stats("slash_blast").hp_cost) > 0)
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	assert_eq(profile.x, SkillRunner.reach_of(w.loadout.stats("slash_blast"), w))
	assert_true(profile.x > 0.0)


func test_a_knight_with_the_whole_pool_is_a_melee_bot_and_walks_toward_a_mob() -> void:
	var w := _world()
	_learn_whole_pool(w)
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	assert_true(profile.x > 0.0 and profile.x < kite_reach, "longest reach %.0f is a melee reach (< %.0f)" % [profile.x, kite_reach])
	var mob := RF.put_mob(w, 100100, 650, 190, 10000.0)
	var mi := BotInput.decide(w, {})
	assert_true(mi.right and not mi.left, "a mob 250 px ahead: walk toward it")
	w.swarm.x[mob] = 400.0 - 150.0 # past Rush's escape distance, inside every skill's reach
	mi = BotInput.decide(w, {})
	assert_true(mi.left and not mi.right, "a mob in reach behind: turn toward it")


func test_without_the_rule_the_same_knight_would_kite() -> void:
	# The control for the test above: with the HP-paying skills' reach counted, the longest reach passes the threshold.
	var w := _world()
	_learn_whole_pool(w)
	var longest := 0.0
	for key: String in HP_SKILLS:
		longest = maxf(longest, -(w.loadout.stats(key, 8).box as Rect2).position.x)
	assert_true(longest > float(w.balance.bot.engage.kite_reach))


func test_every_pool_skill_has_a_known_reach_and_only_hp_payers_reach_past_the_kite_threshold() -> void:
	var w := _world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	var long_ones := []
	for key: String in w.jobs.skill_pool(132):
		w.learn_skill(key)
		w.loadout.set_rank(key, 8)
		var st := w.loadout.stats(key)
		var reach := SkillRunner.reach_of(st, w)
		assert_true(reach >= 0.0, "%s reach %.0f" % [key, reach])
		if reach >= kite_reach:
			long_ones.append(key)
			assert_true(int(st.hp_cost) > 0 or float(st.hp_gate) > 0.0, "%s reaches %.0f px and pays HP" % [key, reach])
	assert_true("dragon_fury" in long_ones and "dragon_roar" in long_ones, "the two long ones the rule exists for: %s" % str(long_ones))


func test_the_bot_keeps_drinking_potions_as_a_dark_knight() -> void:
	var w := _world()
	_learn_whole_pool(w)
	w.god = false
	var ps := w.player_state
	w._hp = float(ps.max_hp) * 0.2
	w._write_player_state(0.0)
	var guard := float(w.balance.get("potions", {}).get("bot", {}).get("min_restore_fraction", 0.5))
	var wants := BotInput.worth_drinking(w, "hp", float(w.player_state.max_hp) - float(w.player_state.hp), guard)
	assert_eq(BotInput.decide(w, {}).drink_hp, wants, "the decision is the one the potion rule gives")
	assert_true(wants, "a knight at 20% HP with a potion ready drinks")


func test_the_knight_escapes_a_mob_on_top_of_it_with_rush_like_hero() -> void:
	var w := _world()
	_learn_whole_pool(w)
	assert_eq(w.manual_skill("rush"), "rush_dark_knight")
	RF.put_mob(w, 100100, 400.0 - 40.0, 190, 10000.0)
	var mi := BotInput.decide(w, {})
	assert_true(mi.skills_pressed.get("rush", false), "a mob within Rush's threat distance: Rush")
	var far := _world()
	_learn_whole_pool(far)
	RF.put_mob(far, 100100, 400.0 + 200.0, 190, 10000.0)
	assert_false(BotInput.decide(far, {}).skills_pressed.get("rush", false), "a mob 200 px away is not an emergency")
