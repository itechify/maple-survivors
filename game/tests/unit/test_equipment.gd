extends TestCase
## The pure Equipment module (game/scripts/sim/equipment.gd): instances from canonical-shaped info, equip slots,
## requirements and the overall/top/bottom rules. Item info here is synthetic, shaped like Character.wz `info`.

## Canonical-shaped info nodes (values invented except where a test says otherwise).
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat
	1040002: {"reqLevel": 0, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top
	1060002: {"reqLevel": 0, "reqJob": 0, "incPDD": 2, "tuc": 7}, # bottom
	1050010: {"reqLevel": 15, "reqJob": 2, "incPDD": 20, "incMDD": 10, "incINT": 3, "tuc": 10}, # overall
	1072001: {"reqLevel": 0, "reqJob": 0, "incPDD": 2, "incSpeed": 30, "incJump": 30, "tuc": 5}, # shoes
	1082019: {"reqLevel": 20, "reqJob": 2, "reqINT": 40, "incPAD": 2, "incMMP": 15, "tuc": 5}, # gloves
	1302000: {"reqLevel": 0, "reqJob": 0, "incPAD": 17, "tuc": 7, "attackSpeed": 4, "price": 1}, # weapon
	1372005: {"reqLevel": 8, "reqJob": 0, "incPAD": 15, "incMAD": 23, "tuc": 7, "attackSpeed": 6}, # wand
	# Warrior shields and two-handed weapons, shaped like the v83 Character.wz info (Shield/01092005 and 01092000,
	# Weapon/01402000: reqJob 1 = the Warrior bit).
	1092005: {"reqLevel": 10, "reqJob": 1, "reqSTR": 0, "incPDD": 10, "incMDD": 3, "tuc": 7}, # wooden shield
	1092000: {"reqLevel": 15, "reqJob": 1, "reqSTR": 40, "incPDD": 15, "tuc": 7}, # shield
	1402000: {"reqLevel": 20, "reqJob": 1, "reqSTR": 70, "incPAD": 40, "tuc": 7, "attackSpeed": 6}, # two-handed sword
	1432000: {"reqLevel": 20, "reqJob": 1, "reqSTR": 70, "incPAD": 41, "tuc": 7, "attackSpeed": 6}, # spear
}


func _state(worn: Array, inventory: Array) -> Dictionary:
	return {"worn": Equipment.worn_from_ids(worn, INFO),
		"inventory": inventory.map(func(id: int) -> Dictionary: return Equipment.create(id, INFO[id]))}


func _magician(level := 30, int_stat := 60) -> Dictionary:
	return {"level": level, "job_id": 200, "str": 4, "dex": 4, "int": int_stat, "luk": 4}


func _warrior(level := 30, str_stat := 80) -> Dictionary:
	return {"level": level, "job_id": 100, "str": str_stat, "dex": 4, "int": 4, "luk": 4}


func _ids(items: Array) -> Array:
	return items.map(func(i: Dictionary) -> int: return i.id)


func test_a_fresh_instance_takes_its_nonzero_inc_stats_and_upgrade_slots_from_info() -> void:
	assert_eq(Equipment.create(1372005, INFO[1372005]),
		{"id": 1372005, "stats": {"incPAD": 15, "incMAD": 23}, "slots": 7, "scrolls": 0})
	var zero := Equipment.create(1040002, {"incPDD": 3.0, "incMDD": 0, "tuc": 7.0})
	assert_eq(zero, {"id": 1040002, "stats": {"incPDD": 3}, "slots": 7, "scrolls": 0}, "zeroes are left out, ints kept")
	assert_true(typeof(zero.stats.incPDD) == TYPE_INT and typeof(zero.slots) == TYPE_INT)
	assert_eq(Equipment.create(1072001, {}).slots, 0, "no tuc means no upgrade slots")


