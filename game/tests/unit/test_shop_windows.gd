extends TestCase
## The shop window (#111) over a RunWorld on the synthetic quiet stage (no asset cache: the window keeps its layout and
## draws plain panels): stock rows and selection, the Buy quantity box and the purchase, refusals as notices that change
## nothing, selling scroll stacks and spare equipment (YesNo first, never worn items), scrolling and the sell tabs;
## then the Free Market hub (needs the cache): Space next to a scroll NPC and a double-click open its shop, NPC Chat
## can be rebound. Mouse and key events are synthetic.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const IW := preload("res://tests/unit/test_inventory_windows.gd")
const INFO := {
	1002001: {"incPDD": 4, "tuc": 7, "price": 1500},
	1040002: {"incPDD": 3, "tuc": 7, "price": 50},
	1060002: {"incPDD": 2, "tuc": 7, "price": 40},
	1072001: {"incPDD": 2, "tuc": 5, "price": 30},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7, "price": 100},
	1372005: {"reqJob": 2, "reqLevel": 8, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7, "price": 1000},
	1382000: {"reqJob": 2, "reqLevel": 10, "incMAD": 25, "attackSpeed": 6, "tuc": 7, "price": 1200},
}
const SCROLL_INFO := {
	2040000: {"incPDD": 2, "success": 100, "price": 1},
	2043700: {"incMAD": 1, "success": 100, "price": 1},
}
const SPACE_KEY := KEY_SPACE

var _nodes: Array[Node] = []
var _saved_events: Array = []


func before_each() -> void:
	_saved_events = InputMap.action_get_events("npc_chat").duplicate() if InputMap.has_action("npc_chat") else []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if InputMap.has_action("npc_chat"):
		InputMap.action_erase_events("npc_chat")
		for e: InputEvent in _saved_events:
			InputMap.action_add_event("npc_chat", e)


func _world(job_id := 200, mesos := 200000, inventory: Array = [], scrolls: Dictionary = {}) -> RunWorld:
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
	RF.change_job_bare(world, job_id)
	# The job weapon grant moved the beginner sword into the inventory: only the test's own spare items stay.
	world.equipment.inventory = world.equipment.inventory.filter(func(i: Dictionary) -> bool: return int(i.id) != 1302000)
	RF.place_player(world, 400)
	return world


## [stack, shop window] for NPC `npc_id` over `world`.
func _shop(world: RunWorld, npc_id := 1032103) -> Array:
	var s := WindowStack.new()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	var shop := ShopWindow.new(world, npc_id)
	s.open(shop)
	return [s, shop]


func _click_row(shop: ShopWindow, panel: int, row: int, double := false) -> void:
	var at := shop.row_rect(panel, row).get_center()
	shop._gui_input(IW.press(at))
	shop._gui_input(IW.press(at, false))
	if double:
		shop._gui_input(IW.press(at, true, true))
		shop._gui_input(IW.press(at, false))


func _index_of(shop: ShopWindow, id: int) -> int:
	return shop.stock.map(func(e: Dictionary) -> int: return int(e.id)).find(id)


## Brings stock row `index` into view and clicks it.
func _select_stock(shop: ShopWindow, index: int) -> void:
	shop.buy_offset = clampi(index, 0, ShopWindow.max_offset(shop.stock.size()))
	_click_row(shop, 0, index - shop.buy_offset)


# --- layout and lists ----------------------------------------------------------------------------------------------

func test_the_window_is_the_v83_shop_with_the_npcs_stock_and_the_characters_inventory() -> void:
	var world := _world(200, 5000, [1002001, 1040002])
	var made := _shop(world)
	var shop: ShopWindow = made[1]
	assert_eq(shop.size, Vector2(463, 339), "the v83 Shop backgrnd size")
	assert_eq(shop.window_id, "shop")
	assert_eq(shop.stock, world.shop_stock(1032103), "the NPC's stock for this job")
	assert_eq(shop.meso_text(), "5,000")
	assert_eq(shop.sell_cells().map(func(c: Dictionary) -> int: return int(c.id)), [1002001, 1040002],
		"the Equip tab lists the spare equipment")
	assert_true(shop.row_rect(0, 0).position.x < shop.row_rect(1, 0).position.x, "stock left, inventory right")
	assert_eq(shop.row_rect(0, 1).position.y - shop.row_rect(0, 0).position.y, ShopWindow.ROW_STEP)
	assert_eq(shop.payload_at(shop.row_rect(0, 0).get_center()).id, int(shop.stock[0].id))
	assert_eq(shop.payload_at(shop.row_rect(1, 1).get_center()).id, 1040002)
	assert_eq(shop.payload_at(shop.row_rect(1, 4).get_center()), {}, "an empty row")


