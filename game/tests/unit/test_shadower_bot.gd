extends TestCase
## The autoplay bot's Shadower scoring, reach and presses (spec #425, SH13 #438). The data checks run on the shipped files; the
## card, reach and press checks run in a synthetic Shadower world (all nine pool skills, Assaulter and Assassinate defined, a dagger
## worn), so they need no cache. Shadower ships `playable: false` until SH14: the fixtures flip it in the test's data copy only.

const SF := preload("res://tests/fixtures/shadower_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## The six a round can hold at once (six active slots); Assaulter is the mobility skill outside them.
const SIX := ["double_stab", "steal", "band_of_thieves", "meso_explosion", "ninja_ambush_shadower", "dark_sight"]
const POOL := ["double_stab", "steal", "savage_blow", "boomerang_step", "band_of_thieves", "meso_explosion", "ninja_ambush_shadower",
	"dark_sight", "smokescreen"]


func _world(p_seed := 438) -> RunWorld:
	var w := RunWorld.new(SF.setup("quiet", p_seed, RF.quiet_data()))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0 # a still monster: the test places it and the bot reacts to where it stands
	return w


## Learns `keys` at rank 1 (and keeps the round-start Assaulter) with nothing else, so the bot's reach profile and presses come
## from those skills alone.
func _only(w: RunWorld, keys: Array) -> void:
	var rank := w.loadout.rank("assaulter")
	assert_true(rank > 0, "Assaulter is learned at round start")
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.loadout.ranks["assaulter"] = rank
	w.loadout.order.append("assaulter")
	for key: String in keys:
		assert_true(w.learn_skill(key), "%s is learnable" % key)
	w.refresh_player_stats()


func _mob(w: RunWorld, x: float, y := 190.0) -> int:
	var slot := RF.put_mob(w, 1110100, x, y, 1000.0)
	w.swarm.y[slot] = y
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	return slot


func test_the_shipped_pool_is_the_nine_skills_and_each_scores_100_new_and_74_rank() -> void:
	var data := DataRepo.load_all()
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	var pool: Array = tree.skill_pool(422)
	assert_eq(pool, POOL)
	var scores: Dictionary = data.balance.bot.card_scores
	for key: String in ["dark_sight", "smokescreen", "meso_explosion"]:
		assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s has an explicit learn score (SH2)" % key)
		assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s has an explicit rank score" % key)


func test_all_nine_pool_skills_assaulter_and_assassinate_are_defined_in_the_synthetic_world() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(422) + ["assaulter", "assassinate"]:
		assert_true(w.book.has(key), "%s has a definition and a book" % key)
	assert_eq(w.jobs.mobility_skill(422), "assaulter")
	assert_eq(Array(w.jobs.start_skills(422)), ["double_stab", "assaulter"])


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	var seen := 0
	for key: String in w.jobs.skill_pool(422):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty() and rank.is_empty(), "%s is offered" % key)
		if not learn.is_empty():
			seen += 1
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_eq(seen, 9, "all nine learn cards exist")


func test_the_bot_takes_each_pool_skills_learn_card_over_passives_and_other_ranks() -> void:
	var w := _world()
	var rivals: Array = []
	for id: String in ["passive_might_new", "steal_rank", "band_of_thieves_rank"]:
		var c := w.upgrades.choice_card(id, w, "normal")
		if not c.is_empty():
			rivals.append(c)
	assert_false(rivals.is_empty(), "something to compete with")
	var taken := 0
	for key: String in w.jobs.skill_pool(422):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		if learn.is_empty():
			continue
		var offer: Array = [rivals[0], learn] + rivals.slice(1)
		assert_eq(BotInput.pick_card_for(w, offer), key + "_new", "%s is taken when offered" % key)
		taken += 1
	assert_eq(taken, 9, "all nine pool skills were offered and taken")


func test_a_mastery_rank_card_of_each_skill_beats_a_passive() -> void:
	var w := _world()
	var passive := w.upgrades.choice_card("passive_might_new", w, "normal")
	assert_false(passive.is_empty())
	for key: String in POOL:
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		if rank.is_empty():
			continue
		assert_true(BotInput.card_score(w, rank) >= 74.0, "%s: a rank card is never scored as a passive" % key)


# --- reach and targets ------------------------------------------------------------------------------------------------