func test_equip_slot_comes_from_the_item_category() -> void:
	for spec: Array in [[1002001, "hat"], [1040002, "top"], [1041011, "top"], [1060002, "bottom"],
			[1050010, "overall"], [1051001, "overall"], [1072001, "shoes"], [1082019, "gloves"],
			[1302000, "weapon"], [1372005, "weapon"], [1382000, "weapon"], [1472000, "weapon"],
			[2000000, ""], [1012000, ""], [30030, ""]]:
		assert_eq(Equipment.slot_of(spec[0]), spec[1], str(spec[0]))


func test_totals_sum_every_worn_stat() -> void:
	var state := _state([1002001, 1040002, 1060002, 1072001, 1302000], [])
	assert_eq(Equipment.total(state.worn, "incPDD"), 11.0)
	assert_eq(Equipment.total(state.worn, "incPAD"), 17.0)
	assert_eq(Equipment.total(state.worn, "incSpeed"), 30.0)
	assert_eq(Equipment.total(state.worn, "incMAD"), 0.0)
	assert_eq(Equipment.held_ids(state), [1002001, 1040002, 1060002, 1072001, 1302000])


func test_equipping_swaps_with_the_worn_item_of_that_slot() -> void:
	var state := _state([1040002, 1302000], [1372005])
	assert_eq(Equipment.equip(state, 0, INFO[1372005], _magician(), 24), "")
	assert_eq(state.worn.weapon.id, 1372005)
	assert_eq(state.inventory.map(func(i: Dictionary) -> int: return i.id), [1302000])
	assert_eq(Equipment.unequip(state, "weapon", 24), "")
	assert_false(state.worn.has("weapon"))
	assert_eq(state.inventory.map(func(i: Dictionary) -> int: return i.id), [1302000, 1372005])


func test_an_overall_fills_top_and_bottom_and_either_one_removes_it() -> void:
	var state := _state([1040002, 1060002, 1302000], [1050010])
	assert_eq(Equipment.equip(state, 0, INFO[1050010], _magician(), 24), "")
	assert_eq(state.worn.keys().filter(func(s: String) -> bool: return s in ["top", "bottom", "overall"]), ["overall"])
	assert_eq(state.inventory.map(func(i: Dictionary) -> int: return i.id), [1040002, 1060002])
	assert_eq(Equipment.equip(state, 1, INFO[1060002], _magician(), 24), "")
	assert_false(state.worn.has("overall"), "a bottom takes the overall off")
	assert_eq(state.worn.bottom.id, 1060002)
	assert_eq(state.inventory.map(func(i: Dictionary) -> int: return i.id), [1040002, 1050010])
	assert_eq(Equipment.equip(state, 1, INFO[1050010], _magician(), 24), "")
	assert_eq(Equipment.equip(state, 0, INFO[1040002], _magician(), 24), "", "a top takes the overall off too")
	assert_eq(state.worn.top.id, 1040002)
	assert_false(state.worn.has("overall"))


func test_a_full_inventory_blocks_a_swap_that_needs_room() -> void:
	var state := _state([1040002, 1060002], [1050010])
	var before := state.duplicate(true)
	assert_eq(Equipment.equip(state, 0, INFO[1050010], _magician(), 1), "inventory_full",
		"one out, two in: overall over top and bottom needs a free slot")
	assert_eq(state, before)
	var full := _state([1302000], [1040002])
	assert_eq(Equipment.unequip(full, "weapon", 1), "inventory_full")
	assert_eq(Equipment.unequip(full, "hat", 24), "empty")
	assert_eq(Equipment.equip(full, 3, INFO[1040002], _magician(), 24), "no_item")