func test_worn_equipment_is_not_in_the_sell_list() -> void:
	var world := _world(200, 0, [1002001])
	assert_eq(world.equip_item(0), "")
	var shop: ShopWindow = _shop(world)[1]
	assert_false(shop.sell_cells().any(func(c: Dictionary) -> bool: return int(c.id) == 1002001), "the worn hat is not offered")


func test_the_use_tab_lists_the_scroll_stacks_only_and_the_other_tabs_nothing() -> void:
	var world := _world(200, 0, [], {"2043700": 3, "2040000": 2})
	var shop: ShopWindow = _shop(world)[1]
	shop.select_tab(1)
	var cells := shop.sell_cells()
	assert_eq(cells.map(func(c: Dictionary) -> int: return int(c.id)), [2040000, 2043700], "no potions, scrolls by id")
	assert_eq(int(cells[1].count), 3)
	for tab in [2, 3, 4]:
		shop.select_tab(tab)
		assert_eq(shop.sell_cells(), [], "tab %d is empty" % tab)
	shop.select_tab(99)
	assert_eq(shop.tab, 4, "clamped")


func test_clicking_a_tab_and_the_wheel_and_the_scrollbar_move_the_lists() -> void:
	var world := _world(200, 0, [], {"2043700": 3})
	var shop: ShopWindow = _shop(world)[1]
	shop._gui_input(IW.press(shop.tab_rect(1).get_center()))
	shop._gui_input(IW.press(shop.tab_rect(1).get_center(), false))
	assert_eq(shop.tab, 1, "a click on the Use tab")
	assert_true(shop.stock.size() > ShopWindow.ROWS, "the stock needs scrolling")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = shop.row_rect(0, 2).get_center()
	shop._gui_input(wheel)
	assert_eq(shop.buy_offset, 1, "the wheel over the stock scrolls it")
	assert_eq(shop.sell_offset, 0, "the other list stays")
	shop.scroll_panel(0, 999)
	assert_eq(shop.buy_offset, shop.stock.size() - ShopWindow.ROWS, "never past the last row")
	shop.scroll_panel(0, -999)
	assert_eq(shop.buy_offset, 0)
	var bar := shop.scrollbar_rect(0)
	shop._gui_input(IW.press(bar.position + Vector2(5, bar.size.y - 4)))
	assert_eq(shop.buy_offset, 1, "the lower arrow scrolls down")


# --- buying ----------------------------------------------------------------------------------------------------------

func test_buying_asks_how_many_then_charges_and_adds_the_scrolls() -> void:
	var world := _world(200, 200000)
	var made := _shop(world)
	var stack: WindowStack = made[0]
	var shop: ShopWindow = made[1]
	var actions: Array = []
	shop.item_action.connect(func(a: String) -> void: actions.append(a))
	var wand := _index_of(shop, 2043700)
	assert_true(wand >= 0)
	shop.begin_buy()
	assert_eq(stack.find_window("shop_quantity"), null, "nothing selected: nothing asked")
	_select_stock(shop, wand)
	assert_eq(shop.buy_selected, wand, "a click selects the row")
	shop.begin_buy()
	var box := stack.find_window("shop_quantity") as ShopQuantity
	assert_true(box != null, "Buy asks how many")
	assert_eq(box.message, "How many are you willing to buy?")
	box.type_digit(2)
	assert_eq(box.count, 2)
	box.accept()
	assert_eq(world.mesos, 200000 - 2 * 70000, "two wand scrolls at 70,000")
	assert_eq(world.scrolls, {"2043700": 2})
	assert_eq(actions, ["buy"], "the host is told to save and redraw")
	assert_eq(stack.find_window("shop_quantity"), null, "the box closed")
	assert_eq(shop.meso_text(), "60,000")


