extends TestCase
## The pure Scrolls module (game/scripts/sim/scrolls.gd, #110): v83 scroll rules on worn equipment with a seeded RNG.
## Scroll info here is the real v83 Item.wz/Consume/0204.img `info` of the ids named in the ticket (success, cursed
## and inc* literals read from the original data); no asset cache needed.

const WAND := 1372005
const SCROLLS := {
	2043700: {"incMAD": 1, "success": 100},
	2043701: {"incMAD": 2, "incINT": 1, "success": 60},
	2043702: {"incMAD": 5, "incINT": 3, "incMDD": 1, "success": 10},
	2043704: {"incMAD": 2, "incINT": 1, "success": 70, "cursed": 50},
	2043705: {"incMAD": 5, "incINT": 3, "incMDD": 1, "success": 30, "cursed": 50},
	2040512: {"incINT": 1, "success": 100}, # overall INT
	2040818: {"success": 100, "incMAD": 1}, # gloves magic att.
}


func _worn(slots: int = 7) -> Dictionary:
	var wand := Equipment.create(WAND, {"incPAD": 15, "incMAD": 23, "tuc": slots})
	return {"weapon": wand}


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_a_100_percent_scroll_always_succeeds_adding_exactly_its_stats() -> void:
	var rng := _rng(5)
	for i in 50:
		var worn := _worn()
		assert_eq(Scrolls.use(worn, "weapon", 2043700, SCROLLS[2043700], rng), "success")
		assert_eq(worn.weapon.stats, {"incPAD": 15, "incMAD": 24})
		assert_eq(worn.weapon.slots, 6)
		assert_eq(worn.weapon.scrolls, 1)


func test_success_adds_every_inc_stat_of_the_scroll_and_keeps_others() -> void:
	var worn := _worn()
	var rng := _rng()
	# A 10% scroll through a rigged info (success 100) shows the stats added; the stat keys come from the info.
	var info: Dictionary = SCROLLS[2043702].duplicate()
	info.success = 100
	assert_eq(Scrolls.use(worn, "weapon", 2043702, info, rng), "success")
	assert_eq(worn.weapon.stats, {"incPAD": 15, "incMAD": 28, "incINT": 3, "incMDD": 1})


func test_a_failure_spends_a_slot_and_changes_nothing_else() -> void:
	# Seed 1 on the 10% scroll: find a failing roll deterministically, then check the item.
	var rng := _rng(3)
	var failures := 0
	for i in 40:
		var worn := _worn()
		var result := Scrolls.use(worn, "weapon", 2043702, SCROLLS[2043702], rng)
		if result == "failure":
			failures += 1
			assert_eq(worn.weapon.stats, {"incPAD": 15, "incMAD": 23})
			assert_eq(worn.weapon.slots, 6)
			assert_eq(worn.weapon.scrolls, 0)
		else:
			assert_eq(result, "success")
			assert_eq(worn.weapon.scrolls, 1)
	assert_true(failures > 20, "a 10 percent scroll mostly fails (%d of 40)" % failures)


func test_plain_scrolls_never_destroy_the_item() -> void:
	var rng := _rng(11)
	for i in 300:
		var worn := _worn()
		var result := Scrolls.use(worn, "weapon", 2043702, SCROLLS[2043702], rng)
		assert_true(result in ["success", "failure"], result)
		assert_true(worn.has("weapon"))


func test_success_rate_follows_info_success() -> void:
	var rng := _rng(2026)
	var wins := 0
	for i in 2000:
		var worn := _worn()
		if Scrolls.use(worn, "weapon", 2043701, SCROLLS[2043701], rng) == "success":
			wins += 1
	assert_true(wins > 1130 and wins < 1270, "60 percent scroll won %d of 2000" % wins)


