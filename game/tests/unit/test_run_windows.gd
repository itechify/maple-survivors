extends TestCase
## RunScene's in-run windows (#85) against the real asset cache (SKIP without it): the Stat hotkey opens the Stat
## window and holds the sim, Esc closes the top window before the pause menu opens, Stat opens over a level-up choice
## and keeps the choice's keys away until it closes, the status bar's Menu button opens the Menu popup and its Stat
## entry, and the Stat window shows the sim's v83 stats. Hotkeys go through RunScene.handle_hotkey (what
## _unhandled_input calls); frames are advance_frame(1/60) calls.

const DT := 1.0 / 60.0

var lib: AssetLibrary
var scene: RunScene


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	lib.free()


func _make(p_seed: int, options: Dictionary) -> RunScene:
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	var o := options.duplicate()
	o["use_flow"] = false
	s.configure("henesys_hg1", p_seed, o)
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	return s


func _frames(n: int) -> void:
	for i in n:
		scene.advance_frame(DT)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


## Levels the player up with a drop and waits until the level-up window is open; null when it did not open.
func _open_level_up() -> LevelUpWindow:
	var w := scene.world
	_frames(2)
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	var ticks := 0
	while scene.window == null and ticks < 300:
		scene.advance_frame(DT)
		ticks += 1
	return scene.window as LevelUpWindow


func test_stat_hotkey_holds_the_run_and_esc_closes_it_before_the_pause_menu() -> void:
	if not require_cache():
		return
	scene = _make(13, {"autoplay": true, "autopick": true})
	var w := scene.world
	_frames(30)
	var t := w.time
	assert_true(scene.handle_hotkey(_key(KEY_S)), "S is the Stat hotkey")
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["stat"]), "the Stat window opened")
	assert_true(scene.ui_windows.top() is StatWindow)
	assert_true(scene.ui_layer.layer > scene.windows_layer.layer, "drawn above the level-up / pause windows")
	_frames(30)
	assert_eq(w.time, t, "no sim ticks while a window is open")
	assert_eq(scene.world_root.process_mode, Node.PROCESS_MODE_DISABLED, "world animations frozen like the pause")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "the cursor shows")
	assert_true(scene.handle_hotkey(_key(KEY_ESCAPE)), "Esc used")
	assert_false(scene.ui_windows.has_windows(), "Esc closed the Stat window")
	assert_false(scene.paused, "and did not open the pause menu")
	_frames(5)
	assert_true(w.time > t, "running again")
	assert_eq(scene.world_root.process_mode, Node.PROCESS_MODE_INHERIT, "unfrozen")
	scene.handle_hotkey(_key(KEY_S))
	scene.handle_hotkey(_key(KEY_S))
	assert_false(scene.ui_windows.has_windows(), "S toggles the window closed")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_true(scene.paused and scene.window is PauseMenu, "with no window open Esc pauses")
	assert_false(scene.handle_hotkey(_key(KEY_S)) and scene.ui_windows.has_windows(), "no Stat window while paused")


func test_stat_opens_over_a_level_up_choice_and_closing_it_returns_to_the_choice() -> void:
	if not require_cache():
		return
	scene = _make(11, {})
	var w := scene.world
	var lw := _open_level_up()
	assert_true(lw != null, "the level-up window opened")
	if lw == null:
		return
	lw.input_delay = 0.0
	assert_true(scene.handle_hotkey(_key(KEY_S)), "S during the choice")
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["stat"]), "Stat opened over the choice")
	assert_true(lw.input_blocked, "the choice ignores input under the Stat window")
	lw._input(_key(KEY_1))
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "key 1 did not pick a card under the Stat window")
	assert_true(lw.is_open())
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed Stat")
	assert_eq(scene.window, lw, "back to the same choice")
	assert_false(lw.input_blocked, "the choice takes input again")
	assert_false(scene.paused, "Esc did not pause")
	assert_true(lw.handle_input(_key(KEY_1)), "1 picks now")
	assert_eq(w.state, RunWorld.PLAYING)


func test_window_hotkeys_pass_through_the_choice_windows() -> void:
	if not require_cache():
		return
	scene = _make(11, {})
	var lw := _open_level_up()
	assert_true(lw != null, "the level-up window opened")
	if lw == null:
		return
	lw.input_delay = 0.0
	assert_true(lw.passes_hotkey(_key(KEY_S)), "the choice lets the Stat hotkey through to the run")
	assert_true(lw.passes_hotkey(_key(KEY_K)), "and the Skill hotkey")
	assert_false(lw.passes_hotkey(_key(KEY_1)), "but keeps its own keys")


func test_menu_button_opens_the_menu_popup_and_its_stat_entry() -> void:
	if not require_cache():
		return
	scene = _make(13, {"autoplay": true, "autopick": true})
	var w := scene.world
	_frames(10)
	var t := w.time
	var bt := scene.hud.menu_button
	assert_true(bt != null and bt.has_art(), "the status bar's BtMenu (v83 art)")
	assert_eq(bt.process_mode, Node.PROCESS_MODE_ALWAYS, "still clickable while the HUD is frozen")
	bt.pressed.emit()
	var menu := scene.ui_windows.top() as GameMenuPopup
	assert_true(menu != null, "the Menu popup opened")
	if menu == null:
		return
	assert_true(menu.get_global_rect().end.y <= bt.get_global_rect().position.y + 1.0, "above the button")
	assert_true(menu.is_enabled("stat"))
	assert_true(menu.is_enabled("skill"), "the Skill window (#86)")
	assert_false(menu.is_enabled("key_config"))
	assert_false(menu.is_enabled("options"))
	_frames(10)
	assert_eq(w.time, t, "the popup holds the sim too")
	assert_true(menu.choose("stat"))
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["stat"]), "Menu -> Stat")
	bt.pressed.emit()
	bt.pressed.emit()
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["stat"]), "the button toggles its popup")


