extends TestCase
## The Key Config and Options windows (UiWindows, #87) driven with synthetic mouse events local to the window: drag a
## tray icon onto a key, move an icon between keys, drag it off the keyboard, a fixed key refusing a drop, Delete,
## Default, OK (saved and applied) and Cancel (nothing saved); Options' volume sliders, mute boxes, frame cap and
## movement setting apply and save at once. Works with or without the asset cache (the windows keep their layout).
## Each test uses its own GameSettings file; the global InputMap it writes is restored after every test.

var cfg_path := TestCase.test_dir("key_config_window_test.cfg")
var settings: GameSettings
var _nodes: Array[Node] = []
var _saved_map: Dictionary = {}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	_saved_map = {}
	for a: StringName in InputMap.get_actions():
		_saved_map[a] = InputMap.action_get_events(a).duplicate()
	settings = GameSettings.new(cfg_path)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	settings.free()
	for a: StringName in _saved_map:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
			for e: InputEvent in _saved_map[a]:
				InputMap.action_add_event(a, e)


func _add(w: UiWindow) -> UiWindow:
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(w)
	_nodes.append(w)
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


## A left-button drag from local `a` to local `b`.
static func drag(w: UiWindow, a: Vector2, b: Vector2) -> void:
	w._gui_input(motion(a))
	w._gui_input(press(a))
	w._gui_input(motion(a.lerp(b, 0.5)))
	w._gui_input(motion(b))
	w._gui_input(press(b, false))


func _key_config() -> KeyConfigWindow:
	return _add(KeyConfigWindow.new(settings)) as KeyConfigWindow


# --- Key Config ----------------------------------------------------------------------------------------------------

func test_key_config_is_the_v83_keyboard_with_a_tray_of_the_bindable_actions() -> void:
	var w := _key_config()
	assert_eq(w.size, KeyConfigWindow.ART_SIZE, "the v83 KeyConfig backgrnd size")
	assert_eq(w.window_id, "key_config")
	for a: String in KeyBindings.BINDABLE:
		assert_true(w.tray_rect(a).size == Vector2(32, 32), "%s has a tray slot" % a)
	for code: int in [KEY_ESCAPE, KEY_F1, KEY_1, KEY_Q, KEY_A, KEY_Z, KEY_SPACE, KEY_ALT, KEY_DELETE, KEY_LEFT]:
		var r := w.key_rect(code)
		assert_true(r.size.x >= 30.0 and r.size.y >= 30.0, "%s has a key" % OS.get_keycode_string(code))
		assert_eq(w.key_at(r.get_center()), code, "%s is found under its own rect" % OS.get_keycode_string(code))
	assert_eq(w.key_at(Vector2(30, 115)), -1, "Tab (v83 'move menu', baked in the art) is no drop target")
	assert_true(w.key_rect(KEY_Q).position.x < w.key_rect(KEY_W).position.x, "Q left of W")
	assert_true(w.key_rect(KEY_1).position.y < w.key_rect(KEY_Q).position.y, "the digits above the letters")


func test_drag_a_tray_icon_onto_a_free_key_binds_it() -> void:
	var w := _key_config()
	drag(w, w.tray_rect("jump").get_center(), w.key_rect(KEY_F).get_center())
	assert_eq(w.draft.action_on(KEY_F), "jump", "F jumps")
	assert_true(KEY_SPACE in w.draft.keys_of("jump"), "the tray is a source: the old keys stay")
	assert_eq(settings.binding_keys("jump"), GameSettings.default_keys("jump"), "nothing saved before OK")
	drag(w, w.tray_rect("teleport").get_center(), w.key_rect(KEY_Q).get_center())
	assert_eq(w.draft.action_on(KEY_Q), "teleport", "dropping on a bound key replaces its action")
	assert_eq(w.draft.keys_of("drink_hp"), PackedInt32Array([KEY_DELETE]))


func test_drag_between_keys_moves_and_off_the_keyboard_unbinds() -> void:
	var w := _key_config()
	drag(w, w.key_rect(KEY_SPACE).get_center(), w.key_rect(KEY_F).get_center())
	assert_eq(w.draft.action_on(KEY_F), "jump")
	assert_eq(w.draft.action_on(KEY_SPACE), "", "moved off Space")
	drag(w, w.key_rect(KEY_F).get_center(), Vector2(w.size.x + 40.0, 100.0))
	assert_eq(w.draft.action_on(KEY_F), "", "dragged off the window: unbound")
	drag(w, w.key_rect(KEY_C).get_center(), w.tray_rect("jump").get_center())
	assert_eq(w.draft.action_on(KEY_C), "", "dragged back onto the tray: unbound")


func test_a_fixed_key_refuses_a_drop() -> void:
	var w := _key_config()
	for code: int in [KEY_ESCAPE, KEY_1, KEY_LEFT]:
		drag(w, w.tray_rect("jump").get_center(), w.key_rect(code).get_center())
		assert_eq(w.draft.action_on(code), "", "%s stays fixed" % OS.get_keycode_string(code))
	drag(w, w.key_rect(KEY_SPACE).get_center(), w.key_rect(KEY_2).get_center())
	assert_eq(w.draft.action_on(KEY_SPACE), "jump", "a refused move leaves the icon where it was")
	assert_true(w.is_fixed_key(KEY_UP), "Arrows: the arrows are movement")


