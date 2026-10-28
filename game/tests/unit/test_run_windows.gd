extends TestCase
## RunScene's in-run windows (#85) against the real asset cache (SKIP without it): the Stat hotkey opens the Stat
## window and holds the sim, Esc closes the top window before the pause menu opens, Stat opens over a level-up choice
## and keeps the choice's keys away until it closes, the status bar's Menu button opens the Menu popup and its Stat
## entry, and the Stat window shows the sim's v83 stats. Hotkeys go through RunScene.handle_hotkey (what
## _unhandled_input calls); frames are advance_frame(1/60) calls. The last tests cover the hold and the Esc order on
## a synthetic world without the cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
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
	s.configure("henesys", p_seed, o)
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


func test_reserved_f3_dispatch_toggles_performance_and_the_valid_window_key_still_opens() -> void:
	if not require_cache():
		return
	var saved := InputMap.action_get_events("stat_window").duplicate()
	var cfg := TestCase.test_dir("run_f3_settings.cfg")
	var file := ConfigFile.new()
	file.set_value("input", "stat_window", [KEY_F3, KEY_F])
	file.save(cfg)
	var temp := GameSettings.new(cfg)
	temp.apply_bindings()
	scene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	scene.library = lib
	scene.settings = temp
	scene.configure("henesys", 13, {"use_flow": false})
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(scene)
	assert_eq(temp.binding_keys("stat_window"), PackedInt32Array([KEY_F]), "F3 is removed before input dispatch")
	assert_false(bool(scene.get("_perf_on")))
	scene._unhandled_input(_key(KEY_F3))
	assert_true(bool(scene.get("_perf_on")), "the dispatch path toggles the reserved overlay")
	assert_false(scene.ui_windows.has_windows(), "F3 opens no inspection window")
	scene._unhandled_input(_key(KEY_F))
	assert_true(scene.ui_windows.top() is StatWindow, "the retained binding reaches window dispatch")
	scene._unhandled_input(_key(KEY_F3))
	assert_false(bool(scene.get("_perf_on")), "F3 toggles off while Stat holds the run")
	scene.free()
	scene = null
	temp.free()
	InputMap.action_erase_events("stat_window")
	for event: InputEvent in saved:
		InputMap.action_add_event("stat_window", event)


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
	assert_true(menu.is_enabled("key_config"), "Key Config (#87)")
	assert_true(menu.is_enabled("options"), "Options (#87)")
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
	RF.as_job(w, 200)
	w.upgrades.apply("magic_claw_new", w)
	w.loadout.add_skill_mod("magic_claw", "count", "add", 1.0)
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
	assert_eq(names, ["Magician"], "the job line, with no Beginner or star tab")
	assert_eq(sw.tab, 0, "on the current job's tab")
	assert_true(scene.handle_hotkey(_key(KEY_DOWN)), "the run hands arrows to the top window")
	var claw_row := -1
	for i in sw.rows().size():
		if String(sw.rows()[i].key) == "magic_claw":
			claw_row = i
	while sw.selected < claw_row:
		scene.handle_hotkey(_key(KEY_DOWN))
	var tip := sw.tooltip()
	assert_eq(tip.get("key"), "magic_claw")
	assert_true(tip.upgrades.is_empty(), "retired standalone cards have no Upgrades rows")
	assert_eq(w.loadout.stats("magic_claw").count, 2, "effective modifier remains in the skill stats")
	assert_false("canonical" in String(tip.desc) + String(tip.current) + String(tip.next), "player-visible text")
	scene.handle_hotkey(_key(KEY_2))
	assert_eq(sw.tab, 0, "2: there is no second tab (no Beginner or star tab), so the tab is unchanged")
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


func test_stat_window_shows_main_stats_as_total_with_base_plus_equipment_bonus() -> void:
	var sw := StatWindow.new({"str": 15, "str_bonus": 3, "dex": 5, "dex_bonus": 0, "int": 4, "luk": 9, "luk_bonus": 5})
	assert_eq(sw.value_text("str"), "15 (12+3)", "v83: total (base+bonus) when equipment adds")
	assert_eq(sw.value_text("dex"), "5", "no bonus: just the total")
	assert_eq(sw.value_text("int"), "4")
	assert_eq(sw.value_text("luk"), "9 (4+5)")
	sw.free()


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
	assert_eq(sw.value_text("job"), "Arch Mage (Fire, Poison)", "a fresh character is the only playable job, 212")
	assert_eq(sw.value_text("level"), str(int(ps.level)))
	assert_eq(sw.value_text("hp"), "%d / %d" % [int(ps.hp), int(ps.max_hp)])
	assert_eq(sw.value_text("mp"), "-", "no MP row value (no MP, #285)")
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


# --- Equip / Item (#108) -------------------------------------------------------------------------------------------

