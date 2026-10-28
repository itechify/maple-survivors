extends TestCase
## The scroll shops (spec #33, #111): the pure Shop module on plain character state (stock by NPC rate and job, buying,
## selling) and its RunWorld wrappers (shop_stock, buy_scroll, sell_item, sell_scrolls). Real survivor data
## (shops.json, scrolls.json, the drop list) with synthetic canonical item info; no asset cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const INFO := {
	1002001: {"incPDD": 4, "tuc": 7, "price": 1500}, # all-job hat
	1040002: {"incPDD": 3, "tuc": 7, "price": 50}, # all-job top
	1060002: {"incPDD": 2, "tuc": 7, "price": 40},
	1072001: {"incPDD": 2, "tuc": 5, "price": 30},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7, "price": 100},
	1372005: {"reqJob": 2, "reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7, "price": 1000},
	1382000: {"reqJob": 2, "reqLevel": 10, "incMAD": 25, "attackSpeed": 6, "tuc": 7, "price": 1200},
	1050001: {"reqJob": 2, "incMDD": 3, "tuc": 7, "price": 500}, # a Magician overall
}
const SCROLL_INFO := {
	2040000: {"incPDD": 2, "success": 100, "price": 1},
	2040400: {"incPDD": 1, "success": 100, "price": 1, "slotMax": 100},
	2043700: {"incMAD": 1, "success": 100, "price": 1},
	2043705: {"incMAD": 5, "success": 30, "cursed": 50, "price": 1},
}

var _data: Dictionary


func before_each() -> void:
	_data = DataRepo.load_all()


func _stock(npc_id: int, job_id: int) -> Array:
	for npc: Dictionary in _data.shops.npcs:
		if int(npc.id) == npc_id:
			return Shop.stock(npc, _data.shops, _data.scrolls, _data.equipment_drops.items, INFO, job_id)
	return []


func _ids(stock: Array) -> Array:
	return stock.map(func(e: Dictionary) -> int: return int(e.id))


func _state(mesos: int, scrolls: Dictionary = {}, inventory: Array = [], worn: Dictionary = {}) -> Dictionary:
	return {"mesos": mesos, "scrolls": scrolls, "equipment": {"worn": worn, "inventory": inventory}}


# --- data ---

func test_the_four_scroll_npcs_and_their_rates() -> void:
	var by_id := {}
	for npc: Dictionary in _data.shops.npcs:
		by_id[int(npc.id)] = npc.rates
	assert_eq(by_id, {1032103: ["100"], 2022002: ["60"], 1052104: ["10"], 2041016: ["dark70", "dark30"]})
	assert_eq([int(_data.shops.prices.armour), int(_data.shops.prices.weapon)], [35000, 70000])
	assert_true("wand" in _data.shops.weapon_slots and "staff" in _data.shops.weapon_slots, "the Magician weapon slots")
	assert_false("shield" in _data.shops.weapon_slots, "shield scrolls are priced as armour")


# --- stock ---

func test_a_beginner_sees_only_scrolls_for_all_job_equipment() -> void:
	var stock := _stock(1032103, 0)
	assert_eq(stock.size(), 19, "hat 5, top 5, bottom 5 and shoes 4 families at 100%: the all-job items of the synthetic list")
	for e: Dictionary in stock:
		assert_true(e.slot in ["hat", "top", "bottom", "shoes"], "slot %s" % e.slot)
		assert_eq(e.rate, "100")
		assert_eq(e.price, 35000)
	assert_true(2040000 in _ids(stock) and 2040400 in _ids(stock))
	assert_false(2043700 in _ids(stock), "no wand scroll for a Beginner")


func test_a_magician_also_sees_wand_and_staff_scrolls_at_the_weapon_price() -> void:
	var stock := _stock(1032103, 210)
	assert_eq(stock.size(), 26, "the Beginner stock plus the Magician overall (5), wand (1) and staff (1)")
	for e: Dictionary in stock:
		assert_eq(e.price, 70000 if e.slot in ["wand", "staff"] else 35000)
	assert_true(2043700 in _ids(stock), "wand Magic Att. 100%")
	assert_true(2043800 in _ids(stock), "staff Magic Att. 100%")