func test_a_click_selects_and_clear_all_unbinds_every_action() -> void:
	var w := _key_config()
	w._gui_input(press(w.key_rect(KEY_E).get_center()))
	w._gui_input(press(w.key_rect(KEY_E).get_center(), false))
	assert_eq(w.selected_key, KEY_E, "a click selects (outlines) a bound key")
	assert_eq(w.draft.action_on(KEY_E), "drink_mp", "a click does not move it")
	w._bt_delete.pressed.emit()
	for a: String in KeyBindings.BINDABLE:
		assert_eq(w.draft.keys_of(a), PackedInt32Array(), "BtDelete (v83 CLEAR ALL) unbinds %s" % a)
	assert_eq(w.selected_key, -1)
	assert_eq(settings.binding_keys("jump"), GameSettings.default_keys("jump"), "only the draft: OK saves it")


func test_ok_saves_and_applies_cancel_discards() -> void:
	var w := _key_config()
	var closed := [0]
	w.close_requested.connect(func() -> void: closed[0] += 1)
	drag(w, w.tray_rect("jump").get_center(), w.key_rect(KEY_F).get_center())
	w._bt_cancel.pressed.emit()
	assert_eq(closed[0], 1, "Cancel closes")
	assert_false(KEY_F in settings.binding_keys("jump"), "Cancel saved nothing")
	assert_false(FileAccess.file_exists(cfg_path), "no file written")
	var v := _key_config()
	v.close_requested.connect(func() -> void: closed[0] += 1)
	drag(v, v.tray_rect("jump").get_center(), v.key_rect(KEY_F).get_center())
	v._bt_ok.pressed.emit()
	assert_eq(closed[0], 2, "OK closes")
	assert_true(KEY_F in settings.binding_keys("jump"), "OK applied F to jump")
	var t := GameSettings.new(cfg_path)
	assert_true(KEY_F in t.bindings.get("jump", PackedInt32Array()), "and saved it")
	t.free()


func test_default_restores_the_defaults_in_the_draft() -> void:
	settings.set_bindings({"stat_window": PackedInt32Array(), "jump": PackedInt32Array([KEY_F])})
	var w := _key_config()
	assert_eq(w.draft.keys_of("jump"), PackedInt32Array([KEY_F]), "opens on the saved bindings")
	w._bt_default.pressed.emit()
	assert_eq(w.draft.keys_of("jump"), GameSettings.default_keys("jump"))
	assert_eq(w.draft.keys_of("stat_window"), PackedInt32Array([KEY_S]))
	w._bt_ok.pressed.emit()
	assert_eq(settings.binding_keys("stat_window"), PackedInt32Array([KEY_S]), "S opens Stat again")


func test_key_config_follows_a_movement_switch_in_options() -> void:
	var w := _key_config()
	assert_eq(w.draft.action_on(KEY_S), "stat_window")
	settings.set_movement_keys("wasd")
	assert_true(w.is_fixed_key(KEY_W) and not w.is_fixed_key(KEY_UP), "the open draft follows the setting")
	assert_eq(w.draft.action_on(KEY_S), "", "S is movement now")


# --- Options ---------------------------------------------------------------------------------------------------------

func _options() -> OptionsWindow:
	return _add(OptionsWindow.new(settings)) as OptionsWindow


func _click(w: UiWindow, p: Vector2) -> void:
	w._gui_input(press(p))
	w._gui_input(press(p, false))


func test_options_volume_sliders_apply_and_save_at_once() -> void:
	var w := _options()
	assert_eq(w.window_id, "options")
	var track := w.slider_rect("bgm")
	assert_true(track.size.x > 60.0, "a slider track")
	drag(w, track.get_center(), Vector2(track.position.x + track.size.x * 0.25, track.get_center().y))
	assert_near(settings.bgm_volume, 0.25, 0.02, "dragged to a quarter")
	var t := GameSettings.new(cfg_path)
	assert_near(t.bgm_volume, settings.bgm_volume, 1e-6, "saved")
	t.free()
	_click(w, Vector2(w.slider_rect("sfx").end.x + 30.0, w.slider_rect("sfx").get_center().y))
	assert_eq(settings.sfx_volume, 0.9, "a click beside the track changes nothing")
	_click(w, w.slider_rect("sfx").position + Vector2(0, 4))
	assert_eq(settings.sfx_volume, 0.0, "the left end: silent")


func test_options_mute_boxes() -> void:
	var w := _options()
	assert_false(w.is_muted("sfx"))
	_click(w, w.mute_rect("sfx").get_center())
	assert_eq(settings.sfx_volume, 0.0, "MUTE silences the sound")
	assert_true(w.is_muted("sfx"))
	_click(w, w.mute_rect("sfx").get_center())
	assert_eq(settings.sfx_volume, 0.9, "unmute: back to the default volume")
	assert_eq(settings.bgm_volume, 0.8, "BGM untouched")


func test_options_frame_cap_and_movement() -> void:
	var w := _options()
	assert_eq(w.frame_cap_choice(), 0, "default: the display's refresh rate")
	_click(w, w.frame_cap_rect(OptionsWindow.FRAME_CAPS.find(-1)).get_center())
	assert_eq(settings.max_fps, -1, "uncapped")
	_click(w, w.frame_cap_rect(OptionsWindow.FRAME_CAPS.find(60)).get_center())
	assert_eq(settings.max_fps, 60)
	_click(w, w.movement_rect("wasd").get_center())
	assert_eq(settings.movement_keys, "wasd")
	assert_eq(settings.binding_keys("move_left"), PackedInt32Array([KEY_A]), "applied to the InputMap")
	var t := GameSettings.new(cfg_path)
	assert_eq(t.movement_keys, "wasd", "saved")
	assert_eq(t.max_fps, 60)
	t.free()
	_click(w, w.movement_rect("arrows").get_center())
	assert_eq(settings.binding_keys("move_left"), PackedInt32Array([KEY_LEFT]))
	var closed := [false]
	w.close_requested.connect(func() -> void: closed[0] = true)
	w._bt_ok.pressed.emit()
	assert_true(closed[0], "OK closes")