func test_a_double_click_on_a_stock_row_asks_how_many() -> void:
	var made := _shop(_world())
	var shop: ShopWindow = made[1]
	_click_row(shop, 0, 1, true)
	assert_eq(shop.buy_selected, 1)
	assert_true((made[0] as WindowStack).find_window("shop_quantity") != null)


func test_not_enough_mesos_shows_the_message_and_changes_nothing() -> void:
	var world := _world(200, 69999)
	var made := _shop(world)
	var shop: ShopWindow = made[1]
	var actions: Array = []
	shop.item_action.connect(func(a: String) -> void: actions.append(a))
	assert_eq(shop.buy(_index_of(shop, 2043700), 1), "mesos")
	assert_eq(shop.last_notice, "You do not have enough mesos.")
	var notice := (made[0] as WindowStack).find_window("shop_notice") as ShopNotice
	assert_true(notice != null and notice.message == "You do not have enough mesos.", "the v83 notice box")
	assert_eq(world.mesos, 69999)
	assert_eq(world.scrolls, {})
	assert_eq(actions, [], "nothing was saved")


func test_a_full_use_tab_shows_the_message_and_changes_nothing() -> void:
	var stacks := {}
	for i in 22:
		stacks[str(2040010 + i)] = 1
	var world := _world(200, 1000000, [], stacks)
	var shop: ShopWindow = _shop(world)[1]
	assert_eq(shop.buy(_index_of(shop, 2043700), 1), "use_full")
	assert_eq(shop.last_notice, "Please check if your inventory is full or not.")
	assert_eq(world.mesos, 1000000)
	assert_false(world.scrolls.has("2043700"))


func test_the_quantity_box_types_clamps_and_cancels() -> void:
	var box := _quantity(5)
	assert_eq(box.count, 1)
	box.type_digit(3)
	assert_eq(box.count, 3, "the first digit replaces the shown 1")
	box.type_digit(7)
	assert_eq(box.count, 5, "never above the maximum")
	box.backspace()
	assert_eq(box.count, 1)
	box.step(1)
	box.step(1)
	assert_eq(box.count, 3, "Up raises it")
	box.step(-99)
	assert_eq(box.count, 1, "never below 1")
	var got: Array = []
	box.confirmed.connect(func(n: int) -> void: got.append(n))
	box.type_digit(4)
	assert_eq(box.count, 5, "after step() a typed digit appends: 14 is clamped to the maximum")
	assert_true(box.handle_key(_key(KEY_ENTER)), "Enter confirms")
	assert_eq(got, [5])
	var b2 := _quantity(5)
	var got2: Array = []
	b2.confirmed.connect(func(n: int) -> void: got2.append(n))
	b2.cancel()
	assert_eq(got2, [], "No tells nobody")
	var b3 := _quantity(99)
	assert_true(b3.handle_key(_key(KEY_4)))
	assert_true(b3.handle_key(_key(KEY_KP_2)))
	assert_eq(b3.count, 42, "digits and keypad digits type a number")


func _quantity(max_count: int) -> ShopQuantity:
	var box := ShopQuantity.new("How many?", max_count)
	_nodes.append(box)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(box)
	return box


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.physical_keycode = code
	return e


# --- selling ---------------------------------------------------------------------------------------------------------

func test_selling_a_scroll_stack_asks_how_many_and_pays_one_meso_each() -> void:
	var world := _world(200, 0, [], {"2043700": 5})
	var made := _shop(world)
	var shop: ShopWindow = made[1]
	shop.select_tab(1)
	_click_row(shop, 1, 0)
	assert_eq(shop.sell_selected, 0)
	shop.begin_sell()
	var box := (made[0] as WindowStack).find_window("shop_quantity") as ShopQuantity
	assert_true(box != null and box.max_count == 5 and box.message == "How many are you willing to sell?")
	box.type_digit(3)
	box.accept()
	assert_eq(world.mesos, 3)
	assert_eq(world.scrolls, {"2043700": 2})


