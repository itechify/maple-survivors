extends TestCase
## The Skill window, Key Config, quick slot and HUD meter for a Night Lord (412; spec #383, NL11 #410): the tabs follow the
## lineage (Thief 400, Assassin 410, Hermit 411, Night Lord 412, after the Common tab), every skill sits on the tab of its own
## job, and a test fails if a skill the run owns is on no tab. Flash Jump has its Key Config tray slot, its default X key and its
## quick-slot cell; the meso charge is a ten-pip row (HudMeter) beside the skill bar. The model tests use the synthetic books of
## the Night Lord fixtures and the canonical job names (no cache); the RunScene test (SKIP without the cache) drives the real
## window through its hotkeys. Night Lord ships `playable: true` since NL12 #411.

const NF := preload("res://tests/fixtures/night_lord_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Tab -> the keys its book holds, ordered by skill id (the window sorts by id).
const TABS := {400: ["lucky_seven"], 410: ["drain"], 411: ["shadow_partner", "shadow_meso", "avenger", "flash_jump"],
	412: ["ninja_ambush", "triple_throw", "ninja_storm"]}

var lib: AssetLibrary # only the real-cache RunScene test opens it
var scene: RunScene
var cfg_path := TestCase.test_dir("skill_window_night_lord.cfg")
var settings: GameSettings
var _nodes: Array[Node] = []
var _saved_map: Dictionary = {}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(cfg_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path + suffix))
	_saved_map = {}
	for a: StringName in InputMap.get_actions():
		_saved_map[a] = InputMap.action_get_events(a).duplicate()
	InputMap.load_from_project_settings()
	settings = GameSettings.new(cfg_path)


func after_each() -> void:
	DataRepo.patch = {}
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	settings.free()
	if lib != null:
		lib.free()
		lib = null
	for a: StringName in _saved_map:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
			for e: InputEvent in _saved_map[a]:
				InputMap.action_add_event(a, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _world() -> RunWorld:
	var w := RunWorld.new(NF.setup("quiet", 410, RF.quiet_data()))
	RF.place_player(w, 400)
	return w


func _model(w: RunWorld) -> SkillWindowModel:
	return SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 412, SkillText.new(w.book, {}))


static func _tab_names(m: SkillWindowModel) -> Array:
	return m.tabs.map(func(t: Dictionary) -> String: return String(t.name))


static func _row_keys(tab: Dictionary) -> Array:
	return tab.rows.map(func(r: Dictionary) -> String: return String(r.key))


## The keys the run owns (the loadout's skills, learned or started) that no tab of `m` lists. Empty when the window is complete.
static func _unlisted(w: RunWorld, m: SkillWindowModel) -> Array:
	var listed := {}
	for t: Dictionary in m.tabs:
		for r: Dictionary in t.rows:
			listed[String(r.key)] = true
	var out: Array = []
	for key: String in w.loadout.order:
		if not listed.has(key):
			out.append(key)
	return out


func test_tabs_follow_the_lineage_400_410_411_412_after_common() -> void:
	var m := _model(_world())
	assert_eq(_tab_names(m), ["Common", "Thief", "Assassin", "Hermit", "Night Lord"])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.job_id)), [0, 400, 410, 411, 412])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.tier)), [0, 1, 2, 3, 4], "glyphs 0, I, II, III, IV")
	for t: Dictionary in m.tabs.slice(1):
		assert_eq(t.book_icon, "Skill.wz/%d.img/info/icon" % int(t.job_id))


func test_every_skill_sits_on_the_tab_of_its_own_job_in_skill_id_order() -> void:
	var w := _world()
	var m := _model(w)
	for i in 4:
		var tab: Dictionary = m.tabs[i + 1]
		assert_eq(_row_keys(tab), TABS[int(tab.job_id)], "the %s tab" % tab.name)
		for r: Dictionary in tab.rows:
			assert_eq(int(w.book.def(String(r.key)).job), int(tab.job_id), "%s is a %s skill" % [r.key, tab.name])
	assert_eq(m.tabs[0].rows.size(), 9, "the Common tab keeps the nine passives")


func test_the_whole_pool_and_flash_jump_are_listed_and_no_owned_skill_is_on_no_tab() -> void:
	var w := _world()
	var m := _model(w)
	var listed := []
	for t: Dictionary in m.tabs.slice(1):
		listed.append_array(_row_keys(t))
	for key: String in w.jobs.skill_pool(412) + ["flash_jump"]:
		assert_true(key in listed, "%s is on a tab" % key)
	assert_eq(listed.size(), 8 + 1, "the eight pool skills and Flash Jump, each once")
	assert_eq(_unlisted(w, m), [], "everything the run starts with is listed")
	# The guard fails when it should: a skill of a job outside the lineage (here a Hero skill) sits on no Night Lord tab.
	w.book.defs["stray"] = {"name": "Stray", "job": 112, "kind": "passive"}
	w.loadout.ranks["stray"] = 1
	w.loadout.order.append("stray")
	assert_eq(_unlisted(w, _model(w)), ["stray"], "an owned skill on no tab is reported")


func test_every_owned_skill_stays_listed_as_the_bot_fills_the_slots() -> void:
	var w := _world()
	for key in ["drain", "avenger", "triple_throw", "ninja_storm", "shadow_partner"]:
		assert_true(w.learn_skill(key), key)
	var m := _model(w)
	assert_eq(_unlisted(w, m), [])
	var learned := {}
	for t: Dictionary in m.tabs.slice(1):
		for r: Dictionary in t.rows:
			learned[String(r.key)] = bool(r.learned)
	for key in ["lucky_seven", "flash_jump", "drain", "avenger", "triple_throw", "ninja_storm", "shadow_partner"]:
		assert_true(learned[key], "%s reads as learned" % key)
	assert_false(learned["ninja_ambush"], "an offered skill is greyed until taken")
	assert_false(learned["shadow_meso"])


