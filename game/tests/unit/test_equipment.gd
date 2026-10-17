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
}


func _state(worn: Array, inventory: Array) -> Dictionary:
	return {"worn": Equipment.worn_from_ids(worn, INFO),
		"inventory": inventory.map(func(id: int) -> Dictionary: return Equipment.create(id, INFO[id]))}


func _magician(level := 30, int_stat := 60) -> Dictionary:
	return {"level": level, "job_id": 200, "str": 4, "dex": 4, "int": int_stat, "luk": 4}


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


func test_each_requirement_blocks_equipping_with_its_reason_and_changes_nothing() -> void:
	var cases := [
		[1050010, _magician(14), "reqLevel"],
		[1050010, {"level": 30, "job_id": 0, "str": 4, "dex": 4, "int": 60, "luk": 4}, "reqJob"],
		[1050010, {"level": 30, "job_id": 100, "str": 4, "dex": 4, "int": 60, "luk": 4}, "reqJob"],
		[1082019, _magician(30, 39), "reqINT"],
		[1302000, _magician(), ""],
	]
	var str_item := {"reqSTR": 35, "tuc": 7}
	var dex_item := {"reqDEX": 25, "tuc": 7}
	var luk_item := {"reqLUK": 20, "tuc": 7}
	for spec: Array in cases:
		var state := _state([1040002, 1060002], [spec[0]])
		var before := state.duplicate(true)
		var reason := Equipment.equip(state, 0, INFO[spec[0]], spec[1], 24)
		assert_eq(reason, spec[2], "%d %s" % [spec[0], spec[1]])
		if spec[2] != "":
			assert_eq(state, before, "a failed check changes nothing")
	var who := _magician()
	assert_eq(Equipment.requirement_error(str_item, who), "reqSTR")
	assert_eq(Equipment.requirement_error(dex_item, who), "reqDEX")
	assert_eq(Equipment.requirement_error(luk_item, who), "reqLUK")
	who.luk = 20
	assert_eq(Equipment.requirement_error(luk_item, who), "")


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