func test_equip_and_item_hotkeys_open_their_windows_hold_the_run_and_stack_with_the_others() -> void:
	if not require_cache():
		return
	scene = _make(13, {"autoplay": true, "autopick": true})
	var w := scene.world
	_frames(30)
	var t := w.time
	assert_true(scene.handle_hotkey(_key(KEY_E)), "E is the Equip hotkey")
	var ew := scene.ui_windows.top() as EquipWindow
	assert_true(ew != null, "the Equip window opened")
	_frames(10)
	assert_eq(w.time, t, "no sim ticks while it is open")
	assert_true(scene.handle_hotkey(_key(KEY_I)), "I is the Item hotkey")
	var iw := scene.ui_windows.top() as ItemWindow
	assert_true(iw != null, "the Item window opened")
	scene.handle_hotkey(_key(KEY_S))
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["equip", "item", "stat"]), "the three stack")
	if ew == null or iw == null:
		return
	assert_eq(ew.worn_id("weapon"), 1302000, "the Equip window shows the creation sword")
	assert_eq(ew.worn_id("top"), 1040002)
	assert_eq(iw.meso_text(), InventoryModel.meso_text(w.mesos), "the meso line shows the character's mesos")
	assert_true(ew.position.x + ew.size.x <= iw.position.x, "they open side by side, not on top of each other")
	assert_eq(ew.item_name(1302000), "Sword", "String.wz/Eqp names")
	assert_eq(ew.item_name(2000000), "Red Potion", "String.wz/Consume names")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["equip", "item"]), "Esc closes the front window")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed them all")
	assert_false(scene.paused, "without pausing")
	_frames(5)
	assert_true(w.time > t, "running again")
	scene.handle_hotkey(_key(KEY_I))
	scene.handle_hotkey(_key(KEY_I))
	assert_false(scene.ui_windows.has_windows(), "I toggles the Item window closed")


func test_taking_the_sword_off_in_the_equip_window_redraws_the_character_bare_handed() -> void:
	if not require_cache():
		return
	scene = _make(13, {"autoplay": true, "autopick": true})
	_frames(10)
	scene.handle_hotkey(_key(KEY_E))
	var ew := scene.ui_windows.top() as EquipWindow
	assert_true(ew != null)
	if ew == null:
		return
	assert_true(1302000 in scene.avatar.look.equips, "drawn with the sword")
	assert_eq(ew.take_off("weapon"), "")
	assert_false(1302000 in scene.avatar.look.equips, "the look followed the change at once")
	assert_eq(scene.world.weapon_id(), 0)
	var notices := []
	ew.notice.connect(func(t: String) -> void: notices.append(t))
	scene.handle_hotkey(_key(KEY_I))
	var iw := scene.ui_windows.top() as ItemWindow
	assert_eq(iw.cell(0).get("id"), 1302000, "the Item window lists the sword")
	assert_eq(iw.wear(0), "", "wearing it again from the Item window")
	assert_true(1302000 in scene.avatar.look.equips)


func test_equip_and_item_open_over_a_level_up_choice() -> void:
	if not require_cache():
		return
	scene = _make(11, {})
	var lw := _open_level_up()
	assert_true(lw != null, "the level-up window opened")
	if lw == null:
		return
	lw.input_delay = 0.0
	assert_true(lw.passes_hotkey(_key(KEY_E)), "the choice lets the Equip hotkey through")
	assert_true(lw.passes_hotkey(_key(KEY_I)), "and the Item hotkey")
	assert_true(scene.handle_hotkey(_key(KEY_E)))
	assert_true(scene.ui_windows.top() is EquipWindow and lw.input_blocked, "Equip opened over the choice")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_eq(scene.window, lw, "back to the choice")


# --- Key Config / Options (#87) ------------------------------------------------------------------------------------

func test_pause_menu_opens_key_config_and_options_over_the_paused_run() -> void:
	if not require_cache():
		return
	var cfg := TestCase.test_dir("run_windows_settings.cfg")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(cfg + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg + suffix))
	var temp := GameSettings.new(cfg)
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.settings = temp # never the live autoload: OK would write the developer's settings.cfg
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	_frames(10)
	scene.handle_hotkey(_key(KEY_ESCAPE))
	var pm := scene.window as PauseMenu
	assert_true(pm != null and scene.paused, "paused")
	if pm == null:
		temp.free()
		return
	assert_true(pm.activate(1, false), "pause menu: Key Config")
	var kc := scene.ui_windows.top() as KeyConfigWindow
	assert_true(kc != null, "the Key Config window opened over the pause menu")
	assert_true(kc != null and kc.settings == temp, "it edits the run's settings")
	assert_true(pm.input_blocked and pm.is_open(), "the pause menu waits underneath")
	assert_true(pm.activate(2, false), "Options too (the pause menu stays usable from code)")
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["key_config", "options"]))
	assert_true(pm.activate(1, false))
	assert_eq(scene.ui_windows.ids(), PackedStringArray(["options", "key_config"]),
		"choosing an open window brings it to the front instead of closing it")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed both windows")
	assert_true(scene.paused and scene.window == pm and not pm.input_blocked, "still paused, the menu takes input")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.paused, "Esc resumes")
	assert_false(FileAccess.file_exists(cfg), "nothing was saved")
	scene.free()
	scene = null
	temp.free()