func test_selling_equipment_asks_yes_no_and_pays_its_info_price() -> void:
	var world := _world(200, 0, [1002001, 1040002])
	var made := _shop(world)
	var shop: ShopWindow = made[1]
	_click_row(shop, 1, 0)
	shop.begin_sell()
	var confirm := (made[0] as WindowStack).find_window("drop_confirm") as DropConfirm
	assert_true(confirm != null and confirm.message == "Are you sure you want to sell it?", "the YesNo box first")
	assert_eq(world.equipment.inventory.size(), 2, "nothing sold before Yes")
	confirm.cancel()
	assert_eq(world.mesos, 0)
	shop.begin_sell()
	((made[0] as WindowStack).find_window("drop_confirm") as DropConfirm).accept()
	assert_eq(world.mesos, 1500, "the hat's info/price")
	assert_eq(world.equipment.inventory.size(), 1)
	assert_eq(int(world.equipment.inventory[0].id), 1040002)
	assert_eq(shop.sell_selected, 0, "the selection stays on the row that moved up")


func test_a_double_click_on_an_inventory_row_asks_to_sell_it() -> void:
	var made := _shop(_world(200, 0, [1002001]))
	_click_row(made[1], 1, 0, true)
	assert_true((made[0] as WindowStack).find_window("drop_confirm") != null)


func test_a_confirmation_for_an_item_that_moved_sells_nothing() -> void:
	var world := _world(200, 0, [1002001, 1040002])
	var shop: ShopWindow = _shop(world)[1]
	assert_eq(shop.sell_item(0, 1040002), "no_item", "index 0 is the hat now")
	assert_eq(world.equipment.inventory.size(), 2)
	assert_eq(world.mesos, 0)


func test_selling_the_last_row_clears_the_selection() -> void:
	var world := _world(200, 0, [1002001])
	var shop: ShopWindow = _shop(world)[1]
	_click_row(shop, 1, 0)
	assert_eq(shop.sell_item(0, 1002001), "")
	assert_eq(shop.sell_selected, -1)
	assert_eq(shop.sell_cells(), [])


func test_a_shop_row_cannot_be_dragged_onto_the_equip_window() -> void:
	var world := _world(200, 0, [], {"2043700": 2})
	var made := _shop(world)
	var stack: WindowStack = made[0]
	var shop: ShopWindow = made[1]
	shop.select_tab(1)
	var equip := EquipWindow.new(world)
	stack.open(equip)
	equip.position = Vector2(500, 0)
	var from := shop.row_rect(1, 0).get_center()
	shop._gui_input(IW.motion(from))
	shop._gui_input(IW.press(from))
	shop._gui_input(IW.motion(from + Vector2(20, 0)))
	shop._gui_input(IW.motion(from + Vector2(60, 0)))
	assert_false(shop.is_dragging_item(), "no drag starts in a shop")
	shop._gui_input(IW.press(from, false))
	assert_eq(world.scrolls, {"2043700": 2}, "the scroll was not read")
	assert_eq(world.mesos, 0)


# --- tooltips --------------------------------------------------------------------------------------------------------

func test_hovering_a_stock_row_shows_the_scrolls_tooltip() -> void:
	var shop: ShopWindow = _shop(_world())[1]
	shop._gui_input(IW.motion(shop.row_rect(0, 0).get_center()))
	var tip := shop.tooltip()
	assert_false(tip.is_empty())
	assert_eq(int(shop.stock_cell(0).id), int(shop.stock[0].id))
	assert_true(tip.has("name") and tip.has("icon"))


# --- the Free Market hub ----------------------------------------------------------------------------------------------

func _hub() -> FreeMarket:
	var character := DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json") as Dictionary
	character.mesos = 100000
	var hub := FreeMarket.new()
	hub.configure({"name": "Shopper", "character": character}, null)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(hub)
	hub.set_process(false)
	_nodes.append(hub)
	# The player's own settings may have given Space away: NPC Chat is put on its project default for the test.
	InputMap.action_erase_events("npc_chat")
	for code in GameSettings.default_keys("npc_chat"):
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event("npc_chat", ev)
	return hub


func test_the_hub_stands_the_four_scroll_npcs_on_the_floor() -> void:
	if not require_cache():
		return
	var hub := _hub()
	assert_eq(hub.shop_npcs.map(func(n: Dictionary) -> int: return int(n.id)), [1032103, 2022002, 1052104, 2041016])
	for npc: Dictionary in hub.shop_npcs:
		assert_eq((npc.pos as Vector2).y, 34.0, "on the floor")
	assert_eq(AssetLibrary.get_default().string_name("Npc", 1032103), "El Moth", "String.wz names the NPCs")
	assert_eq(hub.npcs.map(func(n: Dictionary) -> int: return int(n.id)), [9030000, 9030100, 9250025, 9000069],
		"the map's own NPCs stay as they were")
	assert_eq(hub.missing_paths(), PackedStringArray())


func test_space_next_to_an_npc_opens_its_shop_and_far_away_it_does_not() -> void:
	if not require_cache():
		return
	var hub := _hub()
	var npc: Dictionary = hub.shop_npcs[1]
	hub.motion.player.place((npc.pos as Vector2) + Vector2(40, 0), hub.motion.fhm)
	assert_eq(int(hub.nearest_shop_npc().id), 2022002, "the nearest NPC in range")
	var space := _key(SPACE_KEY)
	assert_true(hub.handle_hotkey(space), "NPC Chat is used")
	var shop := hub.ui_windows.find_window("shop") as ShopWindow
	assert_true(shop != null and shop.npc_id == 2022002, "Barun's shop is open")
	assert_true(hub.windows_open(), "the hub holds like for any window")
	assert_false(hub.handle_hotkey(space), "Space again does nothing while the shop is open")
	assert_true(hub.handle_hotkey(_key(KEY_ESCAPE)), "Esc closes the shop")
	assert_false(hub.windows_open())
	hub.motion.player.place(Vector2(900, 34), hub.motion.fhm)
	assert_eq(hub.nearest_shop_npc(), {}, "nobody in range")
	assert_false(hub.handle_hotkey(space), "Space far from every NPC opens nothing")
	assert_false(hub.windows_open())


func test_a_double_click_on_an_npc_opens_its_shop() -> void:
	if not require_cache():
		return
	var hub := _hub()
	var npc: Dictionary = hub.shop_npcs[3]
	var world_point: Vector2 = (npc.rect as Rect2).get_center()
	assert_eq(int(hub.shop_npc_at(world_point).id), 2041016)
	assert_eq(hub.shop_npc_at(Vector2(5000, 5000)), {})
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = true
	e.position = hub.get_canvas_transform() * world_point
	hub._unhandled_input(e)
	var shop := hub.ui_windows.find_window("shop") as ShopWindow
	assert_true(shop != null and shop.npc_id == 2041016, "Vega's shop is open")
	e.double_click = false
	hub.ui_windows.close("shop")
	hub._unhandled_input(e)
	assert_eq(hub.ui_windows.find_window("shop"), null, "a single click opens nothing")


func test_npc_chat_can_be_rebound_and_the_hub_follows() -> void:
	if not require_cache():
		return
	var hub := _hub()
	var npc: Dictionary = hub.shop_npcs[0]
	hub.motion.player.place(npc.pos as Vector2, hub.motion.fhm)
	InputMap.action_erase_events("npc_chat")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_N
	InputMap.action_add_event("npc_chat", ev)
	assert_false(hub.handle_hotkey(_key(SPACE_KEY)), "Space no longer talks")
	assert_true(hub.handle_hotkey(_key(KEY_N)), "the rebound key does")
	assert_true(hub.ui_windows.find_window("shop") != null)


func test_a_purchase_in_the_hub_is_carried_in_the_snapshot() -> void:
	if not require_cache():
		return
	var hub := _hub()
	assert_true(hub.open_shop(1032103))
	var shop := hub.ui_windows.find_window("shop") as ShopWindow
	var before: int = hub.inventory.mesos
	assert_eq(shop.buy(0, 1), "")
	assert_eq(hub.inventory.mesos, before - 35000)
	assert_eq(int(hub.snapshot.character.mesos), before - 35000, "the carried character holds the new mesos")
	assert_eq(int(hub.snapshot.character.scrolls[str(int(shop.stock[0].id))]), 1)
