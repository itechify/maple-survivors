extends TestCase
## Cash equipment in a round: CharacterSnapshot cash/pet fields, Fortune computed live from the filled cash slots,
## the unowned-item warning and no compounding across rounds (spec #34, ticket #116).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const EVERY_SLOT := {"hat": 1000001, "face": 1010001, "eye": 1020001, "earrings": 1030001, "top": 1040001,
	"bottom": 1060001, "shoes": 1070001, "gloves": 1080001, "cape": 1100001, "weapon": 1700001, "shield": 1090001}
const OVERALL := 1050001
const TWO_HANDED_COVER := 1700002
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]


func _data() -> Dictionary:
	var data := RF.quiet_data()
	data.cash_items.items.append({"id": TWO_HANDED_COVER, "kind": "equip", "price": 1, "two_handed": true})
	return data


func _setup(data: Dictionary, character: Dictionary = {}, owned: Array = [], seed_value := 11) -> Dictionary:
	var setup := RF.setup("quiet", seed_value, data)
	if not character.is_empty():
		setup.character = character
	if not owned.is_empty():
		setup.account = {"owned": owned}
	return setup


func _fresh(data: Dictionary) -> Dictionary:
	return RunWorld.new(_setup(data)).character_snapshot()


func _with_cash(data: Dictionary, cash: Dictionary, pet := 0) -> Dictionary:
	var character := _fresh(data)
	character.cash = cash
	if pet > 0:
		character.pet = pet
	return character


func _fortune(data: Dictionary, cash: Dictionary, owned: Array, own := 0.0) -> float:
	data.balance.player["fortune"] = own
	var w := RunWorld.new(_setup(data, _with_cash(data, cash), owned))
	return float(w.player_state.fortune)


func test_snapshot_validation_accepts_optional_cash_and_pet_and_defaults_when_absent() -> void:
	var character := _fresh(_data())
	assert_eq(CharacterSnapshot.validation_error(character), "")
	assert_false(character.has("cash"), "a character without cash equipment is byte-identical to before")
	assert_false(character.has("pet"))
	character.cash = {"hat": 1000001, "top": OVERALL, "bottom": OVERALL}
	character.pet = 5000001
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(character))
	assert_eq(CharacterSnapshot.validation_error(parsed), "", "JSON floats are accepted")
	for bad: Variant in [[1], {"helmet": 1000001}, {"hat": "x"}, {"hat": 0}, {"hat": 1.5}, {"hat": -3}]:
		character.cash = bad
		assert_ne(CharacterSnapshot.validation_error(character), "", "bad cash %s" % [bad])
	character.cash = {}
	for bad: Variant in ["x", -1, 2.5, [5000000]]:
		character.pet = bad
		assert_ne(CharacterSnapshot.validation_error(character), "", "bad pet %s" % [bad])


func test_fortune_is_the_characters_own_plus_the_sum_of_the_filled_slots() -> void:
	var catalog := CashCatalog.from_data(_data())
	var owned: Array = EVERY_SLOT.values()
	assert_eq(_fortune(_data(), {}, owned), 0.0, "no cash equipment, no Fortune")
	assert_eq(_fortune(_data(), {"hat": 1000001}, owned), 10.0, "hat is worth 10")
	assert_eq(_fortune(_data(), {"hat": 1000001, "shoes": 1070001}, owned, 12.0), 12.0 + 10.0 + 9.0,
		"on top of the character's own Fortune")
	assert_eq(_fortune(_data(), EVERY_SLOT, owned), 100.0, "every slot filled")
	var w := RunWorld.new(_setup(_data(), _with_cash(_data(), EVERY_SLOT), owned))
	assert_eq(w.cash_fortune, 100.0)
	assert_eq(w.player_state.fortune, 100.0 + 0.0)
	assert_eq(catalog.slot_fortune.size(), 11)


