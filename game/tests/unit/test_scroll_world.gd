extends TestCase
## Scrolls in the live character through RunWorld's public interface (grant_scrolls, use_scroll, discard_scrolls,
## character_snapshot, events) on the synthetic quiet stage. Scroll info is the real v83 0204.img `info` of the ids used.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const DT := 1.0 / 60.0
const INFO := {
	1040002: {"incPDD": 3, "tuc": 7}, 1060002: {"incPDD": 2, "tuc": 7}, 1072001: {"incPDD": 2, "tuc": 5},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1372005: {"reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7},
	1002001: {"incPDD": 4, "tuc": 7},
}
const SCROLL_INFO := {
	2043700: {"incMAD": 1, "success": 100},
	2043702: {"incMAD": 5, "incINT": 3, "incMDD": 1, "success": 10},
	2043705: {"success": 30, "cursed": 50, "incMAD": 5, "incINT": 3, "incMDD": 1},
	2040400: {"incPDD": 1, "success": 100},
	2040518: {"incINT": 2, "incMDD": 1, "success": 70, "cursed": 50},
	2043701: {"incMAD": 2, "incINT": 1, "success": 60},
}


func _setup(character: Dictionary = {}, seed_value: int = 7) -> Dictionary:
	var setup := RF.setup("quiet", seed_value, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	setup.scroll_info = SCROLL_INFO.duplicate(true)
	if not character.is_empty():
		setup.character = character
	return setup


## A world wearing the starter outfit with `scrolls` in the Use tab and `inventory` ids spare.
func _world(scrolls: Dictionary = {}, inventory: Array = [], seed_value: int = 7) -> RunWorld:
	var character := RunWorld.new(_setup()).character_snapshot()
	character.scrolls = scrolls
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	var world := RunWorld.new(_setup(character, seed_value))
	RF.place_player(world, 400)
	return world


func _events(world: RunWorld, type: String) -> Array:
	return world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == type)


func test_a_100_percent_scroll_adds_stats_spends_a_slot_and_is_used_up() -> void:
	var world := _world({"2040400": 2})
	var pdd_before: float = world.player_state.pdd
	world.drain_events()
	assert_eq(world.use_scroll(2040400, "top"), "")
	assert_eq(world.equipment.worn.top, {"id": 1040002, "stats": {"incPDD": 4}, "slots": 6, "scrolls": 1})
	assert_eq(world.scrolls, {"2040400": 1}, "one scroll used up")
	assert_eq(world.player_state.pdd, pdd_before + 1.0, "stats update at once")
	var events := world.drain_events()
	assert_eq(events.size(), 2)
	assert_eq(events[0], {"type": "equipment_changed", "action": "scroll", "slot": "top", "item_id": 1040002})
	assert_eq(events[1], {"type": "scroll_used", "result": "success", "scroll_id": 2040400, "slot": "top",
		"item_id": 1040002})


func test_the_last_scroll_of_a_stack_removes_the_stack_and_the_snapshot_stays_valid() -> void:
	var world := _world({"2040400": 1})
	assert_eq(world.use_scroll(2040400, "top"), "")
	assert_eq(world.scrolls, {})
	assert_eq(CharacterSnapshot.validation_error(world.character_snapshot()), "")
	assert_eq(world.use_scroll(2040400, "top"), "no_item", "none left")


func test_a_refused_scroll_is_kept_and_nothing_changes() -> void:
	var world := _world({"2043700": 1, "2040400": 1}, [1002001])
	var before := world.equipment.duplicate(true)
	world.drain_events()
	assert_eq(world.use_scroll(2043700, "top"), "scroll_type", "a wand scroll on a top")
	assert_eq(world.use_scroll(2040400, "hat"), "empty", "nothing worn on the head")
	assert_eq(world.scrolls, {"2043700": 1, "2040400": 1})
	assert_eq(world.equipment, before)
	assert_eq(world.drain_events(), [])
	world.equipment.worn.top.slots = 0
	assert_eq(world.use_scroll(2040400, "top"), "scroll_slots")
	assert_eq(world.scrolls, {"2043700": 1, "2040400": 1})
	assert_eq(world.use_scroll(2040400, "inventory"), "not_worn", "inventory items cannot be scrolled")
	assert_eq(world.equipment.inventory[0].slots, 7)


func test_a_scroll_without_wz_info_is_refused_and_kept() -> void:
	var world := _world({"2040999": 1})
	assert_eq(world.use_scroll(2040999, "top"), "scroll_unknown")
	assert_eq(world.scrolls, {"2040999": 1})


func test_a_failed_plain_scroll_spends_a_slot_and_the_scroll_only() -> void:
	# Seed search: find a seed whose first roll fails the 10% scroll, so the test does not depend on luck below.
	for seed_value in range(1, 30):
		var world := _world({"2043702": 1}, [], seed_value)
		world.equipment.worn.weapon = Equipment.create(1372005, INFO[1372005])
		assert_eq(world.use_scroll(2043702, "weapon"), "")
		var used: Dictionary = _events(world, "scroll_used")[0]
		if used.result != "failure":
			continue
		assert_eq(world.equipment.worn.weapon, {"id": 1372005, "stats": {"incPAD": 15, "incMAD": 23}, "slots": 6, "scrolls": 0})
		assert_eq(world.scrolls, {})
		return
	fail("no failing seed in 1..29 for a 10% scroll")


func test_the_same_seed_scrolls_the_same_way_and_other_streams_are_untouched() -> void:
	var outcomes := []
	for run in 2:
		var world := _world({"2043705": 30}, [], 42)
		world.equipment.worn.weapon = Equipment.create(1372005, {"incPAD": 15, "incMAD": 23, "tuc": 100})
		var results := []
		for i in 12:
			if world.equipment.worn.has("weapon"):
				world.use_scroll(2043705, "weapon")
				results.append(_events(world, "scroll_used")[0].result)
		outcomes.append(results)
	assert_eq(outcomes[0], outcomes[1])
	var a := _world({"2043705": 2}, [], 42)
	var b := _world({"2043705": 2}, [], 42)
	b.equipment.worn.weapon = Equipment.create(1372005, INFO[1372005])
	b.use_scroll(2043705, "weapon")
	assert_eq(a.rng.randi(), b.rng.randi(), "combat rolls are not shifted by scrolling")
	assert_eq(a.meso_rng.randi(), b.meso_rng.randi())


func test_a_destroyed_weapon_leaves_the_character_bare_handed_and_still_able_to_attack() -> void:
	var world := BF.world()
	world.setup.scroll_info = SCROLL_INFO.duplicate(true)
	world.scrolls = {"2043705": 40}
	world.equipment.worn.weapon = Equipment.create(1372005, {"incPAD": 15, "incMAD": 23, "tuc": 100})
	world.drain_events()
	var destroyed := false
	for i in 40:
		if world.use_scroll(2043705, "weapon") != "":
			break
		var used: Dictionary = _events(world, "scroll_used")[-1]
		if used.result == "destroyed":
			destroyed = true
			break
	assert_true(destroyed, "a dark 30% scroll destroys the wand within 40 tries")
	assert_eq(world.weapon_id(), 0)
	assert_eq(world.weapon_attack(), 0.0)
	assert_false(world.equipment.worn.has("weapon"))
	assert_eq(CharacterSnapshot.validation_error(world.character_snapshot()), "")
	var mob := RF.put_mob(world, 100100, 450.0, 190, 100)
	world.swarm.hp[mob] = 1000
	world.swarm.max_hp[mob] = 1000
	var hits := 0
	for tick in 120:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "mob_hit":
				hits += 1
	assert_true(hits >= 1, "the bare-handed punch still hits")


func test_a_destroyed_overall_leaves_neither_top_nor_bottom_worn() -> void:
	var world := _world({"2040518": 60})
	Equipment.grant(world.equipment, Equipment.create(1050010, {"incPDD": 20, "tuc": 100}), 24)
	assert_true(world.equipment.worn.has("overall") and not world.equipment.worn.has("top"))
	var gone := false
	for i in 60:
		if world.use_scroll(2040518, "overall") != "":
			break
		if not world.equipment.worn.has("overall"):
			gone = true
			break
	assert_true(gone, "a dark 70% scroll destroys the overall at its 50% curse rate within 60 tries")
	for slot: String in ["top", "bottom", "overall"]:
		assert_false(world.equipment.worn.has(slot), slot)


func test_granting_scrolls_respects_slot_max_and_the_use_tab() -> void:
	var world := _world()
	assert_eq(world.grant_scrolls(2040400, 60), 60)
	assert_eq(world.grant_scrolls(2040400, 60), 40, "a stack stops at 100 (no info/slotMax in the data)")
	assert_eq(world.scrolls, {"2040400": 100})
	assert_eq(world.grant_scrolls(2040400, 1), 0)
	assert_eq(world.grant_scrolls(2043700, 0), 0)
	assert_eq(world.grant_scrolls(2043700, -3), 0)
	var cap := Scrolls.USE_SLOTS - 2
	for i in cap - 1:
		world.scrolls[str(2049000 + i)] = 1
	assert_eq(world.scrolls.size(), cap, "the two potion stacks leave 22 slots for scrolls")
	assert_eq(world.grant_scrolls(2043700, 5), 0, "the Use tab is full")
	assert_eq(world.grant_scrolls(2040400, 5), 0, "that stack is full too")
	world.scrolls["2049000"] = 3
	assert_eq(world.grant_scrolls(2049000, 4), 4, "an existing stack needs no free slot")


func test_scrolls_survive_a_snapshot_round_trip() -> void:
	var world := _world({"2040400": 3, "2043700": 1})
	world.use_scroll(2040400, "top")
	var snapshot := world.character_snapshot()
	assert_eq(snapshot.scrolls, {"2040400": 2, "2043700": 1})
	var again := RunWorld.new(_setup(snapshot))
	assert_eq(again.scrolls, {"2040400": 2, "2043700": 1})
	assert_eq(again.equipment.worn.top.stats, {"incPDD": 4})
	assert_eq(again.equipment.worn.top.scrolls, 1)
	assert_eq(again.equipment.worn.top.slots, 6)
