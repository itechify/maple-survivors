extends TestCase
## The HP / MP ALERT levels of the Options window (spec #34, ticket #121): GameSettings keeps them in [alert] (defaults
## 30% / 20%, tier C), the Options sliders set them, a persistent round takes them from the flow's settings at launch
## and follows them live, and a tool round (--run, balance, playtest with --account) ignores the user's settings.
## Scene tests need the real asset cache and SKIP without it.

var _nodes: Array[Node] = []
var _scenes: Array[Node] = []
var _windows: Array[Control] = []


func after_each() -> void:
	for scene in _scenes:
		if is_instance_valid(scene):
			scene.free()
	_scenes.clear()
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	for w in _windows:
		if is_instance_valid(w):
			w.free()
	_windows.clear()


func _cfg(name: String) -> String:
	var path := TestCase.test_dir(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return path


func _settings(name: String) -> GameSettings:
	var s := GameSettings.new(_cfg(name))
	_nodes.append(s)
	return s


func test_defaults_are_the_tier_c_levels_and_a_missing_section_loads_them() -> void:
	var path := _cfg("alert_defaults.cfg")
	var s := GameSettings.new(path)
	_nodes.append(s)
	assert_near(s.alert_hp, 0.3, 1e-6, "HP ALERT 30% (tier C)")
	assert_near(s.alert_mp, 0.2, 1e-6, "MP ALERT 20% (tier C)")
	assert_eq(s.alert_levels(), {"hp": 0.3, "mp": 0.2})
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm", 0.5)
	cfg.save(path)
	var old := GameSettings.new(path)
	_nodes.append(old)
	assert_near(old.alert_hp, 0.3, 1e-6, "a file from before #121 loads the defaults")
	assert_near(old.alert_mp, 0.2, 1e-6)


func test_alert_levels_round_trip_through_settings_cfg_and_defaults_are_not_written() -> void:
	var path := _cfg("alert_round_trip.cfg")
	var s := GameSettings.new(path)
	_nodes.append(s)
	s.set_alert("hp", 0.65)
	s.set_alert("mp", 0.0)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(path), OK)
	assert_near(float(cfg.get_value("alert", "hp")), 0.65, 1e-6)
	assert_near(float(cfg.get_value("alert", "mp")), 0.0, 1e-6, "0 = do not alert is a real choice, so it is written")
	var t := GameSettings.new(path)
	_nodes.append(t)
	assert_near(t.alert_hp, 0.65, 1e-6)
	assert_near(t.alert_mp, 0.0, 1e-6)
	t.set_alert("mp", 0.2)
	cfg = ConfigFile.new()
	cfg.load(path)
	assert_false(cfg.has_section_key("alert", "mp"), "back to the default -> key removed")
	assert_true(cfg.has_section_key("alert", "hp"))


func test_alert_levels_are_clamped_and_unknown_kinds_are_ignored() -> void:
	var s := _settings("alert_clamp.cfg")
	s.set_alert("hp", 1.5)
	assert_near(s.alert_hp, 1.0, 1e-6)
	s.set_alert("mp", -0.4)
	assert_near(s.alert_mp, 0.0, 1e-6)
	s.set_alert("xp", 0.5)
	assert_eq(s.alert_levels(), {"hp": 1.0, "mp": 0.0})


func _click(w: OptionsWindow, local: Vector2, pressed := true) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = local
	w._window_gui_input(mb, local)


