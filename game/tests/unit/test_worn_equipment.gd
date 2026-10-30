extends TestCase
## Worn equipment in the live character through RunWorld's public interface (equip_item, unequip_item, discard_item,
## character_snapshot, player_state), seeded on the synthetic quiet stage with canonical-shaped info.

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
	1092005: {"reqLevel": 10, "incPDD": 10, "incMDD": 3, "tuc": 7}, # a shield
	1402000: {"incPAD": 40, "attackSpeed": 6, "tuc": 7}, # a two-handed sword
	1402001: {"reqJob": 1, "incPAD": 41, "attackSpeed": 6, "tuc": 7}, # a Warrior's two-handed sword
}


func _setup(character: Dictionary = {}) -> Dictionary:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	# This equipment fixture deliberately starts with a sword; bare tools use each job's creation weapon.
	setup.character = character if not character.is_empty() else {"format": 3, "job_id": 212, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids(Equipment.DEFAULT_OUTFIT, setup.equipment_info), "inventory": []},
		"scrolls": {}, "mesos": 0, "cleared_regions": []}
	return setup


## A fresh world's character with `inventory` ids added to its inventory (as later drops will).
func _world(inventory: Array = [], change: Callable = Callable()) -> RunWorld:
	var character := RF.character_with_round_state(RunWorld.new(_setup()))
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	if change.is_valid():
		change.call(character)
	var world := RF.world_from(_setup(), character)
	RF.place_player(world, 400)
	return world


func _ids(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> int: return int(i.id))


func test_an_explicit_character_wears_its_outfit_with_plain_wz_stats() -> void:
	var world := RunWorld.new(_setup())
	assert_eq(Equipment.worn_ids(world.equipment.worn), [1040002, 1060002, 1072001, 1302000])
	assert_eq(world.equipment.worn.top, {"id": 1040002, "stats": {"incPDD": 3}, "slots": 7, "scrolls": 0})
	assert_eq(world.equipment.inventory, [])
	assert_eq(world.weapon_id(), 1302000)
	assert_eq(world.weapon_attack(), 17.0)
	assert_eq(world.player_state.pdd, 7.0, "W.DEF 3 + 2 + 2")
	var snapshot := world.character_snapshot()
	assert_eq(int(snapshot.format), 3)
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
	assert_near(float(ps.acc) - float(before.acc), 11.1, 1e-6, "incACC7 plus DEX2 x0.8 and LUK5 x0.5")
	assert_near(float(ps.avoid) - float(before.avoid), 6.0 + 2 * RunWorld.AVOID_DEX_FACTOR + 5 * RunWorld.AVOID_LUK_FACTOR,
		1e-6, "avoid gains incEVA and the DEX/LUK it adds")
	assert_eq(int(ps.max_hp) - int(before.max_hp), 40)
	assert_false(ps.has("max_mp"), "the cap's incMMP does nothing: there is no MP (#285)")
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


func test_max_hp_equipment_swaps_only_clamp_current_hp() -> void:
	var world := _world([1002001])
	assert_eq(world.equip_item(0), "")
	world._hp = 10.0
	world._write_player_state(0.0)
	for swap in 5:
		assert_eq(world.unequip_item("hat"), "")
		assert_eq(int(world.player_state.hp), 10, "taking off gear preserves HP below the smaller pool")
		assert_eq(world.equip_item(world.equipment.inventory.size() - 1), "")
		assert_eq(int(world.player_state.hp), 10, "putting it back grants no HP")
	assert_eq(world.time, 0.0, "equipment windows hold simulation time")
	var full := int(world.player_state.max_hp)
	world.restore_player("hp", full, "test")
	assert_eq(world.unequip_item("hat"), "")
	assert_eq(int(world.player_state.hp), full - 40, "taking off the +40 HP cap clamps HP to the smaller pool")
	assert_eq(world.equip_item(world.equipment.inventory.size() - 1), "")
	assert_eq(int(world.player_state.hp), full - 40, "the clamped HP is not refunded")


