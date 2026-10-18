extends TestCase
## Worn equipment in the live character through RunWorld's public interface (equip_item, unequip_item, discard_item,
## change_job, character_snapshot, player_state), seeded on the synthetic quiet stage with canonical-shaped info.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Synthetic info nodes shaped like Character.wz `info` (stats invented for the test).
const INFO := {
	1040002: {"incPDD": 3, "tuc": 7}, 1060002: {"incPDD": 2, "tuc": 7}, 1072001: {"incPDD": 2, "tuc": 5},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1372005: {"reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7},
	1002001: {"incSTR": 3, "incDEX": 2, "incINT": 4, "incLUK": 5, "incACC": 7, "incEVA": 6, "incMHP": 40,
		"incMMP": 25, "incMDD": 9, "incSpeed": 20, "incJump": 15, "tuc": 7},
	1082019: {"reqJob": 2, "reqLevel": 20, "reqINT": 40, "incPAD": 2, "incMAD": 5, "tuc": 5},
	1072999: {"incSpeed": 35, "incJump": 20, "tuc": 5},
	1050010: {"reqLevel": 15, "incPDD": 20, "tuc": 10},
}


func _setup(character: Dictionary = {}) -> Dictionary:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	if not character.is_empty():
		setup.character = character
	return setup


## A fresh world's character with `inventory` ids added to its inventory (as later drops will).
func _world(inventory: Array = [], change: Callable = Callable()) -> RunWorld:
	var character := RunWorld.new(_setup()).character_snapshot()
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	if change.is_valid():
		change.call(character)
	var world := RunWorld.new(_setup(character))
	RF.place_player(world, 400)
	return world


func _ids(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> int: return int(i.id))


func test_a_new_character_wears_the_first_creation_outfit_with_plain_wz_stats() -> void:
	var world := RunWorld.new(_setup())
	assert_eq(Equipment.worn_ids(world.equipment.worn), [1040002, 1060002, 1072001, 1302000])
	assert_eq(world.equipment.worn.top, {"id": 1040002, "stats": {"incPDD": 3}, "slots": 7, "scrolls": 0})
	assert_eq(world.equipment.inventory, [])
	assert_eq(world.weapon_id(), 1302000)
	assert_eq(world.weapon_attack(), 17.0)
	assert_eq(world.player_state.pdd, 7.0, "W.DEF 3 + 2 + 2")
	var snapshot := world.character_snapshot()
	assert_eq(int(snapshot.format), 2)
	assert_eq(snapshot.equipment, world.equipment)
	assert_eq(snapshot.scrolls, {})
	assert_eq(snapshot.mesos, 0)
	assert_false(snapshot.has("beginner_weapon"), "the weapon is worn equipment now")
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")


func test_equipping_and_unequipping_changes_every_derived_stat() -> void:
	var world := _world([1002001])
	var before := world.player_state.duplicate(true)
	var speed := world.player_speed_stat()
	assert_eq(world.equip_item(0), "")
	var ps := world.player_state
	for stat: String in ["str", "dex", "int", "luk"]:
		assert_eq(int(ps[stat]) - int(before[stat]), int(INFO[1002001]["inc" + stat.to_upper()]), stat)
	assert_eq(world.equipment_bonus("incLUK"), 5.0)
	assert_eq(int(ps.acc) - int(before.acc), 7)
	assert_near(float(ps.avoid) - float(before.avoid), 6.0 + 2 * RunWorld.AVOID_DEX_FACTOR + 5 * RunWorld.AVOID_LUK_FACTOR,
		1e-6, "avoid gains incEVA and the DEX/LUK it adds")
	assert_eq(int(ps.max_hp) - int(before.max_hp), 40)
	assert_eq(int(ps.max_mp) - int(before.max_mp), 25)
	assert_eq(float(ps.mdd) - float(before.mdd), 9.0)
	assert_near(world.player_speed_stat() - speed, 20.0, 1e-6)
	assert_eq(world.player.jump_stat, 115)
	assert_eq(world.unequip_item("hat"), "")
	assert_eq(world.player_state.str, before.str)
	assert_eq(world.player_state.max_hp, before.max_hp)
	assert_eq(world.player.jump_stat, 100)
	assert_eq(_ids(world.equipment.inventory), [1002001])


func test_weapon_attack_and_magic_attack_come_from_every_worn_item() -> void:
	var world := _world([1372005, 1082019], func(c: Dictionary) -> void:
		c.level = 20
		c.job_id = 200
		c.base_attributes.int = 40)
	var matk := world.loadout.matk
	assert_eq(world.equip_item(0), "", "Wooden Wand")
	assert_eq(world.weapon_attack(), 15.0)
	assert_near(world.loadout.matk - matk, 23.0, 1e-6)
	assert_eq(_ids(world.equipment.inventory), [1302000, 1082019], "the sword takes the wand's inventory place")
	assert_eq(world.equip_item(1), "", "gloves")
	assert_eq(world.weapon_attack(), 17.0, "W.ATT from gloves counts too")
	assert_near(world.loadout.matk - matk, 28.0, 1e-6)


func test_speed_and_jump_are_capped_at_the_v83_limits() -> void:
	var world := _world([1002001, 1072999])
	assert_eq(world.equip_item(0), "")
	assert_eq(world.equip_item(0), "", "shoes +35 over the hat's +20")
	assert_near(world.player_speed_stat(), 140.0, 1e-6, "100 + 20 + 35 caps at 140")
	assert_eq(world.player.speed_stat, 140)
	assert_eq(world.player.jump_stat, 123, "100 + 15 + 20 caps at 123")


func test_the_overall_rule_holds_for_the_live_character() -> void:
	var world := _world([1050010], func(c: Dictionary) -> void: c.level = 15)
	assert_eq(world.equip_item(0), "")
	assert_false(world.equipment.worn.has("top") or world.equipment.worn.has("bottom"))
	assert_eq(_ids(world.equipment.inventory), [1040002, 1060002])
	assert_eq(world.player_state.pdd, 22.0, "overall 20 + shoes 2")
	assert_eq(world.equip_item(0), "", "the top takes the overall off")
	assert_eq(_ids(world.equipment.inventory), [1050010, 1060002])
	assert_eq(world.player_state.pdd, 5.0)


func test_each_requirement_blocks_the_live_character_and_changes_nothing() -> void:
	for spec: Array in [[1372005, {}, "reqLevel"], [1050010, {}, "reqLevel"],
			[1082019, {"level": 30}, "reqJob"], [1082019, {"level": 30, "job_id": 200}, "reqINT"]]:
		var fields: Dictionary = spec[1]
		var world := _world([spec[0]], func(c: Dictionary) -> void: c.merge(fields, true))
		var snapshot := world.character_snapshot()
		var state := world.player_state.duplicate(true)
		world.drain_events()
		assert_eq(world.equip_item(0), spec[2], str(spec))
		assert_eq(world.character_snapshot(), snapshot)
		assert_eq(world.player_state, state)
		assert_eq(world.drain_events(), [])
	var lucky := _world([1082019, 1002001], func(c: Dictionary) -> void:
		c.level = 30
		c.job_id = 200
		c.base_attributes.int = 36)
	assert_eq(lucky.equip_item(0), "reqINT", "INT 36 < 40")
	assert_eq(lucky.equip_item(1), "", "the hat adds INT 4")
	assert_eq(lucky.equip_item(0), "", "total INT including equipment meets reqINT 40")


func test_equipment_changes_emit_one_event_and_discard_removes_inventory_items() -> void:
	var world := _world([1002001, 1050010])
	world.drain_events()
	assert_eq(world.equip_item(0), "")
	assert_eq(world.drain_events(), [{"type": "equipment_changed", "action": "equip", "slot": "hat", "item_id": 1002001}])
	assert_eq(world.discard_item(0), "")
	assert_eq(world.drain_events(), [{"type": "equipment_changed", "action": "discard", "slot": "", "item_id": 1050010}])
	assert_eq(world.equipment.inventory, [])
	assert_eq(world.discard_item(0), "no_item")
	assert_eq(world.unequip_item("gloves"), "empty")


func test_a_full_inventory_blocks_unequipping() -> void:
	var world := _world([], func(c: Dictionary) -> void:
		for i in 24:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	assert_eq(int(world.balance.player.inventory_slots), 24)
	assert_eq(world.unequip_item("weapon"), "inventory_full")
	assert_eq(world.weapon_id(), 1302000)


func test_magician_advancement_grants_and_wears_the_wooden_wand() -> void:
	var world := _world()
	world.drain_events()
	world.change_job(200)
	assert_eq(world.weapon_id(), 1372005)
	assert_eq(world.equipment.worn.weapon, Equipment.create(1372005, INFO[1372005]))
	assert_eq(_ids(world.equipment.inventory), [1302000], "the creation weapon moves to the inventory")
	assert_eq(world.weapon_attack(), 15.0)
	var changed := world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed")
	assert_eq(changed, [{"type": "equipment_changed", "action": "grant", "slot": "weapon", "item_id": 1372005}])
	world.change_job(210)
	assert_eq(_ids(world.equipment.inventory), [1302000], "second job grants nothing")


func test_a_full_inventory_wears_the_wand_and_drops_the_old_weapon_at_the_feet() -> void:
	var world := _world([], func(c: Dictionary) -> void:
		for i in 24:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	world.drain_events()
	world.change_job(200)
	assert_eq(world.progression.job_id, 200, "the advancement itself still happens")
	assert_eq(world.weapon_id(), 1372005, "the grant is worn (spec #151 #157: advancing never fails)")
	assert_eq(world.equipment.inventory.size(), 24, "the inventory is unchanged")
	var events := world.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed"),
		[{"type": "equipment_changed", "action": "grant", "slot": "weapon", "item_id": 1372005}])
	var spawned := events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
	assert_eq(spawned.map(func(e: Dictionary) -> int: return int(e.item_id)), [1302000],
		"the creation sword lies on the ground as a normal pickup")


func test_format_two_round_trips_through_json_text_into_an_identical_world() -> void:
	var source := _world([1002001, 1050010], func(c: Dictionary) -> void:
		c.mesos = 1234
		c.scrolls = {"2040002": 3})
	source.equip_item(0)
	var character := source.character_snapshot()
	assert_eq(character.mesos, 1234)
	assert_eq(character.scrolls, {"2040002": 3})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(character))
	assert_eq(CharacterSnapshot.validation_error(parsed), "")
	var a := RunWorld.new(_setup(character))
	var b := RunWorld.new(_setup(parsed))
	assert_eq(b.character_snapshot(), character, "JSON numbers come back as the same integers")
	assert_eq(a.player_state, b.player_state)
	parsed.equipment.worn.hat.stats.incSTR = 99
	assert_eq(b.equipment.worn.hat.stats.incSTR, 3, "the world is detached from its input")
