extends TestCase
## The autoplay bot's Bishop scoring and reach (spec #372, BS9 #381; the Bishop copy of test_il_bot). The data-level checks run on
## the shipped files; the card and reach checks loop the Bishop pool and skip a key whose skill is not defined yet (Summon Dragon,
## Bahamut and Resurrection, BS7 #379 and BS8 #380, were in flight when this ticket landed), so they cover those automatically once
## they merge. Worlds are the BS5/BS4/BS6 tests' synthetic books on the quiet stage, Bishop made playable in the test's own data.
## No `card_scores` block is added by this ticket: the ten pool keys already score new 100 / rank 74 (BS2).

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const G := preload("res://tests/unit/test_bishop_genesis.gd")
const HF := preload("res://tests/fixtures/heal_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const POOL := ["holy_arrow", "magic_claw", "shining_ray", "angel_ray", "heal", "summon_dragon", "bahamut", "genesis",
	"big_bang_bishop", "resurrection"]


func test_every_pool_skill_of_the_four_arch_mage_lines_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [212, 222, 232]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_the_bishop_keys_are_exactly_the_ten_pool_skills_and_no_card_scores_block_is_added_here() -> void:
	var jobs: Dictionary = DataRepo.load_all().jobs_survivor.jobs
	var pool: Array = jobs["232"].skill_pool
	var want := POOL.duplicate()
	want.sort()
	var have := pool.duplicate()
	have.sort()
	assert_eq(have, want, "a pool change must come with its card scores")
	var file: Dictionary = DataRepo.load_json("res://data/survivor/jobs/bishop.json")
	var block: Dictionary = file.balance.bot.card_scores
	var keys: Array = block.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))
	assert_eq(keys.size(), 2 * POOL.size(), "the line file spells out only the pool's new/rank pairs (BS2); BS9 adds none")


## A Bishop round on the quiet stage: the bolts, Heal, Genesis and Big Bang as synthetic books (Bishop playable in this copy of
## the data), the player at x = 400 facing right, god mode.
func _world(seed_value := 381) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["232"]["playable"] = true
	var setup := G.add_books(BF.setup(data, seed_value))
	setup.skill_imgs["230"].skill["2301002"] = {"level": HF.levels()}
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	w.drain_events()
	return w


func test_a_learn_card_of_every_defined_bishop_pool_skill_scores_100_and_a_rank_card_74() -> void:
	var w := _world()
	var seen := 0
	for key: String in w.jobs.skill_pool(232):
		if not w.book.has(key):
			continue # a skill of a Bishop ticket not merged yet is inert (never offered)
		seen += 1
		var learn := w.upgrades.choice_card(key + "_new", w, "normal")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		if key != "holy_arrow":
			assert_false(learn.is_empty(), key + " has a learn card (a defined pool skill is offered)")
		if not learn.is_empty():
			assert_eq(BotInput.card_score(w, learn), 100.0, key + " learn card")
		if not rank.is_empty():
			assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
	assert_true(seen >= 6, "Holy Arrow, Shining Ray, Angel Ray, Heal, Genesis and Big Bang are defined (%d of the pool)" % seen)
	for key: String in ["heal", "genesis", "big_bang_bishop"]:
		assert_true(w.book.has(key), "%s, which the default scorer could file with the passives, is checked" % key)


func test_the_bot_prefers_a_new_bishop_attack_card_to_a_global_passive() -> void:
	var w := _world()
	for key: String in ["shining_ray", "angel_ray", "genesis"]:
		var cards := [w.upgrades.choice_card(key + "_new", w, "normal"), w.upgrades.choice_card("passive_might_new", w, "normal")]
		assert_false(cards[0].is_empty(), key + " is offered")
		assert_eq(BotInput.pick_card_for(w, cards), key + "_new", "a new active beats a passive (%s)" % key)


func test_heal_scores_like_an_attack_card_though_it_is_not_one() -> void:
	var w := _world()
	var card := w.upgrades.choice_card("heal_new", w, "normal")
	assert_false(card.is_empty(), "Heal is offered")
	assert_eq(BotInput.card_score(w, card), 100.0)
	assert_eq(BotInput.pick_card_for(w, [card, w.upgrades.choice_card("passive_might_new", w, "normal")]), "heal_new")


func test_every_defined_bishop_skill_has_a_known_reach_and_heal_and_resurrection_have_none() -> void:
	var w := _world()
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	var checked := 0
	for key: String in w.jobs.skill_pool(232) + ["teleport_cleric"]:
		if not w.book.has(key):
			continue
		w.learn_skill(key)
		var st := w.loadout.stats(key)
		var reach := SkillRunner.reach_of(st, w)
		checked += 1
		assert_true(reach >= 0.0, "%s reach %.0f" % [key, reach])
		if key in ["heal", "resurrection", "teleport_cleric"]:
			assert_eq(reach, 0.0, "%s is not an attack: no engage reach" % key)
		elif String(st.cast_rule) == "chain":
			assert_true(reach > 0.0, "%s: a chain skill's reach is its acquire range" % key)
	assert_true(checked >= 7, "the pool skills and Teleport that exist are checked (%d)" % checked)
	assert_eq(SkillRunner.reach_of(w.loadout.stats("heal"), w), 0.0, "Heal's reach is 0")
	assert_true(SkillRunner.reach_of(w.loadout.stats("holy_arrow"), w) >= kite_reach, "Holy Arrow reaches past the kite threshold")


func test_a_bishop_with_holy_arrow_kites_because_its_reach_is_past_the_kite_threshold() -> void:
	var w := _world()
	w.learn_skill("heal")
	var profile := BotInput._reach_profile(w)
	var kite_reach := float(w.balance.bot.engage.kite_reach)
	assert_true(profile.x >= kite_reach, "longest reach %.0f is a ranged reach (>= %.0f): no melee engage mode" % [profile.x, kite_reach])
	assert_eq(profile.x, 480.0, "Holy Arrow's 480 px; Heal (reach 0) does not change the profile")
	RF.put_mob(w, 100100, 470, 190, 100000.0)
	assert_true(BotInput.decide(w, {}).left, "a mob 70 px ahead: back away (kite), as the F/P bot does")


func test_the_bot_presses_a_key_only_for_teleport_and_never_for_the_pool_skills() -> void:
	var w := _world()
	for key: String in w.jobs.skill_pool(232):
		if w.book.has(key):
			w.learn_skill(key)
	RF.put_mob(w, 100100, 440, 190, 100000.0)
	RF.put_mob(w, 100100, 360, 190, 100000.0)
	var memo := {}
	for tick in 120:
		var input := BotInput.decide(w, memo)
		for id: String in input.skills_pressed.keys() + input.skills_held.keys():
			assert_eq(id, "teleport", "the only key the Bishop bot presses is Teleport (never %s: Heal, Resurrection and the rest cast themselves)" % id)
		w.step(1.0 / 60.0, input)
	assert_false(w.book.has("resurrection") and BotInput.decide(w, memo).skill_requested("resurrection"), "never a key for Resurrection")
