extends TestCase
## Web profile in game/ (spec #130, docs/ARCHITECTURE.md 10 "Web profile"): the cache location the web shell writes,
## the bundled fallback font, the web display settings and the hidden desktop-only controls. All checked on desktop
## with WebProfile.forced instead of a web export.

var _cfg := TestCase.test_dir("web_profile_settings.cfg")
var _nodes: Array[Node] = []
var _env_cache := ""
var _env_wz := ""


func before_each() -> void:
	_env_cache = OS.get_environment(AssetCachePaths.CACHE_ENV)
	_env_wz = OS.get_environment(AssetCachePaths.WZ_ENV)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_cfg + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg + suffix))


func after_each() -> void:
	WebProfile.forced = -1
	OS.set_environment(AssetCachePaths.CACHE_ENV, _env_cache)
	OS.set_environment(AssetCachePaths.WZ_ENV, _env_wz)
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


# --- cache path ------------------------------------------------------------------------------------------------------

func test_web_cache_root_is_the_user_dir_default() -> void:
	var want := OS.get_user_data_dir().replace("\\", "/").path_join("asset_cache/v83")
	assert_eq(AssetCachePaths.cache_root_for(true, "/env/cache", "/settings/cache", OS.get_user_data_dir()), want,
		"web ignores the env var and cache_dir")
	assert_eq(AssetCachePaths.cache_root_for(true, "", "", "/userfs/MapleSurvivors"),
		"/userfs/MapleSurvivors/asset_cache/v83", "the path the web shell writes (IDBFS /userfs)")


func test_desktop_cache_root_keeps_its_order() -> void:
	assert_eq(AssetCachePaths.cache_root_for(false, "C:\\env", "/settings", "/u"), "C:/env", "env first")
	assert_eq(AssetCachePaths.cache_root_for(false, "", "/settings/", "/u"), "/settings", "then cache_dir")
	assert_eq(AssetCachePaths.cache_root_for(false, "", "", "/u"), "/u/asset_cache/v83")


func test_resolve_uses_the_web_rule_when_web() -> void:
	OS.set_environment(AssetCachePaths.CACHE_ENV, "/somewhere/else")
	OS.set_environment(AssetCachePaths.WZ_ENV, "/wz")
	assert_eq(AssetCachePaths.resolve_cache_root(), "/somewhere/else", "desktop honours the env var")
	assert_eq(AssetCachePaths.resolve_wz_root(), "/wz")
	WebProfile.forced = 1
	assert_eq(AssetCachePaths.resolve_cache_root(),
		OS.get_user_data_dir().replace("\\", "/").path_join("asset_cache/v83"))
	assert_eq(AssetCachePaths.resolve_wz_root(), "", "web has no WZ folder")


# --- fonts -----------------------------------------------------------------------------------------------------------

const NOPE := ["NoSuchFont_for_tests"]


func _width(f: Font, bold_size: int = 12) -> Vector2:
	return f.get_string_size("Hello World", HORIZONTAL_ALIGNMENT_LEFT, -1, bold_size)


func test_arimo_fonts_load_with_arial_metrics() -> void:
	var regular := MapleFonts.arimo(400)
	var bold := MapleFonts.arimo(700)
	assert_true(regular != null and bold != null, "bundled Arimo loads")
	var w := _width(regular).x
	var wb := _width(bold).x
	# Arial's advances at 12 px for 'Hello World' add up to about 62 (Arimo is metric compatible with Arial).
	assert_near(w, 62.0, 2.0, "Arial-like metrics")
	assert_true(wb > w, "bold is wider than regular (%f vs %f)" % [wb, w])


func test_no_system_font_means_arimo_itself() -> void:
	# A SystemFont with no match would draw with the engine's built-in font and ignore its fallbacks (checked: same
	# size as ThemeDB.fallback_font), so the browser build, which has no system fonts, must get Arimo directly.
	var f := MapleFonts.make(PackedStringArray(NOPE), 400)
	assert_false(f is SystemFont, "no system match -> not a SystemFont")
	assert_eq(_width(f), _width(MapleFonts.arimo(400)))
	var b := MapleFonts.make(PackedStringArray(NOPE), 700)
	assert_eq(_width(b), _width(MapleFonts.arimo(700)), "bold too")
	assert_ne(_width(f), _width(ThemeDB.fallback_font), "not the engine's built-in font")