func test_skill_hotkey_opens_the_skill_window_and_routes_the_keys_to_it() -> void:
	if not require_cache():
		return
	scene = _make(13, {"autoplay": true, "autopick": true})
	var w := scene.world
	_frames(10)
	w.change_job(200)
	w.upgrades.apply("magic_claw_new", w)
	w.upgrades.apply("magic_claw_targets", w)
	w.upgrades.apply("magnet", w)
	var t := w.time
	assert_true(scene.handle_hotkey(_key(KEY_K)), "K is the Skill hotkey")
	var sw := scene.ui_windows.top() as SkillWindow
	assert_true(sw != null, "the Skill window opened")
	if sw == null:
		return
	_frames(10)
	assert_eq(w.time, t, "no sim ticks while it is open")
	var names := []
	for tab: Dictionary in sw.model.tabs:
		names.append(String(tab.name))
	assert_eq(names, ["Beginner", "Magician", "Star"], "the job path and the star tab")
	assert_eq(sw.tab, 1, "on the current job's tab")
	assert_true(scene.handle_hotkey(_key(KEY_DOWN)), "the run hands arrows to the top window")
	var claw_row := -1
	for i in sw.rows().size():
		if String(sw.rows()[i].key) == "magic_claw":
			claw_row = i
	while sw.selected < claw_row:
		scene.handle_hotkey(_key(KEY_DOWN))
	var tip := sw.tooltip()
	assert_eq(tip.get("key"), "magic_claw")
	assert_eq(tip.upgrades[0].text, "Twin Claw ×1: +1 target", "the real card's Upgrades line")
	assert_false("canonical" in String(tip.desc) + String(tip.current) + String(tip.next), "player-visible text")
	scene.handle_hotkey(_key(KEY_3))
	assert_eq(sw.rows().size(), 1, "3: the star tab with Magnet")
	assert_eq(String(sw.rows()[0].id), "magnet")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
	assert_false(scene.paused)


func test_skill_window_opens_over_a_level_up_choice() -> void:
	if not require_cache():
		return
	scene = _make(11, {})
	var w := scene.world
	var lw := _open_level_up()
	assert_true(lw != null, "the level-up window opened")
	if lw == null:
		return
	lw.input_delay = 0.0
	assert_true(scene.handle_hotkey(_key(KEY_K)), "K during the choice")
	assert_true(scene.ui_windows.top() is SkillWindow, "Skill opened over the choice")
	assert_true(lw.input_blocked)
	scene.handle_hotkey(_key(KEY_1))
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "1 switched the Skill tab, it did not pick a card")
	assert_eq((scene.ui_windows.top() as SkillWindow).tab, 0)
	scene.handle_hotkey(_key(KEY_K))
	assert_false(scene.ui_windows.has_windows(), "K toggles it closed")
	assert_eq(scene.window, lw, "back to the choice")
	assert_true(lw.handle_input(_key(KEY_1)), "1 picks now")
	assert_eq(w.state, RunWorld.PLAYING)


func test_stat_window_shows_the_sims_v83_stats() -> void:
	if not require_cache():
		return
	scene = _make(13, {"autoplay": true, "autopick": true})
	_frames(10)
	var ps := scene.world.player_state
	scene.handle_hotkey(_key(KEY_S))
	var sw := scene.ui_windows.top() as StatWindow
	assert_true(sw != null, "open")
	if sw == null:
		return
	assert_eq(sw.value_text("name"), RunScene.DEFAULT_NAME, "the character name placeholder")
	assert_eq(sw.value_text("job"), "Beginner")
	assert_eq(sw.value_text("level"), str(int(ps.level)))
	assert_eq(sw.value_text("hp"), "%d / %d" % [int(ps.hp), int(ps.max_hp)])
	assert_eq(sw.value_text("mp"), "%d / %d" % [int(ps.mp), int(ps.max_mp)])
	for stat: String in ["str", "dex", "int", "luk"]:
		assert_eq(sw.value_text(stat), str(int(ps[stat])), stat)
	assert_eq(sw.value_text("ap"), "0", "AP is spent automatically")
	assert_eq(sw.value_text("weapon_def"), str(int(ps.pdd)))
	assert_eq(sw.value_text("magic_def"), str(int(ps.mdd)))
	assert_eq(sw.value_text("avoid"), str(int(ps.avoid)))
	assert_eq(sw.value_text("speed"), "100%", "speed points as the v83 percentage")
	assert_eq(sw.value_text("jump"), "100%")
	for unmodelled: String in ["guild", "fame", "hands"]:
		assert_eq(sw.value_text(unmodelled), "-", "%s is not in the sim" % unmodelled)
	assert_false(sw.ap_buttons_visible(), "read-only: no +AP buttons")
	assert_true(sw.show_detail, "the detail panel is open")
