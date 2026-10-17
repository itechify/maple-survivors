extends TestCase
## The Equip window's Cash tab and Pet page (spec #34, ticket #122) over a RunWorld on the synthetic quiet stage with an
## account: the page switch, the 11 cash slots and the owned-equipment panel (double-click wears and takes off, the
## overall and two-handed rules, paging), the owned pets (double-click brings one out or puts it away) and the owned
## pet upgrades listed read-only. No asset cache: the windows keep their layout and draw plain cells. Mouse events are
## synthetic and local to the window, as in test_inventory_windows.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const IW := preload("res://tests/unit/test_inventory_windows.gd")
const HAT := 1000001
const HAT2 := 1000002
const FACE := 1010001
const TOP := 1040001
const OVERALL := 1050001
const SHIELD := 1090001
const TWO_HANDED_COVER := 1700002
const KITTY := 5000000
const PUPPY := 5000001
const AUTO_HP := 1812002
const WING_BOOTS := 1812004
const OWNED := [HAT, HAT2, FACE, TOP, OVERALL, SHIELD, TWO_HANDED_COVER, KITTY, PUPPY, AUTO_HP, WING_BOOTS]

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _data(extra_hats := 0) -> Dictionary:
	var data := RF.quiet_data()
	for id: int in [HAT, HAT2, FACE, TOP, OVERALL, SHIELD]:
		data.cash_items.items.append({"id": id, "kind": "equip", "price": 1})
	data.cash_items.items.append({"id": TWO_HANDED_COVER, "kind": "equip", "price": 1, "two_handed": true})
	for i in extra_hats:
		data.cash_items.items.append({"id": 1002000 + i, "kind": "equip", "price": 1})
	return data


func _world(owned: Array = OWNED, extra_hats := 0) -> RunWorld:
	var data := _data(extra_hats)
	var setup := RF.setup("quiet", 7, data)
	setup.account = {"owned": owned}
	var world := RunWorld.new(setup)
	RF.place_player(world, 400)
	return world


func _window(world: RunWorld) -> EquipWindow:
	var s := WindowStack.new()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	s.register("equip", func() -> UiWindow: return EquipWindow.new(world))
	s.toggle("equip")
	return s.find_window("equip") as EquipWindow


func _centre(r: Rect2) -> Vector2:
	return r.get_center()


## The panel cell of item `id` on the shown page (-1 when it is not there).
func _cell_of(w: EquipWindow, id: int) -> int:
	for i in w.panel_capacity():
		if w.panel_item(i) == id:
			return i
	return -1


func _wear_by_double_click(w: EquipWindow, id: int) -> void:
	IW.double_click(w, _centre(w.panel_cell(_cell_of(w, id))))


# --- pages ---------------------------------------------------------------------------------------------------------------

func test_the_equip_page_is_unchanged_and_the_cash_and_pet_pages_add_a_panel() -> void:
	var w := _window(_world())
	assert_eq(w.page, "equip")
	assert_eq(w.size, EquipWindow.WINDOW_SIZE, "the Equip page keeps the v83 size")
	assert_eq(w.owned_items(), [], "no panel on the Equip page")
	w.set_page("cash")
	assert_eq(w.page, "cash")
	assert_eq(w.size, Vector2(175 + EquipWindow.PANEL_GAP + EquipWindow.PANEL_W, 304))
	w.set_page("pet")
	assert_eq(w.size, Vector2(177 + EquipWindow.PANEL_GAP + EquipWindow.PANEL_W, 181), "the Pet page is the v83 Equip/pet art")
	w.set_page("nonsense")
	assert_eq(w.page, "pet", "an unknown page is ignored")
	w.set_page("equip")
	assert_eq(w.size, EquipWindow.WINDOW_SIZE)


func test_the_strip_tabs_and_the_pet_button_switch_pages_by_mouse() -> void:
	var w := _window(_world())
	IW.double_click(w, _centre(w.tab_rect("cash")))
	assert_eq(w.page, "cash", "the Cash glyph opens the Cash page")
	IW.double_click(w, _centre(w.tab_rect("equip")))
	assert_eq(w.page, "equip")
	w._bt_pet.pressed.emit()
	assert_eq(w.page, "pet", "PET EQUIP. opens the Pet page")
	assert_true(w._bt_pet.disabled, "and shows its disabled art there")
	IW.double_click(w, _centre(w.tab_rect("equip")))
	assert_eq(w.page, "equip")
	assert_false(w._bt_pet.disabled)
	assert_eq(w._bt_close.position, Vector2(10, 281), "the close button keeps its v83 place on the Equip page")
	w.set_page("pet")
	assert_eq(w._bt_close.position, Vector2(10, 158), "and moves into the Pet art's bottom strip")