func test_the_tooltip_of_a_night_lord_skill_reads_its_rank() -> void:
	var m := _model(_world())
	var tip := m.skill_tooltip("lucky_seven")
	assert_eq(tip.key, "lucky_seven")
	assert_true(int(tip.level) >= 1)
	assert_true(tip.cooldown > 0.0, "an active skill shows its cooldown")
	assert_true(int(tip.next_level) > int(tip.level), "and the next rank's level")


func test_the_flash_jump_tooltip_states_its_distance_at_the_rank_now() -> void:
	# Review S8 (spec Presentation): the card / window text carries the Flash Jump distance.
	var w := _world()
	var text := SkillText.new(w.book)
	for pair: Array in [[1, 1, 140.0], [40, 20, 280.0]]:
		w._level_ranks(int(pair[0]))
		var stats := w.loadout.stats("flash_jump")
		assert_near(float(stats.flash_distance), float(pair[2]), 1e-6, "stats at Lv%d" % pair[0])
		assert_near(float(stats.flash_distance), w.flash_jump_distance("flash_jump"), 1e-9, "the same number the flash uses")
		var line := text.level_line("flash_jump", w.loadout.level("flash_jump"), stats)
		assert_true(("Flash: %d px" % int(pair[2])) in line, "Lv%d line: %s" % [pair[0], line])
	assert_false(w.loadout.stats("lucky_seven").has("flash_distance"), "other skills carry no flash distance")


# --- Flash Jump's key and quick slot, the meso charge row ---------------------------------------------------------------

func test_flash_jump_has_a_key_config_tray_slot_on_x_and_a_quick_slot_cell() -> void:
	var w := _world()
	var keys := w.manual_skill_keys()
	assert_eq(keys.size(), 1)
	var kc := KeyConfigWindow.new(settings, keys)
	_nodes.append(kc)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(kc)
	assert_eq(kc.tray_rect("flash_jump").size, Vector2(32, 32), "a Night Lord's Key Config tray holds Flash Jump")
	assert_eq(kc.draft.action_on(KEY_X), "flash_jump", "X is its default key")
	var plain := KeyConfigWindow.new(settings, [])
	_nodes.append(plain)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(plain)
	assert_eq(plain.tray_rect("flash_jump"), Rect2(), "a job without it has no slot")
	var quick := HudQuickSlot.new()
	_nodes.append(quick)
	quick.update({"potions": {}}, {"movement_skill": HudQuickSlot.movement_skill_of(keys)})
	assert_eq(quick.cell("flash_jump").caption, "X", "the quick-slot movement cell shows Flash Jump on X")
	assert_eq(quick.cell("flash_jump").icon_path, "Skill.wz/411.img/skill/4111006/icon")


func test_the_meso_charge_is_a_ten_pip_row_that_starts_empty() -> void:
	var w := _world()
	var snap: Dictionary = w.meter.snapshot()
	assert_eq(snap.id, "meso_charge")
	assert_eq(int(snap.max), 10)
	assert_eq(int(snap.value), 0)
	assert_eq(String(snap.art), "Item.wz/Special/0900.img/09000002/iconRaw")
	var hud := HudMeter.new()
	_nodes.append(hud)
	hud.update(w.player_state, {"meter": snap})
	assert_eq(hud.pip_count(), 10)
	assert_eq(hud.filled_count(), 0)
	hud.update(w.player_state, {"meter": {"id": "meso_charge", "value": 4, "max": 10, "art": snap.art}})
	assert_eq(hud.filled_count(), 4, "lit pips for the held charge")
	var right_edge := 244.0 + 9.0 * HudMeter.PITCH + HudMeter.RADIUS + 1.0
	assert_true(right_edge < 800.0 - 80.0, "the row ends well inside the 800 px screen (%s)" % right_edge)


func test_a_non_night_lord_has_no_meso_charge_row() -> void:
	var w := RF.quiet_world(400, 7)
	assert_true(w.meter.snapshot().is_empty())


# --- The real window ----------------------------------------------------------------------------------------------------

func test_a_412_run_opens_the_skill_window_on_the_night_lord_tab_and_every_tab_has_rows() -> void:
	if not require_cache():
		return
	lib = AssetLibrary.new()
	lib.open()
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 412})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 412)
	var t := w.time
	assert_true(scene.handle_hotkey(_key(KEY_K)), "K is the Skill hotkey")
	var sw := scene.ui_windows.top() as SkillWindow
	assert_true(sw != null, "the Skill window opened")
	if sw == null:
		return
	for i in 10:
		scene.advance_frame(DT)
	assert_eq(w.time, t, "no sim ticks while it is open")
	assert_eq(sw.model.tabs.map(func(tab: Dictionary) -> String: return String(tab.name)),
		["Common", "Thief", "Assassin", "Hermit", "Night Lord"])
	assert_eq(sw.tab, 4, "on the current job's tab (the fourth job, the fifth tab)")
	assert_eq(_unlisted(w, sw.model), [], "no skill the run owns is on no tab")
	for i in 5:
		scene.handle_hotkey(_key(KEY_1 + i))
		assert_eq(sw.tab, i)
		assert_true(sw.rows().size() > 0, "every lineage tab has rows")
	scene.handle_hotkey(_key(KEY_1))
	assert_eq(sw.rows().size(), 9, "Common contains nine passives")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