func test_an_overall_gives_top_and_bottom_and_a_two_handed_cover_gives_weapon_and_shield() -> void:
	assert_eq(_fortune(_data(), {"top": OVERALL, "bottom": OVERALL}, [OVERALL]), 10.0 + 10.0)
	assert_eq(_fortune(_data(), {"top": OVERALL}, [OVERALL]), 20.0, "stored under one key still fills both")
	assert_eq(_fortune(_data(), {"weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER}, [TWO_HANDED_COVER]),
		12.0 + 8.0)


func test_card_fortune_stacks_with_cash_fortune() -> void:
	var data := _data()
	var w := RunWorld.new(_setup(data, _with_cash(data, {"hat": 1000001}), [1000001]))
	w.loadout.add_player_mod("fortune", "add", 7.0)
	w.refresh_player_stats()
	assert_eq(w.player_state.fortune, 17.0)
	assert_false(w.character_snapshot().has("fortune"), "Fortune is part of the round, not of the saved character (#286)")


func test_an_unowned_worn_item_gives_no_fortune_and_raises_a_world_warning() -> void:
	var data := _data()
	var character := _with_cash(data, {"hat": 1000001, "face": 1010001}, 5000000)
	var w := RunWorld.new(_setup(data, character, [1010001]))
	assert_eq(w.player_state.fortune, 8.0, "only the owned face accessory counts")
	var text := "\n".join(Array(w.warnings))
	assert_true(text.contains("1000001") and text.contains("not owned"), "warns about the hat: " + text)
	assert_true(text.contains("5000000"), "and about the unowned pet: " + text)
	assert_eq(w.pet, 0, "an unowned pet is not out")
	var none := RunWorld.new(_setup(data, character))
	assert_eq(none.player_state.fortune, 0.0, "no account, nothing owned")
	assert_eq(none.warnings.size(), 3, "hat, face and pet are all reported")
	assert_eq(w.character_snapshot().cash, character.cash, "what the character wears is carried, owned or not")
	assert_eq(w.character_snapshot().pet, 5000000)


func test_a_pet_out_is_the_owned_species_and_alert_levels_reach_the_world() -> void:
	var data := _data()
	var setup := _setup(data, _with_cash(data, {}, 5000001), [5000001])
	setup.alert = {"hp": 0.5, "mp": 0.25}
	var w := RunWorld.new(setup)
	assert_eq(w.pet, 5000001)
	assert_eq(w.alert, {"hp": 0.5}, "an old MP ALERT is dropped (no MP, #285)")
	assert_eq(w.warnings.size(), 0)
	assert_eq(RunWorld.new(RF.setup("quiet", 1, data)).alert, {"hp": 0.0}, "absent = do not alert")


func test_three_rounds_with_every_slot_filled_do_not_compound_base_fortune() -> void:
	var data := _data()
	data.stages.stages.quiet.duration = 1.0
	data.balance.run_time_cap = 2.0
	var owned: Array = EVERY_SLOT.values()
	var character := _with_cash(data, EVERY_SLOT)
	var base := float(RunWorld.new(_setup(data, character, owned)).player_state.fortune) - 100.0
	for round_index in 3:
		var w := RunWorld.new(_setup(data, character, owned, 100 + round_index))
		assert_eq(w.player_state.fortune, base + 100.0, "round %d plays at base + 100" % round_index)
		w.god = true
		for tick in 90:
			w.step(DT, MoveInput.new())
		assert_eq(w.state, RunWorld.CLEARED)
		character = w.character_snapshot()
		assert_false(character.has("base_fortune") or character.has("fortune"), "no Fortune is saved")
		assert_eq(character.cash, EVERY_SLOT, "the worn items travel with the character")
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(character))
		assert_eq(CharacterSnapshot.validation_error(parsed), "")
		character = parsed


func _tier_counts(w: RunWorld, draws: int) -> Dictionary:
	var counts := {"normal": 0, "rare": 0, "epic": 0, "unique": 0, "legendary": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	for draw in draws:
		counts[String(w.upgrades.roll_choices(w, rng, 1)[0].get("tier", "missing"))] += 1
	return counts


func test_card_rarity_weights_follow_the_existing_formula_with_cash_fortune() -> void:
	var data := _data()
	data.upgrades.cards = [{"id": "roomy", "kind": "skill_mod", "skill": "energy_bolt", "max_rank": 100,
		"effects": [{"stat": "count", "op": "add", "value": 1}]}]
	data.upgrades.pity.draws = 0
	var character := _with_cash(data, EVERY_SLOT)
	var plain := RunWorld.new(_setup(data))
	var cash := RunWorld.new(_setup(data, character, EVERY_SLOT.values()))
	var base := _tier_counts(plain, 20000)
	var lucky := _tier_counts(cash, 20000)
	# Literal bands from the documented formula: non-Normal weights x (1 + Fortune * 0.02), then normalise.
	# Fortune 0 gives 75/18/5/1.7/0.3 %; Fortune 100 gives 50/36/10/3.4/0.6 %.
	var bands := {"normal": [0.48, 0.52], "rare": [0.34, 0.38], "epic": [0.09, 0.11],
		"unique": [0.029, 0.039], "legendary": [0.004, 0.0082]}
	for tier: String in TIERS:
		var frequency := float(lucky[tier]) / 20000.0
		assert_between(frequency, bands[tier][0], bands[tier][1], "%s at cash Fortune 100: %.4f" % [tier, frequency])
	assert_true(int(lucky.normal) < int(base.normal) - 3500, "cash Fortune measurably raises non-Normal offers")
	# The same seeded draws as a character whose own Fortune is 100: cash Fortune IS Fortune.
	var cash_data := _data()
	cash_data.upgrades.cards = data.upgrades.cards
	cash_data.upgrades.pity.draws = 0
	data.balance.player["fortune"] = 100.0
	var own := RunWorld.new(_setup(data))
	var fresh_cash := RunWorld.new(_setup(cash_data, character, EVERY_SLOT.values()))
	assert_eq(_tier_counts(own, 2000), _tier_counts(fresh_cash, 2000), "identical offers for identical total Fortune")