# --- cash page -----------------------------------------------------------------------------------------------------------

func test_the_cash_page_has_the_eleven_cash_slots_and_lists_the_owned_equipment_in_slot_order() -> void:
	var w := _window(_world())
	w.set_page("cash")
	assert_eq(EquipWindow.CASH_POS.keys().size(), 11)
	for slot: String in CashCatalog.SLOTS:
		assert_true(EquipWindow.CASH_POS.has(slot), slot)
		assert_eq(w.cash_slot_at(_centre(w.cash_rect(slot))), slot)
	assert_eq(w.owned_items(), [HAT, HAT2, FACE, TOP, OVERALL, TWO_HANDED_COVER, SHIELD],
		"the owned cash equipment by slot (hat, face, top, overall, weapon cover, shield); pets and upgrades are not listed")
	assert_eq(w.payload_at(_centre(w.panel_cell(0))), {"kind": "cash_owned", "id": HAT})
	assert_eq(w.payload_at(_centre(w.panel_cell(20))), {}, "an empty cell has no item")
	assert_eq(w.payload_at(_centre(w.cash_rect("hat"))), {}, "nothing is worn yet")


func test_double_clicking_an_owned_item_wears_it_and_a_worn_item_takes_it_off() -> void:
	var world := _world()
	var w := _window(world)
	w.set_page("cash")
	var actions: Array[String] = []
	w.item_action.connect(func(a: String) -> void: actions.append(a))
	_wear_by_double_click(w, HAT)
	assert_eq(world.worn_cash, {"hat": HAT})
	assert_eq(w.payload_at(_centre(w.cash_rect("hat"))), {"kind": "cash_worn", "slot": "hat", "id": HAT})
	assert_eq(world.account_owned, OWNED, "nothing is used up or moved: the item stays in the panel")
	assert_eq(w.panel_item(0), HAT)
	_wear_by_double_click(w, HAT2)
	assert_eq(world.worn_cash, {"hat": HAT2}, "a second hat replaces the first")
	IW.double_click(w, _centre(w.cash_rect("hat")))
	assert_eq(world.worn_cash, {}, "double-clicking the worn hat takes it off")
	assert_eq(actions, ["wear_cash", "wear_cash", "take_off_cash"], "the host hears every change")


func test_the_window_follows_the_overall_and_two_handed_rules_and_shows_both_slots() -> void:
	var world := _world()
	var w := _window(world)
	w.set_page("cash")
	_wear_by_double_click(w, TOP)
	_wear_by_double_click(w, OVERALL)
	assert_eq(world.worn_cash, {"top": OVERALL, "bottom": OVERALL}, "an overall clears the top and bottom")
	assert_eq(w.payload_at(_centre(w.cash_rect("bottom"))).id, OVERALL, "the PANTS cell answers for the overall too")
	IW.double_click(w, _centre(w.cash_rect("bottom")))
	assert_eq(world.worn_cash, {}, "taking the overall off from either cell clears both")
	_wear_by_double_click(w, OVERALL)
	_wear_by_double_click(w, TOP)
	assert_eq(world.worn_cash, {"top": TOP}, "wearing a top takes the overall off")
	_wear_by_double_click(w, SHIELD)
	_wear_by_double_click(w, TWO_HANDED_COVER)
	assert_eq(world.worn_cash, {"top": TOP, "weapon": TWO_HANDED_COVER, "shield": TWO_HANDED_COVER},
		"a two-handed cover takes the weapon and shield slots")


func test_an_unowned_item_is_not_listed_and_cannot_be_worn() -> void:
	var world := _world([HAT, KITTY])
	var w := _window(world)
	w.set_page("cash")
	assert_eq(w.owned_items(), [HAT])
	assert_eq(w.wear_cash(HAT2), "not_owned")
	assert_eq(world.worn_cash, {})
	var notices: Array[String] = []
	w.notice.connect(func(t: String) -> void: notices.append(t))
	assert_eq(w.wear_cash(KITTY), "not_cash")
	assert_eq(world.worn_cash, {})


