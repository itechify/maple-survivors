extends TestCase
## Wearing and taking off cash equipment and bringing a pet out, the rules behind the Equip window's Cash tab and Pet
## page (spec #34, ticket #122): the overall and two-handed rules, refusing what the account does not own, Fortune
## from the next card draw, the pet appearing and disappearing in a live world, and the choice surviving the
## character snapshot and a save file.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const HAT := 1000001
const HAT2 := 1000002
const TOP := 1040001
const BOTTOM := 1060001
const OVERALL := 1050001
const SHIELD := 1090001
const WEAPON_COVER := 1700001
const TWO_HANDED_COVER := 1700002
const KITTY := 5000000
const PUPPY := 5000001
const OWNED := [HAT, HAT2, TOP, BOTTOM, OVERALL, SHIELD, WEAPON_COVER, TWO_HANDED_COVER, KITTY, PUPPY, 1812004]
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]

var save_path := TestCase.test_dir("cash_wear/save.json")


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func _data() -> Dictionary:
	var data := RF.quiet_data()
	for id: int in [HAT, HAT2, TOP, BOTTOM, OVERALL, SHIELD, WEAPON_COVER]:
		data.cash_items.items.append({"id": id, "kind": "equip", "price": 1})
	data.cash_items.items.append({"id": TWO_HANDED_COVER, "kind": "equip", "price": 1, "two_handed": true})
	return data


func _world(owned: Array = OWNED, character_edit: Dictionary = {}) -> RunWorld:
	var data := _data()
	var setup := RF.setup("quiet", 7, data)
	var character := RunWorld.new(setup).character_snapshot()
	character.merge(character_edit, true)
	setup = RF.setup("quiet", 7, data)
	setup.character = character
	setup.account = {"owned": owned}
	var world := RunWorld.new(setup)
	RF.place_player(world, 400)
	return world


# --- CashCatalog.wear / take_off (pure) --------------------------------------------------------------------------------

func test_catalog_wear_puts_an_item_in_its_slot_and_replaces_what_was_there() -> void:
	var catalog := CashCatalog.from_data(_data())
	assert_eq(catalog.wear({}, HAT), {"hat": HAT})
	assert_eq(catalog.wear({"hat": HAT}, HAT2), {"hat": HAT2}, "a new hat replaces the old")
	assert_eq(catalog.wear({"hat": HAT, "shoes": 1070001}, TOP), {"hat": HAT, "shoes": 1070001, "top": TOP})


func test_catalog_an_overall_clears_top_and_bottom_and_a_top_or_bottom_takes_the_overall_off() -> void:
	var catalog := CashCatalog.from_data(_data())
	assert_eq(catalog.wear({"top": TOP, "bottom": BOTTOM}, OVERALL), {"top": OVERALL, "bottom": OVERALL})
	assert_eq(catalog.wear({"top": OVERALL, "bottom": OVERALL}, TOP), {"top": TOP}, "the overall leaves both slots")
	assert_eq(catalog.wear({"top": OVERALL, "bottom": OVERALL}, BOTTOM), {"bottom": BOTTOM})