func test_system_match_keeps_the_system_font_with_arimo_behind_it() -> void:
	var f := MapleFonts.make_with(PackedStringArray(["Arial", "Tahoma"]), 700, true)
	assert_true(f is SystemFont, "a system font was found -> SystemFont")
	var s := f as SystemFont
	assert_eq(s.font_names, PackedStringArray(["Arial", "Tahoma"]))
	assert_eq(s.font_weight, 700)
	assert_eq(s.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(s.fallbacks.size(), 1, "Arimo as the glyph fallback")


func test_game_fonts_ask_for_system_names_first() -> void:
	# On desktop (Arial present) MapleText/HUD fonts are SystemFonts as before; where Arial is missing they are Arimo.
	for bold in [false, true]:
		var f := MapleText.font(bold)
		assert_true(f is SystemFont or f is FontVariation)
		if f is SystemFont:
			assert_true("Arial" in (f as SystemFont).font_names)
	for w in [400, 700]:
		var h := HudWidget.make_font(w)
		assert_true(h is SystemFont or h is FontVariation)
		assert_true(_width(h).x > 40.0)


# --- display settings ------------------------------------------------------------------------------------------------

func test_window_scale_sizes_only_apply_on_desktop() -> void:
	assert_eq(GameSettings.window_scale_size(2, false), Vector2i(1600, 1200))
	assert_eq(GameSettings.window_scale_size(0, false), Vector2i.ZERO, "0 = project default")
	assert_eq(GameSettings.window_scale_size(2, true), Vector2i.ZERO, "web never sizes the window")


func test_frame_cap_is_left_to_the_browser_on_web() -> void:
	var before := Engine.max_fps
	Engine.max_fps = 77
	GameSettings.apply_frame_cap(60)
	assert_eq(Engine.max_fps, 77, "headless desktop: untouched")
	WebProfile.forced = 1
	GameSettings.apply_frame_cap(60)
	assert_eq(Engine.max_fps, 0, "web: no cap, requestAnimationFrame paces the frames")
	GameSettings.apply_frame_cap(-1, true)
	assert_eq(Engine.max_fps, 0)
	Engine.max_fps = before


func test_fullscreen_toggle_target() -> void:
	assert_eq(GameSettings.toggled_window_mode(DisplayServer.WINDOW_MODE_WINDOWED), DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_eq(GameSettings.toggled_window_mode(DisplayServer.WINDOW_MODE_FULLSCREEN), DisplayServer.WINDOW_MODE_WINDOWED)
	assert_eq(GameSettings.toggled_window_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN),
		DisplayServer.WINDOW_MODE_WINDOWED)
	assert_false(GameSettings.is_fullscreen(), "headless test window is windowed")


func test_fullscreen_modes_share_one_definition() -> void:
	assert_true(GameSettings.is_fullscreen_mode(DisplayServer.WINDOW_MODE_FULLSCREEN))
	assert_true(GameSettings.is_fullscreen_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN))
	assert_false(GameSettings.is_fullscreen_mode(DisplayServer.WINDOW_MODE_WINDOWED))
	assert_false(GameSettings.is_fullscreen_mode(DisplayServer.WINDOW_MODE_MINIMIZED))
	for mode: int in [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_MAXIMIZED]:
		assert_eq(GameSettings.is_fullscreen_mode(GameSettings.toggled_window_mode(mode)),
			not GameSettings.is_fullscreen_mode(mode), "toggling flips fullscreen-ness of mode %d" % mode)


# --- Options window --------------------------------------------------------------------------------------------------

func _options(web: bool) -> OptionsWindow:
	WebProfile.forced = 1 if web else 0
	var s := GameSettings.new(_cfg)
	_nodes.append(s)
	var w := OptionsWindow.new(s)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(w)
	_nodes.append(w)
	return w