func test_a_failed_dark_scroll_destroys_the_item_at_its_cursed_rate() -> void:
	var rng := _rng(77)
	var failed := 0
	var destroyed := 0
	var wins := 0
	for i in 3000:
		var worn := _worn()
		var result := Scrolls.use(worn, "weapon", 2043705, SCROLLS[2043705], rng)
		match result:
			"success":
				wins += 1
				assert_true(worn.has("weapon"))
			"failure":
				failed += 1
				assert_true(worn.has("weapon"))
				assert_eq(worn.weapon.slots, 6)
			"destroyed":
				destroyed += 1
				failed += 1
				assert_false(worn.has("weapon"), "a destroyed item leaves its slot")
			_:
				fail("unexpected " + result)
	assert_true(wins > 800 and wins < 1000, "dark 30 percent won %d of 3000" % wins)
	assert_true(destroyed > failed * 0.45 and destroyed < failed * 0.55, "destroyed %d of %d failures" % [destroyed, failed])


func test_a_dark_scroll_that_succeeds_never_destroys() -> void:
	var rng := _rng(4)
	for i in 500:
		var worn := _worn()
		var info: Dictionary = SCROLLS[2043704].duplicate()
		info.success = 100
		assert_eq(Scrolls.use(worn, "weapon", 2043704, info, rng), "success")
		assert_true(worn.has("weapon"))


func test_a_scroll_for_another_item_type_is_refused_and_changes_nothing() -> void:
	var worn := _worn()
	var before := worn.duplicate(true)
	assert_eq(Scrolls.use(worn, "weapon", 2040512, SCROLLS[2040512], _rng()), "scroll_type", "overall scroll on a wand")
	assert_eq(Scrolls.use(worn, "weapon", 2040818, SCROLLS[2040818], _rng()), "scroll_type", "gloves scroll on a wand")
	assert_eq(worn, before)


func test_an_item_without_upgrade_slots_is_refused() -> void:
	var worn := _worn(0)
	var before := worn.duplicate(true)
	assert_eq(Scrolls.use(worn, "weapon", 2043700, SCROLLS[2043700], _rng()), "scroll_slots")
	assert_eq(worn, before)


func test_a_scroll_can_be_used_until_the_slots_run_out() -> void:
	var worn := _worn(2)
	var rng := _rng()
	assert_eq(Scrolls.use(worn, "weapon", 2043700, SCROLLS[2043700], rng), "success")
	assert_eq(Scrolls.use(worn, "weapon", 2043700, SCROLLS[2043700], rng), "success")
	assert_eq(Scrolls.use(worn, "weapon", 2043700, SCROLLS[2043700], rng), "scroll_slots")
	assert_eq(worn.weapon.stats.incMAD, 25)
	assert_eq(worn.weapon.scrolls, 2)


func test_only_worn_items_can_be_scrolled() -> void:
	var worn := _worn()
	assert_eq(Scrolls.use(worn, "hat", 2043700, SCROLLS[2043700], _rng()), "empty", "nothing worn in that slot")
	assert_eq(Scrolls.use(worn, "inventory", 2043700, SCROLLS[2043700], _rng()), "not_worn", "not an equip slot")
	assert_eq(Scrolls.use(worn, "weapon", 2043700, {}, _rng()), "scroll_unknown", "no WZ info for the scroll")
	assert_eq(Scrolls.use(worn, "weapon", 2043700, {"incMAD": 1}, _rng()), "scroll_unknown", "no info/success")


func test_the_overall_scroll_works_on_a_worn_overall_not_on_a_top() -> void:
	var overall := Equipment.create(1050010, {"incPDD": 20, "tuc": 10})
	var top := Equipment.create(1040002, {"incPDD": 3, "tuc": 7})
	var worn := {"overall": overall}
	assert_eq(Scrolls.use(worn, "overall", 2040512, SCROLLS[2040512], _rng()), "success")
	assert_eq(worn.overall.stats, {"incPDD": 20, "incINT": 1})
	worn = {"top": top}
	assert_eq(Scrolls.use(worn, "top", 2040512, SCROLLS[2040512], _rng()), "scroll_type")


func test_the_same_seed_gives_the_same_outcomes() -> void:
	var a := []
	var b := []
	for out: Array in [a, b]:
		var rng := _rng(99)
		for i in 30:
			out.append(Scrolls.use(_worn(), "weapon", 2043705, SCROLLS[2043705], rng))
	assert_eq(a, b)


# --- stacks -----------------------------------------------------------------------------------------------------------

