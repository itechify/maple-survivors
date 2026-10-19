extends TestCase
## TabStrip (#219): the piece layout of a v83 tab row (pure geometry, no art), and that the Item and Equip windows' hit
## areas are exactly the tabs TabStrip draws (contiguous over the strip, a click anywhere in a tab picks it). The real
## Basic.img/Tab3 and Tab5 piece widths are checked only when the asset cache is imported (otherwise SKIP).

const IW := preload("res://tests/unit/test_inventory_windows.gd")

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


static func _names(pieces: Array[Dictionary]) -> Array:
	var out := []
	for p: Dictionary in pieces:
		out.append(String(p.name))
	return out


## Asserts the pieces tile [from, to) without a gap or an overlap.
func _assert_tiles(pieces: Array[Dictionary], from: float, to: float) -> void:
	var x := from
	for p: Dictionary in pieces:
		assert_eq(float(p.x), x, "%s starts where the previous piece ended" % p.name)
		x += float(p.w)
	assert_eq(x, to, "the row ends at the last bound")


func test_a_row_is_left_then_fills_and_joins_then_right() -> void:
	var p := TabStrip.pieces(PackedFloat32Array([4.0, 40.0, 80.0, 120.0]), 1)
	assert_eq(_names(p), ["left0", "fill0", "middle2", "fill1", "middle1", "fill0", "right0"],
		"hidden | shown joins with middle2, shown | hidden with middle1")


func test_the_first_and_last_tab_shown_use_the_shown_ends() -> void:
	var first := TabStrip.pieces(PackedFloat32Array([0.0, 30.0, 60.0]), 0)
	assert_eq(_names(first), ["left1", "fill1", "middle1", "fill0", "right0"])
	var last := TabStrip.pieces(PackedFloat32Array([0.0, 30.0, 60.0]), 1)
	assert_eq(_names(last), ["left0", "fill0", "middle2", "fill1", "right1"])


func test_no_tab_shown_draws_only_hidden_pieces() -> void:
	var p := TabStrip.pieces(PackedFloat32Array([0.0, 30.0, 60.0, 90.0]), -1)
	assert_eq(_names(p), ["left0", "fill0", "middle0", "fill0", "middle0", "fill0", "right0"])


func test_the_pieces_tile_the_row_for_every_shown_tab() -> void:
	var bounds := PackedFloat32Array([4.0, 37.0, 71.0, 104.0, 137.0, 171.0])
	for shown in range(-1, 5):
		_assert_tiles(TabStrip.pieces(bounds, shown), 4.0, 171.0)
	_assert_tiles(TabStrip.pieces(PackedFloat32Array([5.0, 41.0]), 0), 5.0, 41.0)


func test_a_row_without_tabs_has_no_pieces() -> void:
	assert_eq(TabStrip.pieces(PackedFloat32Array([4.0]), 0).size(), 0)
	assert_eq(TabStrip.pieces(PackedFloat32Array(), 0).size(), 0)


func test_tab_rects_are_the_cells_between_the_bounds() -> void:
	var r := TabStrip.tab_rects(PackedFloat32Array([4.0, 37.0, 71.0]), 23.0, 19.0)
	assert_eq(r, [Rect2(4, 23, 33, 19), Rect2(37, 23, 34, 19)])


func test_the_real_piece_sets_have_the_widths_the_layout_assumes() -> void:
	if not require_cache():
		return
	for set_path: String in [TabStrip.RED_BASE_SET, TabStrip.GREY_BASE_SET]:
		assert_true(TabStrip.has_art(set_path), "%s is in the cache" % set_path)
		for state in 2:
			assert_eq(UiArt.size_of(set_path + "left%d" % state).x, TabStrip.EDGE_W)
			assert_eq(UiArt.size_of(set_path + "right%d" % state).x, TabStrip.EDGE_W)
			assert_eq(UiArt.size_of(set_path + "fill%d" % state).x, 1.0, "a fill is one column")
		for join in 3:
			assert_eq(UiArt.size_of(set_path + "middle%d" % join).x, TabStrip.JOIN_W)
	assert_eq(UiArt.size_of(TabStrip.RED_BASE_SET + "left0").y, 21.0, "Tab5: 19 body rows + 2 red")


func _stack() -> WindowStack:
	var s := WindowStack.new()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	return s


func test_the_item_windows_tabs_fill_the_strip_and_every_pixel_of_a_tab_picks_it() -> void:
	var s := _stack()
	s.register("item", func() -> UiWindow: return ItemWindow.new())
	s.toggle("item")
	var w := s.find_window("item") as ItemWindow
	assert_eq(w.tab_rect(0).position.x, ItemWindow.TAB_BOUNDS[0])
	assert_eq(w.tab_rect(4).end.x, ItemWindow.TAB_BOUNDS[5])
	for i in ItemWindow.TABS.size():
		var r := w.tab_rect(i)
		if i > 0:
			assert_eq(r.position.x, w.tab_rect(i - 1).end.x, "tab %d starts where tab %d ends" % [i, i - 1])
		for at: Vector2 in [r.position + Vector2(0.5, 0.5), r.get_center(), r.end - Vector2(0.5, 0.5)]:
			w.select_tab((i + 2) % 5)
			w._gui_input(IW.press(at))
			w._gui_input(IW.press(at, false))
			assert_eq(w.tab, i, "a click at %s picks tab %d" % [at, i])


func test_the_equip_windows_two_tabs_sit_in_the_blue_strip_and_switch_the_page() -> void:
	var s := _stack()
	s.register("equip", func() -> UiWindow: return EquipWindow.new())
	s.toggle("equip")
	var w := s.find_window("equip") as EquipWindow
	var equip := w.tab_rect("equip")
	var cash := w.tab_rect("cash")
	assert_eq(equip.end.x, cash.position.x, "the two tabs touch")
	assert_eq(equip.size.y, 19.0, "the 19 rows of the blue strip")
	assert_eq(equip.end.y, EquipWindow.WINDOW_SIZE.y - 5.0, "ending just above the window's bottom border")
	w._gui_input(IW.press(cash.get_center()))
	assert_eq(w.page, "cash", "a click on the Cash tab shows the cash page")
	w._gui_input(IW.press(w.tab_rect("equip").get_center()))
	assert_eq(w.page, "equip")
