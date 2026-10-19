extends TestCase
## Auto-equip on pickup (#222): a collected equipment drop whose slot is empty is worn at once through the same
## requirement and slot rules as a manual equip; everything else stays in the Equip tab. Synthetic item info (shaped
## like Character.wz `info`), seeded RNG, fixed 1/60 s ticks, the synthetic quiet stage.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const INFO := {
	1040002: {"incPDD": 3, "tuc": 7}, 1060002: {"incPDD": 2, "tuc": 7}, 1072001: {"incPDD": 2, "tuc": 5},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1002001: {"incSTR": 3, "incMHP": 40, "tuc": 7}, # a hat, no requirement
	1002017: {"reqLevel": 10, "reqJob": 2, "incPDD": 5, "tuc": 7}, # a Magician hat
	1082019: {"reqJob": 2, "reqLevel": 20, "reqINT": 40, "incPAD": 2, "tuc": 5}, # gloves
	1050010: {"reqLevel": 15, "incPDD": 20, "tuc": 10}, # an overall
	1092005: {"reqLevel": 10, "incPDD": 10, "tuc": 7}, # a shield
	1402000: {"incPAD": 40, "attackSpeed": 6, "tuc": 7}, # a two-handed sword
	1372005: {"reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7}, # a wand
}


func _setup(character: Dictionary = {}) -> Dictionary:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	setup.data.balance.player.skills = []
	if not character.is_empty():
		setup.character = character
	return setup


## A world whose character starts as the creation outfit (top, bottom, shoes, sword), changed by `change`.
func _world(change: Callable = Callable()) -> RunWorld:
	var character := RunWorld.new(_setup()).character_snapshot()
	if change.is_valid():
		change.call(character)
	var world := RunWorld.new(_setup(character))
	RF.place_player(world, 400)
	world.god = true
	world.drain_events()
	return world


func _worn(character: Dictionary, id: int) -> void:
	character.equipment.worn[Equipment.slot_of(id)] = Equipment.create(id, INFO[id])


## Drops `id` at the player's feet, lets the magnet collect it and returns the equipment_changed events.
func _pick_up(world: RunWorld, id: int) -> Array:
	world.pickups.spawn_equipment(world.player.pos, Equipment.create(id, INFO[id]))
	var changed := []
	for i in 180:
		RF.auto_choose(world)
		world.step(DT, MoveInput.new())
		for e: Dictionary in world.drain_events():
			if e.type == "equipment_changed":
				changed.append(e)
	return changed


func _ids(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> int: return int(i.id))


func test_a_hat_picked_up_with_an_empty_hat_slot_is_worn_at_once() -> void:
	var world := _world()
	var before := world.player_state.duplicate(true)
	var changed := _pick_up(world, 1002001)
	assert_eq(world.equipment.worn.hat.id, 1002001)
	assert_eq(world.equipment.inventory, [], "it never waits in the Equip tab")
	assert_eq(changed, [
		{"type": "equipment_changed", "action": "pickup", "slot": "", "item_id": 1002001},
		{"type": "equipment_changed", "action": "auto_equip", "slot": "hat", "item_id": 1002001}])
	assert_eq(int(world.player_state.max_hp) - int(before.max_hp), 40, "the stats refreshed like a manual equip")
	assert_eq(world.equips_collected, 1)


func test_an_occupied_slot_keeps_the_pickup_in_the_equip_tab() -> void:
	var world := _world(func(c: Dictionary) -> void: _worn(c, 1002001))
	var changed := _pick_up(world, 1002001)
	assert_eq(_ids(world.equipment.inventory), [1002001])
	assert_eq(changed.map(func(e: Dictionary) -> String: return e.action), ["pickup"])


func test_an_unmet_requirement_keeps_the_pickup_in_the_equip_tab() -> void:
	for spec: Array in [[1002017, {}], [1082019, {"level": 30, "job_id": 200}]]:
		var fields: Dictionary = spec[1]
		var world := _world(func(c: Dictionary) -> void: c.merge(fields, true))
		var changed := _pick_up(world, spec[0])
		assert_eq(_ids(world.equipment.inventory), [spec[0]], str(spec))
		assert_false(world.equipment.worn.has(Equipment.slot_of(spec[0])), str(spec))
		assert_eq(changed.map(func(e: Dictionary) -> String: return e.action), ["pickup"], str(spec))


