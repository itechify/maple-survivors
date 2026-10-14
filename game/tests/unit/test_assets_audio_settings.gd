extends TestCase
## AudioService voice stealing, Settings persistence (never written on load), the view modes and key bindings.

const CFG := "user://_test_cache/settings_test.cfg"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://_test_cache"))
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func test_pick_voice_prefers_idle_then_oldest() -> void:
	assert_eq(AudioService.pick_voice(PackedByteArray([1, 0, 1]), PackedInt64Array([5, 9, 2])), 1, "first idle voice")
	assert_eq(AudioService.pick_voice(PackedByteArray([1, 1, 1]), PackedInt64Array([5, 9, 2])), 2, "steal the oldest")
	assert_eq(AudioService.MAX_VOICES, 16)


func test_settings_defaults_and_no_write_on_load() -> void:
	var s := GameSettings.new(CFG)
	assert_false(FileAccess.file_exists(CFG), "loading never creates the file")
	assert_eq(s.master_volume, 1.0)
	assert_eq(s.window_scale, 0)
	s.free()


func test_settings_round_trip_only_non_defaults() -> void:
	var s := GameSettings.new(CFG)
	s.set_volume("bgm", 0.25)
	s.set_window_scale(3)
	s.free()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(CFG), OK)
	assert_eq(cfg.get_value("audio", "bgm"), 0.25)
	assert_false(cfg.has_section_key("assets", "cache_dir"), "defaults are not written")
	assert_false(cfg.has_section_key("audio", "master"))
	var t := GameSettings.new(CFG)
	assert_eq(t.bgm_volume, 0.25)
	assert_eq(t.window_scale, 3)
	assert_eq(t.sfx_volume, 0.9)
	t.set_volume("bgm", 0.8)
	t.free()
	cfg = ConfigFile.new()
	cfg.load(CFG)
	assert_false(cfg.has_section_key("audio", "bgm"), "back to default -> key removed")


func test_fit_size_integer_scale() -> void:
	assert_eq(GameSettings.fit_size(Vector2i(1600, 1200)), Vector2i(800, 600))
	assert_eq(GameSettings.fit_size(Vector2i(800, 600)), Vector2i(800, 600))
	assert_eq(GameSettings.fit_size(Vector2i(3440, 1440)), Vector2i(1720, 720), "ultrawide fullscreen: 2x, no bars")
	assert_eq(GameSettings.fit_size(Vector2i(3440, 1417)), Vector2i(1720, 708), "maximised: 2x")
	assert_eq(GameSettings.fit_size(Vector2i(2560, 1440)), Vector2i(1280, 720))
	assert_eq(GameSettings.fit_size(Vector2i(1920, 1080)), Vector2i(1920, 1080), "1080p: 1x")
	assert_eq(GameSettings.fit_size(Vector2i(3840, 2160)), Vector2i(1280, 720), "4K: 3x")
	assert_eq(GameSettings.fit_size(Vector2i(0, 0)), Vector2i(800, 600))
	# Smaller than the base on an axis: the window's aspect, scaled down - never a view taller/wider than the window
	# at 1x (which would crop the status bar).
	assert_eq(GameSettings.fit_size(Vector2i(640, 480)), Vector2i(800, 600), "4:3, scaled down")
	assert_eq(GameSettings.fit_size(Vector2i(1024, 576)), Vector2i(1066, 600), "16:9 below 600 px high")
	assert_true(GameSettings.needs_downscale(Vector2i(1024, 576)))
	assert_false(GameSettings.needs_downscale(Vector2i(800, 600)))
	for w: Vector2i in [Vector2i(1024, 576), Vector2i(640, 480), Vector2i(1920, 1080), Vector2i(3440, 1440)]:
		var v := GameSettings.fit_size(w)
		assert_near(float(v.x) / v.y, float(w.x) / w.y, 0.01, "%s keeps the window aspect" % w)


func test_expand_size_matches_godot_project_stretch() -> void:
	# Measured in a Godot 4.7 window with the project's stretch (viewport, expand, integer): get_visible_rect().
	assert_eq(GameSettings.expand_size(Vector2i(1920, 1080)), Vector2i(1066, 600))
	assert_eq(GameSettings.expand_size(Vector2i(1024, 576)), Vector2i(1066, 600))
	assert_eq(GameSettings.expand_size(Vector2i(1600, 1200)), Vector2i(800, 600))
	assert_eq(GameSettings.expand_size(Vector2i(600, 800)), Vector2i(800, 1066), "tall window grows the height")


func test_fill_window_is_opt_in_and_persists() -> void:
	var s := GameSettings.new(CFG)
	assert_false(s.fill_window, "off by default: the documented 800x600 expand view")
	s.set_fill_window(true)
	s.free()
	var t := GameSettings.new(CFG)
	assert_true(t.fill_window)
	t.set_fill_window(false)
	t.free()
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	assert_false(cfg.has_section_key("display", "fill_window"), "default not written")


func test_key_bindings_rebind_persist_and_reset() -> void:
	const ACTION := "ms_test_rebind"
	InputMap.add_action(ACTION)
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	InputMap.action_add_event(ACTION, j)
	var s := GameSettings.new(CFG)
	assert_eq(s.binding_keys(ACTION), PackedInt32Array([KEY_J]), "project default")
	s.set_binding(ACTION, PackedInt32Array([KEY_K, KEY_L]))
	assert_eq(s.binding_keys(ACTION), PackedInt32Array([KEY_K, KEY_L]), "InputMap rebound")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(CFG), OK)
	assert_eq(cfg.get_value("input", ACTION), [KEY_K, KEY_L], "saved as physical keycodes")
	assert_false(cfg.has_section_key("input", "jump"), "untouched actions are not written")
	var t := GameSettings.new(CFG)
	assert_eq(t.bindings.get(ACTION), PackedInt32Array([KEY_K, KEY_L]), "loaded")
	t.free()
	s.reset_binding(ACTION)
	assert_eq(s.binding_keys(ACTION), PackedInt32Array([KEY_J]), "default restored")
	cfg = ConfigFile.new()
	cfg.load(CFG)
	assert_false(cfg.has_section("input"), "no overrides left")
	s.free()
	InputMap.erase_action(ACTION)


func test_project_input_map_has_the_game_design_controls() -> void:
	# GAME_DESIGN section 2 defaults (the Settings rebinding starts from these).
	for a: String in ["move_left", "move_right", "move_up", "move_down", "jump", "pause", "choice_1", "choice_2",
			"choice_3"]:
		assert_true(InputMap.has_action(a), a)
	var s := GameSettings.new(CFG)
	assert_true(KEY_ALT in s.binding_keys("jump") and KEY_SPACE in s.binding_keys("jump"), "jump: Left Alt, Space")
	assert_true(KEY_LEFT in s.binding_keys("move_left") and KEY_A in s.binding_keys("move_left"))
	assert_true(KEY_ESCAPE in s.binding_keys("pause"))
	s.free()
