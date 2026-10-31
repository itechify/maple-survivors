extends TestCase
## The autoplay bot's Night Lord scoring, reach and Flash Jump branch (spec #383, NL11 #410). The data checks run on the shipped
## files; the card, reach and press checks run in a synthetic Night Lord world (all eight pool skills and Flash Jump defined, a claw
## worn), so they need no cache. Night Lord ships `playable: false` until NL12: the fixtures flip it in the test's data copy only.

const NF := preload("res://tests/fixtures/night_lord_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const POOL := ["lucky_seven", "drain", "avenger", "triple_throw", "ninja_storm", "ninja_ambush", "shadow_partner", "shadow_meso"]
## Six of the eight: a round holds six active slots, so a bot never owns the whole pool at once.
const SIX := ["lucky_seven", "drain", "avenger", "triple_throw", "ninja_storm", "shadow_partner"]


func _world(p_seed := 410) -> RunWorld:
	var w := RunWorld.new(NF.setup("quiet", p_seed, RF.quiet_data()))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


## Learns `keys` at rank 1 (and the round-start Flash Jump) with nothing else, so the bot's reach profile and presses come from
## those skills alone.
func _only(w: RunWorld, keys: Array) -> void:
	var flash_rank := w.loadout.rank("flash_jump")
	assert_true(flash_rank > 0, "Flash Jump is learned at round start")
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.loadout.ranks["flash_jump"] = flash_rank
	w.loadout.order.append("flash_jump")
	for key: String in keys:
		assert_true(w.learn_skill(key), "%s is learnable" % key)
	w.refresh_player_stats()


func _mob(w: RunWorld, x: float, y := 190.0) -> int:
	var slot := RF.put_mob(w, 1110100, x, y, 1000.0)
	w.swarm.y[slot] = y # put_mob settles on the floor; a mid-air test wants it level with the character
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	return slot


func test_every_night_lord_pool_skill_has_explicit_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	var pool: Array = tree.skill_pool(412)
	assert_eq(pool.size(), 8)
	for key: String in POOL:
		assert_true(key in pool, key)
		assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card" % key)
		assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card" % key)


func test_all_eight_pool_skills_and_flash_jump_are_defined_in_the_synthetic_world() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(412):
		assert_true(w.book.has(key), "%s has a definition and a book" % key)
	assert_true(w.book.has("flash_jump"))
	assert_eq(w.jobs.mobility_skill(412), "flash_jump")


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	var seen := 0
	for key: String in w.jobs.skill_pool(412):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty() and rank.is_empty(), "%s is offered" % key)
		if not learn.is_empty():
			seen += 1
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_eq(seen, 8, "all eight learn cards exist")


func test_the_summon_scores_like_an_attack_with_or_without_its_explicit_entry() -> void:
	var w := _world()
	var learn := w.upgrades.choice_card("shadow_partner_new", w, "normal")
	assert_false(learn.is_empty())
	assert_eq(BotInput.card_score(w, learn), 100.0)
	assert_eq(float(DataRepo.load_all().balance.bot.card_scores.get("shadow_partner_new", -1)), 100.0, "the explicit entry exists")
	for key in ["shadow_partner_new", "shadow_partner_rank"]:
		w.balance.bot.card_scores.erase(key)
	assert_eq(BotInput.card_score(w, learn), 100.0, "the pool default gives the clone the same base")
	var rank := w.upgrades.choice_card("shadow_partner_rank", w, "normal")
	if not rank.is_empty():
		assert_eq(BotInput.card_score(w, rank), 74.0)


func test_the_bot_takes_each_pool_skills_learn_card_over_passives_and_other_ranks() -> void:
	var w := _world()
	var rivals: Array = []
	for id: String in ["passive_might_new", "lucky_seven_rank", "drain_rank"]:
		var c := w.upgrades.choice_card(id, w, "normal")
		if not c.is_empty():
			rivals.append(c)
	assert_false(rivals.is_empty(), "something to compete with")
	var taken := 0
	for key: String in w.jobs.skill_pool(412):
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		if learn.is_empty():
			continue
		var offer: Array = [rivals[0], learn] + rivals.slice(1)
		assert_eq(BotInput.pick_card_for(w, offer), key + "_new", "%s is taken when offered" % key)
		taken += 1
	assert_eq(taken, 8, "all eight pool skills were offered and taken")


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