func test_each_npc_sells_only_its_own_rates() -> void:
	for pair: Array in [[1032103, ["100"]], [2022002, ["60"]], [1052104, ["10"]], [2041016, ["dark70", "dark30"]]]:
		var stock := _stock(int(pair[0]), 210)
		assert_true(stock.size() > 0, "npc %d sells something" % pair[0])
		for e: Dictionary in stock:
			assert_true(e.rate in pair[1], "npc %d rate %s" % [pair[0], e.rate])
	assert_eq(_ids(_stock(2022002, 210)).filter(func(id: int) -> bool: return id == 2043701).size(), 1, "60% wand scroll")
	var dark := _stock(2041016, 210)
	assert_true(2043704 in _ids(dark) and 2043705 in _ids(dark), "dark 70% and 30% wand scrolls")
	assert_false(2043700 in _ids(dark), "no plain scroll at Vega")


func test_a_family_without_a_rate_is_left_out_at_that_npc() -> void:
	# Hat ACC now has a 10% scroll (2040016, WZ success "10" cast by the loader); shoes ATT has no dark scrolls.
	var ten := _stock(1052104, 210)
	assert_eq(ten.filter(func(e: Dictionary) -> bool: return e.slot == "hat").size(), 5, "hat ACC 10% is stocked")
	var dark := _stock(2041016, 0)
	assert_eq(dark.size(), 36, "hat, top and bottom: five families with two dark rates each; shoes: three (ATT has none)")


func test_an_unknown_job_branch_gets_no_stock_the_list_cannot_reach() -> void:
	# A Thief (job 400) wears the all-job items only: the Beginner stock.
	assert_eq(_stock(1032103, 400).size(), 19)


# --- buying ---

func test_buying_deducts_the_price_and_adds_the_scroll() -> void:
	var state := _state(100000)
	assert_eq(Shop.buy(state, 2040400, 1, 35000, 100), "")
	assert_eq(state.mesos, 65000)
	assert_eq(state.scrolls, {"2040400": 1})


func test_buying_several_at_once_charges_each_and_stacks_them() -> void:
	var state := _state(200000, {"2040400": 3})
	assert_eq(Shop.buy(state, 2040400, 4, 35000, 100), "")
	assert_eq(state.mesos, 200000 - 4 * 35000)
	assert_eq(state.scrolls, {"2040400": 7})


func test_not_enough_mesos_refuses_and_changes_nothing() -> void:
	var state := _state(69999)
	assert_eq(Shop.buy(state, 2043700, 1, 70000, 100), "mesos")
	assert_eq(state.mesos, 69999)
	assert_eq(state.scrolls, {})
	assert_eq(Shop.buy(state, 2040400, 2, 35000, 100), "mesos", "the whole quantity must be affordable")
	assert_eq(state.mesos, 69999)


func test_a_full_stack_refuses_the_whole_purchase() -> void:
	var state := _state(10000000, {"2040400": 99})
	assert_eq(Shop.buy(state, 2040400, 2, 35000, 100), "use_full", "99 + 2 is more than slotMax 100")
	assert_eq(state.mesos, 10000000)
	assert_eq(state.scrolls, {"2040400": 99}, "not even the one that would fit is added")
	assert_eq(Shop.buy(state, 2040400, 1, 35000, 100), "")
	assert_eq(state.scrolls, {"2040400": 100})
	assert_eq(Shop.buy(state, 2040400, 1, 35000, 100), "use_full")