func test_max_hp_equipment_restores_a_full_pool_at_a_round_boundary() -> void:
	var source := _world([1002001])
	assert_eq(source.equip_item(0), "")
	source._hp = 10.0
	var character: Dictionary = JSON.parse_string(JSON.stringify(source.character_snapshot()))
	assert_false(character.has("hp"), "spec #32 snapshots carry growth, not current pools")
	var restored := RunWorld.new(_setup(character))
	assert_eq(restored.character_snapshot(), source.character_snapshot())
	assert_eq(int(restored.player_state.max_hp), int(source.player_state.max_hp), "the worn gear still counts on restore")
	assert_eq(int(restored.player_state.hp), int(restored.player_state.max_hp), "Continue refills the computed pool")
	restored._hp = 10.0
	restored.refresh_player_stats(false)
	assert_eq(int(restored.player_state.hp), 10, "refreshing restored equipment grants no HP")


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


func test_only_the_job_class_blocks_the_live_character_and_changes_nothing() -> void:
	for spec: Array in [[1082019, {"job_id": 0}, "reqJob"], [1402001, {}, "reqJob"]]:
		var fields: Dictionary = spec[1]
		var world := _world([spec[0]], func(c: Dictionary) -> void: c.merge(fields, true))
		var snapshot := world.character_snapshot()
		var state := world.player_state.duplicate(true)
		world.drain_events()
		assert_eq(world.equip_item(0), spec[2], str(spec))
		assert_eq(world.character_snapshot(), snapshot)
		assert_eq(world.player_state, state)
		assert_eq(world.drain_events(), [])


func test_level_and_stat_requirements_never_block_a_level_one_character() -> void:
	var world := _world([1372005, 1082019, 1050010])
	assert_eq(world.progression.level, 1)
	assert_eq(world.equip_item(0), "", "the Lv8 wand")
	assert_eq(world.equip_item(0), "", "reqLevel 20 / reqINT 40 gloves for the Magician (the wand took inventory slot 0)")
	assert_eq(world.equip_item(0), "", "the Lv15 overall")


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


func test_format_three_round_trips_through_json_text_into_an_identical_world() -> void:
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


func test_a_snapshot_with_a_shield_round_trips_and_a_pre_shield_snapshot_loads_unchanged() -> void:
	# A snapshot saved before the shield slot existed: its worn map has no "shield" key at all.
	var old := RunWorld.new(_setup()).character_snapshot()
	assert_false(old.equipment.worn.has("shield"))
	assert_eq(int(old.format), 3)
	var old_parsed: Dictionary = JSON.parse_string(JSON.stringify(old))
	assert_eq(CharacterSnapshot.validation_error(old_parsed), "")
	var loaded := RunWorld.new(_setup(old_parsed))
	assert_eq(loaded.character_snapshot(), old, "loads and saves back unchanged")
	assert_eq(Equipment.worn_ids(loaded.equipment.worn), [1040002, 1060002, 1072001, 1302000])
	# One with a shield worn.
	var source := _world([1092005], func(c: Dictionary) -> void: c.level = 10)
	assert_eq(source.equip_item(0), "")
	var character := source.character_snapshot()
	assert_eq(character.equipment.worn.shield.id, 1092005)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(character))
	assert_eq(CharacterSnapshot.validation_error(parsed), "")
	var restored := RunWorld.new(_setup(parsed))
	assert_eq(restored.character_snapshot(), character, "the shield survives save and load")
	assert_eq(restored.player_state.pdd, source.player_state.pdd, "and still counts")
	assert_eq(AvatarRenderer.part_img_path(1092005), "Character.wz/Shield/01092005.img")
	assert_true(1092005 in DataRepo.character_look(restored.character_snapshot(), {}).equips, "and is drawn")
	# A two-handed weapon beside a shield is not a valid snapshot.
	parsed.equipment.worn.weapon = Equipment.create(1402000, INFO[1402000])
	assert_ne(CharacterSnapshot.validation_error(parsed), "")


func test_a_shield_counts_in_the_live_stats_and_a_two_handed_weapon_moves_it() -> void:
	var world := _world([1092005, 1402000], func(c: Dictionary) -> void: c.level = 20)
	var base_pdd: float = world.player_state.pdd
	assert_eq(world.equip_item(0), "")
	assert_eq(world.player_state.pdd, base_pdd + 10.0, "W.DEF counts the shield")
	assert_eq(world.weapon_id(), 1302000)
	assert_eq(world.equip_item(0), "", "the two-handed sword")
	assert_eq(world.weapon_id(), 1402000)
	assert_false(world.equipment.worn.has("shield"))
	assert_eq(_ids(world.equipment.inventory), [1302000, 1092005])
	assert_eq(world.player_state.pdd, base_pdd, "the shield's defence went with it")
	assert_eq(world.held_weapon_family(), "sword")
