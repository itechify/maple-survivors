extends TestCase
## The Skill window for a Shadower (422; spec #425, SH13 #438): the tabs follow the lineage (Thief 400, Bandit 420, Chief Bandit 421,
## Shadower 422, after the Common tab), every skill sits on the tab of its own job (Assaulter on Chief Bandit with Band of Thieves and
## Meso Explosion; Smokescreen and Ninja Ambush on the Shadower tab), and a test fails if a skill the run owns is on no tab. Assaulter
## has its Key Config row and quick-slot cell. The model tests use the synthetic books of the Shadower fixtures and the canonical job
## names (no cache); the RunScene test (SKIP without the cache) drives the real window through its hotkeys on the shipped (playable) data.

const SF := preload("res://tests/fixtures/shadower_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Tab -> the keys its book holds, ordered by skill id (the window sorts by id). Assassinate is a Dark Sight sub-skill, no row.
const TABS := {400: ["dark_sight", "double_stab"], 420: ["steal", "savage_blow"],
	421: ["assaulter", "band_of_thieves", "meso_explosion"],
	422: ["ninja_ambush_shadower", "smokescreen", "boomerang_step"]}

var lib: AssetLibrary
var scene: RunScene
var cfg_path := TestCase.test_dir("skill_window_shadower.cfg")
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
	var w := RunWorld.new(SF.setup("quiet", 438, data))
	RF.place_player(w, 400)
	return w


func _model(w: RunWorld) -> SkillWindowModel:
	return SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 422, SkillText.new(w.book, {}))


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


func test_tabs_follow_the_lineage_400_420_421_422_after_common() -> void:
	var m := _model(_world())
	assert_eq(_tab_names(m), ["Common", "Thief", "Bandit", "Chief Bandit", "Shadower"])
	assert_eq(m.tabs.map(func(t: Dictionary) -> int: return int(t.job_id)), [0, 400, 420, 421, 422])
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
	# The spec's list by tab, in words.
	assert_true("double_stab" in _row_keys(m.tabs[1]) and "dark_sight" in _row_keys(m.tabs[1]), "Double Stab and Dark Sight: Thief")
	assert_true("steal" in _row_keys(m.tabs[2]) and "savage_blow" in _row_keys(m.tabs[2]), "Steal and Savage Blow: Bandit")
	assert_true("assaulter" in _row_keys(m.tabs[3]) and "band_of_thieves" in _row_keys(m.tabs[3]) and "meso_explosion" in _row_keys(m.tabs[3]),
		"Assaulter, Band of Thieves and Meso Explosion: Chief Bandit")
	for key: String in ["boomerang_step", "ninja_ambush_shadower", "smokescreen"]:
		assert_true(key in _row_keys(m.tabs[4]), "%s: Shadower" % key)
	assert_false("assassinate" in _row_keys(m.tabs[4]), "Assassinate is Dark Sight's sub-skill, never a row")


func test_the_whole_pool_and_assaulter_are_listed_and_no_owned_skill_is_on_no_tab() -> void:
	var w := _world()
	var m := _model(w)
	var listed := []
	for t: Dictionary in m.tabs.slice(1):
		listed.append_array(_row_keys(t))
	for key: String in w.jobs.skill_pool(422) + ["assaulter"]:
		assert_true(key in listed, "%s is on a tab" % key)
	assert_eq(listed.size(), 9 + 1, "the nine pool skills and Assaulter, each once")
	assert_eq(_unlisted(w, m), [], "everything the run starts with is listed")
	# The guard fails when it should: a skill of a job outside the lineage (here a Hero skill) sits on no Shadower tab.
	w.book.defs["stray"] = {"name": "Stray", "job": 112, "kind": "passive"}
	w.loadout.ranks["stray"] = 1
	w.loadout.order.append("stray")
	assert_eq(_unlisted(w, _model(w)), ["stray"], "an owned skill on no tab is reported")


func test_every_owned_skill_stays_listed_and_reads_as_learned_as_the_bot_fills_the_slots() -> void:
	var w := _world()
	for key in ["steal", "band_of_thieves", "meso_explosion", "ninja_ambush_shadower"]:
		assert_true(w.learn_skill(key), key)
	var m := _model(w)
	assert_eq(_unlisted(w, m), [])
	var learned := {}
	for t: Dictionary in m.tabs.slice(1):
		for r: Dictionary in t.rows:
			learned[String(r.key)] = bool(r.learned)
	for key in ["double_stab", "assaulter", "steal", "band_of_thieves", "meso_explosion", "ninja_ambush_shadower"]:
		assert_true(learned[key], "%s reads as learned" % key)
	assert_false(learned["smokescreen"], "an offered skill is greyed until taken")
	assert_false(learned["boomerang_step"])


func test_the_tooltip_of_a_shadower_skill_reads_its_rank_and_assaulter_is_a_mobility_skill() -> void:
	var m := _model(_world())
	var tip := m.skill_tooltip("double_stab")
	assert_eq(tip.key, "double_stab")
	assert_true(int(tip.level) >= 1)
	assert_true(tip.cooldown > 0.0, "an active skill shows its cooldown")
	assert_true(int(tip.next_level) > int(tip.level), "and the next rank's level")
	assert_eq(m.skill_tooltip("assaulter").key, "assaulter")


func test_assaulter_has_a_key_config_row_labelled_by_its_name_and_a_quick_slot_cell() -> void:
	var w := _world()
	var keys := w.manual_skill_keys()
	assert_eq(keys.size(), 1, "the job owns Assaulter alone: one skill key row (the pool has no manual skill)")
	assert_eq(keys[0].action, "rush", "on the existing skill key")
	assert_eq(keys[0].name, "Assaulter", "labelled by the skill's own name")
	assert_eq(KeyBindings.from_settings(settings, ["rush"]).skill_keys, ["rush"], "Key Config lists the row")
	var cell := HudQuickSlot.movement_skill_of(keys)
	assert_eq(cell.get("action", ""), "rush", "the quick slot shows it")
	assert_eq(String(cell.get("name", "")), "Assaulter")


# --- The real window ----------------------------------------------------------------------------------------------------

func test_a_422_run_opens_the_skill_window_on_the_shadower_tab_and_every_tab_has_rows() -> void:
	if not require_cache():
		return
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("henesys", 13, {"use_flow": false, "autoplay": true, "autopick": true, "job": 422})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	scene = s
	for i in 10:
		scene.advance_frame(DT)
	var w := scene.world
	assert_eq(w.job_id(), 422)
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
		["Common", "Thief", "Bandit", "Chief Bandit", "Shadower"])
	assert_eq(sw.tab, 4, "on the current job's tab (the fourth job, the fifth tab)")
	assert_eq(_unlisted(w, sw.model), [], "no skill the run owns is on no tab")
	for i in 5:
		scene.handle_hotkey(_key(KEY_1 + i))
		assert_eq(sw.tab, i)
		assert_true(sw.rows().size() > 0, "every lineage tab has rows")
	scene.handle_hotkey(_key(KEY_4))
	assert_eq(sw.rows().size(), 3, "the Chief Bandit tab holds Assaulter, Band of Thieves and Meso Explosion")
	scene.handle_hotkey(_key(KEY_1))
	assert_eq(sw.rows().size(), 9, "Common contains nine passives")
	scene.handle_hotkey(_key(KEY_ESCAPE))
	assert_false(scene.ui_windows.has_windows(), "Esc closed it")