func test_only_the_job_class_blocks_equipping_and_a_refusal_changes_nothing() -> void:
	var cases := [
		[1050010, _magician(1, 4), ""], # reqLevel 15 at Lv1: ignored (#292)
		[1082019, _magician(1, 4), ""], # reqLevel 20 and reqINT 40 at Lv1 with INT 4: ignored
		[1050010, {"level": 30, "job_id": 0, "str": 4, "dex": 4, "int": 60, "luk": 4}, "reqJob"],
		[1050010, {"level": 30, "job_id": 100, "str": 4, "dex": 4, "int": 60, "luk": 4}, "reqJob"],
		[1302000, _magician(), ""],
	]
	for spec: Array in cases:
		var state := _state([1040002, 1060002], [spec[0]])
		var before := state.duplicate(true)
		var reason := Equipment.equip(state, 0, INFO[spec[0]], spec[1], 24)
		assert_eq(reason, spec[2], "%d %s" % [spec[0], spec[1]])
		if spec[2] != "":
			assert_eq(state, before, "a failed check changes nothing")


func test_a_level_100_magician_item_is_worn_at_level_one_and_a_warrior_item_is_not() -> void:
	var info := {"reqLevel": 100, "reqSTR": 200, "reqDEX": 200, "reqINT": 200, "reqLUK": 200, "reqJob": 2, "tuc": 7}
	var wizard := {"job_id": 212}
	assert_eq(Equipment.requirement_error(info, wizard), "", "no level or stat requirement")
	assert_eq(Equipment.requirement_error(info, {"job_id": 212, "level": 1, "str": 4, "dex": 4, "int": 4, "luk": 4}), "")
	var state := _state([], [1050010])
	assert_eq(Equipment.equip(state, 0, info, wizard, 24), "")
	assert_eq(state.worn.overall.id, 1050010)
	var sword := {"reqLevel": 0, "reqJob": 1, "tuc": 7}
	assert_eq(Equipment.requirement_error(sword, wizard), "reqJob", "a Warrior item stays out of a Magician's hands")
	var other := _state([], [1302000])
	assert_eq(Equipment.equip(other, 0, sword, wizard, 24), "reqJob")
	assert_eq(other.worn, {})
	assert_eq(Equipment.auto_wear_error({}, 1050010, info, wizard), "", "auto-wear ignores them too")
	assert_eq(Equipment.auto_wear_error({}, 1302000, sword, wizard), "reqJob")


func test_req_job_is_the_v83_bit_mask() -> void:
	# tier A: v83 reqJob bits 1 Warrior, 2 Magician, 4 Bowman, 8 Thief, 16 Pirate; 0 = every job.
	for spec: Array in [[0, 0, true], [0, 1, false], [100, 1, true], [110, 1, true], [200, 2, true], [230, 2, true],
			[300, 4, true], [400, 8, true], [500, 16, true], [200, 1, false], [200, 3, true], [300, 3, false],
			[200, 0, true], [100, 0, true]]:
		var who := {"level": 99, "job_id": spec[0], "str": 999, "dex": 999, "int": 999, "luk": 999}
		assert_eq(Equipment.requirement_error({"reqJob": spec[1]}, who) == "", spec[2], str(spec))


func test_discard_removes_only_inventory_items() -> void:
	var state := _state([1302000], [1040002, 1060002])
	assert_eq(Equipment.discard(state, 0), "")
	assert_eq(state.inventory.map(func(i: Dictionary) -> int: return i.id), [1060002])
	assert_eq(Equipment.discard(state, 5), "no_item")
	assert_eq(state.worn.weapon.id, 1302000)


func test_a_grant_is_worn_and_the_previous_item_moves_to_the_inventory() -> void:
	var state := _state([1040002, 1302000], [])
	assert_eq(Equipment.grant(state, Equipment.create(1372005, INFO[1372005]), 24), "")
	assert_eq(state.worn.weapon.id, 1372005)
	assert_eq(state.inventory.map(func(i: Dictionary) -> int: return i.id), [1302000])
	var bare := _state([1040002], [])
	assert_eq(Equipment.grant(bare, Equipment.create(1372005, INFO[1372005]), 24), "")
	assert_eq(bare.worn.weapon.id, 1372005)
	assert_eq(bare.inventory, [])


