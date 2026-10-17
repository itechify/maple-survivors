extends TestCase
## WindowStack and UiWindow (game/scripts/ui/windows/): the in-run window system the Stat, Skill, Key Config and
## Options windows share. Ordering, bring-to-front on click, title-bar dragging, Esc closing the top window, toggling
## registered windows and the Menu popup's enabled entries. Works with or without the asset cache (windows without art
## keep their size and input).

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _stack() -> WindowStack:
	var s := WindowStack.new()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	return s


## A plain 120x80 window; with `at` it stays where it is put, without it the stack places it.
static func _window(id: String, at: Variant = null) -> UiWindow:
	var w := UiWindow.new()
	w.window_id = id
	w.size = Vector2(120, 80)
	if at is Vector2:
		w.auto_place = false
		w.position = at
	return w


static func press(at: Vector2, pressed: bool = true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	return e


static func motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func test_windows_stack_in_opening_order_and_a_click_brings_one_to_the_front() -> void:
	var s := _stack()
	assert_false(s.has_windows(), "empty at first")
	var a := s.open(_window("a", Vector2(10, 10)))
	var b := s.open(_window("b", Vector2(60, 40)))
	var c := s.open(_window("c", Vector2(200, 200)))
	assert_eq(s.ids(), PackedStringArray(["a", "b", "c"]), "bottom to top in opening order")
	assert_eq(s.top(), c, "the last opened is on top")
	a._gui_input(press(Vector2(5, 30)))
	assert_eq(s.ids(), PackedStringArray(["b", "c", "a"]), "clicking a brings it to the front")
	assert_eq(s.top(), a)
	b._gui_input(press(Vector2(5, 30)))
	assert_eq(s.ids(), PackedStringArray(["c", "a", "b"]))
	assert_true(s.has_windows())


func test_close_top_closes_one_window_at_a_time_then_reports_nothing_left() -> void:
	var s := _stack()
	s.open(_window("a"))
	s.open(_window("b"))
	assert_true(s.close_top(), "Esc closes b")
	assert_eq(s.ids(), PackedStringArray(["a"]))
	assert_true(s.close_top(), "Esc closes a")
	assert_false(s.has_windows())
	assert_false(s.close_top(), "nothing left: Esc goes on to the pause menu")


func test_dragging_the_title_bar_moves_the_window_and_the_body_does_not() -> void:
	var s := _stack()
	var w := s.open(_window("a", Vector2(100, 100)))
	w._gui_input(press(Vector2(30, 8)))
	w._gui_input(motion(Vector2(50, 20)))
	assert_eq(w.position, Vector2(120, 112), "the title bar drags by the pointer's movement")
	w._gui_input(press(Vector2(50, 20), false))
	w._gui_input(motion(Vector2(90, 60)))
	assert_eq(w.position, Vector2(120, 112), "released: no more dragging")
	w._gui_input(press(Vector2(30, 60)))
	w._gui_input(motion(Vector2(80, 70)))
	assert_eq(w.position, Vector2(120, 112), "the body is not a drag handle")


func test_dragging_keeps_the_title_bar_inside_the_view() -> void:
	var s := _stack()
	var w := s.open(_window("a", Vector2(100, 100)))
	w._gui_input(press(Vector2(30, 8)))
	w._gui_input(motion(Vector2(-1000, -1000)))
	assert_true(w.position.y >= 0.0, "the title bar cannot leave the top")
	assert_true(w.position.x + w.size.x >= UiWindow.KEEP_VISIBLE, "a strip stays reachable on the left")


func test_toggle_opens_a_registered_window_once_and_closes_it_again() -> void:
	var s := _stack()
	var made := [0]
	s.register("stat", func() -> UiWindow:
		made[0] += 1
		return _window("stat"))
	assert_true(s.can_open("stat"))
	assert_false(s.can_open("skill"), "nothing registered under skill yet")
	assert_true(s.toggle("stat"), "opened")
	assert_eq(s.ids(), PackedStringArray(["stat"]))
	assert_false(s.toggle("skill"), "unregistered ids do nothing")
	assert_false(s.toggle("stat"), "toggling again closes it")
	assert_false(s.has_windows())
	s.toggle("stat")
	assert_eq(made[0], 2, "a closed window is made again on the next open")


func test_reopened_windows_return_where_they_were_dragged() -> void:
	var s := _stack()
	s.register("stat", func() -> UiWindow: return _window("stat"))
	s.toggle("stat")
	var w := s.find_window("stat")
	w._gui_input(press(Vector2(30, 8)))
	w._gui_input(motion(Vector2(70, 28)))
	w._gui_input(press(Vector2(70, 28), false))
	var dragged := w.position
	s.toggle("stat")
	s.toggle("stat")
	assert_eq(s.find_window("stat").position, dragged, "the stack remembers the last position per id")


func test_changed_fires_on_open_close_and_reorder() -> void:
	var s := _stack()
	var n := [0]
	s.changed.connect(func() -> void: n[0] += 1)
	var a := s.open(_window("a"))
	s.open(_window("b"))
	a._gui_input(press(Vector2(5, 30)))
	s.close_top()
	assert_eq(n[0], 4, "open, open, raise, close")


func test_menu_popup_lists_the_four_entries_and_disables_missing_windows() -> void:
	var s := _stack()
	s.register("stat", func() -> UiWindow: return _window("stat"))
	var menu := GameMenuPopup.new()
	menu.stack = s
	s.open(menu)
	assert_eq(menu.entry_ids(), PackedStringArray(["equip", "item", "stat", "skill", "key_config", "options"]))
	assert_true(menu.is_enabled("stat"))
	assert_false(menu.is_enabled("skill"), "the Skill window does not exist yet")
	assert_false(menu.is_enabled("equip"), "nor the Equip window")
	assert_false(menu.choose("options"), "a disabled entry does nothing")
	assert_true("menu" in s.ids(), "still open")
	var r: Rect2 = menu.entry_rect("stat")
	menu._gui_input(press(r.get_center()))
	menu._gui_input(press(r.get_center(), false))
	assert_eq(s.ids(), PackedStringArray(["stat"]), "Stat opened, the popup closed")
