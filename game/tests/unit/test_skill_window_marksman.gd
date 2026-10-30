extends TestCase
## The Skill window, Key Config and quick slot for a Marksman (322; spec #360, MS10 #370): the tabs follow the lineage (Bowman 300,
## Crossbowman 320, Sniper 321, Marksman 322, after the Common tab), every pool skill sits on the tab of its own job, and a test
## fails if a skill the run owns is on no tab. A Marksman has no skill key, so Key Config and the quick slot show nothing for
## movement. The model tests use the synthetic books of the Marksman fixtures and the canonical job names (no cache); the RunScene
## test (SKIP without the cache) drives the real window through its hotkeys. Marksman ships `playable: false` until MS11, so the
## RunScene test mirrors it playable.

const MF := preload("res://tests/fixtures/marksman_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MIRROR := {"jobs_survivor": {"jobs": {"322": {"playable": true}}}}
const DT := 1.0 / 60.0
## Tab -> the pool keys its book holds, ordered by skill id (the window sorts by id). Arrow Blow is the Bowman's (300) shared
## definition; Iron Arrow is the Crossbowman's (320).
const TABS := {300: ["arrow_blow"], 320: ["iron_arrow"],
	321: ["blizzard_crossbow", "arrow_eruption", "golden_eagle", "strafe_crossbow"],
	322: ["piercing_arrow", "dragons_breath_crossbow", "frostprey", "snipe"]}

var lib: AssetLibrary
var scene: RunScene
var cfg_path := TestCase.test_dir("skill_window_marksman.cfg")
var settings: GameSettings
var _nodes: Array[Node] = []
var _saved_map: Dictionary = {}


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()
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
	lib.free()
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
	var w := RunWorld.new(MF.setup("quiet", 370, RF.quiet_data()))
	RF.place_player(w, 400)
	return w


func _model(w: RunWorld) -> SkillWindowModel:
	return SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 322, SkillText.new(w.book, {}))


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


func test_tabs_follow_the_lineage_300_320_321_322_after_common() -> void:
	var m := _model(_world())
	assert_eq(_tab_names(m), ["Common", "Bowman", "Crossbowman", "Sniper", "Marksman"])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.job_id)), [0, 300, 320, 321, 322])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.tier)), [0, 1, 2, 3, 4], "glyphs 0, I, II, III, IV")
	for t: Dictionary in m.tabs.slice(1):
		assert_eq(t.book_icon, "Skill.wz/%d.img/info/icon" % int(t.job_id))


func test_every_pool_skill_sits_on_the_tab_of_its_own_job_in_skill_id_order() -> void:
	var w := _world()
	var m := _model(w)
	for i in 4:
		var tab: Dictionary = m.tabs[i + 1]
		assert_eq(_row_keys(tab), TABS[int(tab.job_id)], "the %s tab" % tab.name)
		for r: Dictionary in tab.rows:
			assert_eq(int(w.book.def(String(r.key)).job), int(tab.job_id), "%s is a %s skill" % [r.key, tab.name])
	assert_eq(m.tabs[0].rows.size(), 9, "the Common tab keeps the nine passives")


func test_the_whole_pool_is_listed_once_and_no_owned_skill_is_on_no_tab() -> void:
	var w := _world()
	var m := _model(w)
	var listed := []
	for t: Dictionary in m.tabs.slice(1):
		listed.append_array(_row_keys(t))
	for key: String in w.jobs.skill_pool(322):
		assert_true(key in listed, "%s is on a tab" % key)
	assert_eq(listed.size(), 10, "the ten pool skills, each once")
	assert_eq(_unlisted(w, m), [], "everything the run starts with is listed")
	# The guard fails when it should: a skill of a job outside the lineage (here a Hero skill) sits on no Marksman tab.
	w.book.defs["stray"] = {"name": "Stray", "job": 112, "kind": "passive"}
	w.loadout.ranks["stray"] = 1
	w.loadout.order.append("stray")
	assert_eq(_unlisted(w, _model(w)), ["stray"], "an owned skill on no tab is reported")


func test_every_owned_skill_stays_listed_as_the_bot_fills_the_slots() -> void:
	var w := _world()
	var taken := ["iron_arrow", "strafe_crossbow", "blizzard_crossbow", "snipe", "piercing_arrow", "golden_eagle"] # six active slots
	for key: String in taken.slice(1):
		assert_true(w.learn_skill(key), key)
	var m := _model(w)
	assert_eq(_unlisted(w, m), [])
	var learned := {}
	for t: Dictionary in m.tabs.slice(1):
		for r: Dictionary in t.rows:
			learned[String(r.key)] = bool(r.learned)
	for key: String in taken:
		assert_true(learned[key], "%s reads as learned" % key)
	for key: String in w.jobs.skill_pool(322):
		assert_true(learned.has(key), "%s is still on a tab, learned or not" % key)


func test_an_offered_but_untaken_skill_is_greyed() -> void:
	var learned := {}
	for t: Dictionary in _model(_world()).tabs.slice(1):
		for r: Dictionary in t.rows:
			learned[String(r.key)] = bool(r.learned)
	assert_true(learned["iron_arrow"], "the starting skill reads as learned")
	assert_false(learned["snipe"], "an offered skill is greyed until taken")
	assert_false(learned["frostprey"])


func test_the_tooltip_of_a_marksman_skill_reads_its_rank() -> void:
	var w := _world()
	assert_true(w.learn_skill("snipe"))
	var m := _model(w)
	var tip := m.skill_tooltip("iron_arrow")
	assert_eq(tip.key, "iron_arrow")
	assert_true(int(tip.level) >= 1)
	assert_true(tip.cooldown > 0.0, "an active skill shows its cooldown")
	assert_true(int(tip.next_level) > int(tip.level), "and the next rank's level")
	assert_eq(m.skill_tooltip("snipe").key, "snipe")


# --- no movement skill: Key Config and the quick slot -----------------------------------------------------------------------

func test_key_config_and_the_quick_slot_show_nothing_for_movement() -> void:
	var w := _world()
	var keys := w.manual_skill_keys()
	assert_eq(keys, [], "a Marksman owns no skill key")
	var kc := KeyConfigWindow.new(settings, keys)
	_nodes.append(kc)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(kc)
	for action: String in ["teleport", "teleport_fp", "dash", "rush", "flash_jump"]:
		assert_eq(kc.tray_rect(action), Rect2(), "%s has no tray slot" % action)
	var quick := HudQuickSlot.new()
	_nodes.append(quick)
	quick.update({"potions": {}}, {"movement_skill": HudQuickSlot.movement_skill_of(keys)})
	assert_eq(String(quick.cell("teleport").get("icon_path", "")), "", "no movement icon in the quick slot")


# --- The real window ----------------------------------------------------------------------------------------------------

func test_a_322_run_opens_the_skill_window_on_the_marksman_tab_and_every_tab_has_rows() -> void:
	if not require_cache():
		return
	DataRepo.patch = MIRROR.duplicate(true)
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 322})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 322)
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
		["Common", "Bowman", "Crossbowman", "Sniper", "Marksman"])
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
