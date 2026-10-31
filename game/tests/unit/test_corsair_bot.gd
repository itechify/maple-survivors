extends TestCase
## The autoplay bot's Corsair scoring, reach and movement (spec #384, C14 #398; the Corsair copy of test_bowmaster_bot). The data
## checks run on the shipped files; the card, reach and movement checks use the synthetic books of `corsair_fixtures.gd` (all thirteen
## pool skills defined, a Pistol worn) on the quiet stage and need no cache. `BotInput._base_score` alone only treats projectile /
## instant / box skills as attacks, so the two summons and the Battleship (a form) need their explicit rows in jobs/corsair.json.

const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const POOL := ["double_shot", "burst_fire", "invisible_shot", "recoil_shot", "grenade", "flamethrower", "ice_splitter", "octopus",
	"gaviota", "homing_beacon", "aerial_strike", "rapid_fire", "battleship"]
## The skills with no reach to kite with: a summon is never the bot's own attack and the ship is a form.
const NO_REACH := ["octopus", "gaviota", "battleship"]


func _world(p_seed := 398) -> RunWorld:
	var data := RF.quiet_data()
	var w := RunWorld.new(CF.setup("quiet", p_seed, data))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w


func test_every_pool_skill_of_every_playable_job_and_of_corsair_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	var jobs: Array = tree.playable_jobs() + [522]
	for job: int in jobs:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_thirteen_corsair_keys_are_exactly_the_pool_and_the_rows_live_in_the_line_file() -> void:
	var data := DataRepo.load_all()
	assert_eq(data.jobs_survivor.jobs["522"].skill_pool, POOL, "a pool change must come with its card scores")
	var line: Dictionary = DataRepo.load_json("res://data/survivor/jobs/corsair.json").balance.bot.card_scores
	var keys: Array = line.keys()
	keys.sort()
	var want: Array = []
	for key: String in POOL:
		want.append(key + "_new")
		want.append(key + "_rank")
	want.sort()
	assert_eq(keys, want, "exactly the pool's pair, nothing shared edited")


func test_the_two_summons_and_the_form_are_named_not_left_to_the_default_scorer() -> void:
	var scores: Dictionary = DataRepo.load_all().balance.bot.card_scores
	for key: String in ["octopus", "gaviota", "battleship"]:
		assert_eq(float(scores.get(key + "_new", -1)), 100.0, key + " learn card is explicit")
		assert_eq(float(scores.get(key + "_rank", -1)), 74.0, key + " rank card is explicit")


func test_all_thirteen_pool_skills_are_defined_and_the_ships_subs_are_not_pool_entries() -> void:
	var w := _world()
	for key: String in POOL:
		assert_true(w.book.has(key), "%s has a definition and a book" % key)
	assert_eq(w.jobs.skill_pool(522), POOL)
	for key: String in ["battleship_cannon", "battleship_torpedo"]:
		assert_true(w.book.has(key), key)
		assert_false(key in w.jobs.skill_pool(522), "%s is a form sub, not a card" % key)


func test_a_learn_card_of_every_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	var seen := 0
	for key: String in POOL:
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(learn.is_empty() and rank.is_empty(), "%s is offered" % key)
		if not learn.is_empty():
			seen += 1
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_eq(seen, 13, "every pool skill has a learn card (the starting Double Shot's is never offered once it is learned)")


func test_the_bot_picks_each_pool_skills_learn_card_over_passives_and_other_ranks() -> void:
	var w := _world()
	var rivals: Array = []
	for id: String in ["passive_might_new", "double_shot_rank", "passive_area_new"]:
		var c := w.upgrades.choice_card(id, w, "normal")
		if not c.is_empty():
			rivals.append(c)
	assert_false(rivals.is_empty(), "something to compete with")
	for key: String in POOL:
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		if learn.is_empty():
			continue # the starting skill is already learned
		var offer: Array = [rivals[0], learn] + rivals.slice(1)
		assert_eq(BotInput.pick_card_for(w, offer), key + "_new", "%s is taken when offered" % key)