func test_a_grant_that_would_push_an_item_out_of_a_full_inventory_changes_nothing() -> void:
	var state := _state([1040002, 1302000], [1002001, 1060002])
	var before := state.duplicate(true)
	assert_eq(Equipment.grant(state, Equipment.create(1372005, INFO[1372005]), 2), "inventory_full")
	assert_eq(state, before, "the worn weapon stays and nothing is destroyed")
	assert_eq(Equipment.grant(state, Equipment.create(1372005, INFO[1372005]), 3), "", "room for the old weapon")
	assert_eq(state.worn.weapon.id, 1372005)


func test_state_validation_accepts_json_and_rejects_malformed_instances() -> void:
	var state := _state([1040002, 1302000], [1372005])
	var parsed: Variant = JSON.parse_string(JSON.stringify(state))
	assert_eq(Equipment.validation_error(parsed), "")
	assert_eq(Equipment.normalized(parsed), state, "JSON floats come back as the same integers")
	for bad: Variant in [[], {"worn": {}}, {"worn": {"cape": {"id": 1102000, "stats": {}, "slots": 0, "scrolls": 0}},
			"inventory": []}, {"worn": {"top": {"id": 1302000, "stats": {}, "slots": 0, "scrolls": 0}}, "inventory": []},
			{"worn": {}, "inventory": [{"id": 1302000}]},
			{"worn": {}, "inventory": [{"id": 1302000, "stats": {"incPAD": "x"}, "slots": 0, "scrolls": 0}]}]:
		assert_ne(Equipment.validation_error(bad), "", str(bad))


# --- shield slot (#158) ---------------------------------------------------------------------------------------------

func test_the_shield_is_an_equip_slot_of_the_shield_category() -> void:
	assert_eq(Equipment.SLOTS[-1], "shield", "appended last: every earlier slot keeps its order")
	for id: int in [1092000, 1092005, 1092062]:
		assert_eq(Equipment.slot_of(id), "shield", str(id))
	assert_eq(Equipment.slot_of(1102000), "", "capes are still not an equip slot")


func test_a_shield_is_worn_beside_a_one_handed_weapon_and_its_stats_count() -> void:
	var state := _state([1040002, 1302000], [1092005])
	assert_eq(Equipment.equip(state, 0, INFO[1092005], _warrior(), 24), "")
	assert_eq(state.worn.shield.id, 1092005)
	assert_eq(state.worn.weapon.id, 1302000, "a one-handed weapon stays")
	assert_eq(state.inventory, [])
	assert_eq(Equipment.total(state.worn, "incPDD"), 13.0, "top 3 + shield 10")
	assert_eq(Equipment.total(state.worn, "incMDD"), 3.0)
	assert_eq(Equipment.worn_ids(state.worn), [1040002, 1302000, 1092005], "drawn after the weapon")
	assert_eq(Equipment.unequip(state, "shield", 24), "")
	assert_eq(_ids(state.inventory), [1092005])


func test_a_shield_takes_the_job_requirement_only() -> void:
	for spec: Array in [[1092005, _warrior(9), ""], [1092005, _magician(30), "reqJob"],
			[1092000, _warrior(30, 39), ""], [1092000, _warrior(30, 40), ""]]:
		var state := _state([1302000], [spec[0]])
		var before := state.duplicate(true)
		var reason := Equipment.equip(state, 0, INFO[spec[0]], spec[1], 24)
		assert_eq(reason, spec[2], "%d %s" % [spec[0], spec[1]])
		if reason != "":
			assert_eq(state, before, "a refusal changes nothing")


func test_a_two_handed_weapon_moves_the_worn_shield_to_the_inventory() -> void:
	var state := _state([1040002, 1302000, 1092005], [1402000])
	assert_eq(Equipment.equip(state, 0, INFO[1402000], _warrior(), 24), "")
	assert_eq(state.worn.weapon.id, 1402000)
	assert_false(state.worn.has("shield"), "the shield is off")
	assert_eq(_ids(state.inventory), [1302000, 1092005], "the old weapon takes the item's place, the shield follows")
	var bare := _state([1092005], [1432000])
	assert_eq(Equipment.equip(bare, 0, INFO[1432000], _warrior(), 24), "")
	assert_eq(_ids(bare.inventory), [1092005], "with no weapon worn the shield takes the item's place")