func test_every_pool_skills_reach_is_known_and_the_finisher_the_form_and_the_zone_are_no_kite_reach() -> void:
	var w := _world()
	var reach := {}
	for key: String in POOL + ["assaulter"]:
		var st: Dictionary = w.loadout.stats(key)
		assert_false(st.is_empty(), "%s resolves" % key)
		reach[key] = SkillRunner.reach_of(st, w)
	# Recorded, not tuned (tier C): the dagger swings and the two wide boxes are short, Boomerang Step's forward line is the one
	# skill past the 220 px kite reach.
	assert_eq(reach.double_stab, 88.0, "the Razor's swing")
	assert_eq(reach.savage_blow, 88.0)
	assert_eq(reach.steal, 100.0, "range_around reads as its range")
	assert_eq(reach.band_of_thieves, 130.0, "a symmetric box reads as its left edge")
	assert_eq(reach.ninja_ambush_shadower, 120.0)
	assert_eq(reach.boomerang_step, 300.0)
	for key: String in ["meso_explosion", "dark_sight", "smokescreen", "assaulter"]:
		assert_eq(reach[key], 0.0, "%s is never an attack to kite with" % key)
	var melee := 0
	for key: String in POOL:
		if float(reach[key]) > 0.0 and float(reach[key]) < 220.0:
			melee += 1
	assert_eq(melee, 5, "five of the nine are short melee reaches; the melee kite is Hero's and is not tuned here")


func test_a_bot_with_only_the_melee_dagger_skills_engages_and_boomerang_step_widens_the_profile() -> void:
	var w := _world()
	_only(w, ["double_stab", "steal", "band_of_thieves"])
	assert_eq(BotInput._reach_profile(w, 220.0).x, 130.0, "Band of Thieves is the longest of the three")
	_only(w, ["double_stab", "boomerang_step"])
	assert_eq(BotInput._reach_profile(w, 220.0).x, 300.0, "Boomerang Step ready: the profile widens past the kite reach")


func test_the_finisher_is_a_box_target_and_a_bot_driven_world_casts_it_only_with_four_pips() -> void:
	var w := _world()
	_only(w, ["meso_explosion"])
	var st: Dictionary = w.runner.stats_of(w, "meso_explosion")
	assert_false(w.runner.has_target(w, "meso_explosion", st, w.player.pos), "no monster in the box")
	for dx in [60.0, 80.0, 100.0]:
		_mob(w, 400.0 + dx)
	assert_true(w.runner.has_target(w, "meso_explosion", st, w.player.pos), "three monsters in the forward box")
	w.meter.value = 3
	for tick in 30:
		w.step(DT, MoveInput.new()) # the cast rule is the runner's; the bot only has to leave the character in reach
	assert_eq(w.runner.casts, 0, "3 pips: the meter refuses, the bot waits")
	w.meter.value = 4
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1, "4 pips and 3 monsters: the finisher fires once")
	assert_eq(w.meter.value, 0, "and spends the whole charge (meter_keep 0 at rank 1)")


func test_the_safe_zone_skill_is_a_target_only_with_a_pack_near() -> void:
	var w := _world()
	_only(w, ["smokescreen"])
	var st: Dictionary = w.runner.stats_of(w, "smokescreen")
	assert_false(w.runner.has_target(w, "smokescreen", st, w.player.pos), "no monster")
	for dx in [60.0, 80.0, 100.0]:
		_mob(w, 400.0 + dx)
	assert_true(w.runner.has_target(w, "smokescreen", st, w.player.pos), "three monsters within the admission radius")


func test_dark_sight_is_a_target_with_a_monster_within_150_px_only() -> void:
	var w := _world()
	_only(w, ["dark_sight"])
	var st: Dictionary = w.runner.stats_of(w, "dark_sight")
	var slot := _mob(w, 700.0)
	assert_false(w.runner.has_target(w, "dark_sight", st, w.player.pos), "300 px away")
	w.swarm.x[slot] = 520.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	assert_true(w.runner.has_target(w, "dark_sight", st, w.player.pos), "120 px away")


# --- presses: only Assaulter --------------------------------------------------------------------------------------------

func test_the_bot_never_presses_a_skill_key_on_a_quiet_field_even_with_every_skill_learned() -> void:
	var w := _world()
	_only(w, SIX)
	_mob(w, 520.0)
	var memo := {}
	var pressed := 0
	for tick in 120:
		var input := BotInput.decide(w, memo)
		if not input.skills_pressed.is_empty() or not input.skills_held.is_empty():
			pressed += 1
		w.step(DT, input)
	assert_eq(pressed, 0, "the pool auto-casts: no skill key is pressed at 120 px")


func test_a_mob_within_60_px_presses_assaulters_key_and_nothing_else() -> void:
	var w := _world()
	_only(w, SIX)
	_mob(w, 440.0)
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("rush"), "Assaulter is on the shared rush key")
	assert_eq(input.skills_pressed.size(), 1, "only the dash branch presses a key")
	assert_true(input.skills_held.is_empty())
	assert_true(input.left and not input.right, "away from the mob")