func test_every_defined_skills_reach_is_known_summons_and_the_form_have_none_and_a_burst_reads_as_its_range() -> void:
	var w := _world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	for key: String in POOL + ["battleship_cannon", "battleship_torpedo", "dash"]:
		var st: Dictionary = w.loadout.stats(key)
		assert_false(st.is_empty(), "%s has stats" % key)
		var reach := SkillRunner.reach_of(st, w)
		if key in NO_REACH or key == "dash":
			assert_eq(reach, 0.0, "%s is never a bot attack to kite with" % key)
		elif key in POOL:
			assert_true(reach >= 220.0, "%s reaches %.0f, above the %.0f kite threshold" % [key, reach, kite_reach])
		else:
			assert_true(reach >= 0.0, "%s has a known reach" % key)
	assert_eq(SkillRunner.reach_of(w.loadout.stats("rapid_fire"), w), 350.0, "a burst reads as its range")
	assert_true(SkillRunner.reach_of(w.loadout.stats("double_shot"), w) >= kite_reach, "the starting skill kites")


func test_the_corsair_kites_a_close_mob_with_the_gun_and_dashes_by_the_existing_rule() -> void:
	var w := _world()
	var profile := BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach))
	assert_true(profile.x >= float(w.balance.bot.engage.kite_reach), "the Pistol's skills out-reach the melee threshold (%.0f)" % profile.x)
	var mob := RF.put_mob(w, 100100, 440, 190, 10000)
	var mi := BotInput.decide(w, {})
	assert_true(mi.left and not mi.right, "a mob 40 px ahead: the bot backs away (it kites, it does not close in)")
	assert_false(mi.skill_pressed("dash"), "healthy and alone: no Dash")
	w.player_state.hp = int(float(w.player_state.max_hp) * 0.1)
	mi = BotInput.decide(w, {})
	assert_true(mi.skill_pressed("dash"), "low HP with a mob close: Dash is pressed, the rule every Pirate shares")
	assert_true(mi.drink_hp, "and the HP potion is drunk")
	assert_true(mob >= 0)


func test_the_corsair_dash_is_learned_at_the_start_and_is_no_card() -> void:
	var w := _world()
	assert_true(w.loadout.has("dash"), "Dash is learned at the start (mobility slot)")
	assert_true(w.loadout.has("double_shot"), "and so is Double Shot")
	assert_false(w.upgrades.cards.any(func(c: Dictionary) -> bool: return String(c.get("skill", "")) == "dash"), "Dash has no card at all")


func test_real_cache_the_reaches_the_spec_names_are_above_the_kite_threshold() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var data := RF.quiet_data()
	var setup := CF.setup("quiet", 398, data)
	for book_id: String in ["500", "520", "521", "522"]:
		var img := lib.img("Skill.wz/%s.img" % book_id)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book_id)
		if img == null:
			lib.free()
			return
		setup.skill_imgs[book_id] = img.root
	var w := RunWorld.new(setup)
	lib.free()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	var seen := {}
	for key: String in POOL + ["battleship_cannon"]:
		var reach := SkillRunner.reach_of(w.loadout.stats(key), w)
		seen[key] = reach
		if key in NO_REACH:
			assert_eq(reach, 0.0, key)
		else:
			assert_true(reach >= kite_reach, "%s reaches %.0f, above the %.0f kite threshold" % [key, reach, kite_reach])
	# tier A: the WZ ranges (the spec's table says Double Shot 350, the cache holds 230, the shortest and only just above the threshold).
	assert_eq(seen.double_shot, 230.0)
	assert_eq(seen.grenade, 400.0)
	assert_eq(seen.flamethrower, 350.0)
	assert_eq(seen.rapid_fire, 350.0)
	assert_eq(seen.battleship_cannon, 400.0)