func test_a_full_use_tab_refuses_a_new_scroll_but_not_more_of_a_held_one() -> void:
	var stacks := {}
	for i in 22:
		stacks[str(2040000 + i)] = 1
	var state := _state(1000000, stacks)
	assert_eq(Shop.use_stack_limit(), 24, "all Use slots are for scrolls")
	assert_eq(Shop.buy(state, 2043700, 1, 35000, 100), "", "a 23rd stack fits")
	assert_eq(Shop.buy(state, 2043800, 1, 35000, 100), "", "a 24th stack fits")
	assert_eq(state.scrolls.size(), 24)
	assert_eq(Shop.buy(state, 2044000, 1, 35000, 100), "use_full", "a 25th stack has no slot")
	assert_eq(state.mesos, 930000, "the refused purchase takes no mesos")
	assert_false(state.scrolls.has("2044000"))
	assert_eq(Shop.buy(state, 2040000, 3, 35000, 100), "", "a held stack still takes more")
	assert_eq(state.scrolls["2040000"], 4)


func test_a_quantity_below_one_is_refused() -> void:
	var state := _state(100000)
	assert_eq(Shop.buy(state, 2040400, 0, 35000, 100), "count")
	assert_eq(Shop.buy(state, 2040400, -2, 35000, 100), "count")
	assert_eq(state.mesos, 100000)


func test_buying_works_on_a_plain_snapshot_dictionary() -> void:
	# The bot planner (#112) calls the same functions on the snapshot RunWorld hands out.
	var world := _world()
	var snapshot := world.character_snapshot()
	snapshot.mesos = 80000
	assert_eq(Shop.buy(snapshot, 2040400, 2, 35000, 100), "")
	assert_eq(snapshot.mesos, 10000)
	assert_eq(snapshot.scrolls["2040400"], 2)


# --- selling ---

func test_selling_spare_equipment_pays_its_info_price() -> void:
	var state := _state(10, {}, [Equipment.create(1002001, INFO[1002001]), Equipment.create(1040002, INFO[1040002])])
	assert_eq(Shop.sell_equipment(state, 0, INFO[1002001]), "")
	assert_eq(state.mesos, 1510)
	assert_eq(state.equipment.inventory.size(), 1)
	assert_eq(int(state.equipment.inventory[0].id), 1040002, "the other item stays")
	assert_eq(Shop.sell_equipment(state, 5, {}), "no_item")
	assert_eq(Shop.sell_equipment(state, 0, {"incPDD": 1}), "unsellable", "no info/price: nothing is bought")
	assert_eq(state.equipment.inventory.size(), 1)
	assert_eq(state.mesos, 1510)


func test_worn_equipment_cannot_be_sold() -> void:
	var worn := {"hat": Equipment.create(1002001, INFO[1002001])}
	var state := _state(0, {}, [], worn)
	assert_eq(Shop.sell_worn(state, "hat"), "worn")
	assert_eq(Shop.sell_worn(state, "top"), "no_item")
	assert_eq(Shop.sell_equipment(state, 0, INFO[1002001]), "no_item", "the hat is not in the spare inventory")
	assert_true(state.equipment.worn.has("hat"))
	assert_eq(state.mesos, 0)


func test_selling_scrolls_pays_one_meso_each_and_clears_an_empty_stack() -> void:
	var state := _state(0, {"2043700": 5})
	assert_eq(Shop.sell_scrolls(state, 2043700, 2, SCROLL_INFO[2043700]), "")
	assert_eq(state.mesos, 2)
	assert_eq(state.scrolls, {"2043700": 3})
	assert_eq(Shop.sell_scrolls(state, 2043700, 4, SCROLL_INFO[2043700]), "no_item", "only three are held")
	assert_eq(state.scrolls, {"2043700": 3})
	assert_eq(Shop.sell_scrolls(state, 2043700, 3, SCROLL_INFO[2043700]), "")
	assert_eq(state.scrolls, {}, "the stack goes with its last scroll")
	assert_eq(state.mesos, 5)
	assert_eq(Shop.sell_scrolls(state, 2043700, 0, SCROLL_INFO[2043700]), "count")


# --- RunWorld ---