func _click(w: UiWindow, p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		w._gui_input(e)


func test_options_rows_desktop_keeps_frame_cap() -> void:
	var w := _options(false)
	assert_eq(OptionsWindow.row_ids(false), ["bgm", "sfx", "frame_cap", "movement", "hp_alert"])
	assert_true(w.row_y("frame_cap") > 0.0)
	assert_eq(w.row_y("fullscreen"), -1.0, "no fullscreen row on desktop")


func test_options_rows_web_swaps_frame_cap_for_fullscreen() -> void:
	var web := _options(true)
	assert_eq(OptionsWindow.row_ids(true), ["bgm", "sfx", "fullscreen", "movement", "hp_alert"],
		"the ALERT sliders stay on web")
	assert_eq(web.row_y("frame_cap"), -1.0, "the frame cap is hidden on web")
	var desktop := _options(false)
	assert_eq(web.row_y("fullscreen"), desktop.row_y("frame_cap"), "same slot")
	assert_eq(web.size, desktop.size, "same window size")


func test_options_fullscreen_click_toggles() -> void:
	var w := _options(true)
	var calls := [0]
	w.fullscreen_toggle = func() -> void: calls[0] += 1
	_click(w, w.fullscreen_rect().get_center())
	assert_eq(calls[0], 1)
	_click(w, Vector2(5, w.size.y - 2))
	assert_eq(calls[0], 1, "a click elsewhere does nothing")
	var d := _options(false)
	d.fullscreen_toggle = func() -> void: calls[0] += 10
	_click(d, Vector2(d.PANEL_X + 10.0, d.row_y("frame_cap") + 14.0))
	assert_eq(calls[0], 1, "desktop has no fullscreen choice")


# --- title screen ----------------------------------------------------------------------------------------------------

func _title(web: bool) -> Node2D:
	WebProfile.forced = 1 if web else 0
	var t := load("res://scenes/ui/title_screen.tscn").instantiate() as Node2D
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(t)
	_nodes.append(t)
	return t


func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	return e


func test_desktop_title_keeps_quit_and_has_no_web_entries() -> void:
	var t := _title(false)
	var quits := [0]
	t.quit_fn = func() -> void: quits[0] += 1
	assert_true(t.quit_button.visible)
	assert_true(t.fullscreen_button == null and t.export_save_button == null and t.import_save_button == null)
	t._unhandled_input(_esc())
	assert_eq(quits[0], 1, "Esc quits on desktop")


func test_web_title_hides_quit_and_ignores_esc() -> void:
	var t := _title(true)
	var quits := [0]
	t.quit_fn = func() -> void: quits[0] += 1
	assert_false(t.quit_button.visible, "no Quit on web")
	t._unhandled_input(_esc())
	assert_eq(quits[0], 0, "Esc does not quit on web")
	t.quit_button.pressed.emit()
	assert_eq(quits[0], 0, "and neither does the hidden button")


func test_web_title_entries_request_the_shell() -> void:
	var t := _title(true)
	var asked: Array[String] = []
	t.web_request = func(kind: String) -> void: asked.append(kind)
	t.reimport.pressed.emit()
	t.export_save_button.pressed.emit()
	t.import_save_button.pressed.emit()
	assert_eq(asked, ["reimport", "export_save", "import_save"] as Array[String])
	var fs := [0]
	t.fullscreen_toggle = func() -> void: fs[0] += 1
	t.fullscreen_button.pressed.emit()
	assert_eq(fs[0], 1, "Fullscreen entry")
	for b: Control in [t.fullscreen_button, t.export_save_button, t.import_save_button]:
		assert_true(b.visible and b.size.x > 40.0)
		assert_true(Rect2(Vector2.ZERO, t.get_viewport_rect().size).encloses(Rect2(b.position, b.size)),
			"%s is inside the view" % b.name)


# --- import screen ---------------------------------------------------------------------------------------------------

func _import_screen(web: bool) -> Control:
	WebProfile.forced = 1 if web else 0
	var s := load("res://scenes/ui/import_screen.tscn").instantiate() as Control
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(s)
	_nodes.append(s)
	return s


func test_web_import_screen_hands_over_to_the_shell() -> void:
	var s := _import_screen(true)
	var asked: Array[String] = []
	s.web_request = func(kind: String) -> void: asked.append(kind)
	assert_false(s.path_edit.visible, "no folder field on web")
	assert_false(s.browse_button.visible, "no native folder dialog on web")
	assert_false(s.import_button.disabled, "the button is always ready")
	assert_true(s.start_import(), "starting the import = handing over")
	assert_eq(asked, ["reimport"] as Array[String])
	assert_eq(s.state, "idle", "no importer process was started")
	assert_eq(s._pid, -1)


func test_desktop_import_screen_still_validates_the_folder() -> void:
	var s := _import_screen(false)
	var asked: Array[String] = []
	s.web_request = func(kind: String) -> void: asked.append(kind)
	assert_true(s.path_edit.visible and s.browse_button.visible)
	s.path_edit.text = "" # the developer's own wz_root must never start a real import here
	s._validate_now()
	assert_true(s.import_button.disabled, "no valid folder yet")
	assert_false(s.start_import())
	assert_eq(asked.size(), 0, "desktop never writes a marker")


# --- keys ------------------------------------------------------------------------------------------------------------

func test_key_bindings_reserve_browser_keys_on_web_only() -> void:
	var desktop := KeyBindings.new()
	assert_false(desktop.is_fixed(KEY_F11))
	assert_true(desktop.bind("jump", KEY_F12), "desktop may bind F12")
	WebProfile.forced = 1
	var kb := KeyBindings.new()
	for k in [KEY_F11, KEY_F12]:
		assert_true(kb.is_fixed(k), "%s stays with the browser" % OS.get_keycode_string(k))
		assert_eq(kb.fixed_label(k), "Web")
		assert_false(kb.bind("jump", k), "cannot bind a browser key")
	assert_false(kb.is_fixed(KEY_F5), "F5 is captured by the canvas (preventDefault), so it can be bound")
	assert_true(kb.bind("jump", KEY_F5))
	assert_true(kb.is_fixed(KEY_ESCAPE), "Esc stays the menu key")