func test_a_shield_stays_in_the_tab_while_a_two_handed_weapon_is_held() -> void:
	var world := _world(func(c: Dictionary) -> void:
		c.level = 10
		_worn(c, 1402000))
	_pick_up(world, 1092005)
	assert_eq(_ids(world.equipment.inventory), [1092005])
	assert_false(world.equipment.worn.has("shield"))
	var one_handed := _world(func(c: Dictionary) -> void: c.level = 10)
	_pick_up(one_handed, 1092005)
	assert_eq(one_handed.equipment.worn.shield.id, 1092005, "with a one-handed weapon the shield is worn")


func test_a_top_waits_while_an_overall_is_worn_and_an_overall_while_a_top_is_worn() -> void:
	var overall_worn := _world(func(c: Dictionary) -> void:
		c.level = 15
		c.equipment.worn.erase("top")
		c.equipment.worn.erase("bottom")
		_worn(c, 1050010))
	_pick_up(overall_worn, 1040002)
	assert_eq(_ids(overall_worn.equipment.inventory), [1040002], "a top beside an overall")
	_pick_up(overall_worn, 1060002)
	assert_eq(_ids(overall_worn.equipment.inventory), [1040002, 1060002], "a bottom beside an overall")
	assert_eq(overall_worn.equipment.worn.overall.id, 1050010)
	var top_worn := _world(func(c: Dictionary) -> void: c.level = 15)
	_pick_up(top_worn, 1050010)
	assert_eq(_ids(top_worn.equipment.inventory), [1050010], "an overall beside a top and bottom")
	assert_false(top_worn.equipment.worn.has("overall"))
	var bottom_only := _world(func(c: Dictionary) -> void:
		c.equipment.worn.erase("top")
		c.equipment.worn.erase("overall"))
	_pick_up(bottom_only, 1040002)
	assert_eq(bottom_only.equipment.worn.top.id, 1040002, "a top beside only a bottom is fine")


func test_a_weapon_never_replaces_the_held_one_and_only_fills_an_empty_slot() -> void:
	var world := _world()
	_pick_up(world, 1372005)
	assert_eq(_ids(world.equipment.inventory), [1372005], "the creation sword is held, so the wand waits")
	assert_eq(world.equipment.worn.weapon.id, 1302000)
	var bare := _world(func(c: Dictionary) -> void:
		c.level = 10
		c.equipment.worn.erase("weapon"))
	_pick_up(bare, 1372005)
	assert_eq(bare.equipment.worn.weapon.id, 1372005, "a bare-handed character wears the wand (tier C, never reached by drops)")


func test_a_full_equip_tab_still_blocks_the_pickup() -> void:
	var world := _world()
	var cap := world.inventory_slots()
	while world.equipment.inventory.size() < cap:
		world.equipment.inventory.append(Equipment.create(1060002, INFO[1060002]))
	world.pickups.spawn_equipment(world.player.pos, Equipment.create(1002001, INFO[1002001]))
	var blocked := 0
	for i in 180:
		RF.auto_choose(world)
		world.step(DT, MoveInput.new())
		for e: Dictionary in world.drain_events():
			if e.type == "pickup_blocked":
				blocked += 1
	assert_eq(blocked, 1)
	assert_false(world.equipment.worn.has("hat"), "not collected, so not worn")
	assert_eq(world.equips_collected, 0)


func test_the_snapshot_round_trips_the_auto_worn_item() -> void:
	var world := _world()
	_pick_up(world, 1002001)
	var snapshot := world.character_snapshot()
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")
	var restored := RunWorld.new(_setup(snapshot))
	assert_eq(restored.equipment.worn.hat, world.equipment.worn.hat)
	assert_eq(restored.equipment, world.equipment)
	assert_eq(restored.player_state.max_hp, world.player_state.max_hp)


func test_the_hud_announces_what_was_worn() -> void:
	var hud := Hud.new()
	hud.show_equipped("Red Hat")
	hud.show_equipped("")
	var texts := hud.messages().map(func(m: Dictionary) -> String: return m.text)
	assert_eq(texts, ["Equipped Red Hat", "Equipped an item"])
	hud.free()


func test_the_same_seed_gives_the_same_worn_outcome() -> void:
	var runs := []
	for i in 2:
		var world := _world()
		_pick_up(world, 1002001)
		runs.append([world.equipment, world.player_state.max_hp])
	assert_eq(runs[0], runs[1])
