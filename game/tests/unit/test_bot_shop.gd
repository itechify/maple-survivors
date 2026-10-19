extends TestCase
## Bot shopping (spec #33, #112): the equip-on-pickup/level-up rule (BotShop.auto_equip) and the Free Market shop plan
## (BotShop.plan, applied by BotShop.visit through RunWorld). Real survivor data (shops.json, scrolls.json, the bot's
## equipment weights) with synthetic canonical item and scroll info; no asset cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const INFO := {
	1040002: {"incPDD": 3, "tuc": 7, "price": 50}, # starter top
	1060002: {"incPDD": 2, "tuc": 7, "price": 40}, # starter bottom
	1072001: {"incPDD": 2, "tuc": 5, "price": 30},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7, "price": 100}, # starter sword
	1372005: {"reqJob": 2, "reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7, "price": 1000},
	1372006: {"reqJob": 2, "reqLevel": 8, "incMAD": 30, "attackSpeed": 6, "tuc": 7, "price": 2000}, # a better wand
	1372007: {"reqJob": 2, "reqLevel": 40, "incMAD": 50, "attackSpeed": 6, "tuc": 7, "price": 9000}, # needs Lv 40
	1372008: {"reqJob": 2, "reqLevel": 8, "incMAD": 10, "attackSpeed": 6, "tuc": 7, "price": 700}, # a worse wand
	1382000: {"reqJob": 2, "reqLevel": 10, "incMAD": 25, "attackSpeed": 6, "tuc": 7, "price": 1200}, # a staff
	1002008: {"incPDD": 9, "tuc": 7, "price": 300}, # all-job hat
	1050001: {"reqJob": 2, "incMDD": 3, "tuc": 7, "price": 500}, # a weak Magician overall
	1050002: {"reqJob": 2, "incMDD": 8, "incINT": 2, "tuc": 7, "price": 800}, # a strong Magician overall
	1082002: {"incPAD": 1, "tuc": 5, "price": 150}, # gloves
	1092009: {"incPDD": 10, "tuc": 7, "price": 400}, # an all-job shield
	1402001: {"incPAD": 40, "attackSpeed": 6, "tuc": 7, "price": 3000}, # a strong two-handed sword
	1402002: {"incPAD": 18, "attackSpeed": 6, "tuc": 7, "price": 900}, # a weak two-handed sword
}
const SCROLL_INFO := {
	2043700: {"incMAD": 1, "success": 100, "price": 1}, # wand 100%
	2043701: {"incMAD": 2, "incINT": 1, "success": 60, "price": 1}, # wand 60%
	2043704: {"incMAD": 3, "success": 70, "cursed": 70, "price": 1}, # wand dark 70%
	2043800: {"incMAD": 1, "success": 100, "price": 1}, # staff 100%
	2040512: {"incINT": 2, "success": 100, "price": 1}, # overall INT 100%
	2040503: {"incPDD": 1, "success": 100, "price": 1}, # overall DEF 100%
	2040818: {"incMAD": 1, "success": 100, "price": 1}, # gloves magic att. 100%
	2040803: {"incPAD": 1, "success": 100, "price": 1}, # gloves ATT 100%
	2040000: {"incPDD": 2, "success": 100, "price": 1}, # hat DEF 100%
	2040400: {"incPDD": 1, "success": 100, "price": 1}, # top DEF 100%
	2040600: {"incPDD": 1, "success": 100, "price": 1}, # bottom DEF 100%
	2040700: {"incDEX": 1, "success": 100, "price": 1}, # shoes DEX 100%
	2040008: {"incPDD": 3, "success": 70, "cursed": 70, "price": 1}, # hat DEF dark 70%
}

var _data: Dictionary


func before_each() -> void:
	_data = DataRepo.load_all()


## A quiet-stage Magician at `level` wearing the starter top/bottom/shoes and the Wooden Wand.
func _world(level := 10, mesos := 0, inventory: Array = [], scrolls: Dictionary = {}, seed_value := 7) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", seed_value, data)
	setup.equipment_info = INFO.duplicate(true)
	setup.scroll_info = SCROLL_INFO.duplicate(true)
	var character := RunWorld.new(setup).character_snapshot()
	character.level = level
	character.job_id = 200
	character.mesos = mesos
	character.scrolls = scrolls
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	character.equipment.worn.weapon = Equipment.create(1372005, INFO[1372005])
	var next := RF.setup("quiet", seed_value, data)
	next.equipment_info = INFO.duplicate(true)
	next.scroll_info = SCROLL_INFO.duplicate(true)
	next.character = character
	var w := RunWorld.new(next)
	RF.place_player(w, 400)
	return w