func test_the_panel_turns_pages_by_arrows_and_wheel_when_more_than_a_page_is_owned() -> void:
	var owned: Array = OWNED.duplicate()
	for i in 30:
		owned.append(1002000 + i)
	var world := _world(owned, 30)
	var w := _window(world)
	w.set_page("cash")
	assert_eq(w.panel_capacity(), 24)
	assert_eq(w.owned_pages(), 2, "37 owned items fill two pages of 24")
	var first := w.panel_item(0)
	IW.double_click(w, _centre(w.pager_rects()[1]))
	assert_eq(w.owned_page, 1, "the next arrow turns the page")
	assert_ne(w.panel_item(0), first)
	IW.double_click(w, _centre(w.pager_rects()[0]))
	assert_eq(w.owned_page, 0)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = _centre(w.panel_cell(0))
	w._gui_input(wheel)
	assert_eq(w.owned_page, 1, "the wheel over the panel turns it too")
	w._gui_input(wheel)
	assert_eq(w.owned_page, 1, "and stops at the last page")


func test_the_cash_tooltip_names_the_item() -> void:
	var w := _window(_world())
	w.set_page("cash")
	var tip := w.tooltip_for({"kind": "cash_owned", "id": HAT})
	assert_has(tip, "name")
	assert_has(tip, "icon")
	assert_eq(tip.icon, "Character.wz/Cap/%08d.img/info/icon" % HAT)


# --- pet page ------------------------------------------------------------------------------------------------------------

func test_the_pet_page_lists_the_owned_pets_and_double_click_brings_one_out_or_puts_it_away() -> void:
	var world := _world()
	var w := _window(world)
	w.set_page("pet")
	assert_eq(w.owned_items(), [KITTY, PUPPY], "only pets, in id order")
	assert_eq(w.payload_at(_centre(w.panel_cell(1))), {"kind": "pet_owned", "id": PUPPY})
	var actions: Array[String] = []
	w.item_action.connect(func(a: String) -> void: actions.append(a))
	_wear_by_double_click(w, PUPPY)
	assert_eq(world.pet, PUPPY)
	assert_eq(world.pet_system.species, PUPPY, "the pet is out at once")
	_wear_by_double_click(w, KITTY)
	assert_eq(world.pet, KITTY, "another pet replaces it")
	_wear_by_double_click(w, KITTY)
	assert_eq(world.pet, 0, "double-clicking the pet that is out puts it away")
	assert_eq(world.pet_state(), {})
	assert_eq(actions, ["pet", "pet", "pet"])


func test_owned_pet_upgrades_are_listed_read_only_in_their_cells() -> void:
	var world := _world()
	var w := _window(world)
	w.set_page("pet")
	var upgrades := func() -> Array:
		return w.pet_cells().filter(func(c: Dictionary) -> bool: return c.payload.kind == "pet_upgrade") \
			.map(func(c: Dictionary) -> int: return int(c.payload.id))
	assert_eq(upgrades.call(), [AUTO_HP, WING_BOOTS], "the owned upgrades; the base pouch and magnet need a pet out")
	var potions := w.pet_cells().filter(func(c: Dictionary) -> bool: return c.payload.kind == "potion")
	assert_eq(potions.map(func(c: Dictionary) -> Vector2: return c.cell), [Vector2(46, 11)],
		"the Auto HP pouch shows the character's HP potion in PET HP; no Auto MP pouch, no PET MP potion")
	var wing: Dictionary = w.pet_cells().filter(func(c: Dictionary) -> bool: return int(c.payload.get("id", 0)) == WING_BOOTS)[0]
	assert_eq(wing.cell, Vector2(13, 110), "Wing Boots sit in MOVE UP")
	IW.double_click(w, _centre(Rect2(wing.cell, EquipWindow.ICON_SLOT)))
	assert_eq(world.account_owned, OWNED, "a double-click on an upgrade changes nothing: upgrades always apply")
	assert_eq(world.pet, 0)
	assert_false(w.is_dragging_item())
	world.set_pet(KITTY)
	var with_pet: Array = upgrades.call()
	assert_true(with_pet.has(1812000) and with_pet.has(1812001), "with a pet out its Meso Magnet and Item Pouch show")
	assert_eq(w.tooltip_for({"kind": "pet_upgrade", "id": AUTO_HP}).icon, "Character.wz/PetEquip/01812002.img/info/icon")
