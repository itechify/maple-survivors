extends TestCase
## The Skill window for a Corsair (522; spec #384, C14 #398): the tabs follow the lineage (Pirate 500, Gunslinger 520, Outlaw 521,
## Corsair 522, after the Common tab), Dash sits on the Pirate tab with Double Shot, every skill sits on the tab of its own job,
## and a test fails if a skill the run owns is on no tab. The model tests use the synthetic books of the Corsair fixtures and the
## canonical job names (no cache); the RunScene test (SKIP without the cache) drives the real window through its hotkeys.
## Corsair ships `playable: false` until C15, so the RunScene test mirrors it playable.

const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MIRROR := {"jobs_survivor": {"jobs": {"522": {"playable": true}}}}
const DT := 1.0 / 60.0
## Tab -> the keys its book holds, ordered by skill id (the window sorts by id). Dash is on the 500 tab beside Double Shot.
const TABS := {500: ["double_shot", "dash"], 520: ["invisible_shot", "grenade", "recoil_shot"],
	521: ["burst_fire", "octopus", "gaviota", "flamethrower", "ice_splitter", "homing_beacon"],
	522: ["aerial_strike", "rapid_fire", "battleship"]}

var lib: AssetLibrary
var scene: RunScene
var cfg_path := TestCase.test_dir("skill_window_corsair.cfg")
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
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["522"]["playable"] = true # in this test's data only: C15 flips the real flag
	var w := RunWorld.new(CF.setup("quiet", 398, data))
	RF.place_player(w, 400)
	return w


func _model(w: RunWorld) -> SkillWindowModel:
	return SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 522, SkillText.new(w.book, {}))


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


func test_tabs_follow_the_lineage_500_520_521_522_after_common() -> void:
	var m := _model(_world())
	assert_eq(_tab_names(m), ["Common", "Pirate", "Gunslinger", "Outlaw", "Corsair"])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.job_id)), [0, 500, 520, 521, 522])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.tier)), [0, 1, 2, 3, 4], "glyphs 0, I, II, III, IV")
	for t: Dictionary in m.tabs.slice(1):
		assert_eq(t.book_icon, "Skill.wz/%d.img/info/icon" % int(t.job_id))


func test_every_skill_sits_on_the_tab_of_its_own_job_in_skill_id_order_and_dash_is_on_the_first() -> void:
	var w := _world()
	var m := _model(w)
	for i in 4:
		var tab: Dictionary = m.tabs[i + 1]
		assert_eq(_row_keys(tab), TABS[int(tab.job_id)], "the %s tab" % tab.name)
		for r: Dictionary in tab.rows:
			assert_eq(int(w.book.def(String(r.key)).job), int(tab.job_id), "%s is a %s skill" % [r.key, tab.name])
	assert_true("dash" in _row_keys(m.tabs[1]), "Dash is on the 500 tab")
	assert_eq(m.tabs[0].rows.size(), 9, "the Common tab keeps the nine passives")


func test_the_whole_pool_and_dash_are_listed_and_no_owned_skill_is_on_no_tab() -> void:
	var w := _world()
	var m := _model(w)
	var listed := []
	for t: Dictionary in m.tabs.slice(1):
		listed.append_array(_row_keys(t))
	for key: String in w.jobs.skill_pool(522) + ["dash"]:
		assert_true(key in listed, "%s is on a tab" % key)
	assert_eq(listed.size(), 13 + 1, "the thirteen pool skills and Dash, each once; the ship's Cannon and Torpedo are no rows")
	assert_eq(_unlisted(w, m), [], "everything the run starts with is listed")
	# The guard fails when it should: a skill of a job outside the lineage (here a Hero skill) sits on no Corsair tab.
	w.book.defs["stray"] = {"name": "Stray", "job": 112, "kind": "passive"}
	w.loadout.ranks["stray"] = 1
	w.loadout.order.append("stray")
	assert_eq(_unlisted(w, _model(w)), ["stray"], "an owned skill on no tab is reported")


func test_every_owned_skill_stays_listed_and_reads_as_learned_as_the_bot_fills_the_slots() -> void:
	var w := _world()
	for key in ["recoil_shot", "ice_splitter", "gaviota", "rapid_fire", "homing_beacon"]:
		assert_true(w.learn_skill(key), key)
	var m := _model(w)
	assert_eq(_unlisted(w, m), [])
	var learned := {}
	for t: Dictionary in m.tabs.slice(1):
		for r: Dictionary in t.rows:
			learned[String(r.key)] = bool(r.learned)
	for key in ["double_shot", "dash", "recoil_shot", "ice_splitter", "gaviota", "rapid_fire", "homing_beacon"]:
		assert_true(learned[key], "%s reads as learned" % key)
	assert_false(learned["battleship"], "an offered skill is greyed until taken")
	assert_false(learned["octopus"])


func test_the_tooltip_of_a_corsair_skill_reads_its_rank_and_dash_is_a_mobility_buff() -> void:
	var m := _model(_world())
	var tip := m.skill_tooltip("double_shot")
	assert_eq(tip.key, "double_shot")
	assert_true(int(tip.level) >= 1)
	assert_true(tip.cooldown > 0.0, "an active skill shows its cooldown")
	assert_true(int(tip.next_level) > int(tip.level), "and the next rank's level")
	assert_eq(m.skill_tooltip("dash").key, "dash")


# --- The real window ----------------------------------------------------------------------------------------------------

func test_a_522_run_opens_the_skill_window_on_the_corsair_tab_and_every_tab_has_rows() -> void:
	if not require_cache():
		return
	DataRepo.patch = MIRROR.duplicate(true)
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 522})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 522)
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
		["Common", "Pirate", "Gunslinger", "Outlaw", "Corsair"])
	assert_eq(sw.tab, 4, "on the current job's tab (the fourth job, the fifth tab)")
	assert_eq(_unlisted(w, sw.model), [], "no skill the run owns is on no tab")
	for i in 5:
		scene.handle_hotkey(_key(KEY_1 + i))
		assert_eq(sw.tab, i)
		assert_true(sw.rows().size() > 0, "every lineage tab has rows")
	scene.handle_hotkey(_key(KEY_2))
	assert_eq(sw.rows().size(), 2, "the Pirate tab holds Double Shot and Dash")
	scene.handle_hotkey(_key(KEY_1))
	assert_eq(sw.rows().size(), 9, "Common contains nine passives")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