func _inventory_ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))


# --- equip on pickup / level-up ---

func test_a_bot_wears_a_better_item_it_picks_up() -> void:
	var w := _world(10, 0, [1372006])
	assert_eq(BotShop.auto_equip(w), 1)
	assert_eq(w.weapon_id(), 1372006, "the 30 M.ATT wand replaces the 23 M.ATT one")
	assert_eq(_inventory_ids(w), [1372005], "the old wand went to the Equip tab")


func test_a_bot_keeps_what_it_wears_when_the_new_item_scores_lower() -> void:
	var w := _world(10, 0, [1372008])
	assert_eq(BotShop.auto_equip(w), 0)
	assert_eq(w.weapon_id(), 1372005)
	assert_eq(_inventory_ids(w), [1372008])


func test_a_bot_does_not_wear_an_item_it_cannot_equip_yet_until_it_levels_into_it() -> void:
	var w := _world(10, 0, [1372007])
	assert_eq(BotShop.auto_equip(w), 0, "reqLevel 40 at Lv 10")
	assert_eq(w.weapon_id(), 1372005)
	w.progression.level = 40
	assert_eq(BotShop.auto_equip(w), 1, "worn once it is Lv 40")
	assert_eq(w.weapon_id(), 1372007)


func test_an_empty_slot_takes_any_item_with_value() -> void:
	var w := _world(10, 0, [1002008])
	assert_eq(BotShop.auto_equip(w), 1)
	assert_eq(w.equipment.worn.hat.id, 1002008)


func test_an_overall_is_compared_with_the_top_and_bottom_it_replaces() -> void:
	var w := _world(10, 0, [1050001])
	assert_eq(BotShop.auto_equip(w), 0, "M.DEF 3 (score 6) is less than the worn top and bottom together (7.5)")
	w = _world(10, 0, [1050002])
	assert_eq(BotShop.auto_equip(w), 1, "a strong overall beats them")
	assert_eq(w.equipment.worn.overall.id, 1050002)
	assert_false(w.equipment.worn.has("top") or w.equipment.worn.has("bottom"))
	assert_eq(_inventory_ids(w).size(), 2, "top and bottom are in the Equip tab")


## A quiet-stage Warrior-job bot (the Beginner weights) wearing the starter sword and `worn_extra` ids, holding `inventory`.
func _warrior(inventory: Array, worn_extra: Array = []) -> RunWorld:
	var w := _world(10, 0, inventory)
	w.progression.job_id = 100
	w.equipment.worn.weapon = Equipment.create(1302000, INFO[1302000])
	for id: int in worn_extra:
		w.equipment.worn[Equipment.slot_of(id)] = Equipment.create(id, INFO[id])
	return w


func test_the_shield_is_a_slot_the_bot_fills_and_scores_by_its_defence() -> void:
	var w := _warrior([1092009])
	assert_eq(BotShop.auto_equip(w), 1)
	assert_eq(w.equipment.worn.shield.id, 1092009, "an empty shield slot takes a shield with value")
	assert_eq(w.weapon_id(), 1302000, "beside the one-handed sword")


func test_weapon_loyalty_follows_the_recorded_path_even_after_a_manual_swap_or_destruction() -> void:
	for held in [1302000, 0]:
		var w := _warrior([1402001])
		w.weapon_path = "axe"
		if held == 0:
			w.equipment.worn.erase("weapon")
		w.setup.equipment_info[1312005] = {"incPAD": 25}
		w.equipment.inventory.append(Equipment.create(1312005, w.setup.equipment_info[1312005]))
		assert_eq(BotShop.auto_equip(w), 1, "only the recorded family's upgrade is worn")
		assert_eq(w.weapon_id(), 1312005, "the stronger off-path sword stays in the tab")


func test_a_two_handed_weapon_must_beat_the_sword_and_the_shield_it_displaces() -> void:
	# Beginner weights: incPAD 10, incPDD 1.5. Sword 17 -> 170, shield 10 -> 15.
	var strong := _warrior([1402001], [1092009])
	assert_eq(BotShop.auto_equip(strong), 1, "400 beats 170 + 15")
	assert_eq(strong.weapon_id(), 1402001)
	assert_false(strong.equipment.worn.has("shield"))
	assert_eq(_inventory_ids(strong).size(), 2, "the sword and the shield wait in the Equip tab")
	var weak := _warrior([1402002], [1092009])
	assert_eq(BotShop.auto_equip(weak), 0, "180 beats the sword's 170 but not with the shield's 15 lost")
	assert_eq(weak.weapon_id(), 1302000)
	assert_eq(weak.equipment.worn.shield.id, 1092009)