func test_stacks_are_capped_by_slot_max_and_by_the_use_tab() -> void:
	var stacks := {}
	assert_eq(Scrolls.add(stacks, 2043700, 30, 100, 22), 30)
	assert_eq(Scrolls.add(stacks, 2043700, 90, 100, 22), 70, "a stack stops at slotMax")
	assert_eq(stacks, {"2043700": 100})
	assert_eq(Scrolls.add(stacks, 2043700, 1, 100, 22), 0)
	assert_eq(Scrolls.add(stacks, 2043701, 5, 0, 22), 5, "slotMax absent: the default 100")
	var full := {}
	for i in 3:
		full[str(2043700 + i)] = 1
	assert_eq(Scrolls.add(full, 2043710, 5, 100, 3), 0, "a new stack needs a free Use slot")
	assert_eq(Scrolls.add(full, 2043700, 5, 100, 3), 5, "an existing stack needs none")
	assert_eq(Scrolls.add(full, 2043700, 0, 100, 3), 0)
	assert_eq(Scrolls.add(full, 2043700, -4, 100, 3), 0)


func test_taking_the_last_scroll_removes_the_stack() -> void:
	var stacks := {"2043700": 2}
	assert_true(Scrolls.take(stacks, 2043700))
	assert_eq(stacks, {"2043700": 1})
	assert_true(Scrolls.take(stacks, 2043700))
	assert_eq(stacks, {})
	assert_false(Scrolls.take(stacks, 2043700))


# --- roster data ------------------------------------------------------------------------------------------------------

func test_the_roster_lists_every_family_the_ticket_names() -> void:
	var table: Dictionary = DataRepo.load_all().scrolls
	assert_false(table.is_empty())
	var wanted := {"hat": ["DEF", "HP", "INT", "ACC", "DEX"], "top": ["DEF", "STR", "HP", "LUK"],
		"bottom": ["DEF", "Jump", "HP", "DEX"], "overall": ["INT", "DEX", "DEF", "LUK", "STR"],
		"shoes": ["DEX", "Jump", "Speed", "ATT"], "gloves": ["DEX", "ATT", "HP", "Magic Att."],
		"wand": ["Magic Att."], "staff": ["Magic Att."]}
	for slot: String in wanted:
		for family: String in wanted[slot]:
			assert_true(table.families[slot].has(family), "%s %s" % [slot, family])
	assert_false(table.families.has("cape"))


func _family(table: Dictionary, slot: String, family: String) -> Array:
	var f: Dictionary = table.families[slot][family]
	return ["100", "60", "10", "dark70", "dark30"].map(func(k: String) -> int: return int(f[k]))


func test_the_roster_has_the_ticket_examples_by_rate() -> void:
	var table: Dictionary = DataRepo.load_all().scrolls
	var ids := Scrolls.ids(table)
	assert_eq(_family(table, "wand", "Magic Att."), [2043700, 2043701, 2043702, 2043704, 2043705])
	assert_eq(_family(table, "overall", "INT"), [2040512, 2040513, 2040514, 2040518, 2040519])
	assert_eq(_family(table, "gloves", "Magic Att."), [2040818, 2040817, 2040816, 2040814, 2040815])
	assert_true(2043700 in ids and 2040818 in ids)
	assert_false(2040016 in ids, "hat ACC 10% has no success in WZ")
	assert_false(2040006 in ids, "the strong 100% is out")
	var seen := {}
	for id: int in ids:
		assert_false(seen.has(id), "listed once: %d" % id)
		seen[id] = true


func test_every_roster_scroll_fits_the_item_slot_it_is_listed_under() -> void:
	var table: Dictionary = DataRepo.load_all().scrolls
	var categories := {"hat": 0, "top": 4, "bottom": 6, "overall": 5, "shoes": 7, "gloves": 8, "wand": 37, "staff": 38}
	for slot: String in table.families:
		for family: String in table.families[slot]:
			for rate: String in table.families[slot][family]:
				var id := int(table.families[slot][family][rate])
				assert_eq(Scrolls.category_of_scroll(id), categories[slot], "%d under %s" % [id, slot])