func _motion(w: OptionsWindow, local: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = local
	w._window_gui_input(mm, local)


func test_options_sliders_set_the_alert_levels_from_do_not_alert_to_100_percent() -> void:
	var path := _cfg("alert_sliders.cfg")
	var s := GameSettings.new(path)
	_nodes.append(s)
	var w := OptionsWindow.new(s)
	_windows.append(w)
	var hp := w.slider_rect("hp_alert")
	var mp := w.slider_rect("mp_alert")
	var hp_y := hp.get_center().y
	var mp_y := mp.get_center().y
	_click(w, Vector2(hp.position.x + hp.size.x * 0.5, hp_y))
	assert_near(s.alert_hp, 0.5, 1e-6, "the middle of the HP track is 50%")
	_click(w, Vector2(hp.position.x + hp.size.x * 0.5, hp_y), false)
	_motion(w, Vector2(hp.position.x + hp.size.x * 0.3, hp_y))
	assert_near(s.alert_hp, 0.5, 1e-6, "no drag after the release")
	_click(w, Vector2(mp.position.x, mp_y))
	assert_near(s.alert_mp, 0.0, 1e-6, "the start of the track is do not alert")
	_click(w, Vector2(mp.position.x, mp_y), false)
	_click(w, Vector2(mp.end.x + 8.0, mp_y))
	assert_near(s.alert_mp, 1.0, 1e-6, "the end of the track is 100%")
	_click(w, Vector2(mp.end.x + 8.0, mp_y), false)
	_click(w, Vector2(hp.position.x + hp.size.x * 0.23, hp_y))
	assert_near(s.alert_hp, 0.25, 1e-6, "levels snap to 5%")
	_motion(w, Vector2(hp.position.x + hp.size.x * 0.3, hp_y))
	assert_near(s.alert_hp, 0.3, 1e-6, "dragging moves the level")
	_click(w, Vector2(hp.position.x + hp.size.x * 0.3, hp_y), false)
	var fresh := GameSettings.new(path)
	_nodes.append(fresh)
	assert_near(fresh.alert_hp, 0.3, 1e-6, "every slider change is saved at once")
	assert_near(fresh.alert_mp, 1.0, 1e-6)


func test_the_options_window_has_the_two_alert_rows_below_the_existing_ones() -> void:
	var w := OptionsWindow.new(_settings("alert_rows.cfg"))
	_windows.append(w)
	assert_eq(w.row_y("hp_alert"), 152.0)
	assert_eq(w.row_y("mp_alert"), 182.0)
	assert_eq(w.row_y("movement"), 122.0, "the existing rows keep their places")
	assert_near(w.size.y, 32.0 + 6 * 30.0 + 36.0, 1e-6)


func test_a_persistent_round_gets_the_settings_alert_levels_and_follows_them_live() -> void:
	if not require_cache():
		return
	var s := _settings("alert_round.cfg")
	s.set_alert("hp", 0.45)
	s.set_alert("mp", 0.6)
	var flow := _flow()
	flow.settings = s
	flow.create_character("Alert121")
	flow.start_round("henesys_hg1", 7)
	var run := flow.current as RunScene
	assert_true(run != null, "the round is running")
	if run == null:
		return
	_scenes.append(run)
	assert_eq(run.options.get("settings_alert"), {"hp": 0.45, "mp": 0.6})
	assert_eq(run.world.alert, {"hp": 0.45, "mp": 0.6}, "the setup carries the settings' levels")
	s.set_alert("mp", 0.9)
	assert_eq(run.world.alert, {"hp": 0.45, "mp": 0.9}, "a change mid-round takes effect at once")
	s.set_alert("hp", 0.0)
	assert_near(run.world.alert.hp, 0.0, 1e-6)


func test_a_tool_round_ignores_the_user_settings_and_takes_its_levels_from_the_account() -> void:
	if not require_cache():
		return
	var s := _settings("alert_tool.cfg")
	s.set_alert("hp", 0.9)
	s.set_alert("mp", 0.9)
	var run := _tool_run(s, {"autoplay": true, "autopick": true})
	assert_eq(run.world.alert, {"hp": 0.0, "mp": 0.0}, "no account file: do not alert")
	s.set_alert("hp", 0.1)
	assert_eq(run.world.alert, {"hp": 0.0, "mp": 0.0}, "and a later change does not reach it either")
	var path := ProjectSettings.globalize_path(_cfg("alert_tool_account.json"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"alert": {"hp": 0.4, "mp": 0.25}}))
	file.close()
	var with_account := _tool_run(s, {"autoplay": true, "autopick": true, "account": path})
	assert_eq(with_account.world.alert, {"hp": 0.4, "mp": 0.25}, "the account file's levels, not the settings'")
	s.set_alert("mp", 0.7)
	assert_eq(with_account.world.alert, {"hp": 0.4, "mp": 0.25})


## A one-off RunScene (no flow, no settings_alert option) that reads `s` as its Settings, added to the tree.
func _tool_run(s: GameSettings, options: Dictionary) -> RunScene:
	var lib := AssetLibrary.new()
	lib.open()
	_nodes.append(lib)
	var run: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.library = lib
	run.settings = s
	var o := options.duplicate()
	o["use_flow"] = false
	run.configure("henesys_hg1", 7, o)
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(run)
	_scenes.append(run)
	return run


func _flow() -> SceneFlow:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	TestCase.remove_tree(TestCase.test_dir("alert_flow"))
	flow.save = SaveData.new(TestCase.test_dir("alert_flow/save.json"))
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow
