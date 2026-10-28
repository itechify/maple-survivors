extends TestCase
## Pet rules that cut across the sim (spec #34, ticket #119): no pickup-radius card exists, upgrade prerequisites,
## determinism, and that a round without a pet is untouched.

const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_no_card_ever_raises_the_pickup_radius_with_or_without_a_vac_pet() -> void:
	# Spec #225: the Magnet card is gone, so VAC has nothing to hide and the pickup radius stays at its base.
	for w: RunWorld in [PF.world(PF.EVERYTHING), PF.world([PF.KITTY, PF.WING, PF.BINOCULAR]),
			RunWorld.new(PF.setup(PF.data(), 0, PF.EVERYTHING))]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for draw in 100:
			for card: Dictionary in w.upgrades.roll_choices(w, rng, 3):
				assert_ne(card.id, "magnet")
		assert_false("magnet" in w.upgrades.eligible(w))
		assert_eq(w.magnet_r, float(w.balance.magnet_radius))


func test_vac_without_its_prerequisites_is_ignored_with_a_warning() -> void:
	var w := PF.world([PF.KITTY, PF.VAC])
	assert_false(w.pet_has("vac"), "VAC needs Wing Boots and Binocular")
	assert_true("\n".join(Array(w.warnings)).contains("9990000"), "reported: %s" % [w.warnings])
	var full := PF.world(PF.EVERYTHING)
	assert_true(full.pet_has("vac"))
	assert_eq(full.warnings.size(), 0)


func test_upgrades_without_a_pet_out_do_nothing() -> void:
	var w := RunWorld.new(PF.setup(PF.data(), 0, PF.EVERYTHING, {"hp": 0.9, "mp": 0.9}))
	assert_true(w.pet_system == null)
	assert_false(w.pet_has("auto_hp"))
	w._hp = 1.0
	assert_eq(PF.of_type(PF.run(w, 120), "pet_potion_used").size(), 0)


func _fingerprint(seed_value: int) -> String:
	var setup := PF.busy_setup(seed_value)
	# #284: the fresh character is a 212 whose Energy Bolt costs 6 MP, more than the 5-MP Lv1 pool; a bigger pool keeps
	# the round busy (kills, drops for the pet) under the current MP rules (#285 owns MP).
	setup.character.base_mp = 30.0
	var w := RunWorld.new(setup)
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