func _world(job_id := 0, mesos := 0, inventory: Array = [], scrolls: Dictionary = {}) -> RunWorld:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	setup.scroll_info = SCROLL_INFO.duplicate(true)
	var character := RunWorld.new(setup).character_snapshot()
	character.mesos = mesos
	character.scrolls = scrolls
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	setup.character = character
	var world := RunWorld.new(setup)
	RF.change_job_bare(world, job_id) # a fresh character is 212 (#284); 0 stands a Beginner-class character directly
	return world


func test_a_beginner_world_sells_only_all_job_scrolls_and_a_wizard_gets_weapon_scrolls() -> void:
	var beginner := _world()
	assert_eq(_ids(beginner.shop_stock(1032103)).size(), 19)
	assert_eq(beginner.buy_scroll(1032103, 2043700, 1), "not_sold", "no wand scroll for a Beginner")
	var magician := _world(200)
	assert_true(2043700 in _ids(magician.shop_stock(1032103)))
	assert_eq(magician.shop_stock(5), [], "an unknown NPC sells nothing")


func test_buy_scroll_changes_the_character_and_emits_an_event() -> void:
	var world := _world(200, 100000)
	world.drain_events()
	assert_eq(world.buy_scroll(1032103, 2043700, 1), "")
	assert_eq(world.mesos, 30000, "the weapon price is 70,000")
	assert_eq(world.scrolls, {"2043700": 1})
	assert_eq(world.drain_events(), [{"type": "equipment_changed", "action": "buy", "slot": "", "item_id": 2043700}])
	assert_eq(world.character_snapshot().mesos, 30000, "the carried character holds the new mesos")
	assert_eq(world.buy_scroll(1032103, 2043700, 1), "mesos", "30,000 does not buy another")
	assert_eq(world.mesos, 30000)
	assert_eq(world.drain_events(), [], "a refusal emits nothing")
	assert_eq(world.buy_scroll(2022002, 2043700, 1), "not_sold", "the 60% NPC does not sell the 100% scroll")


func test_sell_item_and_sell_scrolls_pay_the_character() -> void:
	var world := _world(0, 0, [1002001], {"2043700": 4})
	world.drain_events()
	assert_eq(world.sell_item(0), "")
	assert_eq(world.mesos, 1500)
	assert_eq(world.equipment.inventory.size(), 0)
	assert_eq(world.sell_item(0), "no_item")
	assert_eq(world.sell_scrolls(2043700, 3), "")
	assert_eq(world.mesos, 1503)
	assert_eq(world.scrolls, {"2043700": 1})
	var events := world.drain_events()
	assert_eq(events.map(func(e: Dictionary) -> String: return e.action), ["sell", "sell"])


func test_a_worn_item_is_not_sellable_through_the_world() -> void:
	var world := _world(0, 0, [1002001])
	assert_eq(world.equip_item(0), "")
	assert_true(world.equipment.worn.has("hat"))
	assert_eq(world.sell_item(0), "no_item", "the hat moved out of the spare inventory")
	assert_true(world.equipment.worn.has("hat"))
	assert_eq(world.mesos, 0)


func test_scroll_info_keeps_the_sell_price() -> void:
	var loader := func(_p: String) -> Dictionary:
		return {"02040000": {"info": {"price": 1.0, "success": 100.0, "incPDD": 2.0, "icon": {"x": 1}}}}
	var info := DataRepo.scroll_info([2040000], loader)
	assert_eq(info[2040000], {"price": 1, "success": 100, "incPDD": 2}, "numbers only, price included")


func test_grant_scrolls_and_the_shop_agree_on_the_use_tab_size() -> void:
	var world := _world()
	for i in 24:
		assert_eq(world.grant_scrolls(2040000 + i, 1), 1)
	assert_eq(world.grant_scrolls(2043700, 1), 0, "24 scroll stacks fill the Use tab")
	world.mesos = 1000000
	assert_eq(world.buy_scroll(1032103, 2040400, 1), "use_full", "the shop sees the same full tab")
	assert_eq(world.mesos, 1000000)
	assert_eq(world.buy_scroll(1032103, 2040000, 1), "", "more of a held scroll still fits")
