extends TestCase
## Scrolling through the Equip and Item windows (#110): a scroll dragged from the Use tab onto a worn item in the Equip
## window is read (RunWorld.use_scroll); a wrong item, an item without slots, an empty cell or empty space keeps the
## scroll and says why; inventory items cannot be scrolled; the tooltip shows the new upgrade slots and scroll count.
## Synthetic item info and the real v83 scroll `info` of 2040400 / 2043700; mouse events are synthetic.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const IW := preload("res://tests/unit/test_inventory_windows.gd")
const INFO := {
	1040002: {"incPDD": 3, "tuc": 7}, 1060002: {"incPDD": 2, "tuc": 7}, 1072001: {"incPDD": 2, "tuc": 5},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1372005: {"reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7},
}
const SCROLL_INFO := {
	2040400: {"incPDD": 1, "success": 100}, # top DEF 100%
	2043700: {"incMAD": 1, "success": 100}, # wand magic att. 100%
}

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _world(scrolls: Dictionary, inventory: Array = []) -> RunWorld:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	setup.scroll_info = SCROLL_INFO.duplicate(true)
	var character := RunWorld.new(setup).character_snapshot()
	character.scrolls = scrolls
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	setup.character = character
	var world := RunWorld.new(setup)
	RF.place_player(world, 400)
	return world


## [stack, equip window, item window (on the Use tab)] over `world`.
func _windows(world: RunWorld) -> Array:
	var s := WindowStack.new()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	s.register("equip", func() -> UiWindow: return EquipWindow.new(world))
	s.register("item", func() -> UiWindow: return ItemWindow.new(world))
	s.toggle("equip")
	s.toggle("item")
	var iw := s.find_window("item") as ItemWindow
	iw.select_tab(1)
	return [s, s.find_window("equip") as EquipWindow, iw]


## Drags the scroll stack of `id` from the Use tab to the centre of the Equip window's `slot` cell.
func _drag_scroll(made: Array, id: int, slot: String) -> void:
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	var index := -1
	for i in iw.cells().size():
		if int(iw.cell(i).id) == id:
			index = i
	assert_true(index >= 0, "the Use tab holds scroll %d" % id)
	IW.drag_to(iw, iw.slot_rect(index).get_center(), ew.position + ew.slot_rect(slot).get_center())


func test_dragging_a_scroll_onto_a_worn_item_reads_it() -> void:
	var world := _world({"2040400": 2})
	var made := _windows(world)
	var iw: ItemWindow = made[2]
	var actions := []
	var notices := []
	iw.item_action.connect(func(a: String) -> void: actions.append(a))
	(made[1] as EquipWindow).item_action.connect(func(a: String) -> void: actions.append(a))
	(made[1] as EquipWindow).notice.connect(func(t: String) -> void: notices.append(t))
	world.drain_events()
	_drag_scroll(made, 2040400, "top")
	assert_eq(world.equipment.worn.top, {"id": 1040002, "stats": {"incPDD": 4}, "slots": 6, "scrolls": 1})
	assert_eq(world.scrolls, {"2040400": 1}, "one scroll used up")
	assert_eq(actions, ["scroll"], "the host is told once")
	assert_eq(notices, [])
	assert_eq(world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "scroll_used").size(), 1)
	assert_true(made[0].top() == null or not made[0].top() is DropConfirm, "no discard question")


func test_the_tooltip_shows_the_new_upgrade_slots_and_scroll_count_and_stats() -> void:
	var world := _world({"2043700": 1})
	Equipment.grant(world.equipment, Equipment.create(1372005, INFO[1372005]), 24)
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var payload := ew.payload_at(ew.slot_rect("weapon").get_center())
	var before := ew.tooltip_for(payload)
	assert_eq([before.slots, before.scrolls], [7, 0])
	_drag_scroll(made, 2043700, "weapon")
	var after := ew.tooltip_for(ew.payload_at(ew.slot_rect("weapon").get_center()))
	assert_eq([after.slots, after.scrolls], [6, 1])
	assert_eq(world.weapon_id(), 1372005)
	assert_eq(after.stats, [["incPAD", 15], ["incMAD", 24]], "the scroll's M.ATT +1 shows at once")


func test_a_scroll_for_another_item_type_is_refused_with_a_message_and_kept() -> void:
	var world := _world({"2043700": 1})
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var notices := []
	ew.notice.connect(func(t: String) -> void: notices.append(t))
	var before := world.equipment.duplicate(true)
	_drag_scroll(made, 2043700, "top")
	assert_eq(notices, [InventoryWindow.MESSAGES.scroll_type])
	assert_eq(world.scrolls, {"2043700": 1})
	assert_eq(world.equipment, before)


func test_an_item_without_upgrade_slots_is_refused_with_a_message() -> void:
	var world := _world({"2040400": 1})
	world.equipment.worn.top.slots = 0
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var notices := []
	ew.notice.connect(func(t: String) -> void: notices.append(t))
	_drag_scroll(made, 2040400, "top")
	assert_eq(notices, [InventoryWindow.MESSAGES.scroll_slots])
	assert_eq(world.scrolls, {"2040400": 1})
	assert_eq(world.equipment.worn.top.stats, {"incPDD": 3})


func test_dropping_a_scroll_on_an_empty_cell_or_empty_space_changes_nothing() -> void:
	var world := _world({"2040400": 1})
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	var before := world.equipment.duplicate(true)
	_drag_scroll(made, 2040400, "hat")
	assert_eq(world.scrolls, {"2040400": 1}, "nothing worn on the head")
	var index := 2
	IW.drag_to(iw, iw.slot_rect(index).get_center(), ew.position + Vector2(160, 290))
	assert_eq(world.scrolls, {"2040400": 1}, "the empty part of the Equip window")
	assert_eq(world.equipment, before)
	assert_false(made[0].top() is DropConfirm, "a drop on a window never asks to discard")


func test_a_scroll_cannot_be_used_on_an_inventory_item() -> void:
	var world := _world({"2040400": 1}, [1040002])
	var made := _windows(world)
	var iw: ItemWindow = made[2]
	iw.select_tab(1)
	var before := world.equipment.duplicate(true)
	# Dropping the scroll on the Item window itself (its Equip tab shows the spare top) is not a scroll target.
	assert_false(iw.receive_drop_at({"kind": "scroll", "id": 2040400, "count": 1}, iw.slot_rect(0).get_center()))
	assert_eq(world.use_scroll(2040400, "inventory"), "not_worn")
	assert_eq(world.scrolls, {"2040400": 1})
	assert_eq(world.equipment, before)
	assert_eq(world.equipment.inventory[0].slots, 7)


func test_an_overall_takes_the_overall_scroll_through_the_clothes_cell() -> void:
	var world := _world({"2040512": 1})
	world.setup.scroll_info[2040512] = {"incINT": 1, "success": 100}
	Equipment.grant(world.equipment, Equipment.create(1050010, {"incPDD": 20, "tuc": 10}), 24)
	var made := _windows(world)
	_drag_scroll(made, 2040512, "overall")
	assert_eq(world.equipment.worn.overall.stats, {"incPDD": 20, "incINT": 1})