func test_a_shield_does_not_replace_a_two_handed_weapon_that_scores_higher() -> void:
	var w := _warrior([1092009], [])
	w.equipment.worn.weapon = Equipment.create(1402001, INFO[1402001])
	assert_eq(BotShop.auto_equip(w), 0, "a 15 point shield against the 400 point weapon it would move")
	assert_eq(w.weapon_id(), 1402001)
	assert_false(w.equipment.worn.has("shield"))


func test_an_equip_that_does_not_fit_the_full_tab_is_skipped_without_looping() -> void:
	var w := _world(10, 0, [1050002])
	while w.equipment.inventory.size() < w.inventory_slots():
		w.equipment.inventory.append(Equipment.create(1072001, INFO[1072001]))
	assert_eq(BotShop.auto_equip(w), 0, "the overall would displace two items into a full tab")
	assert_false(w.equipment.worn.has("overall"))


func test_equip_triggers_are_equipment_pickups_level_ups_and_job_changes() -> void:
	assert_true(BotShop.equip_trigger([{"type": "pickup_collected", "kind": "equip"}]))
	assert_true(BotShop.equip_trigger([{"type": "mob_hit"}, {"type": "level_up", "level": 5}]))
	assert_true(BotShop.equip_trigger([{"type": "job_changed", "job_id": 200}]))
	assert_false(BotShop.equip_trigger([{"type": "pickup_collected", "kind": "exp"}, {"type": "mob_died"}]))
	assert_false(BotShop.equip_trigger([]))


func test_equip_after_wears_only_when_the_drained_events_are_a_trigger() -> void:
	var w := _world(10, 0, [1372006])
	assert_eq(BotShop.equip_after(w, [{"type": "mob_died"}]), 0, "no trigger, no change")
	assert_eq(w.weapon_id(), 1372005)
	assert_eq(BotShop.equip_after(w, [{"type": "pickup_collected", "kind": "equip"}]), 1)
	assert_eq(w.weapon_id(), 1372006)
	assert_eq(BotShop.equip_after(w, [{"type": "level_up", "level": 11}]), 0, "nothing left to improve")


# --- the shop plan ---

const DARK := [2043704, 2040008]


func _plan(w: RunWorld, policy: String, seed_value := 1, edit := Callable()) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var character := BotShop.character_of(w)
	if edit.is_valid():
		edit.call(character)
	return BotShop.plan(character, BotShop.stock_of(w), BotShop.facts_of(w), policy, rng)


## Wears gloves, an overall, a hat and shoes beside the wand, as a bot that has been collecting for a while would.
func _dressed(mesos: int, seed_value := 7) -> RunWorld:
	var w := _world(10, mesos, [], {}, seed_value)
	w.equipment.worn.erase("top")
	w.equipment.worn.erase("bottom")
	for id: int in [1050002, 1082002, 1002008]:
		w.equipment.worn[Equipment.slot_of(id)] = Equipment.create(id, INFO[id])
	return w


func _uses(plan: Dictionary) -> Array:
	return plan.steps.filter(func(s: Dictionary) -> bool: return s.op == "use")


func _buys(plan: Dictionary) -> Array:
	return plan.steps.filter(func(s: Dictionary) -> bool: return s.op == "buy")


func _cost(plan: Dictionary, w: RunWorld) -> int:
	var price := {}
	for entry: Dictionary in BotShop.stock_of(w):
		price[int(entry.id)] = int(entry.price)
	var sum := 0
	for step: Dictionary in _buys(plan):
		sum += int(price[int(step.scroll)]) * int(step.count)
	return sum


func test_the_stock_lists_every_npc_with_its_id() -> void:
	var w := _dressed(0)
	var stock := BotShop.stock_of(w)
	var npcs := {}
	for entry: Dictionary in stock:
		npcs[int(entry.npc)] = true
	assert_eq(npcs.keys(), [1032103, 2022002, 1052104, 2041016])
	assert_true(stock.any(func(e: Dictionary) -> bool: return int(e.id) == 2043701 and int(e.npc) == 2022002))


func test_the_sensible_plan_sells_equipment_it_will_not_wear_and_keeps_what_it_can_still_grow_into() -> void:
	var w := _world(10, 0, [1372008, 1372007, 1040002])
	var plan := _plan(w, "sensible")
	assert_eq(plan.sell, [2, 0], "the worse wand and the duplicate top, last index first; the Lv 40 wand stays")