func test_every_pool_skills_reach_is_known_and_the_filler_stars_are_the_shortest() -> void:
	var w := _world()
	var reach := {}
	for key: String in POOL:
		var st: Dictionary = w.loadout.stats(key)
		assert_false(st.is_empty(), "%s resolves" % key)
		reach[key] = SkillRunner.reach_of(st, w)
	assert_eq(reach.lucky_seven, 250.0, "the filler reach, tier C (recorded, not tuned)")
	assert_eq(reach.drain, 250.0)
	assert_eq(reach.avenger, 350.0, "pierce_field reads as its range")
	assert_eq(reach.triple_throw, 300.0, "focus reads as its range")
	assert_eq(reach.shadow_meso, 300.0)
	assert_eq(reach.shadow_partner, 0.0, "a clone is never a bot attack to kite with")
	for key: String in ["ninja_storm", "ninja_ambush"]:
		var st: Dictionary = w.loadout.stats(key)
		assert_true(bool(st.has_box), key)
		assert_eq(reach[key], maxf(-(st.box as Rect2).position.x, 0.0), "%s reads as the left edge of its box" % key)
		assert_true(reach[key] > 0.0)
	var shortest := 1e9
	for key: String in ["lucky_seven", "drain", "avenger", "triple_throw", "shadow_meso"]:
		shortest = minf(shortest, float(reach[key]))
	assert_eq(shortest, 250.0, "the two fillers have the shortest star reach of the pool")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("flash_jump"), w), 0.0, "Flash Jump is no attack")


func test_has_target_follows_the_range_of_a_focus_and_a_pierce_field_skill() -> void:
	var w := _world()
	_only(w, ["triple_throw", "avenger"])
	var origin := w.player.pos
	assert_true(w.book.def("triple_throw").cast.has("focus"), "Triple Throw is a cast.focus skill")
	assert_eq(String(w.book.def("avenger").pierce_field), "mobCount", "Avenger is a pierce_field skill")
	var near := _mob(w, w.player.pos.x + 280.0)
	for key: String in ["triple_throw", "avenger"]:
		assert_true(w.runner.has_target(w, key, w.runner.stats_of(w, key), origin), "%s: a monster in its range" % key)
	w.swarm.x[near] = w.player.pos.x + 330.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	assert_false(w.runner.has_target(w, "triple_throw", w.runner.stats_of(w, "triple_throw"), origin), "330 px is past 300")
	assert_true(w.runner.has_target(w, "avenger", w.runner.stats_of(w, "avenger"), origin), "but inside Avenger's 350")
	w.swarm.x[near] = w.player.pos.x + 380.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	assert_false(w.runner.has_target(w, "avenger", w.runner.stats_of(w, "avenger"), origin), "380 px is past 350")


func test_a_bot_with_only_the_filler_keeps_the_250_px_kite_and_a_longer_skill_widens_it() -> void:
	var w := _world()
	_only(w, ["lucky_seven"])
	assert_eq(BotInput._reach_profile(w, 400.0).x, 250.0, "Lucky Seven alone: the tighter kite than an archer's 300-450")
	_only(w, ["lucky_seven", "drain", "avenger"])
	assert_eq(BotInput._reach_profile(w, 400.0).x, 350.0, "Avenger ready: the profile widens to its 350")


# --- the Flash Jump branch and no other press -------------------------------------------------------------------------

func test_the_bot_never_presses_a_skill_key_on_the_ground_even_with_every_skill_learned() -> void:
	var w := _world()
	_only(w, SIX)
	_mob(w, 440.0)
	var memo := {}
	var pressed := 0
	for tick in 120:
		var input := BotInput.decide(w, memo)
		if not input.skills_pressed.is_empty() or not input.skills_held.is_empty():
			pressed += 1
		w.step(DT, input)
	assert_eq(pressed, 0, "the pool auto-casts and Flash Jump refuses the ground: no skill key is ever pressed")


func test_airborne_beside_a_close_mob_the_bot_presses_flash_jump_and_nothing_else() -> void:
	var w := _world()
	_only(w, SIX)
	w.player.place(Vector2(400.0, 100.0), w.fhm)
	_mob(w, 440.0, 100.0)
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("flash_jump"), "a mob 40 px away at its height")
	assert_eq(input.skills_pressed.size(), 1, "only Flash Jump's branch presses a key")
	assert_true(input.skills_held.is_empty())
	assert_true(input.left and not input.right, "away from the mob")


func test_a_far_mob_or_a_spent_flash_does_not_press_it() -> void:
	var w := _world()
	_only(w, SIX)
	w.player.place(Vector2(400.0, 100.0), w.fhm)
	var m := _mob(w, 600.0, 100.0)
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "200 px away is no emergency")
	w.swarm.x[m] = 440.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	w.player.flash_spent = true
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "already flashed in this jump")


func test_a_job_without_flash_jump_never_gets_the_branch() -> void:
	var w := RF.quiet_world(400.0, 410)
	w.player.place(Vector2(400.0, 100.0), w.fhm)
	_mob(w, 440.0, 100.0)
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "the F/P bot has no mobility skill of this name")
