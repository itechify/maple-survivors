extends TestCase
## Pet rules that cut across the sim (spec #34, ticket #119): the Magnet card with a VAC pet, upgrade prerequisites,
## determinism, and that a round without a pet is untouched.

const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func _offered_magnet(w: RunWorld, draws: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seen := 0
	for draw in draws:
		for card: Dictionary in w.upgrades.roll_choices(w, rng, 3):
			if card.id == "magnet":
				seen += 1
	return seen


func test_magnet_is_never_offered_while_a_vac_pet_is_out_and_is_offered_again_without_one() -> void:
	var vac := PF.world(PF.EVERYTHING)
	assert_false("magnet" in vac.upgrades.eligible(vac), "not eligible with VAC")
	assert_eq(_offered_magnet(vac, 400), 0, "never offered in 400 draws")
	var no_vac := PF.world([PF.KITTY, PF.WING, PF.BINOCULAR])
	assert_true("magnet" in no_vac.upgrades.eligible(no_vac), "a pet without VAC does not remove it")
	assert_true(_offered_magnet(no_vac, 400) > 0, "offered again")
	var no_pet := RunWorld.new(PF.setup(PF.data(), 0, PF.EVERYTHING))
	assert_true("magnet" in no_pet.upgrades.eligible(no_pet), "owning VAC with no pet out does nothing")
	assert_true(_offered_magnet(no_pet, 400) > 0)


func test_magnet_is_also_gone_from_boss_and_advancement_draws() -> void:
	var w := PF.world(PF.EVERYTHING)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	w.choice_bonus = true
	for draw in 200:
		for card: Dictionary in w.upgrades.roll_choices(w, rng, 3):
			assert_ne(card.id, "magnet")
	w.choice_bonus = false
	for draw in 200:
		for card: Dictionary in w.upgrades.roll_advancement_choices(w, rng, 3):
			assert_ne(card.id, "magnet")


func test_vac_without_its_prerequisites_is_ignored_with_a_warning() -> void:
	var w := PF.world([PF.KITTY, PF.VAC])
	assert_false(w.pet_has("vac"), "VAC needs Wing Boots and Binocular")
	assert_true("\n".join(Array(w.warnings)).contains("9990000"), "reported: %s" % [w.warnings])
	assert_true("magnet" in w.upgrades.eligible(w))
	var full := PF.world(PF.EVERYTHING)
	assert_true(full.pet_has("vac"))
	assert_eq(full.warnings.size(), 0)


func test_upgrades_without_a_pet_out_do_nothing() -> void:
	var w := RunWorld.new(PF.setup(PF.data(), 0, PF.EVERYTHING, {"hp": 0.9, "mp": 0.9}))
	assert_true(w.pet_system == null)
	assert_false(w.pet_has("auto_hp"))
	w._hp = 1.0
	w.potions.stock.hp.count = 3
	assert_eq(PF.of_type(PF.run(w, 120), "pet_potion_used").size(), 0)


func _fingerprint(seed_value: int) -> String:
	var w := RunWorld.new(PF.busy_setup(seed_value))
	var bot_memo := {}
	var out: Array = []
	for tick in 3600:
		w.step(PF.DT, RF.bot_input(w, bot_memo))
		for e: Dictionary in w.drain_events():
			out.append(e)
		if w.state != RunWorld.PLAYING:
			RF.auto_choose(w)
	out.append(w.pet_state())
	return JSON.stringify(out)


func test_two_worlds_with_the_same_seed_account_and_pet_give_identical_event_streams() -> void:
	var a := _fingerprint(21)
	var b := _fingerprint(21)
	assert_true(a.length() > 2000, "a busy round: %d bytes" % a.length())
	assert_eq(a, b)
	assert_true(a.contains("\"collector\":\"pet\""), "and the pet took part")
	assert_ne(_fingerprint(22), a, "another seed differs")
