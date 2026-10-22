extends TestCase
## The v83 Equip and Item windows (#108) over a RunWorld on the synthetic quiet stage with canonical-shaped item
## info (no asset cache: the windows keep their layout and draw plain slots): InventoryModel's tooltip data, wearing
## from the Equip tab (double-click and drag onto the Equip window), taking off into the inventory (double-click and
## drag onto the Item window), a full inventory blocking a take-off, a requirement failure showing the message and
## changing nothing, and discarding by dragging out of the Item window with the YesNo confirmation (worn items and
## potions never discard). Mouse events are synthetic and local to the window.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
## Synthetic info nodes shaped like Character.wz `info` (stats invented for the test).
const INFO := {
	1040002: {"incPDD": 3, "tuc": 7}, 1060002: {"incPDD": 2, "tuc": 7}, 1072001: {"incPDD": 2, "tuc": 5},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1472000: {"incPAD": 10, "attackSpeed": 6, "tuc": 7}, # a claw
	1372005: {"reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7},
	1002001: {"reqLevel": 15, "incPDD": 10, "tuc": 7},
	1092005: {"reqLevel": 10, "incPDD": 10, "incMDD": 3, "tuc": 7}, # a shield
	1402000: {"incPAD": 40, "attackSpeed": 6, "tuc": 7}, # a two-handed sword
	1082002: {"reqLevel": 10, "incPDD": 2, "tuc": 5},
	1050035: {"reqJob": 2, "reqLevel": 38, "reqINT": 115, "reqLUK": 40, "incINT": 1, "incLUK": 4, "incPDD": 36,
		"incMDD": 18, "tuc": 10},
}

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


# --- fixtures ------------------------------------------------------------------------------------------------------

func _setup(character: Dictionary = {}) -> Dictionary:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.equipment_info = INFO.duplicate(true)
	if not character.is_empty():
		setup.character = character
	return setup


## A world whose character holds `inventory` ids (fresh instances), after `change` edited the snapshot.
func _world(inventory: Array = [], change: Callable = Callable()) -> RunWorld:
	var character := RunWorld.new(_setup()).character_snapshot()
	for id: int in inventory:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	if change.is_valid():
		change.call(character)
	var world := RunWorld.new(_setup(character))
	RF.place_player(world, 400)
	return world


func _stack() -> WindowStack:
	var s := WindowStack.new()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	return s


## Both windows open in a stack over `world`: [stack, equip window, item window].
func _windows(world: RunWorld) -> Array:
	var s := _stack()
	s.register("equip", func() -> UiWindow: return EquipWindow.new(world))
	s.register("item", func() -> UiWindow: return ItemWindow.new(world))
	s.toggle("equip")
	s.toggle("item")
	return [s, s.find_window("equip") as EquipWindow, s.find_window("item") as ItemWindow]


func _ids(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> int: return int(i.id))


static func press(at: Vector2, pressed: bool = true, double: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.double_click = double
	e.position = at
	return e


static func motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


static func double_click(w: UiWindow, at: Vector2) -> void:
	w._gui_input(press(at))
	w._gui_input(press(at, false))
	w._gui_input(press(at, true, true))
	w._gui_input(press(at, false))


## A left drag from local `a` in `w` to the global point `to` (the pressed window keeps the mouse, as in Godot).
static func drag_to(w: UiWindow, a: Vector2, to: Vector2) -> void:
	var b := to - w.position
	w._gui_input(motion(a))
	w._gui_input(press(a))
	w._gui_input(motion(a.lerp(b, 0.5)))
	w._gui_input(motion(b))
	w._gui_input(press(b, false))


# --- InventoryModel -------------------------------------------------------------------------------------------------

func test_tooltip_data_lists_requirements_with_met_flags_category_stats_and_upgrade_slots() -> void:
	var character := {"level": 20, "job_id": 200, "str": 4, "dex": 4, "int": 60, "luk": 10}
	var tip := InventoryModel.tooltip(Equipment.create(1050035, INFO[1050035]), INFO[1050035], character,
		"Brown Starlight")
	assert_eq(tip.name, "Brown Starlight")
	assert_eq(tip.category, 21, "ToolTip/Equip/ItemCategory 21 = LONGCOAT")
	assert_eq(tip.weapon_category, -1)
	assert_eq(tip.attack_speed, -1, "armour has no attack speed")
	assert_eq(tip.reqs, [{"key": "reqLEV", "value": 38, "met": false}, {"key": "reqSTR", "value": 0, "met": true},
		{"key": "reqDEX", "value": 0, "met": true}, {"key": "reqINT", "value": 115, "met": false},
		{"key": "reqLUK", "value": 40, "met": false}])
	assert_eq(tip.jobs, ["magician"], "reqJob 2 = the Magician line")
	assert_true(tip.job_ok, "a Magician (200) may wear it")
	assert_eq(tip.stats, [["incINT", 1], ["incLUK", 4], ["incPDD", 36], ["incMDD", 18]], "v83 stat order, non-zero only")
	assert_eq(tip.slots, 10)
	assert_eq(tip.scrolls, 0)
	assert_false(tip.can_equip, "level, INT and LUK fail")
	var sword := InventoryModel.tooltip(Equipment.create(1302000, INFO[1302000]), INFO[1302000],
		{"level": 1, "job_id": 0, "str": 4, "dex": 4, "int": 4, "luk": 4}, "Sword")
	assert_eq(sword.weapon_category, 30, "ToolTip/Equip/WeaponCategory 30 = ONE-HANDED SWORD")
	assert_eq(sword.category, -1)
	assert_eq(sword.attack_speed, 2, "attackSpeed 4 = FAST")
	assert_eq(sword.jobs, ["beginner", "warrior", "magician", "bowman", "thief", "pirate"], "reqJob 0: every job")
	assert_true(sword.can_equip)


func test_attack_speed_maps_to_the_seven_v83_speed_words() -> void:
	var want := {2: 0, 3: 1, 4: 2, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6}
	for speed: int in want:
		assert_eq(InventoryModel.speed_index(speed), want[speed], "attackSpeed %d" % speed)


func test_item_names_icons_and_the_use_tab_cells() -> void:
	assert_eq(InventoryModel.icon_path(1040002), "Character.wz/Coat/01040002.img/info/icon")
	assert_eq(InventoryModel.icon_path(1372005), "Character.wz/Weapon/01372005.img/info/icon")
	assert_eq(InventoryModel.icon_path(2000000), "Item.wz/Consume/0200.img/02000000/info/icon")
	assert_eq(InventoryModel.name_path(2000000), "String.wz/Consume.img/2000000/name")
	assert_eq(InventoryModel.name_path(1050018), "String.wz/Eqp.img/Eqp/Longcoat/1050018/name")
	assert_eq(InventoryModel.desc_path(1372005), "String.wz/Eqp.img/Eqp/Weapon/1372005/desc")
	assert_eq(InventoryModel.meso_text(0), "0")
	assert_eq(InventoryModel.meso_text(1234567), "1,234,567")
	var cells := InventoryModel.use_cells({"hp": {"item_id": 2000000, "count": 5}, "mp": {"item_id": 2000003, "count": 0}},
		{"2040002": 3, "2040000": 1})
	assert_eq(cells, [{"kind": "potion", "potion": "hp", "id": 2000000, "count": 5},
		{"kind": "potion", "potion": "mp", "id": 2000003, "count": 0},
		{"kind": "scroll", "id": 2040000, "count": 1}, {"kind": "scroll", "id": 2040002, "count": 3}],
		"the two potion stacks, then the scroll stacks by id")


# --- wearing and taking off -----------------------------------------------------------------------------------------

func test_double_clicking_an_equip_tab_item_wears_it_and_the_equip_window_shows_it() -> void:
	var world := _world([1082002], func(c: Dictionary) -> void: c.level = 10)
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	var actions := []
	iw.item_action.connect(func(a: String) -> void: actions.append(a))
	assert_eq(iw.tab, 0, "opens on the Equip tab")
	assert_eq(iw.cell(0).get("id"), 1082002, "the gloves sit in the first slot")
	assert_eq(ew.worn_id("gloves"), 0, "nothing worn on the hands yet")
	double_click(iw, iw.slot_rect(0).get_center())
	assert_eq(_ids(world.equipment.inventory), [], "worn: gone from the inventory")
	assert_eq(ew.worn_id("gloves"), 1082002, "the Equip window shows them in the GLOVES slot")
	assert_eq(iw.cell(0), {}, "the slot is empty now")
	assert_eq(actions, ["equip"], "the host is told once")
	assert_eq(world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed").size(), 1)


func test_double_clicking_a_worn_item_takes_it_off_into_the_inventory() -> void:
	var world := _world()
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	assert_eq(ew.slot_at(ew.slot_rect("weapon").get_center()), "weapon")
	double_click(ew, ew.slot_rect("weapon").get_center())
	assert_eq(ew.worn_id("weapon"), 0, "bare-handed")
	assert_eq(_ids(world.equipment.inventory), [1302000], "the sword is in the inventory")
	assert_eq(iw.cell(0).get("id"), 1302000, "and the Item window shows it")
	assert_eq(ew.slot_at(ew.slot_rect("top").get_center()), "top", "the CLOTHES slot holds the top (no overall)")


func test_a_full_inventory_blocks_taking_off_and_says_so() -> void:
	var world := _world([], func(c: Dictionary) -> void:
		for i in 24:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var notices := []
	ew.notice.connect(func(t: String) -> void: notices.append(t))
	double_click(ew, ew.slot_rect("weapon").get_center())
	assert_eq(ew.worn_id("weapon"), 1302000, "still worn")
	assert_eq(notices, [InventoryWindow.MESSAGES.inventory_full], "the full-inventory message")


func test_a_failed_requirement_shows_the_message_and_changes_nothing() -> void:
	var world := _world([1050035])
	var made := _windows(world)
	var iw: ItemWindow = made[2]
	var notices := []
	var actions := []
	iw.notice.connect(func(t: String) -> void: notices.append(t))
	iw.item_action.connect(func(a: String) -> void: actions.append(a))
	var before := world.character_snapshot()
	world.drain_events()
	double_click(iw, iw.slot_rect(0).get_center())
	assert_eq(notices, [InventoryWindow.MESSAGES.requirement], "the requirement message")
	assert_eq(actions, [], "no action happened")
	assert_eq(world.character_snapshot(), before, "nothing changed")
	assert_eq(world.drain_events(), [])
	var tip := iw.tooltip_for(iw.cell(0))
	assert_false(tip.can_equip, "the tooltip marks the unmet requirements")
	assert_false(tip.reqs[0].met, "REQ LEV 38 in red")


# --- dragging ----------------------------------------------------------------------------------------------------------

func test_dragging_an_item_onto_the_equip_window_wears_it() -> void:
	var world := _world([1002001], func(c: Dictionary) -> void: c.level = 15)
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	drag_to(iw, iw.slot_rect(0).get_center(), ew.position + ew.slot_rect("hat").get_center())
	assert_eq(ew.worn_id("hat"), 1002001, "dropped on the CAP slot: worn")
	assert_eq(_ids(world.equipment.inventory), [])
	assert_false(iw.is_dragging_item(), "the drag ended")


func test_dragging_a_worn_item_onto_the_item_window_takes_it_off() -> void:
	var world := _world()
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	drag_to(ew, ew.slot_rect("shoes").get_center(), iw.position + iw.slot_rect(5).get_center())
	assert_eq(ew.worn_id("shoes"), 0)
	assert_eq(_ids(world.equipment.inventory), [1072001], "the boots are in the inventory")


func test_dragging_out_of_the_item_window_asks_before_discarding() -> void:
	var world := _world([1082002, 1002001])
	var made := _windows(world)
	var s: WindowStack = made[0]
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	var outside := Vector2(760, 40)
	for w: UiWindow in s.windows():
		assert_false(w.get_global_rect().has_point(outside), "%s does not cover the drop point" % w.window_id)
	drag_to(iw, iw.slot_rect(1).get_center(), outside)
	var confirm := s.top() as DropConfirm
	assert_true(confirm != null, "the v83 YesNo confirmation opened on top")
	if confirm == null:
		return
	assert_eq(confirm.message, DropConfirm.DROP_QUESTION)
	assert_eq(_ids(world.equipment.inventory), [1082002, 1002001], "nothing is gone before Yes")
	s.close_top()
	assert_eq(_ids(world.equipment.inventory), [1082002, 1002001], "Esc keeps the item")
	drag_to(iw, iw.slot_rect(1).get_center(), outside)
	(s.top() as DropConfirm).accept()
	assert_eq(_ids(world.equipment.inventory), [1082002], "Yes destroys the item")
	assert_eq(s.ids(), PackedStringArray(["equip", "item"]), "the confirmation closed")
	# Worn items have to be taken off first: a worn item dragged out stays worn.
	drag_to(ew, ew.slot_rect("weapon").get_center(), outside)
	assert_eq(ew.worn_id("weapon"), 1302000, "still worn")
	assert_false(s.top() is DropConfirm, "no confirmation for worn items")
	# Potions can't be discarded either.
	iw.select_tab(1)
	assert_eq(iw.cell(0).get("kind"), "potion", "the Use tab's first stack is the HP potion")
	var count := int(iw.cell(0).count)
	drag_to(iw, iw.slot_rect(0).get_center(), outside)
	assert_false(s.top() is DropConfirm, "no confirmation for potions")
	assert_eq(int(iw.cell(0).count), count, "the stack is untouched")


func test_a_discard_confirmation_acts_only_on_the_instance_it_asked_about() -> void:
	var world := _world([1082002, 1002001])
	var made := _windows(world)
	var s: WindowStack = made[0]
	var iw: ItemWindow = made[2]
	drag_to(iw, iw.slot_rect(1).get_center(), Vector2(760, 40))
	var confirm := s.top() as DropConfirm
	assert_true(confirm != null, "the confirmation opened")
	if confirm == null:
		return
	# The window is not modal: a differently rolled copy of the same hat takes the slot before Yes.
	var swapped := Equipment.create(1002001, INFO[1002001])
	swapped.stats["incPDD"] = int(swapped.stats.get("incPDD", 0)) + 5
	swapped.scrolls = 1
	world.equipment.inventory[1] = swapped
	confirm.accept()
	assert_eq(world.equipment.inventory.size(), 2, "the replacement was not destroyed")
	assert_eq(world.equipment.inventory[1], swapped)


func test_dragging_a_scroll_stack_out_asks_and_then_destroys_the_whole_stack() -> void:
	var world := _world([], func(c: Dictionary) -> void: c.scrolls = {"2040002": 2, "2040000": 1})
	var made := _windows(world)
	var s: WindowStack = made[0]
	var iw: ItemWindow = made[2]
	iw.select_tab(1)
	assert_eq(iw.cell(3), {"kind": "scroll", "id": 2040002, "count": 2}, "the second scroll stack after the potions")
	world.drain_events()
	drag_to(iw, iw.slot_rect(3).get_center(), Vector2(760, 40))
	var confirm := s.top() as DropConfirm
	assert_true(confirm != null, "scrolls ask the same question")
	if confirm == null:
		return
	confirm.accept()
	assert_eq(world.scrolls, {"2040000": 1}, "Yes destroyed the whole stack")
	assert_eq(world.drain_events(), [{"type": "equipment_changed", "action": "discard", "slot": "", "item_id": 2040002}])
	assert_eq(iw.cells().size(), 3, "the Use tab shows the two potions and the remaining stack")
	assert_eq(world.discard_scrolls(2040002), "no_item", "a stack that is gone")


# --- what the Item window shows ---------------------------------------------------------------------------------------

func test_the_item_window_shows_the_mesos_and_the_use_tab_stacks_read_only() -> void:
	var world := _world([], func(c: Dictionary) -> void:
		c.mesos = 1234567
		c.scrolls = {"2040002": 2})
	var made := _windows(world)
	var iw: ItemWindow = made[2]
	assert_eq(iw.meso_text(), "1,234,567")
	iw._gui_input(press(iw.tab_rect(1).get_center()))
	iw._gui_input(press(iw.tab_rect(1).get_center(), false))
	assert_eq(iw.tab, 1, "a click picks the Use tab")
	var cells := iw.cells()
	assert_eq(cells.size(), 3, "HP potion, MP potion, one scroll stack")
	assert_eq(cells[0].get("potion"), "hp")
	assert_eq(int(cells[0].count), 0)
	assert_eq(cells[2], {"kind": "scroll", "id": 2040002, "count": 2})
	double_click(iw, iw.slot_rect(0).get_center())
	assert_eq(int(iw.cells()[0].count), 0, "potions are read-only here")
	for i in [2, 3, 4]:
		iw.select_tab(i)
		assert_eq(iw.cells(), [], "tab %d is empty" % i)


func test_hovering_a_slot_shows_its_tooltip() -> void:
	var world := _world([1372005])
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	iw._gui_input(InputEventMouseMotion.new())
	assert_eq(iw.tooltip(), {}, "nothing hovered")
	var m := InputEventMouseMotion.new()
	m.position = iw.slot_rect(0).get_center()
	iw._gui_input(m)
	var tip := iw.tooltip()
	assert_eq(tip.get("weapon_category"), 37, "WAND")
	assert_eq(tip.get("attack_speed"), 3, "attackSpeed 6 = NORMAL")
	assert_false(bool(tip.reqs[0].met), "REQ LEV 8 unmet at Lv 1")
	var m2 := InputEventMouseMotion.new()
	m2.position = ew.slot_rect("top").get_center()
	ew._gui_input(m2)
	assert_eq(ew.tooltip().get("stats"), [["incPDD", 3]], "the worn undershirt")
	assert_eq(ew.tooltip().get("slots"), 7)


# --- shield slot (#158) ---------------------------------------------------------------------------------------------

func test_the_equip_window_has_a_shield_cell_where_the_v83_art_puts_it() -> void:
	var world := _world()
	var ew: EquipWindow = _windows(world)[1]
	assert_eq(ew.slot_rect("shield").position, Vector2(137, 134), "SHIELD, right of WEAPON on the same row")
	assert_eq(ew.slot_at(ew.slot_rect("shield").get_center()), "shield")
	assert_eq(ew.slot_at(ew.slot_rect("weapon").get_center()), "weapon")
	assert_eq(ew.worn_id("shield"), 0)


func test_double_clicking_a_shield_wears_it_beside_the_sword_and_shows_in_the_shield_cell() -> void:
	var world := _world([1092005], func(c: Dictionary) -> void: c.level = 10)
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	var pdd_before: float = world.player_state.pdd
	double_click(iw, iw.slot_rect(0).get_center())
	assert_eq(ew.worn_id("shield"), 1092005)
	assert_eq(ew.worn_id("weapon"), 1302000, "the one-handed sword stays")
	assert_eq(world.player_state.pdd, pdd_before + 10.0, "the shield's incPDD counts")
	assert_eq(world.equipment_bonus("incMDD"), 3.0)
	assert_eq(ew.tooltip_for({"kind": "worn", "slot": "shield", "id": 1092005}).category, 10, "ItemCategory SHIELD")
	double_click(ew, ew.slot_rect("shield").get_center())
	assert_eq(ew.worn_id("shield"), 0, "a double-click takes it off")
	assert_eq(_ids(world.equipment.inventory), [1092005])


func test_a_two_handed_weapon_takes_the_shield_off_and_a_full_inventory_refuses_with_the_v83_message() -> void:
	var world := _world([1402000], func(c: Dictionary) -> void:
		c.equipment.worn["shield"] = Equipment.create(1092005, INFO[1092005]))
	var made := _windows(world)
	var ew: EquipWindow = made[1]
	var iw: ItemWindow = made[2]
	double_click(iw, iw.slot_rect(0).get_center())
	assert_eq(ew.worn_id("weapon"), 1402000)
	assert_eq(ew.worn_id("shield"), 0, "the shield moved to the inventory")
	assert_eq(_ids(world.equipment.inventory), [1302000, 1092005])
	var full := _world([1402000], func(c: Dictionary) -> void:
		c.equipment.worn["shield"] = Equipment.create(1092005, INFO[1092005])
		for i in 23:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	var made2 := _windows(full)
	var iw2: ItemWindow = made2[2]
	var notices := []
	iw2.notice.connect(func(t: String) -> void: notices.append(t))
	var before := full.character_snapshot()
	double_click(iw2, iw2.slot_rect(0).get_center())
	assert_eq(notices, [InventoryWindow.MESSAGES.equip_full], "refused with the v83 message")
	assert_eq(InventoryWindow.MESSAGES.equip_full, "You can't get anymore items.")
	assert_eq(full.character_snapshot(), before, "nothing changed")


# --- ranged weapon ammo (#155) --------------------------------------------------------------------------------------

func test_a_ranged_weapons_tooltip_lists_the_current_ammo() -> void:
	var world := _world([1472000, 1302000], func(character: Dictionary) -> void:
		character.job_id = 410
		character.level = 52)
	var made := _windows(world)
	var iw: ItemWindow = made[2]
	var claw := iw.tooltip_for(iw.cell(0))
	assert_eq(claw.ammo.item_id, 2070005, "Lv 52 Assassin: Steely Throwing-Knives")
	assert_eq(claw.ammo.incPAD, 25)
	assert_true(String(claw.ammo.name) != "", "named from String.wz, or by id without the cache")
	var lines := ItemTooltip.fact_lines(claw)
	var ammo_line := lines.filter(func(l: Array) -> bool: return l[0] == "ammo")
	assert_eq(ammo_line.size(), 1)
	assert_true(String(ammo_line[0][1]).ends_with("(+25)"), String(ammo_line[0][1]))
	assert_false(iw.tooltip_for(iw.cell(1)).has("ammo"), "a sword lists no ammo")