func test_catalog_a_two_handed_cover_takes_weapon_and_shield_and_a_shield_takes_it_off() -> void:
	var catalog := CashCatalog.from_data(_data())
	assert_eq(catalog.wear({"weapon": WEAPON_COVER, "shield": SHIELD}, TWO_HANDED_COVER),
		{"weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER})
	assert_eq(catalog.wear({"weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER}, SHIELD), {"shield": SHIELD})
	assert_eq(catalog.wear({"weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER}, WEAPON_COVER),
		{"weapon": WEAPON_COVER}, "a one-handed cover frees the shield slot")


func test_catalog_wear_ignores_what_is_not_cash_equipment_and_take_off_clears_every_slot_of_the_item() -> void:
	var catalog := CashCatalog.from_data(_data())
	assert_eq(catalog.wear({"hat": HAT}, KITTY), {"hat": HAT}, "a pet is not worn")
	assert_eq(catalog.wear({"hat": HAT}, 1002001), {"hat": HAT}, "regular equipment is not cash")
	assert_eq(catalog.take_off({"top": OVERALL, "bottom": OVERALL, "hat": HAT}, "bottom"), {"hat": HAT})
	assert_eq(catalog.take_off({"hat": HAT}, "shoes"), {"hat": HAT}, "an empty slot changes nothing")


# --- RunWorld ------------------------------------------------------------------------------------------------------

func test_wear_cash_fills_the_slot_from_an_owned_item_and_nothing_is_used_up() -> void:
	var w := _world()
	assert_eq(w.wear_cash(HAT), "")
	assert_eq(w.worn_cash, {"hat": HAT})
	assert_eq(w.character_snapshot().cash, {"hat": HAT}, "carried with the character")
	assert_eq(w.account_owned, OWNED, "the account keeps the item: wearing never moves or uses it up")
	assert_eq(w.wear_cash(HAT2), "")
	assert_eq(w.worn_cash, {"hat": HAT2})
	var events := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed")
	assert_eq(events.map(func(e: Dictionary) -> String: return String(e.action)), ["wear_cash", "wear_cash"])
	assert_eq(int(events[0].item_id), HAT)


func test_wear_cash_follows_the_overall_and_two_handed_rules() -> void:
	var w := _world()
	assert_eq(w.wear_cash(TOP), "")
	assert_eq(w.wear_cash(BOTTOM), "")
	assert_eq(w.wear_cash(OVERALL), "")
	assert_eq(w.worn_cash, {"top": OVERALL, "bottom": OVERALL})
	assert_eq(w.wear_cash(TOP), "")
	assert_eq(w.worn_cash, {"top": TOP}, "wearing a top takes the overall off")
	assert_eq(w.wear_cash(SHIELD), "")
	assert_eq(w.wear_cash(TWO_HANDED_COVER), "")
	assert_eq(w.worn_cash, {"top": TOP, "weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER})
	assert_eq(w.character_snapshot().cash, w.worn_cash)


func test_wear_cash_refuses_unowned_and_non_cash_items_and_changes_nothing() -> void:
	var w := _world([HAT])
	assert_eq(w.wear_cash(HAT2), "not_owned", "the account does not own it")
	assert_eq(w.wear_cash(KITTY), "not_cash", "a pet is not worn")
	assert_eq(w.wear_cash(1002001), "not_cash", "nor is regular equipment")
	assert_eq(w.wear_cash(0), "not_cash")
	assert_eq(w.worn_cash, {})
	assert_false(w.character_snapshot().has("cash"), "no key without cash equipment")
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed").size(), 0)


func test_take_off_cash_clears_the_item_from_every_slot_it_fills() -> void:
	var w := _world(OWNED, {"cash": {"hat": HAT, "top": OVERALL, "bottom": OVERALL}})
	assert_eq(w.worn_cash.size(), 3)
	assert_eq(w.take_off_cash("bottom"), "")
	assert_eq(w.worn_cash, {"hat": HAT}, "the overall leaves top and bottom")
	assert_eq(w.take_off_cash("shoes"), "empty")
	assert_eq(w.take_off_cash("helmet"), "empty")
	assert_eq(w.take_off_cash("hat"), "")
	assert_eq(w.worn_cash, {})
	assert_false(w.character_snapshot().has("cash"))


func test_fortune_changes_at_once_in_the_state_and_from_the_next_card_draw() -> void:
	var data := _data()
	data.upgrades.cards = [{"id": "roomy", "kind": "skill_mod", "skill": "three_snails", "max_rank": 100,
		"effects": [{"stat": "count", "op": "add", "value": 1}]}]
	data.upgrades.pity.draws = 0
	var setup := RF.setup("quiet", 7, data)
	setup.account = {"owned": OWNED}
	var w := RunWorld.new(setup)
	assert_eq(w.player_state.fortune, 0.0)
	assert_eq(w.wear_cash(HAT), "")
	assert_eq(w.player_state.fortune, 10.0, "the hat is worth 10 Fortune the moment it is worn")
	var born := RunWorld.new(setup.merged({"character": w.character_snapshot()}, true))
	assert_eq(born.player_state.fortune, 10.0)
	assert_eq(_tier_counts(w, 4000), _tier_counts(born, 4000), "the same draws as a world that started wearing it")
	assert_eq(w.take_off_cash("hat"), "")
	assert_eq(w.player_state.fortune, 0.0)
	var plain := RunWorld.new(setup)
	assert_eq(_tier_counts(w, 4000), _tier_counts(plain, 4000), "and back to the plain draws after taking it off")


func _tier_counts(w: RunWorld, draws: int) -> Dictionary:
	var counts := {}
	for tier: String in TIERS:
		counts[tier] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	for draw in draws:
		counts[String(w.upgrades.roll_choices(w, rng, 1)[0].get("tier", "missing"))] += 1
	return counts


func test_set_pet_brings_an_owned_pet_out_and_none_takes_it_back() -> void:
	var w := _world()
	assert_eq(w.pet, 0)
	assert_true(w.pet_system == null)
	assert_eq(w.set_pet(PUPPY), "")
	assert_eq(w.pet, PUPPY)
	assert_eq(w.pet_system.species, PUPPY, "the pet is simulated at once")
	assert_eq(w.pet_state().species, PUPPY)
	assert_eq(w.character_snapshot().pet, PUPPY)
	assert_true(w.pet_has("wing_boots"), "the owned upgrades apply to it")
	assert_eq(w.set_pet(KITTY), "")
	assert_eq(w.pet_system.species, KITTY, "choosing another pet swaps it")
	assert_eq(w.set_pet(0), "")
	assert_eq(w.pet, 0)
	assert_true(w.pet_system == null)
	assert_eq(w.pet_state(), {})
	assert_false(w.character_snapshot().has("pet"))
	var kinds := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed") \
		.map(func(e: Dictionary) -> String: return String(e.action))
	assert_eq(kinds, ["pet", "pet", "pet"])


func test_set_pet_refuses_unowned_and_non_pet_items_and_keeps_the_pet_that_was_out() -> void:
	var w := _world([KITTY, HAT])
	assert_eq(w.set_pet(KITTY), "")
	assert_eq(w.set_pet(PUPPY), "not_owned")
	assert_eq(w.set_pet(HAT), "not_pet")
	assert_eq(w.set_pet(12345), "not_pet")
	assert_eq(w.pet, KITTY)
	assert_eq(w.pet_system.species, KITTY)


func test_the_pet_keeps_playing_after_it_is_brought_out_mid_round() -> void:
	var w := _world()
	w.set_pet(KITTY)
	for tick in 120:
		w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.pet_state().species, KITTY)
	assert_true(absf(w.pet_state().pos.x - w.player.pos.x) < 200.0, "it follows the player")


# --- Saved with the character --------------------------------------------------------------------------------------

func test_worn_cash_and_the_pet_survive_a_save_file_and_the_next_round() -> void:
	var w := _world()
	w.wear_cash(OVERALL)
	w.wear_cash(HAT)
	w.set_pet(PUPPY)
	var save := SaveData.new(save_path)
	assert_eq(save.set_account({"nx": 0, "owned": OWNED}), OK)
	var character := w.character_snapshot()
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var slot := save.create_slot({"name": "Dresser", "created": "2026-01-01", "character": character, "tier": 0,
		"phase": "map_select", "rounds_played": 0, "tiers_cleared": 0})
	assert_true(slot >= 0)
	var reloaded := SaveData.new(save_path)
	var saved: Dictionary = reloaded.slot(slot).character
	assert_eq(CharacterSnapshot.integers(saved.cash), {"hat": HAT, "top": OVERALL, "bottom": OVERALL})
	assert_eq(int(saved.pet), PUPPY)
	var setup := RF.setup("quiet", 9, _data())
	setup.character = saved
	setup.account = {"owned": reloaded.account.owned}
	var next := RunWorld.new(setup)
	assert_eq(next.worn_cash, {"hat": HAT, "top": OVERALL, "bottom": OVERALL})
	assert_eq(next.pet, PUPPY)
	assert_eq(next.player_state.fortune, 10.0 + 10.0 + 10.0, "hat + both overall slots")