func test_the_sensible_plan_scrolls_the_weapon_overall_and_gloves_first_then_the_other_slots() -> void:
	var w := _dressed(5000000)
	var plan := _plan(w, "sensible")
	var order := []
	for step: Dictionary in _uses(plan):
		if order.is_empty() or order[-1] != step.slot:
			order.append(step.slot)
	assert_eq(order, ["weapon", "overall", "gloves", "hat", "shoes"])
	assert_eq(_uses(plan).size(), 7 + 7 + 5 + 7 + 5, "one scroll per remaining upgrade slot")
	var first_use := {}
	for step: Dictionary in _uses(plan):
		if not first_use.has(step.slot):
			first_use[step.slot] = int(step.scroll)
	assert_eq(first_use.weapon, 2043701, "the 60% wand scroll (expected 15.6) beats the 100% one (10)")
	assert_eq(first_use.overall, 2040512, "INT before defence for a Magician")
	assert_eq(first_use.gloves, 2040818, "Magic Att. gloves scroll")


func test_a_warrior_bot_scrolls_its_sword_and_shield_from_the_warrior_families() -> void:
	var w := _warrior([], [1092009])
	w.mesos = 5000000
	# the shops stock the families of the listed equipment the job can wear: one sword and one shield of the list
	w.setup.equipment_info[1302008] = {"reqJob": 1, "reqLevel": 30, "incPAD": 47, "tuc": 7}
	w.setup.equipment_info[1092002] = {"reqJob": 1, "reqLevel": 30, "incPDD": 40, "tuc": 7}
	for id: int in [2043000, 2043001, 2043004, 2040900, 2040929]:
		w.setup.scroll_info[id] = {"success": 100, "price": 1}
	w.setup.scroll_info[2043000].incPAD = 1 # sword ATT 100%
	w.setup.scroll_info[2043001] = {"incPAD": 2, "incSTR": 1, "success": 60, "price": 1} # sword ATT 60%
	w.setup.scroll_info[2043004] = {"incPAD": 2, "incSTR": 1, "success": 70, "cursed": 50, "price": 1} # sword ATT dark 70%
	w.setup.scroll_info[2040900].incPDD = 1 # shield DEF 100%
	w.setup.scroll_info[2040929].incSTR = 1 # shield STR 100%
	var stock_ids := BotShop.stock_of(w).map(func(e: Dictionary) -> int: return int(e.id))
	assert_true(2043001 in stock_ids and 2040929 in stock_ids, "a Warrior's shops stock the new families")
	var plan := _plan(w, "sensible")
	var first_use := {}
	for step: Dictionary in _uses(plan):
		if not first_use.has(step.slot):
			first_use[step.slot] = int(step.scroll)
	assert_eq(first_use.weapon, 2043001, "the 60% sword scroll (expected 15.6) beats the 100% one (10)")
	assert_eq(first_use.shield, 2040929, "STR (6) before defence (1.5) for a Warrior")
	assert_eq(_uses(plan).filter(func(s: Dictionary) -> bool: return s.slot == "weapon").size(), 7, "one per upgrade slot")
	for step: Dictionary in plan.steps:
		assert_false(int(step.scroll) == 2043004, "never the dark one")
	assert_true(_cost(plan, w) <= 5000000)
	var careless := _plan(w, "careless", 4)
	assert_true(_uses(careless).any(func(s: Dictionary) -> bool: return s.slot == "shield"), "the careless bot scrolls the shield too")


func test_the_sensible_plan_never_buys_dark_scrolls() -> void:
	var w := _dressed(5000000)
	var plan := _plan(w, "sensible")
	for step: Dictionary in plan.steps:
		assert_false(int(step.scroll) in DARK, "scroll %d is dark" % int(step.scroll))
	assert_false(_buys(plan).is_empty())


func test_the_sensible_plan_never_overspends() -> void:
	var w := _dressed(100000)
	var plan := _plan(w, "sensible")
	assert_eq(_buys(plan), [{"op": "buy", "npc": 2022002, "scroll": 2043701, "count": 1}], "one 70,000 wand scroll; 30,000 buys no 35,000 one")
	assert_eq(_uses(plan).size(), 1)
	assert_true(_cost(plan, w) <= 100000)