# --- without the asset cache -------------------------------------------------------------------------------------

## A RunScene on a synthetic world (no asset cache, never added to the tree, like the other bare scenes): its window
## stack holds plain windows registered as "stat" and "options", and the pause menu goes to a layer of its own. Only
## held frames can run on it (they skip the renderers), which is what these tests drive. Returns [scene, nodes to free].
func _bare_scene() -> Array:
	var s := RunScene.new()
	s.world = RF.quiet_world()
	var root := (Engine.get_main_loop() as SceneTree).current_scene
	s.windows_layer = CanvasLayer.new()
	root.add_child(s.windows_layer)
	var stack := WindowStack.new()
	root.add_child(stack)
	for id: String in ["stat", "options", "equip", "item"]:
		stack.register(id, func() -> UiWindow:
			var w := UiWindow.new()
			w.window_id = id
			w.size = Vector2(120, 80)
			return w)
	s.use_window_stack(stack)
	return [s, [s.windows_layer, stack]]


func _free_bare(made: Array) -> void:
	(made[0] as RunScene).free()
	for n: Node in made[1]:
		n.free()


func test_no_sim_ticks_while_an_in_run_window_is_open_without_the_cache() -> void:
	var made := _bare_scene()
	var s: RunScene = made[0]
	var t := s.world.time
	assert_eq(s.world.state, RunWorld.PLAYING, "a running world")
	assert_true(s.handle_hotkey(_key(KEY_S)), "S opens the Stat window")
	assert_eq(s.ui_windows.ids(), PackedStringArray(["stat"]))
	for i in 30:
		s.advance_frame(DT)
	assert_eq(s.world.time, t, "no sim ticks while a window is open")
	assert_true(s.handle_hotkey(_key(KEY_E)), "E opens the Equip window (#108)")
	assert_true(s.handle_hotkey(_key(KEY_I)), "I opens the Item window")
	assert_eq(s.ui_windows.ids(), PackedStringArray(["stat", "equip", "item"]), "the three stack")
	for i in 3:
		s.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(s.ui_windows.has_windows(), "Esc closed them one by one")
	assert_false(s.paused)
	s.handle_hotkey(_key(KEY_S))
	assert_true(s.handle_hotkey(_key(KEY_ESCAPE)))
	assert_true(s.handle_hotkey(_key(KEY_ESCAPE)), "Esc with nothing open pauses")
	assert_true(s.toggle_window("options"), "Options opens over the pause menu")
	for i in 30:
		s.advance_frame(DT)
	assert_eq(s.world.time, t, "nor while a window is open over the paused run")
	_free_bare(made)


func test_esc_closes_the_top_window_then_pauses_then_resumes_without_the_cache() -> void:
	var made := _bare_scene()
	var s: RunScene = made[0]
	s.toggle_window("stat")
	assert_true(s.handle_hotkey(_key(KEY_ESCAPE)), "Esc used")
	assert_false(s.ui_windows.has_windows(), "Esc closed the Stat window first")
	assert_false(s.paused, "and did not pause")
	s.handle_hotkey(_key(KEY_ESCAPE))
	assert_true(s.paused and s.window is PauseMenu, "with no window open Esc opens the pause menu")
	s.toggle_window("options")
	s.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(s.ui_windows.has_windows(), "Esc over the pause menu closes Options first")
	assert_true(s.paused and s.window is PauseMenu, "the pause menu stays")
	s.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(s.paused, "the next Esc resumes")
	assert_eq(s.window, null, "and closes the pause menu")
	_free_bare(made)


# --- an equipment drop picked up under open Equip / Item windows (spec #33, #113) --------------------------------------

func test_an_open_item_window_refreshes_when_an_equipment_drop_is_picked_up() -> void:
	if not require_cache():
		return
	scene = _make(13, {})
	var w := scene.world
	_frames(5)
	scene.handle_hotkey(_key(KEY_I))
	var iw := scene.ui_windows.top() as ItemWindow
	assert_true(iw != null, "the Item window opened")
	if iw == null:
		return
	var had: int = w.equipment.inventory.size()
	var drawn: int = iw.get("refresh_count") if iw.get("refresh_count") != null else -1
	# The run is held while a window is open, so nothing is picked up through advance_frame; drive the sim directly,
	# as a world that keeps running under the window (a bot's, a later feature's) would.
	w.spawn_equipment(w.player.pos, {"id": 1002001, "stats": {"incPDD": 4}, "slots": 7, "scrolls": 0})
	var events := []
	for i in 120:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
		if w.equipment.inventory.size() > had:
			break
	assert_eq(w.equipment.inventory.size(), had + 1, "the magnet put the drop in the Equip tab")
	scene.handle_events(events)
	assert_eq(iw.cell(had).get("id"), 1002001, "the Item window's Equip tab lists the drop")
	var after: Variant = iw.get("refresh_count")
	assert_true(after != null and int(after) > drawn, "and the window redrew for it")