func test_a_shield_moves_the_held_two_handed_weapon() -> void:
	var state := _state([1040002, 1402000], [1092005])
	assert_eq(Equipment.equip(state, 0, INFO[1092005], _warrior(), 24), "")
	assert_eq(state.worn.shield.id, 1092005)
	assert_false(state.worn.has("weapon"), "bare-handed now")
	assert_eq(_ids(state.inventory), [1402000], "the weapon took the shield's place")


func test_a_full_inventory_refuses_the_two_handed_rule_and_changes_nothing() -> void:
	# A two-handed sword over a one-handed sword and a shield: one item leaves the tab, two come in.
	var sword_over_shield := _state([1302000, 1092005], [1402000])
	var before := sword_over_shield.duplicate(true)
	assert_eq(Equipment.equip(sword_over_shield, 0, INFO[1402000], _warrior(), 1), "inventory_full")
	assert_eq(sword_over_shield, before, "refused: nothing moved")
	assert_eq(Equipment.equip(sword_over_shield, 0, INFO[1402000], _warrior(), 2), "", "room for both")
	# The same with the tab holding other things.
	var tab_full := _state([1302000, 1092005], [1402000, 1002001, 1040002])
	var tab_before := tab_full.duplicate(true)
	assert_eq(Equipment.equip(tab_full, 0, INFO[1402000], _warrior(), 3), "inventory_full")
	assert_eq(tab_full, tab_before)
	# A shield over a held spear swaps place for place, so even a full tab takes it.
	var shield_over_spear := _state([1432000], [1092005])
	assert_eq(Equipment.equip(shield_over_spear, 0, INFO[1092005], _warrior(), 1), "", "swap place for place")


func test_a_one_handed_weapon_over_a_shield_needs_no_room() -> void:
	var state := _state([1302000, 1092005], [1372005])
	assert_eq(Equipment.equip(state, 0, INFO[1372005], _warrior(), 1), "")
	assert_eq(state.worn.shield.id, 1092005, "the shield stays under a one-handed weapon")
	assert_eq(_ids(state.inventory), [1302000])


func test_a_two_handed_grant_moves_the_shield_or_leaves_everything() -> void:
	var state := _state([1040002, 1092005], [])
	assert_eq(Equipment.grant(state, Equipment.create(1402000, INFO[1402000]), 24), "")
	assert_eq(state.worn.weapon.id, 1402000)
	assert_eq(_ids(state.inventory), [1092005])
	var full := _state([1302000, 1092005], [1002001])
	var before := full.duplicate(true)
	assert_eq(Equipment.grant(full, Equipment.create(1402000, INFO[1402000]), 2), "inventory_full")
	assert_eq(full, before)


func test_a_two_handed_weapon_is_never_worn_with_a_shield_in_validation_or_outfits() -> void:
	var state := _state([1302000, 1092005], [])
	assert_eq(Equipment.validation_error(state), "")
	state.worn.weapon = Equipment.create(1402000, INFO[1402000])
	assert_ne(Equipment.validation_error(state), "", "a two-handed weapon beside a shield is invalid")
	var outfit := Equipment.worn_from_ids([1302000, 1092005, 1402000], INFO)
	assert_eq(outfit.weapon.id, 1402000)
	assert_false(outfit.has("shield"), "the two-handed weapon wins, as in equip")
	var reverse := Equipment.worn_from_ids([1402000, 1092005], INFO)
	assert_false(reverse.has("weapon"), "a shield after a two-handed weapon replaces it, as in equip")
	assert_eq(reverse.shield.id, 1092005)