func test_the_sensible_plan_spends_what_the_sales_bring_in() -> void:
	var w := _world(10, 69500, [1372008])
	var plan := _plan(w, "sensible")
	assert_eq(plan.sell, [0])
	assert_eq(_buys(plan).size(), 1, "69,500 + 700 from the worse wand buys one 70,000 scroll")
	assert_true(_cost(plan, w) <= 69500 + 700)
	assert_eq(_buys(plan)[0].scroll, 2043701, "the weapon scroll")
	var without := _plan(_world(10, 69500), "sensible")
	assert_eq(_buys(without).size(), 1, "without the sale it cannot afford the weapon scroll, but one armour scroll")
	assert_eq(_buys(without)[0].scroll, 2040400, "the top's defence scroll (35,000)")


func test_the_sensible_plan_uses_scrolls_it_already_holds_before_buying() -> void:
	var w := _world(10, 70000, [], {"2043701": 2})
	var plan := _plan(w, "sensible")
	assert_eq(_buys(plan).size(), 1)
	assert_eq(_uses(plan).size(), 3, "2 held + 1 bought")


func test_the_careless_plan_is_deterministic_for_a_seed_buys_dark_scrolls_and_keeps_its_equipment() -> void:
	var w := _dressed(3000000)
	var a := _plan(w, "careless", 5)
	var b := _plan(w, "careless", 5)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same seed, same plan")
	assert_eq(a.sell, [], "a careless player does not tidy its Equip tab")
	assert_false(_buys(a).is_empty())
	assert_true(_cost(a, w) <= 3000000)
	var other := false
	var dark := false
	for s in range(1, 9):
		var plan := _plan(w, "careless", s)
		other = other or JSON.stringify(plan) != JSON.stringify(a)
		dark = dark or _buys(plan).any(func(step: Dictionary) -> bool: return int(step.scroll) in DARK)
	assert_true(other, "another seed gives another plan")
	assert_true(dark, "dark scrolls are bought by some seed")


func test_every_careless_scroll_bought_is_used_on_a_worn_item_it_fits() -> void:
	var w := _dressed(3000000)
	var plan := _plan(w, "careless", 3)
	for step: Dictionary in _uses(plan):
		assert_eq(Scrolls.category_of_scroll(int(step.scroll)), Scrolls.category_of_item(int(w.equipment.worn[step.slot].id)))
	assert_eq(_uses(plan).size(), _buys(plan).size(), "one scroll bought per use")


# --- visiting the shop ---

func test_a_sensible_visit_sells_buys_and_scrolls_through_the_world() -> void:
	var w := _dressed(600000)
	w.equipment.inventory.append(Equipment.create(1040002, INFO[1040002]))
	w.equipment.inventory.append(Equipment.create(1372008, INFO[1372008]))
	var rng := RandomNumberGenerator.new()
	var r := BotShop.visit(w, "bot", rng)
	assert_eq([r.sold, r.sale_mesos], [2, 750])
	assert_eq(r.mesos_before, 600000)
	assert_eq(r.mesos_after, w.mesos)
	assert_eq(r.spent, 600750 - w.mesos, "everything it paid")
	assert_true(w.mesos >= 0)
	assert_eq(r.used, r.succeeded + r.failed + r.destroyed)
	assert_eq(r.destroyed, 0, "no dark scrolls, so nothing is destroyed")
	assert_eq(r.bought, r.used, "every scroll bought was read")
	assert_eq(w.equipment.worn.weapon.slots, 0, "all seven weapon slots used")
	assert_eq(w.equipment.worn.overall.slots, 7 - 3, "110,750 left buys three armour scrolls")
	assert_eq(w.equipment.inventory, [], "spare equipment sold")
	assert_eq(r.worn.weapon, 1372005)


func test_a_visit_is_reproducible_from_the_seeds() -> void:
	var results := []
	for i in 2:
		var w := _dressed(900000, 21)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		var r := BotShop.visit(w, "random", rng)
		results.append(JSON.stringify([r, w.character_snapshot()]))
	assert_eq(results[0], results[1], "same seeds, same purchases and scroll results")


func test_a_careless_visit_keeps_its_books_even_when_dark_scrolls_destroy_items() -> void:
	var destroyed := 0
	for s in range(1, 13):
		var w := _dressed(2000000, 100 + s)
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var r := BotShop.visit(w, "random", rng)
		destroyed += r.destroyed
		assert_true(w.mesos >= 0, "never overspends")
		assert_eq(r.mesos_after, w.mesos)
		assert_eq(r.used, r.succeeded + r.failed + r.destroyed)
		var held := 0
		for n: Variant in w.scrolls.values():
			held += int(n)
		assert_eq(r.bought, r.used + held, "scrolls bought are read or still held")
		assert_eq(r.mesos_before - r.spent, r.mesos_after, "no sales for a careless player")
	assert_true(destroyed > 0, "some of twelve careless visits lost an item to a dark scroll")
